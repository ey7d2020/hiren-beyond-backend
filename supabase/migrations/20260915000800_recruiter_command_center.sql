-- =============================================================================
-- Migration: 20260915000800_recruiter_command_center.sql
-- Description: Recruiter Dashboard, Bulk Screening, Shortlists, Talent Pools & Review Queue
-- Author: Hiren Beyond Engineering
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. BULK SCREENING RUNS (Batch Screening Orchestration)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bulk_screening_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    matching_profile_id UUID REFERENCES public.matching_profiles(id) ON DELETE SET NULL,
    matching_profile_version INT NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'cancelled')),
    candidate_count INT NOT NULL DEFAULT 0,
    processed_count INT NOT NULL DEFAULT 0,
    matched_count INT NOT NULL DEFAULT 0,
    rejected_count INT NOT NULL DEFAULT 0,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    error_message TEXT,
    engine_version TEXT NOT NULL DEFAULT 'v1.0.0',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bulk_screening_org ON public.bulk_screening_runs(organization_id);
CREATE INDEX IF NOT EXISTS idx_bulk_screening_job ON public.bulk_screening_runs(job_id);
CREATE INDEX IF NOT EXISTS idx_bulk_screening_status ON public.bulk_screening_runs(status);

-- -----------------------------------------------------------------------------
-- 2. BULK SCREENING CANDIDATES (Per-Candidate Queue & Results)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bulk_screening_candidates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bulk_screening_run_id UUID NOT NULL REFERENCES public.bulk_screening_runs(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'skipped')),
    match_score NUMERIC CHECK (match_score >= 0 AND match_score <= 100),
    hard_match BOOLEAN,
    confidence NUMERIC CHECK (confidence >= 0 AND confidence <= 1.0),
    rank_position INT,
    screening_summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bulk_screening_run_candidate UNIQUE (bulk_screening_run_id, candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_bulk_screening_cand_run ON public.bulk_screening_candidates(bulk_screening_run_id);
CREATE INDEX IF NOT EXISTS idx_bulk_screening_cand_cand ON public.bulk_screening_candidates(candidate_id);
CREATE INDEX IF NOT EXISTS idx_bulk_screening_cand_score ON public.bulk_screening_candidates(match_score DESC);

-- -----------------------------------------------------------------------------
-- 3. CANDIDATE SHORTLISTS (Job Shortlist Management)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.candidate_shortlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidate_shortlists_job_cand UNIQUE (job_id, candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_shortlists_org ON public.candidate_shortlists(organization_id);
CREATE INDEX IF NOT EXISTS idx_shortlists_job ON public.candidate_shortlists(job_id);
CREATE INDEX IF NOT EXISTS idx_shortlists_cand ON public.candidate_shortlists(candidate_id);
CREATE INDEX IF NOT EXISTS idx_shortlists_status ON public.candidate_shortlists(status);

-- -----------------------------------------------------------------------------
-- 4. TALENT POOLS (Manual & Smart Talent Pools)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.talent_pools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    description TEXT,
    pool_type TEXT NOT NULL CHECK (pool_type IN ('manual', 'smart')),
    is_dynamic BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_talent_pools_org_slug UNIQUE (organization_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_talent_pools_org ON public.talent_pools(organization_id);
CREATE INDEX IF NOT EXISTS idx_talent_pools_type ON public.talent_pools(pool_type);
CREATE INDEX IF NOT EXISTS idx_talent_pools_dynamic ON public.talent_pools(is_dynamic) WHERE is_dynamic = true;

-- -----------------------------------------------------------------------------
-- 5. TALENT POOL MEMBERS (Pool Membership)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.talent_pool_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    talent_pool_id UUID NOT NULL REFERENCES public.talent_pools(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    added_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'smart_rule', 'bulk_import', 'ats_shortlist')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_talent_pool_members_pool_cand UNIQUE (talent_pool_id, candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_pool_members_pool ON public.talent_pool_members(talent_pool_id);
CREATE INDEX IF NOT EXISTS idx_pool_members_candidate ON public.talent_pool_members(candidate_id);
CREATE INDEX IF NOT EXISTS idx_pool_members_status ON public.talent_pool_members(status);

-- -----------------------------------------------------------------------------
-- 6. TALENT POOL RULES (Deterministic Rules for Smart Pools)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.talent_pool_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    talent_pool_id UUID NOT NULL REFERENCES public.talent_pools(id) ON DELETE CASCADE,
    rule_type TEXT NOT NULL CHECK (rule_type IN ('skill', 'experience_years', 'language', 'education', 'location', 'career_level', 'match_score')),
    operator TEXT NOT NULL CHECK (operator IN ('equals', 'greater_than_or_equal', 'less_than_or_equal', 'contains', 'in_list')),
    field TEXT NOT NULL,
    value TEXT NOT NULL,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pool_rules_pool ON public.talent_pool_rules(talent_pool_id);

-- -----------------------------------------------------------------------------
-- 7. TALENT POOL MEMBERSHIP EVENTS (Dynamic Membership Audit Log)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.talent_pool_membership_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    talent_pool_id UUID NOT NULL REFERENCES public.talent_pools(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('entered', 'exited', 'manually_added', 'manually_removed')),
    reason TEXT,
    rule_snapshot JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pool_events_pool ON public.talent_pool_membership_events(talent_pool_id);
CREATE INDEX IF NOT EXISTS idx_pool_events_cand ON public.talent_pool_membership_events(candidate_id);

-- -----------------------------------------------------------------------------
-- 8. RECRUITER SAVED SEARCHES (Reusable Search Filter Presets)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recruiter_saved_searches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    search_type TEXT NOT NULL DEFAULT 'candidate' CHECK (search_type IN ('candidate', 'job', 'application')),
    filters JSONB NOT NULL DEFAULT '{}'::jsonb,
    sort_configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_shared BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_saved_searches_org ON public.recruiter_saved_searches(organization_id);
CREATE INDEX IF NOT EXISTS idx_saved_searches_creator ON public.recruiter_saved_searches(created_by);

-- -----------------------------------------------------------------------------
-- 9. CANDIDATE SCREENING SUMMARIES (Structured Recruiter Digests)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.candidate_screening_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    matching_run_id UUID REFERENCES public.matching_runs(id) ON DELETE SET NULL,
    summary TEXT NOT NULL,
    strengths TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    gaps TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    risk_flags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    recommendation TEXT NOT NULL CHECK (recommendation IN ('strong_match', 'match', 'borderline', 'weak_match', 'needs_review')),
    confidence NUMERIC NOT NULL DEFAULT 1.0 CHECK (confidence >= 0 AND confidence <= 1.0),
    generated_by TEXT NOT NULL DEFAULT 'system',
    generation_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_screening_summaries_job_cand UNIQUE (job_id, candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_screening_summaries_cand ON public.candidate_screening_summaries(candidate_id);
CREATE INDEX IF NOT EXISTS idx_screening_summaries_job ON public.candidate_screening_summaries(job_id);

-- -----------------------------------------------------------------------------
-- 10. RECRUITER REVIEW QUEUE (Human Review Inbox for Ambiguities/Flags)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recruiter_review_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    job_id UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'dismissed')),
    assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_review_queue_org ON public.recruiter_review_queue(organization_id);
CREATE INDEX IF NOT EXISTS idx_review_queue_status ON public.recruiter_review_queue(status);
CREATE INDEX IF NOT EXISTS idx_review_queue_priority ON public.recruiter_review_queue(priority);
CREATE INDEX IF NOT EXISTS idx_review_queue_assigned ON public.recruiter_review_queue(assigned_to);

-- -----------------------------------------------------------------------------
-- 11. SEED PERMISSIONS
-- -----------------------------------------------------------------------------
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('recruiter.dashboard.view', 'View Recruiter Dashboard', 'Access organization dashboard metrics and analytics', 'recruitment'),
    ('candidates.screen', 'Screen Candidates', 'Execute single and bulk candidate CV screening runs', 'recruitment'),
    ('candidates.rank', 'Rank Candidates', 'View and sort candidate rankings and comparative match scores', 'recruitment'),
    ('candidates.shortlist', 'Manage Shortlists', 'Add, remove, and manage shortlisted candidates for jobs', 'recruitment'),
    ('candidates.bulk_action', 'Execute Bulk Actions', 'Perform bulk status transitions, shortlisting, or rejections', 'recruitment'),
    ('talent_pools.manage', 'Manage Talent Pools', 'Create and administer manual and smart talent pools and rules', 'recruitment'),
    ('saved_searches.manage', 'Manage Saved Searches', 'Save, share, and update candidate search filter configurations', 'recruitment'),
    ('reviews.manage', 'Manage Review Queue', 'Assign and resolve items in the recruiter human review queue', 'recruitment')
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;

-- Assign permissions to recruiter roles
WITH new_perms AS (
    SELECT id, key FROM public.permissions WHERE category = 'recruitment'
),
target_roles AS (
    SELECT id, key FROM public.roles WHERE key IN ('platform_admin', 'platform_operations', 'recruiter_manager', 'recruiter')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM target_roles r
CROSS JOIN new_perms p
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 12. RPC FUNCTIONS: RECRUITER DASHBOARDS & METRICS
-- -----------------------------------------------------------------------------

-- 12.1 Organization Recruiter Dashboard Metrics
CREATE OR REPLACE FUNCTION public.get_recruiter_dashboard_metrics(
    p_organization_id UUID,
    p_date_from TIMESTAMPTZ DEFAULT NULL,
    p_date_to TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
    active_jobs_count BIGINT,
    new_applications_count BIGINT,
    screening_count BIGINT,
    shortlisted_count BIGINT,
    assessment_count BIGINT,
    interview_count BIGINT,
    offer_count BIGINT,
    hired_count BIGINT,
    rejected_count BIGINT,
    avg_match_score NUMERIC,
    unreviewed_candidates_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Authorization check
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(p_organization_id, 'recruiter.dashboard.view', auth.uid())
        OR public.has_org_permission(p_organization_id, 'applications.read', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: caller does not have permission to view dashboard for organization %', p_organization_id;
    END IF;

    RETURN QUERY
    WITH filtered_apps AS (
        SELECT app.status, app.match_score
        FROM public.applications app
        WHERE app.organization_id = p_organization_id
          AND (p_date_from IS NULL OR app.created_at >= p_date_from)
          AND (p_date_to IS NULL OR app.created_at <= p_date_to)
    ),
    org_jobs AS (
        SELECT count(*) AS active_count
        FROM public.jobs j
        WHERE j.organization_id = p_organization_id
          AND j.status = 'published'
    ),
    org_shortlists AS (
        SELECT count(*) AS short_count
        FROM public.candidate_shortlists cs
        WHERE cs.organization_id = p_organization_id
          AND cs.status = 'active'
          AND (p_date_from IS NULL OR cs.created_at >= p_date_from)
          AND (p_date_to IS NULL OR cs.created_at <= p_date_to)
    ),
    org_reviews AS (
        SELECT count(*) AS rev_count
        FROM public.recruiter_review_queue rrq
        WHERE rrq.organization_id = p_organization_id
          AND rrq.status IN ('open', 'in_progress')
    )
    SELECT
        COALESCE((SELECT active_count FROM org_jobs), 0)::BIGINT AS active_jobs_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'submitted'), 0)::BIGINT AS new_applications_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'screening'), 0)::BIGINT AS screening_count,
        COALESCE((SELECT short_count FROM org_shortlists), 0)::BIGINT AS shortlisted_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'assessment'), 0)::BIGINT AS assessment_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'interview'), 0)::BIGINT AS interview_count,
        COALESCE(COUNT(*) FILTER (WHERE status IN ('offer_pending', 'offer_sent', 'offer_accepted')), 0)::BIGINT AS offer_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'hired'), 0)::BIGINT AS hired_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'rejected'), 0)::BIGINT AS rejected_count,
        COALESCE(ROUND(AVG(match_score), 2), 0.0) AS avg_match_score,
        COALESCE((SELECT rev_count FROM org_reviews), 0)::BIGINT AS unreviewed_candidates_count
    FROM filtered_apps;
