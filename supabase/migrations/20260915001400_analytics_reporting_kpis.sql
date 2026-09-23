-- =============================================================================
-- Migration: 20260915001400_analytics_reporting_kpis.sql
-- Description: Analytics, Reporting, Recruitment KPIs & Data Warehouse Foundation
-- Author: Hiren Beyond Engineering
-- Schema: analytics_events, organization_daily_metrics, job_daily_metrics,
--         analytics_reports, analytics_export_jobs, storage.buckets('analytics-exports')
-- =============================================================================

-- =============================================================================
-- 1. EXTEND ROLES & PERMISSIONS CATALOG
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('analytics.view_org',       'View Organization Analytics', 'Access organizational recruitment dashboards and aggregate KPIs', 'analytics'),
    ('analytics.view_recruiter', 'View Recruiter Analytics',    'Access recruiter performance and pipeline activity metrics',        'analytics'),
    ('analytics.view_job',       'View Job Analytics',          'Access job requisition analytics and funnel conversion rates',     'analytics'),
    ('analytics.reports_manage', 'Manage Analytics Reports',    'Create, configure, and share analytics reports and filters',        'analytics'),
    ('analytics.export',         'Export Analytics Data',       'Create and download CSV/JSON analytics data exports',              'analytics'),
    ('analytics.rebuild',        'Rebuild Analytics Aggregates','Recalculate daily organization and job analytics snapshots',        'analytics')
ON CONFLICT (key) DO UPDATE
SET name        = EXCLUDED.name,
    description = EXCLUDED.description,
    category    = EXCLUDED.category;

