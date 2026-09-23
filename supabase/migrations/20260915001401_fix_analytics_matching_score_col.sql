-- =============================================================================
-- Migration: 20260915001401_fix_analytics_matching_score_col.sql
-- Fix: Update matching score column reference from overall_score to final_score
--      matching_runs schema defined final_score in 20260915000700_matching_engine.sql.
-- =============================================================================

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