END;
$$;

-- 12.2 Job-Specific Recruiter Dashboard
CREATE OR REPLACE FUNCTION public.get_job_recruiter_dashboard(p_job_id UUID)
RETURNS TABLE (
    job_id UUID,
    job_title TEXT,
    job_status TEXT,
    applications_count BIGINT,
    screening_count BIGINT,
    shortlisted_count BIGINT,
    assessment_count BIGINT,
    interview_count BIGINT,
    offer_count BIGINT,
    hired_count BIGINT,
    rejected_count BIGINT,
    average_match_score NUMERIC,
    high_match_candidates_count BIGINT,
    unreviewed_candidates_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    -- Authorization check
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'jobs.manage', auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'applications.read', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: caller cannot view metrics for job %', p_job_id;
    END IF;

    RETURN QUERY
    WITH job_apps AS (
        SELECT app.status, app.match_score
        FROM public.applications app
        WHERE app.job_id = p_job_id
    ),
    job_shortlists AS (
        SELECT count(*) AS short_count
        FROM public.candidate_shortlists cs
        WHERE cs.job_id = p_job_id AND cs.status = 'active'
    ),
    job_reviews AS (
        SELECT count(*) AS rev_count
        FROM public.recruiter_review_queue rrq
        WHERE rrq.job_id = p_job_id AND rrq.status IN ('open', 'in_progress')
    )
    SELECT
        v_job.id AS job_id,
        v_job.title AS job_title,
        v_job.status AS job_status,
        COALESCE(COUNT(*), 0)::BIGINT AS applications_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'screening'), 0)::BIGINT AS screening_count,
        COALESCE((SELECT short_count FROM job_shortlists), 0)::BIGINT AS shortlisted_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'assessment'), 0)::BIGINT AS assessment_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'interview'), 0)::BIGINT AS interview_count,
        COALESCE(COUNT(*) FILTER (WHERE status IN ('offer_pending', 'offer_sent', 'offer_accepted')), 0)::BIGINT AS offer_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'hired'), 0)::BIGINT AS hired_count,
        COALESCE(COUNT(*) FILTER (WHERE status = 'rejected'), 0)::BIGINT AS rejected_count,
        COALESCE(ROUND(AVG(match_score), 2), 0.0) AS average_match_score,
        COALESCE(COUNT(*) FILTER (WHERE match_score >= 80), 0)::BIGINT AS high_match_candidates_count,
        COALESCE((SELECT rev_count FROM job_reviews), 0)::BIGINT AS unreviewed_candidates_count
    FROM job_apps;