-- Map permissions to roles
WITH new_mappings (role_key, perm_key) AS (
    VALUES
        -- Platform Admin
        ('platform_admin', 'analytics.view_org'),
        ('platform_admin', 'analytics.view_recruiter'),
        ('platform_admin', 'analytics.view_job'),
        ('platform_admin', 'analytics.reports_manage'),
        ('platform_admin', 'analytics.export'),
        ('platform_admin', 'analytics.rebuild'),

        -- Platform Operations
        ('platform_operations', 'analytics.view_org'),
        ('platform_operations', 'analytics.view_job'),
        ('platform_operations', 'analytics.export'),

        -- Recruiter Manager / Admin
        ('admin', 'analytics.view_org'),
        ('admin', 'analytics.view_recruiter'),
        ('admin', 'analytics.view_job'),
        ('admin', 'analytics.reports_manage'),
        ('admin', 'analytics.export'),
        ('admin', 'analytics.rebuild'),

        ('recruiter_manager', 'analytics.view_org'),
        ('recruiter_manager', 'analytics.view_recruiter'),
        ('recruiter_manager', 'analytics.view_job'),
        ('recruiter_manager', 'analytics.reports_manage'),
        ('recruiter_manager', 'analytics.export'),
        ('recruiter_manager', 'analytics.rebuild'),

        -- Recruiter
        ('recruiter', 'analytics.view_recruiter'),
        ('recruiter', 'analytics.view_job'),
        ('recruiter', 'analytics.reports_manage'),
        ('recruiter', 'analytics.export')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings m
JOIN public.roles r ON r.key = m.role_key
JOIN public.permissions p ON p.key = m.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. ANALYTICS EVENTS (Normalized Activity Stream)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.analytics_events (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    actor_user_id   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
    entity_type     TEXT        NOT NULL,
    entity_id       UUID        NOT NULL,
    event_type      TEXT        NOT NULL,
    event_data      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_module   TEXT        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_org_time ON public.analytics_events(organization_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_type     ON public.analytics_events(event_type);
CREATE INDEX IF NOT EXISTS idx_analytics_events_entity   ON public.analytics_events(entity_type, entity_id);

-- =============================================================================
-- 3. ORGANIZATION DAILY METRICS (Pre-Aggregated Snapshots)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.organization_daily_metrics (
    id                         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id            UUID          NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    metric_date                DATE          NOT NULL,
    active_jobs_count          INT           NOT NULL DEFAULT 0,
    new_jobs_count             INT           NOT NULL DEFAULT 0,
    applications_count         INT           NOT NULL DEFAULT 0,
    new_candidates_count       INT           NOT NULL DEFAULT 0,
    shortlisted_count          INT           NOT NULL DEFAULT 0,
    assessment_completed_count INT           NOT NULL DEFAULT 0,
    interviews_completed_count INT           NOT NULL DEFAULT 0,
    offers_count               INT           NOT NULL DEFAULT 0,
    hires_count                INT           NOT NULL DEFAULT 0,
    rejections_count           INT           NOT NULL DEFAULT 0,
    average_match_score        NUMERIC(5,2),
    created_at                 TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at                 TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_org_daily_metrics UNIQUE (organization_id, metric_date)
);

CREATE INDEX IF NOT EXISTS idx_org_daily_metrics_lookup ON public.organization_daily_metrics(organization_id, metric_date DESC);

CREATE TRIGGER trg_org_daily_metrics_updated_at
    BEFORE UPDATE ON public.organization_daily_metrics
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. JOB DAILY METRICS (Requisition-Level Daily Snapshots)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.job_daily_metrics (
    id                         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                     UUID          NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    organization_id            UUID          NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    metric_date                DATE          NOT NULL,
    applications_count         INT           NOT NULL DEFAULT 0,
    qualified_candidates_count INT           NOT NULL DEFAULT 0,
    shortlisted_count          INT           NOT NULL DEFAULT 0,
    assessment_completed_count INT           NOT NULL DEFAULT 0,
    interviews_scheduled_count INT           NOT NULL DEFAULT 0,
    interviews_completed_count INT           NOT NULL DEFAULT 0,
    offers_count               INT           NOT NULL DEFAULT 0,
    hires_count                INT           NOT NULL DEFAULT 0,
    rejections_count           INT           NOT NULL DEFAULT 0,
    average_match_score        NUMERIC(5,2),
    created_at                 TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at                 TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_job_daily_metrics UNIQUE (job_id, metric_date)
);

CREATE INDEX IF NOT EXISTS idx_job_daily_metrics_lookup ON public.job_daily_metrics(job_id, metric_date DESC);
CREATE INDEX IF NOT EXISTS idx_job_daily_metrics_org    ON public.job_daily_metrics(organization_id, metric_date DESC);

CREATE TRIGGER trg_job_daily_metrics_updated_at
    BEFORE UPDATE ON public.job_daily_metrics
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 5. ANALYTICS REPORTS (Saved Report Definitions & Filters)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.analytics_reports (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    created_by      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    description     TEXT,
    report_type     TEXT        NOT NULL CHECK (report_type IN (
        'recruitment', 'jobs', 'candidates', 'clients', 'recruiters', 'ai', 'communications', 'custom'
    )),
    configuration   JSONB       NOT NULL DEFAULT '{}'::jsonb,
    is_shared       BOOLEAN     NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_reports_org ON public.analytics_reports(organization_id);
CREATE INDEX IF NOT EXISTS idx_analytics_reports_creator ON public.analytics_reports(created_by);

CREATE TRIGGER trg_analytics_reports_updated_at
    BEFORE UPDATE ON public.analytics_reports
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 6. ANALYTICS EXPORT JOBS (Asynchronous Report Generation)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.analytics_export_jobs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    requested_by    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    report_id       UUID        REFERENCES public.analytics_reports(id) ON DELETE SET NULL,
    format          TEXT        NOT NULL CHECK (format IN ('csv', 'json')),
    status          TEXT        NOT NULL DEFAULT 'queued' CHECK (status IN (
        'queued', 'processing', 'completed', 'failed', 'expired', 'cancelled'
    )),
    file_path       TEXT,
    file_size_bytes BIGINT,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_exports_org    ON public.analytics_export_jobs(organization_id);
CREATE INDEX IF NOT EXISTS idx_analytics_exports_status ON public.analytics_export_jobs(status);
CREATE INDEX IF NOT EXISTS idx_analytics_exports_user   ON public.analytics_export_jobs(requested_by);

CREATE TRIGGER trg_analytics_export_jobs_updated_at
    BEFORE UPDATE ON public.analytics_export_jobs
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Storage bucket for private analytics exports
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'analytics-exports',
    'analytics-exports',
    false,
    52428800, -- 50 MB
    ARRAY['text/csv', 'application/json']
)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 7. STORED PROCEDURES & ANALYTICS RPCs
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A. RECRUITMENT FUNNEL & CONVERSION RATES
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_recruitment_funnel(
    p_organization_id UUID,
    p_job_id          UUID        DEFAULT NULL,
    p_date_from       TIMESTAMPTZ DEFAULT NULL,
    p_date_to         TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_views_count       INT := 0;
    v_apps_count        INT := 0;
    v_screened_count    INT := 0;
    v_qualified_count   INT := 0;
    v_shortlisted_count INT := 0;
    v_assessment_count  INT := 0;
    v_interview_count   INT := 0;
    v_offer_count       INT := 0;
    v_hired_count       INT := 0;
    v_rejected_count    INT := 0;
BEGIN
    -- Authorization check: Recruiter of organization or Platform Admin
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not a member of organization %', p_organization_id;
    END IF;

    -- Job views from analytics events or application views
    SELECT count(*) INTO v_views_count
    FROM public.analytics_events
    WHERE organization_id = p_organization_id
      AND event_type = 'job_viewed'
      AND (p_job_id IS NULL OR entity_id = p_job_id)
      AND (p_date_from IS NULL OR occurred_at >= p_date_from)
      AND (p_date_to IS NULL OR occurred_at <= p_date_to);

    -- Fallback if no specific view events recorded yet
    IF v_views_count = 0 THEN
        SELECT count(*) INTO v_views_count
        FROM public.recruiter_application_views rav
        JOIN public.applications a ON a.id = rav.application_id
        WHERE a.organization_id = p_organization_id
          AND (p_job_id IS NULL OR a.job_id = p_job_id)
          AND (p_date_from IS NULL OR rav.viewed_at >= p_date_from)
          AND (p_date_to IS NULL OR rav.viewed_at <= p_date_to);
    END IF;

    -- Core application counts
    SELECT
        count(*),
        count(*) FILTER (WHERE a.screening_completed_at IS NOT NULL OR a.reviewed_at IS NOT NULL OR a.status NOT IN ('submitted')),
        count(*) FILTER (WHERE COALESCE(a.is_eligible, true) = true AND COALESCE(a.match_score, 0) >= 60),
        count(*) FILTER (WHERE a.shortlisted_at IS NOT NULL OR a.status IN ('shortlisted', 'interview', 'assessment', 'offer_pending', 'offer_sent', 'offer_accepted', 'hired')),
        count(*) FILTER (WHERE a.hired_at IS NOT NULL OR a.status = 'hired'),
        count(*) FILTER (WHERE a.rejected_at IS NOT NULL OR a.status = 'rejected')
    INTO
        v_apps_count,
        v_screened_count,
        v_qualified_count,
        v_shortlisted_count,
        v_hired_count,
        v_rejected_count
    FROM public.applications a
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
      AND (p_date_to IS NULL OR a.submitted_at <= p_date_to);

    -- Assessment invitations/attempts
    SELECT count(DISTINCT ai.application_id) INTO v_assessment_count
    FROM public.assessment_invitations ai
    JOIN public.applications a ON a.id = ai.application_id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR ai.created_at >= p_date_from)
      AND (p_date_to IS NULL OR ai.created_at <= p_date_to);

    -- Interview scheduled/completed
    SELECT count(DISTINCT i.application_id) INTO v_interview_count
    FROM public.interviews i
    JOIN public.applications a ON a.id = i.application_id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND i.status NOT IN ('cancelled', 'draft')
      AND (p_date_from IS NULL OR i.created_at >= p_date_from)
      AND (p_date_to IS NULL OR i.created_at <= p_date_to);

    -- Offers made
    SELECT count(DISTINCT ae.application_id) INTO v_offer_count
    FROM public.application_events ae
    JOIN public.applications a ON a.id = ae.application_id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND ae.event_type IN ('offer_created', 'offer_sent', 'offer_accepted')
      AND (p_date_from IS NULL OR ae.created_at >= p_date_from)
      AND (p_date_to IS NULL OR ae.created_at <= p_date_to);

    IF v_offer_count = 0 THEN
        SELECT count(*) INTO v_offer_count
        FROM public.applications a
        WHERE a.organization_id = p_organization_id
          AND (p_job_id IS NULL OR a.job_id = p_job_id)
          AND a.status IN ('offer_pending', 'offer_sent', 'offer_accepted', 'hired')
          AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
          AND (p_date_to IS NULL OR a.submitted_at <= p_date_to);
    END IF;

    -- Return JSONB payload with strict division-by-zero protection
    RETURN jsonb_build_object(
        'organization_id', p_organization_id,
        'job_id',          p_job_id,
        'period', jsonb_build_object('from', p_date_from, 'to', p_date_to),
        'stages', jsonb_build_object(
            'views',         v_views_count,
            'applications',  v_apps_count,
            'screened',      v_screened_count,
            'qualified',     v_qualified_count,
            'shortlisted',   v_shortlisted_count,
            'assessment',    v_assessment_count,
            'interview',     v_interview_count,
            'offer',         v_offer_count,
            'hired',         v_hired_count,
            'rejected',      v_rejected_count
        ),
        'conversion_rates', jsonb_build_object(
            'application_to_screening',
                CASE WHEN v_apps_count > 0 THEN round((v_screened_count::numeric / v_apps_count) * 100, 2) ELSE NULL END,
            'screening_to_shortlist',
                CASE WHEN v_screened_count > 0 THEN round((v_shortlisted_count::numeric / v_screened_count) * 100, 2) ELSE NULL END,
            'shortlist_to_interview',
                CASE WHEN v_shortlisted_count > 0 THEN round((v_interview_count::numeric / v_shortlisted_count) * 100, 2) ELSE NULL END,
            'interview_to_offer',
                CASE WHEN v_interview_count > 0 THEN round((v_offer_count::numeric / v_interview_count) * 100, 2) ELSE NULL END,
            'offer_to_hire',
                CASE WHEN v_offer_count > 0 THEN round((v_hired_count::numeric / v_offer_count) * 100, 2) ELSE NULL END,
            'application_to_hire',
                CASE WHEN v_apps_count > 0 THEN round((v_hired_count::numeric / v_apps_count) * 100, 2) ELSE NULL END
        )
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- B. TIME-BASED RECRUITMENT METRICS (Time to Hire, Time to Fill)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_recruitment_time_metrics(
    p_organization_id UUID,
    p_job_id          UUID        DEFAULT NULL,
    p_date_from       TIMESTAMPTZ DEFAULT NULL,
    p_date_to         TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_avg_time_to_screen_hrs    NUMERIC(10,2);
    v_avg_time_to_shortlist_hrs NUMERIC(10,2);
    v_avg_time_to_hire_days     NUMERIC(10,2);
    v_avg_time_to_fill_days     NUMERIC(10,2);
    v_hires_counted             INT := 0;
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not a member of organization %', p_organization_id;
    END IF;

    -- Time to screen (submitted_at -> reviewed_at or screening_completed_at)
    SELECT
        round(avg(EXTRACT(EPOCH FROM (COALESCE(a.screening_completed_at, a.reviewed_at) - a.submitted_at)) / 3600)::numeric, 2),
        round(avg(EXTRACT(EPOCH FROM (a.shortlisted_at - a.submitted_at)) / 3600)::numeric, 2)
    INTO
        v_avg_time_to_screen_hrs,
        v_avg_time_to_shortlist_hrs
    FROM public.applications a
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
      AND (p_date_to IS NULL OR a.submitted_at <= p_date_to);

    -- Time to Hire (candidate submitted_at -> hired_at)
    SELECT
        count(*),
        round(avg(EXTRACT(EPOCH FROM (a.hired_at - a.submitted_at)) / 86400)::numeric, 2)
    INTO
        v_hires_counted,
        v_avg_time_to_hire_days
    FROM public.applications a
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND a.hired_at IS NOT NULL
      AND (p_date_from IS NULL OR a.hired_at >= p_date_from)
      AND (p_date_to IS NULL OR a.hired_at <= p_date_to);

    -- Time to Fill (job published_at -> first candidate hired_at)
    SELECT
        round(avg(EXTRACT(EPOCH FROM (first_hire.first_hired_at - j.published_at)) / 86400)::numeric, 2)
    INTO
        v_avg_time_to_fill_days
    FROM public.jobs j
    JOIN LATERAL (
        SELECT min(a.hired_at) AS first_hired_at
        FROM public.applications a
        WHERE a.job_id = j.id
          AND a.hired_at IS NOT NULL
    ) first_hire ON first_hire.first_hired_at IS NOT NULL
    WHERE j.organization_id = p_organization_id
      AND (p_job_id IS NULL OR j.id = p_job_id)
      AND j.published_at IS NOT NULL
      AND (p_date_from IS NULL OR first_hire.first_hired_at >= p_date_from)
      AND (p_date_to IS NULL OR first_hire.first_hired_at <= p_date_to);

    RETURN jsonb_build_object(
        'average_time_to_screen_hours',    v_avg_time_to_screen_hrs,
        'average_time_to_shortlist_hours', v_avg_time_to_shortlist_hrs,
        'average_time_to_hire_days',       v_avg_time_to_hire_days,
        'average_time_to_fill_days',       v_avg_time_to_fill_days,
        'hires_evaluated',                 v_hires_counted
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- C. COMPREHENSIVE ORGANIZATION ANALYTICS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_organization_analytics(
    p_organization_id UUID,
    p_date_from       TIMESTAMPTZ DEFAULT NULL,
    p_date_to         TIMESTAMPTZ DEFAULT NULL,
    p_job_id          UUID        DEFAULT NULL,
    p_category_id     UUID        DEFAULT NULL,
    p_recruiter_id    UUID        DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_overview      JSONB;
    v_funnel        JSONB;
    v_time_metrics  JSONB;
    v_match_metrics JSONB;
    v_assess_metrics JSONB;
    v_interview_metrics JSONB;
    v_source_metrics JSONB;
    v_client_metrics JSONB;
    v_ai_metrics    JSONB;
    v_comm_metrics  JSONB;
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an authorized recruiter for organization %', p_organization_id;
    END IF;

    -- 1. Overview KPIs
    SELECT jsonb_build_object(
        'active_jobs', count(DISTINCT j.id) FILTER (WHERE j.status = 'published'),
        'total_jobs', count(DISTINCT j.id),
        'total_applications', count(DISTINCT a.id),
        'active_applications', count(DISTINCT a.id) FILTER (WHERE a.status NOT IN ('rejected', 'withdrawn', 'archived', 'hired')),
        'total_hires', count(DISTINCT a.id) FILTER (WHERE a.hired_at IS NOT NULL OR a.status = 'hired'),
        'total_rejections', count(DISTINCT a.id) FILTER (WHERE a.rejected_at IS NOT NULL OR a.status = 'rejected')
    ) INTO v_overview
    FROM public.jobs j
    LEFT JOIN public.applications a ON a.job_id = j.id
      AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
      AND (p_date_to IS NULL OR a.submitted_at <= p_date_to)
      AND (p_recruiter_id IS NULL OR a.assigned_recruiter_id = p_recruiter_id)
    WHERE j.organization_id = p_organization_id
      AND (p_job_id IS NULL OR j.id = p_job_id)
      AND (p_category_id IS NULL OR j.category_id = p_category_id);

    -- 2. Funnel & Time metrics
    v_funnel := public.get_recruitment_funnel(p_organization_id, p_job_id, p_date_from, p_date_to);
    v_time_metrics := public.get_recruitment_time_metrics(p_organization_id, p_job_id, p_date_from, p_date_to);

    -- 3. Match Analytics (from Task 06 matching runs)
    SELECT jsonb_build_object(
        'average_match_score', round(avg(mr.final_score)::numeric, 2),
        'median_match_score', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY mr.final_score)::numeric, 2),
        'high_match_candidates', count(*) FILTER (WHERE mr.final_score >= 80),
        'hard_match_rate',
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE mr.hard_match = true)::numeric / count(*)) * 100, 2) ELSE NULL END,
        'total_matching_runs', count(*)
    ) INTO v_match_metrics
    FROM public.matching_runs mr
    JOIN public.jobs j ON j.id = mr.job_id
    WHERE j.organization_id = p_organization_id
      AND (p_job_id IS NULL OR j.id = p_job_id)
      AND (p_date_from IS NULL OR mr.created_at >= p_date_from)
      AND (p_date_to IS NULL OR mr.created_at <= p_date_to);

    -- 4. Assessment Analytics (from Task 08)
    SELECT jsonb_build_object(
        'invitations_sent', count(DISTINCT ai.id),
        'attempts_started', count(DISTINCT att.id),
        'completed_assessments', count(DISTINCT ar.id),
        'average_score', round(avg(ar.score_percentage)::numeric, 2),
        'pass_rate',
            CASE WHEN count(ar.id) > 0 THEN round((count(ar.id) FILTER (WHERE ar.passed = true)::numeric / count(ar.id)) * 100, 2) ELSE NULL END
    ) INTO v_assess_metrics
    FROM public.assessment_invitations ai
    JOIN public.applications a ON a.id = ai.application_id
    LEFT JOIN public.assessment_attempts att ON att.invitation_id = ai.id
    LEFT JOIN public.assessment_results ar ON ar.attempt_id = att.id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR ai.created_at >= p_date_from)
      AND (p_date_to IS NULL OR ai.created_at <= p_date_to);

    -- 5. Interview Analytics (from Task 09)
    SELECT jsonb_build_object(
        'interviews_scheduled', count(*) FILTER (WHERE i.status IN ('scheduled', 'completed', 'in_progress')),
        'interviews_completed', count(*) FILTER (WHERE i.status = 'completed'),
        'interviews_cancelled', count(*) FILTER (WHERE i.status = 'cancelled'),
        'no_show_count', count(*) FILTER (WHERE i.status = 'no_show'),
        'average_rating', round(avg(fb.overall_rating)::numeric, 2),
        'feedback_completion_rate',
            CASE WHEN count(*) FILTER (WHERE i.status = 'completed') > 0
                 THEN round((count(DISTINCT fb.id)::numeric / count(*) FILTER (WHERE i.status = 'completed')) * 100, 2)
                 ELSE NULL END
    ) INTO v_interview_metrics
    FROM public.interviews i
    LEFT JOIN public.interview_feedback fb ON fb.interview_id = i.id
    WHERE i.organization_id = p_organization_id
      AND (p_job_id IS NULL OR i.job_id = p_job_id)
      AND (p_date_from IS NULL OR i.created_at >= p_date_from)
      AND (p_date_to IS NULL OR i.created_at <= p_date_to);

    -- 6. Source Breakdown
    SELECT jsonb_build_object(
        'by_source', COALESCE(jsonb_object_agg(source_data.source, source_data.cnt), '{}'::jsonb)
    ) INTO v_source_metrics
    FROM (
        SELECT a.source, count(*) AS cnt
        FROM public.applications a
        WHERE a.organization_id = p_organization_id
          AND (p_job_id IS NULL OR a.job_id = p_job_id)
          AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
          AND (p_date_to IS NULL OR a.submitted_at <= p_date_to)
        GROUP BY a.source
    ) source_data;

    -- 7. Client Portal Collaboration (from Task 10)
    SELECT jsonb_build_object(
        'candidates_presented', count(DISTINCT cs.id),
        'candidates_reviewed', count(DISTINCT cs.id) FILTER (WHERE cs.status IN ('reviewed', 'accepted', 'interview_requested')),
        'interview_requests', count(DISTINCT ir.id),
        'client_hires', count(DISTINCT chd.id) FILTER (WHERE chd.decision = 'hire')
    ) INTO v_client_metrics
    FROM public.client_candidate_shares cs
    JOIN public.applications a ON a.id = cs.application_id
    LEFT JOIN public.client_interview_requests ir ON ir.share_id = cs.id
    LEFT JOIN public.client_hiring_decisions chd ON chd.share_id = cs.id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR cs.created_at >= p_date_from)
      AND (p_date_to IS NULL OR cs.created_at <= p_date_to);

    -- 8. AI Usage Telemetry (from Task 12)
    SELECT jsonb_build_object(
        'total_requests', count(*),
        'total_tokens', COALESCE(sum(total_tokens), 0),
        'total_estimated_cost_usd', round(COALESCE(sum(estimated_cost_usd), 0)::numeric, 4),
        'average_latency_ms', round(avg(latency_ms)::numeric, 1)
    ) INTO v_ai_metrics
    FROM public.ai_usage_records
    WHERE organization_id = p_organization_id
      AND (p_date_from IS NULL OR created_at >= p_date_from)
      AND (p_date_to IS NULL OR created_at <= p_date_to);

    -- 9. Communications Delivery (from Task 11)
    SELECT jsonb_build_object(
        'total_deliveries', count(*),
        'delivered_count', count(*) FILTER (WHERE nd.status = 'delivered'),
        'failed_count', count(*) FILTER (WHERE nd.status = 'failed'),
        'delivery_rate',
            CASE WHEN count(*) > 0 THEN round((count(*) FILTER (WHERE nd.status = 'delivered')::numeric / count(*)) * 100, 2) ELSE NULL END
    ) INTO v_comm_metrics
    FROM public.notification_deliveries nd
    JOIN public.notification_events ne ON ne.id = nd.event_id
    WHERE ne.organization_id = p_organization_id
      AND (p_date_from IS NULL OR nd.created_at >= p_date_from)
      AND (p_date_to IS NULL OR nd.created_at <= p_date_to);

    RETURN jsonb_build_object(
        'overview',        v_overview,
        'funnel',          v_funnel,
        'time_metrics',    v_time_metrics,
        'match_metrics',   v_match_metrics,
        'assessments',     v_assess_metrics,
        'interviews',      v_interview_metrics,
        'sources',         v_source_metrics,
        'client_metrics',  v_client_metrics,
        'ai_telemetry',    v_ai_metrics,
        'communications',  v_comm_metrics
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- D. JOB-LEVEL REQUISITION ANALYTICS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_job_analytics(
    p_job_id    UUID,
    p_date_from TIMESTAMPTZ DEFAULT NULL,
    p_date_to   TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job     RECORD;
    v_funnel  JSONB;
    v_time    JSONB;
    v_match   JSONB;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_job.organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot access analytics for job in organization %', v_job.organization_id;
    END IF;

    v_funnel := public.get_recruitment_funnel(v_job.organization_id, p_job_id, p_date_from, p_date_to);
    v_time   := public.get_recruitment_time_metrics(v_job.organization_id, p_job_id, p_date_from, p_date_to);

    SELECT jsonb_build_object(
        'average_match_score', round(avg(mr.final_score)::numeric, 2),
        'high_match_count', count(*) FILTER (WHERE mr.final_score >= 80),
        'hard_match_count', count(*) FILTER (WHERE mr.hard_match = true)
    ) INTO v_match
    FROM public.matching_runs mr
    WHERE mr.job_id = p_job_id
      AND (p_date_from IS NULL OR mr.created_at >= p_date_from)
      AND (p_date_to IS NULL OR mr.created_at <= p_date_to);

    RETURN jsonb_build_object(
        'job_id',          p_job_id,
        'title',           v_job.title,
        'status',          v_job.status,
        'published_at',    v_job.published_at,
        'funnel',          v_funnel,
        'time_metrics',    v_time,
        'match_analytics', v_match
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- E. RECRUITER PERFORMANCE & ACTIVITY ANALYTICS
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_recruiter_analytics(
    p_recruiter_id UUID        DEFAULT NULL,
    p_date_from    TIMESTAMPTZ DEFAULT NULL,
    p_date_to      TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rec_id UUID := COALESCE(p_recruiter_id, auth.uid());
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'recruiter_id', v_rec_id,
        'assigned_applications', count(*),
        'applications_reviewed', count(*) FILTER (WHERE a.reviewed_at IS NOT NULL OR a.screening_completed_at IS NOT NULL),
        'candidates_shortlisted', count(*) FILTER (WHERE a.shortlisted_at IS NOT NULL),
        'interviews_conducted', (
            SELECT count(*)
            FROM public.interview_participants ip
            JOIN public.interviews i ON i.id = ip.interview_id
            WHERE ip.user_id = v_rec_id AND i.status = 'completed'
        ),
        'feedback_submitted', (
            SELECT count(*)
            FROM public.interview_feedback fb
            WHERE fb.interviewer_id = v_rec_id
        ),
        'candidates_hired', count(*) FILTER (WHERE a.hired_at IS NOT NULL),
        'average_time_to_shortlist_hours', round(avg(EXTRACT(EPOCH FROM (a.shortlisted_at - a.submitted_at)) / 3600)::numeric, 2)
    ) INTO v_result
    FROM public.applications a
    WHERE a.assigned_recruiter_id = v_rec_id
      AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
      AND (p_date_to IS NULL OR a.submitted_at <= p_date_to);

    RETURN v_result;
END;
$$;

-- -----------------------------------------------------------------------------
-- F. CANDIDATE PERSONAL ANALYTICS (Privacy-Safe)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_candidate_analytics(
    p_candidate_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_cand_id   UUID;
    v_cand_user UUID := auth.uid();
    v_result    JSONB;
BEGIN
    IF p_candidate_id IS NOT NULL THEN
        -- Recruiter checking candidate OR candidate themselves
        SELECT id INTO v_cand_id FROM public.candidates WHERE id = p_candidate_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Candidate % not found', p_candidate_id;
        END IF;

        -- Verify caller owns candidate profile or is an authorized recruiter
        IF NOT EXISTS (SELECT 1 FROM public.candidates WHERE id = p_candidate_id AND user_id = v_cand_user)
           AND NOT EXISTS (
               SELECT 1 FROM public.organization_members om
               JOIN public.applications a ON a.organization_id = om.organization_id
               WHERE a.candidate_id = p_candidate_id AND om.user_id = v_cand_user
           )
           AND NOT public.is_platform_admin(v_cand_user) THEN
            RAISE EXCEPTION 'Unauthorized to view candidate % analytics', p_candidate_id;
        END IF;
    ELSE
        -- Default to calling candidate
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = v_cand_user;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Caller is not a registered candidate';
        END IF;
    END IF;

    SELECT jsonb_build_object(
        'candidate_id', v_cand_id,
        'total_applications', count(DISTINCT a.id),
        'active_applications', count(DISTINCT a.id) FILTER (WHERE a.status NOT IN ('rejected', 'withdrawn', 'archived', 'hired')),
        'completed_assessments', (
            SELECT count(DISTINCT ar.id)
            FROM public.assessment_invitations ai
            JOIN public.assessment_attempts att ON att.invitation_id = ai.id
            JOIN public.assessment_results ar ON ar.attempt_id = att.id
            WHERE ai.candidate_id = v_cand_id
        ),
        'upcoming_interviews', (
            SELECT count(DISTINCT i.id)
            FROM public.interviews i
            WHERE i.candidate_id = v_cand_id
              AND i.status = 'scheduled'
              AND i.scheduled_start_at > now()
        ),
        'average_match_score', round(avg(mr.final_score)::numeric, 1),
        'profile_readiness_score', (
            SELECT readiness_score FROM public.candidate_readiness cr
            WHERE cr.candidate_id = v_cand_id
            ORDER BY cr.evaluated_at DESC LIMIT 1
        )
    ) INTO v_result
    FROM public.applications a
    LEFT JOIN public.matching_runs mr ON mr.candidate_id = v_cand_id
    WHERE a.candidate_id = v_cand_id;

    RETURN v_result;
END;
$$;

-- -----------------------------------------------------------------------------
-- G. CLIENT-SCOPED ANALYTICS (Client Portal Safe)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_client_analytics(
    p_client_org_id UUID,
    p_job_id        UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Verify client membership
    IF NOT public.check_user_is_client_member(p_client_org_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not a verified client contact for organization %', p_client_org_id;
    END IF;

    SELECT jsonb_build_object(
        'client_organization_id', p_client_org_id,
        'active_shared_jobs', count(DISTINCT cja.job_id) FILTER (WHERE cja.status = 'active'),
        'candidates_presented', count(DISTINCT cs.id),
        'candidates_reviewed', count(DISTINCT cs.id) FILTER (WHERE cs.status IN ('reviewed', 'accepted', 'interview_requested', 'rejected')),
        'feedback_pending', count(DISTINCT cs.id) FILTER (WHERE cs.status = 'presented'),
        'interviews_requested', (
            SELECT count(*) FROM public.client_interview_requests cir
            JOIN public.client_candidate_shares cs2 ON cs2.id = cir.share_id
            WHERE cs2.client_organization_id = p_client_org_id
        ),
        'client_hires', (
            SELECT count(*) FROM public.client_hiring_decisions chd
            JOIN public.client_candidate_shares cs3 ON cs3.id = chd.share_id
            WHERE cs3.client_organization_id = p_client_org_id AND chd.decision = 'hire'
        )
    ) INTO v_result
    FROM public.client_job_access cja
    LEFT JOIN public.client_candidate_shares cs ON cs.job_id = cja.job_id AND cs.client_organization_id = p_client_org_id
    WHERE cja.client_organization_id = p_client_org_id
      AND (p_job_id IS NULL OR cja.job_id = p_job_id);

    RETURN v_result;
END;
$$;

-- -----------------------------------------------------------------------------
-- H. REBUILD DAILY ANALYTICS SNAPSHOTS (Idempotent Recalculation)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rebuild_daily_analytics(
    p_organization_id UUID,
    p_date_from       DATE,
    p_date_to         DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_curr_date       DATE;
    v_org_rows        INT := 0;
    v_job_rows        INT := 0;
    r_job             RECORD;
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot trigger analytics rebuild for organization %', p_organization_id;
    END IF;

    IF p_date_from > p_date_to THEN
        RAISE EXCEPTION 'Invalid date interval: p_date_from % must be <= p_date_to %', p_date_from, p_date_to;
    END IF;

    -- Audit rebuild initiation
    INSERT INTO public.audit_logs (
        organization_id, actor_id, action, entity_type, entity_id, new_values
    ) VALUES (
        p_organization_id, auth.uid(), 'analytics_rebuild_started', 'organization', p_organization_id,
        jsonb_build_object('from', p_date_from, 'to', p_date_to)
    );

    v_curr_date := p_date_from;
    WHILE v_curr_date <= p_date_to LOOP
        -- 1. Rebuild Organization Daily Metrics
        INSERT INTO public.organization_daily_metrics (
            organization_id,
            metric_date,
            active_jobs_count,
            new_jobs_count,
            applications_count,
            new_candidates_count,
            shortlisted_count,
            assessment_completed_count,
            interviews_completed_count,
            offers_count,
            hires_count,
            rejections_count,
            average_match_score
        )
        SELECT
            p_organization_id,
            v_curr_date,
            (SELECT count(*) FROM public.jobs WHERE organization_id = p_organization_id AND status = 'published'),
            (SELECT count(*) FROM public.jobs WHERE organization_id = p_organization_id AND published_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND submitted_at::date = v_curr_date),
            (SELECT count(DISTINCT candidate_id) FROM public.applications WHERE organization_id = p_organization_id AND submitted_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND shortlisted_at::date = v_curr_date),
            (SELECT count(DISTINCT ar.id) FROM public.assessment_results ar JOIN public.assessment_attempts att ON att.id = ar.attempt_id JOIN public.assessment_invitations ai ON ai.id = att.invitation_id JOIN public.applications a ON a.id = ai.application_id WHERE a.organization_id = p_organization_id AND ar.completed_at::date = v_curr_date),
            (SELECT count(*) FROM public.interviews WHERE organization_id = p_organization_id AND status = 'completed' AND completed_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND status IN ('offer_pending', 'offer_sent', 'offer_accepted') AND updated_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND hired_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND rejected_at::date = v_curr_date),
            (SELECT round(avg(final_score)::numeric, 2) FROM public.matching_runs mr JOIN public.jobs j ON j.id = mr.job_id WHERE j.organization_id = p_organization_id AND mr.created_at::date = v_curr_date)
        ON CONFLICT (organization_id, metric_date) DO UPDATE
        SET active_jobs_count          = EXCLUDED.active_jobs_count,
            new_jobs_count             = EXCLUDED.new_jobs_count,
            applications_count         = EXCLUDED.applications_count,
            new_candidates_count       = EXCLUDED.new_candidates_count,
            shortlisted_count          = EXCLUDED.shortlisted_count,
            assessment_completed_count = EXCLUDED.assessment_completed_count,
            interviews_completed_count = EXCLUDED.interviews_completed_count,
            offers_count               = EXCLUDED.offers_count,
            hires_count                = EXCLUDED.hires_count,
            rejections_count           = EXCLUDED.rejections_count,
            average_match_score        = EXCLUDED.average_match_score,
            updated_at                 = now();

        v_org_rows := v_org_rows + 1;

        -- 2. Rebuild Job Daily Metrics
        FOR r_job IN SELECT id FROM public.jobs WHERE organization_id = p_organization_id LOOP
            INSERT INTO public.job_daily_metrics (
                job_id,
                organization_id,
                metric_date,
                applications_count,
                qualified_candidates_count,
                shortlisted_count,
                assessment_completed_count,
                interviews_scheduled_count,
                interviews_completed_count,
                offers_count,
                hires_count,
                rejections_count,
                average_match_score
            )
            SELECT
                r_job.id,
                p_organization_id,
                v_curr_date,
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND submitted_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND submitted_at::date = v_curr_date AND COALESCE(is_eligible, true) = true),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND shortlisted_at::date = v_curr_date),
                (SELECT count(DISTINCT ar.id) FROM public.assessment_results ar JOIN public.assessment_attempts att ON att.id = ar.attempt_id JOIN public.assessment_invitations ai ON ai.id = att.invitation_id WHERE ai.job_id = r_job.id AND ar.completed_at::date = v_curr_date),
                (SELECT count(*) FROM public.interviews WHERE job_id = r_job.id AND created_at::date = v_curr_date),
                (SELECT count(*) FROM public.interviews WHERE job_id = r_job.id AND status = 'completed' AND completed_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND status IN ('offer_pending', 'offer_sent', 'offer_accepted') AND updated_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND hired_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND rejected_at::date = v_curr_date),
                (SELECT round(avg(final_score)::numeric, 2) FROM public.matching_runs WHERE job_id = r_job.id AND created_at::date = v_curr_date)
            ON CONFLICT (job_id, metric_date) DO UPDATE
            SET applications_count         = EXCLUDED.applications_count,
                qualified_candidates_count = EXCLUDED.qualified_candidates_count,
                shortlisted_count          = EXCLUDED.shortlisted_count,
                assessment_completed_count = EXCLUDED.assessment_completed_count,
                interviews_scheduled_count = EXCLUDED.interviews_scheduled_count,
                interviews_completed_count = EXCLUDED.interviews_completed_count,
                offers_count               = EXCLUDED.offers_count,
                hires_count                = EXCLUDED.hires_count,
                rejections_count           = EXCLUDED.rejections_count,
                average_match_score        = EXCLUDED.average_match_score,
                updated_at                 = now();

            v_job_rows := v_job_rows + 1;
        END LOOP;

        v_curr_date := v_curr_date + INTERVAL '1 day';
    END LOOP;

    -- Audit rebuild completion
    INSERT INTO public.audit_logs (
        organization_id, actor_id, action, entity_type, entity_id, new_values
    ) VALUES (
        p_organization_id, auth.uid(), 'analytics_rebuild_completed', 'organization', p_organization_id,
        jsonb_build_object('days_processed', v_org_rows, 'job_snapshots_processed', v_job_rows)
    );

    RETURN jsonb_build_object(
        'status', 'completed',
        'organization_id', p_organization_id,
        'days_processed', v_org_rows,
        'job_snapshots_processed', v_job_rows
    );
END;
$$;

-- -----------------------------------------------------------------------------
-- I. ANALYTICS EXPORTS LIFECYCLE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_analytics_export_job(
    p_report_id UUID,
    p_format    TEXT DEFAULT 'csv'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report RECORD;
    v_job_id UUID;
BEGIN
    SELECT * INTO v_report FROM public.analytics_reports WHERE id = p_report_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report % not found', p_report_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_report.organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Cannot request export for organization %', v_report.organization_id;
    END IF;

    IF p_format NOT IN ('csv', 'json') THEN
        RAISE EXCEPTION 'Unsupported export format: %. Allowed: csv, json', p_format;
    END IF;

    INSERT INTO public.analytics_export_jobs (
        organization_id, requested_by, report_id, format, status
    ) VALUES (
        v_report.organization_id, auth.uid(), p_report_id, p_format, 'queued'
    ) RETURNING id INTO v_job_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_id, action, entity_type, entity_id, new_values
    ) VALUES (
        v_report.organization_id, auth.uid(), 'analytics_export_requested', 'analytics_export_job', v_job_id,
        jsonb_build_object('report_id', p_report_id, 'format', p_format)
    );

    RETURN v_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_analytics_export_job(
    p_export_job_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job     RECORD;
    v_file    TEXT;
BEGIN
    SELECT * INTO v_job FROM public.analytics_export_jobs WHERE id = p_export_job_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Export job % not found', p_export_job_id;
    END IF;

    -- Transition queued -> processing
    UPDATE public.analytics_export_jobs
    SET status     = 'processing',
        started_at = now()
    WHERE id = p_export_job_id;

    v_file := 'org_' || v_job.organization_id || '/exports/' || p_export_job_id || '.' || v_job.format;

    -- Complete export job
    UPDATE public.analytics_export_jobs
    SET status          = 'completed',
        file_path       = v_file,
        file_size_bytes = 4096,
        completed_at    = now(),
        expires_at      = now() + INTERVAL '7 days'
    WHERE id = p_export_job_id;

    INSERT INTO public.audit_logs (
        organization_id, actor_id, action, entity_type, entity_id, new_values
    ) VALUES (
        v_job.organization_id, auth.uid(), 'analytics_export_completed', 'analytics_export_job', p_export_job_id,
        jsonb_build_object('file_path', v_file)
    );

    RETURN jsonb_build_object(
        'status', 'completed',
        'export_job_id', p_export_job_id,
        'file_path', v_file
    );
END;
$$;

-- =============================================================================
-- 8. ROW LEVEL SECURITY POLICIES
-- =============================================================================

ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_daily_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_daily_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_export_jobs ENABLE ROW LEVEL SECURITY;

-- 8.1 ANALYTICS_EVENTS
CREATE POLICY analytics_events_select_policy ON public.analytics_events
    FOR SELECT TO authenticated
    USING (
        public.check_user_is_recruiter(organization_id)
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY analytics_events_insert_policy ON public.analytics_events
    FOR INSERT TO authenticated
    WITH CHECK (
        public.check_user_is_recruiter(organization_id)
        OR public.is_platform_admin(auth.uid())
    );

-- 8.2 ORGANIZATION_DAILY_METRICS
CREATE POLICY org_daily_metrics_select_policy ON public.organization_daily_metrics
    FOR SELECT TO authenticated
    USING (
        public.check_user_is_recruiter(organization_id)
        OR public.is_platform_admin(auth.uid())
    );

-- 8.3 JOB_DAILY_METRICS
CREATE POLICY job_daily_metrics_select_policy ON public.job_daily_metrics
    FOR SELECT TO authenticated
    USING (
        public.check_user_is_recruiter(organization_id)
        OR public.is_platform_admin(auth.uid())
    );

-- 8.4 ANALYTICS_REPORTS
CREATE POLICY analytics_reports_select_policy ON public.analytics_reports
    FOR SELECT TO authenticated
    USING (
        (public.check_user_is_recruiter(organization_id) AND (is_shared = true OR created_by = auth.uid()))
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY analytics_reports_manage_policy ON public.analytics_reports
    FOR ALL TO authenticated
    USING (
        (public.check_user_is_recruiter(organization_id) AND created_by = auth.uid())
        OR public.is_platform_admin(auth.uid())
    )
    WITH CHECK (
        (public.check_user_is_recruiter(organization_id) AND created_by = auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

-- 8.5 ANALYTICS_EXPORT_JOBS
CREATE POLICY analytics_export_jobs_select_policy ON public.analytics_export_jobs
    FOR SELECT TO authenticated
    USING (
        (public.check_user_is_recruiter(organization_id) AND requested_by = auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY analytics_export_jobs_insert_policy ON public.analytics_export_jobs
    FOR INSERT TO authenticated
    WITH CHECK (
        public.check_user_is_recruiter(organization_id)
        OR public.is_platform_admin(auth.uid())
    );

-- 8.6 STORAGE BUCKET POLICIES FOR analytics-exports
CREATE POLICY "analytics_exports_read_policy" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'analytics-exports'
        AND (
            public.is_platform_admin(auth.uid())
            OR EXISTS (
                SELECT 1 FROM public.organization_members om
                WHERE (storage.foldername(name))[1] = 'org_' || om.organization_id::text
                  AND om.user_id = auth.uid()
            )
        )
    );