END;
$$;

-- 12.3 Recruiter Candidate Summary View
CREATE OR REPLACE FUNCTION public.get_recruiter_candidate_summary(
    p_candidate_id UUID,
    p_job_id UUID DEFAULT NULL
)
RETURNS TABLE (
    candidate_id UUID,
    full_name TEXT,
    headline TEXT,
    location_text TEXT,
    country_code VARCHAR,
    city TEXT,
    profile_completion INT,
    years_of_experience NUMERIC,
    key_skills TEXT[],
    languages TEXT[],
    education_level TEXT,
    latest_cv_analysis_status TEXT,
    latest_match_score NUMERIC,
    latest_application_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_cand RECORD;
    v_prof RECORD;
    v_skills TEXT[];
    v_langs TEXT[];
    v_edu TEXT;
    v_cv_status TEXT;
    v_match_score NUMERIC;
    v_app_status TEXT;
BEGIN
    SELECT * INTO v_cand FROM public.candidates WHERE id = p_candidate_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate % not found', p_candidate_id;
    END IF;

    -- Verify recruiter has read access
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_candidate_read_access(p_candidate_id, auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot view candidate summary for %', p_candidate_id;
    END IF;

    SELECT * INTO v_prof FROM public.candidate_profiles WHERE candidate_id = p_candidate_id;

    -- Collect top 10 skills
    SELECT ARRAY_AGG(skill_name) INTO v_skills
    FROM (
        SELECT skill_name FROM public.candidate_skills
        WHERE candidate_id = p_candidate_id
        ORDER BY years_of_experience DESC NULLS LAST
        LIMIT 10
    ) s;

    -- Collect languages
    SELECT ARRAY_AGG(language_name || ' (' || proficiency_level || ')') INTO v_langs
    FROM public.candidate_languages
    WHERE candidate_id = p_candidate_id;

    -- Highest education
    SELECT degree INTO v_edu
    FROM public.candidate_education
    WHERE candidate_id = p_candidate_id
    ORDER BY end_date DESC NULLS LAST
    LIMIT 1;

    -- Latest CV Analysis status
    SELECT status INTO v_cv_status
    FROM public.cv_processing_jobs
    WHERE candidate_id = p_candidate_id
    ORDER BY created_at DESC
    LIMIT 1;

    -- Latest match score for job or generally
    IF p_job_id IS NOT NULL THEN
        SELECT final_score INTO v_match_score
        FROM public.matching_runs
        WHERE candidate_id = p_candidate_id AND job_id = p_job_id
        ORDER BY created_at DESC
        LIMIT 1;

        SELECT status INTO v_app_status
        FROM public.applications
        WHERE candidate_id = p_candidate_id AND job_id = p_job_id
        LIMIT 1;
    ELSE
        SELECT final_score INTO v_match_score
        FROM public.matching_runs
        WHERE candidate_id = p_candidate_id
        ORDER BY created_at DESC
        LIMIT 1;

        SELECT status INTO v_app_status
        FROM public.applications
        WHERE candidate_id = p_candidate_id
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    RETURN QUERY
    SELECT
        v_cand.id AS candidate_id,
        COALESCE((SELECT p.full_name FROM public.profiles p WHERE p.id = v_cand.user_id), 'Candidate ' || substr(v_cand.id::text, 1, 8)) AS full_name,
        v_prof.headline,
        v_prof.location_text,
        v_prof.country_code,
        v_prof.city,
        v_cand.profile_completion_percentage,
        v_prof.years_of_experience,
        COALESCE(v_skills, ARRAY[]::TEXT[]),
        COALESCE(v_langs, ARRAY[]::TEXT[]),
        COALESCE(v_edu, 'Not recorded'),
        COALESCE(v_cv_status, 'none'),
        v_match_score,
        v_app_status;
END;
$$;

-- -----------------------------------------------------------------------------
-- 13. RPC FUNCTIONS: BULK CV SCREENING
-- -----------------------------------------------------------------------------

-- 13.1 Create Bulk Screening Run
CREATE OR REPLACE FUNCTION public.create_bulk_screening_run(
    p_job_id UUID,
    p_matching_profile_id UUID DEFAULT NULL,
    p_candidate_ids UUID[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
    v_run_id UUID;
    v_count INT := 0;
    r_cand RECORD;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'candidates.screen', auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'jobs.manage', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: caller cannot screen candidates for job %', p_job_id;
    END IF;

    -- Create run record
    INSERT INTO public.bulk_screening_runs (
        organization_id,
        job_id,
        created_by,
        matching_profile_id,
        status,
        started_at
    )
    VALUES (
        v_job.organization_id,
        p_job_id,
        auth.uid(),
        p_matching_profile_id,
        'queued',
        now()
    )
    RETURNING id INTO v_run_id;

    -- Queue candidates: either provided list, or all active applicants to the job
    IF p_candidate_ids IS NOT NULL AND cardinality(p_candidate_ids) > 0 THEN
        FOR r_cand IN
            SELECT c.id AS cand_id, a.id AS app_id
            FROM unnest(p_candidate_ids) AS cid
            JOIN public.candidates c ON c.id = cid
            LEFT JOIN public.applications a ON a.candidate_id = c.id AND a.job_id = p_job_id
        LOOP
            INSERT INTO public.bulk_screening_candidates (
                bulk_screening_run_id, candidate_id, application_id, status
            )
            VALUES (v_run_id, r_cand.cand_id, r_cand.app_id, 'queued')
            ON CONFLICT (bulk_screening_run_id, candidate_id) DO NOTHING;
            v_count := v_count + 1;
        END LOOP;
    ELSE
        -- Queue all candidates who applied to this job
        FOR r_cand IN
            SELECT a.candidate_id AS cand_id, a.id AS app_id
            FROM public.applications a
            WHERE a.job_id = p_job_id
              AND a.status NOT IN ('hired', 'rejected', 'withdrawn')
        LOOP
            INSERT INTO public.bulk_screening_candidates (
                bulk_screening_run_id, candidate_id, application_id, status
            )
            VALUES (v_run_id, r_cand.cand_id, r_cand.app_id, 'queued')
            ON CONFLICT (bulk_screening_run_id, candidate_id) DO NOTHING;
            v_count := v_count + 1;
        END LOOP;
    END IF;

    UPDATE public.bulk_screening_runs
    SET candidate_count = v_count
    WHERE id = v_run_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        actor_user_id, organization_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        auth.uid(), v_job.organization_id, 'bulk_screening_started', 'bulk_screening_run', v_run_id,
        jsonb_build_object('job_id', p_job_id, 'candidate_count', v_count)
    );

    RETURN v_run_id;
END;
$$;

-- 13.2 Process Bulk Screening Run (Batch Evaluation)
CREATE OR REPLACE FUNCTION public.process_bulk_screening_run(
    p_bulk_screening_run_id UUID,
    p_batch_size INT DEFAULT 50
)
RETURNS TABLE (
    processed INT,
    matched INT,
    rejected INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_run RECORD;
    r_item RECORD;
    v_matching_run_id UUID;
    v_mr RECORD;
    v_summary_text TEXT;
    v_rec_val TEXT;
    v_processed INT := 0;
    v_matched INT := 0;
    v_rejected INT := 0;
BEGIN
    SELECT * INTO v_run FROM public.bulk_screening_runs WHERE id = p_bulk_screening_run_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bulk screening run % not found', p_bulk_screening_run_id;
    END IF;

    UPDATE public.bulk_screening_runs
    SET status = 'processing', updated_at = now()
    WHERE id = p_bulk_screening_run_id;

    FOR r_item IN
        SELECT bsc.id AS bsc_id, bsc.candidate_id, bsc.application_id
        FROM public.bulk_screening_candidates bsc
        WHERE bsc.bulk_screening_run_id = p_bulk_screening_run_id
          AND bsc.status = 'queued'
        LIMIT p_batch_size
    LOOP
        BEGIN
            -- Call Task 06 Matching Engine
            v_matching_run_id := public.calculate_candidate_job_match(
                p_candidate_id => r_item.candidate_id,
                p_job_id => v_run.job_id,
                p_application_id => r_item.application_id,
                p_matching_profile_id => v_run.matching_profile_id,
                p_engine_version => v_run.engine_version
            );

            SELECT * INTO v_mr FROM public.matching_runs WHERE id = v_matching_run_id;

            v_summary_text := format('Candidate achieved %s%% match score. Hard match: %s.', v_mr.final_score, v_mr.hard_match);

            IF v_mr.hard_match THEN
                v_matched := v_matched + 1;
                IF v_mr.final_score >= 80 THEN
                    v_rec_val := 'strong_match';
                ELSIF v_mr.final_score >= 65 THEN
                    v_rec_val := 'match';
                ELSE
                    v_rec_val := 'borderline';
                END IF;
            ELSE
                v_rejected := v_rejected + 1;
                v_rec_val := 'weak_match';
            END IF;

            -- Update candidate queue record
            UPDATE public.bulk_screening_candidates
            SET status = 'completed',
                match_score = v_mr.final_score,
                hard_match = v_mr.hard_match,
                confidence = v_mr.confidence,
                screening_summary = v_summary_text,
                updated_at = now()
            WHERE id = r_item.bsc_id;

            -- Upsert structured screening summary
            INSERT INTO public.candidate_screening_summaries (
                candidate_id, job_id, application_id, matching_run_id, summary,
                strengths, gaps, risk_flags, recommendation, confidence
            )
            VALUES (
                r_item.candidate_id, v_run.job_id, r_item.application_id, v_matching_run_id,
                v_summary_text,
                COALESCE((SELECT strengths FROM public.match_explanations WHERE matching_run_id = v_matching_run_id), ARRAY[]::TEXT[]),
                COALESCE((SELECT gaps FROM public.match_explanations WHERE matching_run_id = v_matching_run_id), ARRAY[]::TEXT[]),
                v_mr.hard_failure_reasons,
                v_rec_val,
                v_mr.confidence
            )
            ON CONFLICT (job_id, candidate_id) DO UPDATE
            SET matching_run_id = EXCLUDED.matching_run_id,
                summary = EXCLUDED.summary,
                strengths = EXCLUDED.strengths,
                gaps = EXCLUDED.gaps,
                risk_flags = EXCLUDED.risk_flags,
                recommendation = EXCLUDED.recommendation,
                confidence = EXCLUDED.confidence,
                updated_at = now();

            v_processed := v_processed + 1;
        EXCEPTION WHEN OTHERS THEN
            -- Record failure without corrupting whole batch
            UPDATE public.bulk_screening_candidates
            SET status = 'failed', screening_summary = 'Error: ' || SQLERRM, updated_at = now()
            WHERE id = r_item.bsc_id;
            v_processed := v_processed + 1;
        END;
    END LOOP;

    -- Update rank positions based on final scores
    WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY match_score DESC NULLS LAST, hard_match DESC) AS rnk
        FROM public.bulk_screening_candidates
        WHERE bulk_screening_run_id = p_bulk_screening_run_id AND status = 'completed'
    )
    UPDATE public.bulk_screening_candidates bsc
    SET rank_position = ranked.rnk
    FROM ranked
    WHERE bsc.id = ranked.id;

    -- Update overall run counters
    UPDATE public.bulk_screening_runs
    SET processed_count = processed_count + v_processed,
        matched_count = matched_count + v_matched,
        rejected_count = rejected_count + v_rejected,
        status = CASE WHEN processed_count + v_processed >= candidate_count THEN 'completed' ELSE 'processing' END,
        completed_at = CASE WHEN processed_count + v_processed >= candidate_count THEN now() ELSE NULL END,
        updated_at = now()
    WHERE id = p_bulk_screening_run_id;

    RETURN QUERY SELECT v_processed, v_matched, v_rejected;
END;
$$;

-- -----------------------------------------------------------------------------
-- 14. RPC FUNCTIONS: CANDIDATE SHORTLISTING & BULK ACTIONS
-- -----------------------------------------------------------------------------

-- 14.1 Shortlist Candidate
CREATE OR REPLACE FUNCTION public.shortlist_candidate(
    p_job_id UUID,
    p_candidate_id UUID,
    p_application_id UUID DEFAULT NULL,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
    v_shortlist_id UUID;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'candidates.shortlist', auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'jobs.manage', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot shortlist candidate for job %', p_job_id;
    END IF;

    -- If application_id is null, find existing application
    IF p_application_id IS NULL THEN
        SELECT id INTO p_application_id
        FROM public.applications
        WHERE job_id = p_job_id AND candidate_id = p_candidate_id
        LIMIT 1;
    END IF;

    INSERT INTO public.candidate_shortlists (
        organization_id, job_id, candidate_id, application_id, created_by, status, reason
    )
    VALUES (
        v_job.organization_id, p_job_id, p_candidate_id, p_application_id, auth.uid(), 'active', p_reason
    )
    ON CONFLICT (job_id, candidate_id) DO UPDATE
    SET status = 'active',
        reason = COALESCE(EXCLUDED.reason, candidate_shortlists.reason),
        updated_at = now()
    RETURNING id INTO v_shortlist_id;

    -- If attached to an application, transition application status to 'shortlisted'
    IF p_application_id IS NOT NULL THEN
        UPDATE public.applications
        SET status = 'shortlisted', shortlisted_at = now(), updated_at = now()
        WHERE id = p_application_id AND status != 'shortlisted';
    END IF;

    -- Audit log
    INSERT INTO public.audit_logs (
        actor_user_id, organization_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        auth.uid(), v_job.organization_id, 'candidate_shortlisted', 'candidate_shortlist', v_shortlist_id,
        jsonb_build_object('job_id', p_job_id, 'candidate_id', p_candidate_id, 'reason', p_reason)
    );

    RETURN v_shortlist_id;
END;
$$;

-- 14.2 Bulk Shortlist Candidates
CREATE OR REPLACE FUNCTION public.bulk_shortlist_candidates(
    p_job_id UUID,
    p_candidate_ids UUID[],
    p_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
    candidate_id UUID,
    success BOOLEAN,
    error_code TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    cid UUID;
BEGIN
    FOREACH cid IN ARRAY p_candidate_ids
    LOOP
        BEGIN
            PERFORM public.shortlist_candidate(p_job_id, cid, NULL, p_reason);
            RETURN QUERY SELECT cid, true, NULL::TEXT, NULL::TEXT;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT cid, false, SQLSTATE, SQLERRM;
        END;
    END LOOP;
END;
$$;

-- 14.3 Bulk Move Candidates (ATS Status Transition)
CREATE OR REPLACE FUNCTION public.bulk_move_candidates(
    p_job_id UUID,
    p_application_ids UUID[],
    p_new_status TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
    application_id UUID,
    success BOOLEAN,
    error_code TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
    aid UUID;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'candidates.bulk_action', auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'applications.manage', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot bulk move applications for job %', p_job_id;
    END IF;

    FOREACH aid IN ARRAY p_application_ids
    LOOP
        BEGIN
            UPDATE public.applications
            SET status = p_new_status, updated_at = now()
            WHERE id = aid AND job_id = p_job_id;

            IF FOUND THEN
                INSERT INTO public.audit_logs (
                    actor_user_id, organization_id, action, entity_type, entity_id, metadata
                )
                VALUES (
                    auth.uid(), v_job.organization_id, 'application_status_changed', 'application', aid,
                    jsonb_build_object('new_status', p_new_status, 'reason', p_reason)
                );
                RETURN QUERY SELECT aid, true, NULL::TEXT, NULL::TEXT;
            ELSE
                RETURN QUERY SELECT aid, false, 'NOT_FOUND', 'Application not found for job';
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RETURN QUERY SELECT aid, false, SQLSTATE, SQLERRM;
        END;
    END LOOP;
END;
$$;

-- 14.4 Bulk Reject Candidates
CREATE OR REPLACE FUNCTION public.bulk_reject_candidates(
    p_job_id UUID,
    p_application_ids UUID[],
    p_reason TEXT DEFAULT NULL
)
RETURNS TABLE (
    application_id UUID,
    success BOOLEAN,
    error_code TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.bulk_move_candidates(p_job_id, p_application_ids, 'rejected', p_reason);
END;
$$;

-- -----------------------------------------------------------------------------
-- 15. RPC FUNCTIONS: TALENT POOLS & SMART RULE EVALUATION
-- -----------------------------------------------------------------------------

-- 15.1 Evaluate Smart Talent Pool
CREATE OR REPLACE FUNCTION public.evaluate_talent_pool(p_talent_pool_id UUID)
RETURNS TABLE (
    added_count INT,
    removed_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pool RECORD;
    r_cand RECORD;
    v_added INT := 0;
    v_removed INT := 0;
    v_match BOOLEAN;
    r_rule RECORD;
    v_years NUMERIC;
    v_has_skill BOOLEAN;
    v_has_lang BOOLEAN;
    v_score NUMERIC;
BEGIN
    SELECT * INTO v_pool FROM public.talent_pools WHERE id = p_talent_pool_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Talent pool % not found', p_talent_pool_id;
    END IF;

    -- Iterate over candidates
    FOR r_cand IN
        SELECT c.id, cp.years_of_experience, cp.country_code,
               COALESCE((SELECT ccp.career_level_estimate FROM public.candidate_cv_profiles ccp WHERE ccp.candidate_id = c.id ORDER BY ccp.created_at DESC LIMIT 1), 'mid') AS career_level_estimate
        FROM public.candidates c
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        WHERE c.status = 'active'
    LOOP
        v_match := true;

        -- Evaluate all rules defined for this pool
        FOR r_rule IN
            SELECT * FROM public.talent_pool_rules WHERE talent_pool_id = p_talent_pool_id
        LOOP
            CASE r_rule.rule_type
                WHEN 'experience_years' THEN
                    v_years := COALESCE(r_cand.years_of_experience, 0);
                    IF r_rule.operator = 'greater_than_or_equal' AND v_years < (r_rule.value)::NUMERIC THEN
                        v_match := false;
                    ELSIF r_rule.operator = 'less_than_or_equal' AND v_years > (r_rule.value)::NUMERIC THEN
                        v_match := false;
                    END IF;

                WHEN 'skill' THEN
                    SELECT EXISTS (
                        SELECT 1 FROM public.candidate_skills cs
                        WHERE cs.candidate_id = r_cand.id
                          AND (
                              lower(cs.skill_name) = lower(r_rule.value)
                              OR public.normalize_skill_text(cs.skill_name) = public.normalize_skill_text(r_rule.value)
                          )
                    ) INTO v_has_skill;
                    IF NOT v_has_skill THEN
                        v_match := false;
                    END IF;

                WHEN 'language' THEN
                    SELECT EXISTS (
                        SELECT 1 FROM public.candidate_languages cl
                        WHERE cl.candidate_id = r_cand.id
                          AND lower(cl.language_name) = lower(r_rule.value)
                    ) INTO v_has_lang;
                    IF NOT v_has_lang THEN
                        v_match := false;
                    END IF;

                WHEN 'match_score' THEN
                    SELECT MAX(final_score) INTO v_score
                    FROM public.matching_runs mr
                    WHERE mr.candidate_id = r_cand.id;
                    IF v_score IS NULL OR v_score < (r_rule.value)::NUMERIC THEN
                        v_match := false;
                    END IF;

                ELSE
                    -- Default fallback: ignore unknown rule type
            END CASE;

            IF NOT v_match THEN
                EXIT; -- No need to check further rules for this candidate
            END IF;
        END LOOP;

        IF v_match THEN
            -- Candidate matches: insert if not present
            IF NOT EXISTS (
                SELECT 1 FROM public.talent_pool_members
                WHERE talent_pool_id = p_talent_pool_id AND candidate_id = r_cand.id AND status = 'active'
            ) THEN
                INSERT INTO public.talent_pool_members (
                    talent_pool_id, candidate_id, source, status, notes
                )
                VALUES (p_talent_pool_id, r_cand.id, 'smart_rule', 'active', 'Matched smart talent pool rules')
                ON CONFLICT (talent_pool_id, candidate_id) DO UPDATE
                SET status = 'active', updated_at = now();

                INSERT INTO public.talent_pool_membership_events (
                    talent_pool_id, candidate_id, event_type, reason
                )
                VALUES (p_talent_pool_id, r_cand.id, 'entered', 'Candidate satisfied smart pool rules');

                v_added := v_added + 1;
            END IF;
        ELSE
            -- Candidate does NOT match: if dynamic pool, remove candidate
            IF v_pool.is_dynamic AND EXISTS (
                SELECT 1 FROM public.talent_pool_members
                WHERE talent_pool_id = p_talent_pool_id AND candidate_id = r_cand.id AND status = 'active'
            ) THEN
                UPDATE public.talent_pool_members
                SET status = 'removed', updated_at = now()
                WHERE talent_pool_id = p_talent_pool_id AND candidate_id = r_cand.id;

                INSERT INTO public.talent_pool_membership_events (
                    talent_pool_id, candidate_id, event_type, reason
                )
                VALUES (p_talent_pool_id, r_cand.id, 'exited', 'Candidate no longer satisfies smart pool rules');

                v_removed := v_removed + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_added, v_removed;
END;
$$;

-- 15.2 Add Candidate to Talent Pool Manually
CREATE OR REPLACE FUNCTION public.add_candidate_to_talent_pool(
    p_talent_pool_id UUID,
    p_candidate_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pool RECORD;
    v_member_id UUID;
BEGIN
    SELECT * INTO v_pool FROM public.talent_pools WHERE id = p_talent_pool_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Talent pool % not found', p_talent_pool_id;
    END IF;

    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_pool.organization_id, 'talent_pools.manage', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot manage talent pool for organization %', v_pool.organization_id;
    END IF;

    INSERT INTO public.talent_pool_members (
        talent_pool_id, candidate_id, added_by, source, status, notes
    )
    VALUES (
        p_talent_pool_id, p_candidate_id, auth.uid(), 'manual', 'active', p_notes
    )
    ON CONFLICT (talent_pool_id, candidate_id) DO UPDATE
    SET status = 'active',
        notes = COALESCE(EXCLUDED.notes, talent_pool_members.notes),
        updated_at = now()
    RETURNING id INTO v_member_id;

    INSERT INTO public.talent_pool_membership_events (
        talent_pool_id, candidate_id, event_type, reason
    )
    VALUES (p_talent_pool_id, p_candidate_id, 'manually_added', p_notes);

    RETURN v_member_id;
END;
$$;

-- 15.3 Get Talent Pool Candidates (Paginated)
CREATE OR REPLACE FUNCTION public.get_talent_pool_candidates(
    p_talent_pool_id UUID,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    candidate_id UUID,
    full_name TEXT,
    headline TEXT,
    years_of_experience NUMERIC,
    country_code VARCHAR,
    city TEXT,
    membership_source TEXT,
    joined_at TIMESTAMPTZ,
    notes TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pool RECORD;
BEGIN
    SELECT * INTO v_pool FROM public.talent_pools WHERE id = p_talent_pool_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Talent pool % not found', p_talent_pool_id;
    END IF;

    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_pool.organization_id, 'talent_pools.manage', auth.uid())
        OR public.has_org_permission(v_pool.organization_id, 'candidates.rank', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot view talent pool candidates for %', p_talent_pool_id;
    END IF;

    RETURN QUERY
    SELECT
        c.id AS candidate_id,
        COALESCE(p.full_name, 'Candidate ' || substr(c.id::text, 1, 8)) AS full_name,
        cp.headline,
        cp.years_of_experience,
        cp.country_code,
        cp.city,
        tpm.source AS membership_source,
        tpm.created_at AS joined_at,
        tpm.notes
    FROM public.talent_pool_members tpm
    JOIN public.candidates c ON c.id = tpm.candidate_id
    LEFT JOIN public.profiles p ON p.id = c.user_id
    LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
    WHERE tpm.talent_pool_id = p_talent_pool_id
      AND tpm.status = 'active'
    ORDER BY tpm.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- -----------------------------------------------------------------------------
-- 16. RPC FUNCTIONS: RECRUITER SEARCH & CANDIDATE FILTERING
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.search_recruiter_candidates(
    p_organization_id UUID,
    p_filters JSONB DEFAULT '{}'::jsonb,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    candidate_id UUID,
    full_name TEXT,
    headline TEXT,
    years_of_experience NUMERIC,
    country_code VARCHAR,
    city TEXT,
    profile_completion INT,
    latest_match_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_skill_filter TEXT;
    v_min_exp NUMERIC;
    v_min_score NUMERIC;
    v_country TEXT;
BEGIN
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(p_organization_id, 'candidates.rank', auth.uid())
        OR public.has_org_permission(p_organization_id, 'applications.read', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot search candidates for organization %', p_organization_id;
    END IF;

    v_skill_filter := p_filters->>'skill';
    v_min_exp := (p_filters->>'min_experience')::NUMERIC;
    v_min_score := (p_filters->>'min_match_score')::NUMERIC;
    v_country := p_filters->>'country';

    RETURN QUERY
    SELECT
        c.id AS candidate_id,
        COALESCE(p.full_name, 'Candidate ' || substr(c.id::text, 1, 8)) AS full_name,
        cp.headline,
        cp.years_of_experience,
        cp.country_code,
        cp.city,
        c.profile_completion_percentage AS profile_completion,
        (
            SELECT MAX(mr.final_score)
            FROM public.matching_runs mr
            WHERE mr.candidate_id = c.id
        ) AS latest_match_score
    FROM public.candidates c
    LEFT JOIN public.profiles p ON p.id = c.user_id
    LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
    WHERE c.status = 'active'
      AND (v_country IS NULL OR lower(cp.country_code) = lower(v_country))
      AND (v_min_exp IS NULL OR cp.years_of_experience >= v_min_exp)
      AND (
          v_skill_filter IS NULL OR EXISTS (
              SELECT 1 FROM public.candidate_skills cs
              WHERE cs.candidate_id = c.id
                AND (
                    lower(cs.skill_name) = lower(v_skill_filter)
                    OR public.normalize_skill_text(cs.skill_name) = public.normalize_skill_text(v_skill_filter)
                )
          )
      )
      AND (
          v_min_score IS NULL OR EXISTS (
              SELECT 1 FROM public.matching_runs mr
              WHERE mr.candidate_id = c.id AND mr.final_score >= v_min_score
          )
      )
    ORDER BY latest_match_score DESC NULLS LAST, c.profile_completion_percentage DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- -----------------------------------------------------------------------------
-- 17. RPC FUNCTIONS: RECRUITER HUMAN REVIEW QUEUE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_candidates_needing_review(
    p_organization_id UUID,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    review_id UUID,
    candidate_id UUID,
    candidate_name TEXT,
    job_id UUID,
    job_title TEXT,
    reason TEXT,
    priority TEXT,
    status TEXT,
    assigned_to_name TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(p_organization_id, 'reviews.manage', auth.uid())
        OR public.has_org_permission(p_organization_id, 'applications.read', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot view review queue for organization %', p_organization_id;
    END IF;

    RETURN QUERY
    SELECT
        rrq.id AS review_id,
        rrq.candidate_id,
        COALESCE(p.full_name, 'Candidate ' || substr(c.id::text, 1, 8)) AS candidate_name,
        rrq.job_id,
        j.title AS job_title,
        rrq.reason,
        rrq.priority,
        rrq.status,
        ap.full_name AS assigned_to_name,
        rrq.created_at
    FROM public.recruiter_review_queue rrq
    JOIN public.candidates c ON c.id = rrq.candidate_id
    LEFT JOIN public.profiles p ON p.id = c.user_id
    LEFT JOIN public.jobs j ON j.id = rrq.job_id
    LEFT JOIN public.profiles ap ON ap.id = rrq.assigned_to
    WHERE rrq.organization_id = p_organization_id
      AND rrq.status IN ('open', 'in_progress')
    ORDER BY
        CASE rrq.priority
            WHEN 'urgent' THEN 1
            WHEN 'high' THEN 2
            WHEN 'medium' THEN 3
            WHEN 'low' THEN 4
            ELSE 5
        END,
        rrq.created_at ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_candidate_review(
    p_review_id UUID,
    p_resolution_notes TEXT,
    p_new_status TEXT DEFAULT 'resolved'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rev RECORD;
BEGIN
    SELECT * INTO v_rev FROM public.recruiter_review_queue WHERE id = p_review_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Review item % not found', p_review_id;
    END IF;

    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_rev.organization_id, 'reviews.manage', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot resolve review for organization %', v_rev.organization_id;
    END IF;

    UPDATE public.recruiter_review_queue
    SET status = p_new_status,
        resolution_notes = p_resolution_notes,
        resolved_at = now(),
        updated_at = now()
    WHERE id = p_review_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        actor_user_id, organization_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        auth.uid(), v_rev.organization_id, 'candidate_review_resolved', 'review_queue', p_review_id,
        jsonb_build_object('status', p_new_status, 'notes', p_resolution_notes)
    );

    RETURN p_review_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 18. ROW LEVEL SECURITY (RLS) POLICIES
-- -----------------------------------------------------------------------------

ALTER TABLE public.bulk_screening_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bulk_screening_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_shortlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.talent_pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.talent_pool_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.talent_pool_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.talent_pool_membership_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recruiter_saved_searches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_screening_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recruiter_review_queue ENABLE ROW LEVEL SECURITY;

-- 18.1 bulk_screening_runs
CREATE POLICY bulk_screening_runs_select_policy ON public.bulk_screening_runs
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'candidates.screen', auth.uid())
    );

CREATE POLICY bulk_screening_runs_modify_policy ON public.bulk_screening_runs
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'candidates.screen', auth.uid())
    );

-- 18.2 bulk_screening_candidates
CREATE POLICY bulk_screening_candidates_select_policy ON public.bulk_screening_candidates
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.bulk_screening_runs bsr
            WHERE bsr.id = bulk_screening_candidates.bulk_screening_run_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.has_org_permission(bsr.organization_id, 'candidates.screen', auth.uid())
              )
        )
    );

-- 18.3 candidate_shortlists
CREATE POLICY candidate_shortlists_select_policy ON public.candidate_shortlists
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'candidates.shortlist', auth.uid())
        OR public.has_org_permission(organization_id, 'applications.read', auth.uid())
    );

CREATE POLICY candidate_shortlists_modify_policy ON public.candidate_shortlists
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'candidates.shortlist', auth.uid())
    );

-- 18.4 talent_pools
CREATE POLICY talent_pools_select_policy ON public.talent_pools
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.is_org_member(auth.uid(), organization_id)
    );

CREATE POLICY talent_pools_modify_policy ON public.talent_pools
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'talent_pools.manage', auth.uid())
    );

-- 18.5 talent_pool_members
CREATE POLICY talent_pool_members_select_policy ON public.talent_pool_members
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.talent_pools tp
            WHERE tp.id = talent_pool_members.talent_pool_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.is_org_member(auth.uid(), tp.organization_id)
              )
        )
    );

CREATE POLICY talent_pool_members_modify_policy ON public.talent_pool_members
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.talent_pools tp
            WHERE tp.id = talent_pool_members.talent_pool_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.has_org_permission(tp.organization_id, 'talent_pools.manage', auth.uid())
              )
        )
    );

-- 18.6 talent_pool_rules
CREATE POLICY talent_pool_rules_select_policy ON public.talent_pool_rules
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.talent_pools tp
            WHERE tp.id = talent_pool_rules.talent_pool_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.is_org_member(auth.uid(), tp.organization_id)
              )
        )
    );

CREATE POLICY talent_pool_rules_modify_policy ON public.talent_pool_rules
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.talent_pools tp
            WHERE tp.id = talent_pool_rules.talent_pool_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.has_org_permission(tp.organization_id, 'talent_pools.manage', auth.uid())
              )
        )
    );

-- 18.7 talent_pool_membership_events
CREATE POLICY talent_pool_membership_events_select_policy ON public.talent_pool_membership_events
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.talent_pools tp
            WHERE tp.id = talent_pool_membership_events.talent_pool_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.is_org_member(auth.uid(), tp.organization_id)
              )
        )
    );

-- 18.8 recruiter_saved_searches
CREATE POLICY recruiter_saved_searches_select_policy ON public.recruiter_saved_searches
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR created_by = auth.uid()
        OR (is_shared = true AND public.is_org_member(auth.uid(), organization_id))
    );

CREATE POLICY recruiter_saved_searches_modify_policy ON public.recruiter_saved_searches
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR created_by = auth.uid()
        OR public.has_org_permission(organization_id, 'saved_searches.manage', auth.uid())
    );

-- 18.9 candidate_screening_summaries
CREATE POLICY candidate_screening_summaries_select_policy ON public.candidate_screening_summaries
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = candidate_screening_summaries.job_id
              AND public.has_org_permission(j.organization_id, 'candidates.screen', auth.uid())
        )
    );

-- 18.10 recruiter_review_queue
CREATE POLICY recruiter_review_queue_select_policy ON public.recruiter_review_queue
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'reviews.manage', auth.uid())
        OR public.has_org_permission(organization_id, 'applications.read', auth.uid())
    );

CREATE POLICY recruiter_review_queue_modify_policy ON public.recruiter_review_queue
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(organization_id, 'reviews.manage', auth.uid())
    );
