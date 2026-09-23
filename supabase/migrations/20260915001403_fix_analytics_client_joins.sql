-- =============================================================================
-- Migration: 20260915001403_fix_analytics_client_joins.sql
-- Description: Align client portal analytics joins with Task 10 schema
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_organization_analytics(
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
    v_overview          JSONB;
    v_funnel            JSONB;
    v_time_metrics      JSONB;
    v_match_metrics     JSONB;
    v_assess_metrics    JSONB;
    v_interview_metrics JSONB;
    v_source_metrics    JSONB;
    v_client_metrics    JSONB;
    v_ai_metrics        JSONB;
    v_comm_metrics      JSONB;
    v_caller_id         UUID := auth.uid();
BEGIN
    -- Verify organization membership and role
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(v_caller_id) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not a recruiter or admin for organization %', p_organization_id;
    END IF;

    -- 1. High-level Overview
    SELECT jsonb_build_object(
        'total_jobs', count(DISTINCT j.id),
        'active_jobs', count(DISTINCT j.id) FILTER (WHERE j.status = 'published'),
        'total_applications', count(DISTINCT a.id),
        'active_applications', count(DISTINCT a.id) FILTER (WHERE a.status NOT IN ('rejected', 'withdrawn', 'archived', 'hired')),
        'hired_count', count(DISTINCT a.id) FILTER (WHERE a.status = 'hired' OR a.hired_at IS NOT NULL)
    ) INTO v_overview
    FROM public.jobs j
    LEFT JOIN public.applications a ON a.job_id = j.id
    WHERE j.organization_id = p_organization_id
      AND (p_job_id IS NULL OR j.id = p_job_id);

    -- 2. Stage Funnel Conversion
    v_funnel := public.get_recruitment_funnel(p_organization_id, p_job_id, p_date_from, p_date_to);

    -- 3. Time Metrics
    v_time_metrics := public.get_recruitment_time_metrics(p_organization_id, p_job_id, p_date_from, p_date_to);

    -- 4. Matching Engine Insights (from Task 06)
    SELECT jsonb_build_object(
        'total_matching_runs', count(*),
        'average_match_score', round(avg(mr.final_score)::numeric, 1),
        'candidates_above_70', count(*) FILTER (WHERE mr.final_score >= 70),
        'candidates_above_85', count(*) FILTER (WHERE mr.final_score >= 85)
    ) INTO v_match_metrics
    FROM public.matching_runs mr
    JOIN public.jobs j ON j.id = mr.job_id
    WHERE j.organization_id = p_organization_id
      AND (p_job_id IS NULL OR j.id = p_job_id)
      AND (p_date_from IS NULL OR mr.created_at >= p_date_from)
      AND (p_date_to IS NULL OR mr.created_at <= p_date_to);

    -- 5. Assessments Telemetry (from Task 08)
    SELECT jsonb_build_object(
        'invitations_sent', count(DISTINCT ai.id),
        'assessments_completed', count(DISTINCT att.id) FILTER (WHERE att.status = 'completed'),
        'assessments_passed', count(DISTINCT ar.id) FILTER (WHERE ar.passed = true),
        'average_normalized_score', round(avg(ar.normalized_score)::numeric, 1)
    ) INTO v_assess_metrics
    FROM public.assessment_invitations ai
    JOIN public.applications a ON a.id = ai.application_id
    LEFT JOIN public.assessment_attempts att ON att.assessment_invitation_id = ai.id
    LEFT JOIN public.assessment_results ar ON ar.assessment_attempt_id = att.id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR ai.created_at >= p_date_from)
      AND (p_date_to IS NULL OR ai.created_at <= p_date_to);

    -- 6. Interviews Telemetry (from Task 09)
    SELECT jsonb_build_object(
        'scheduled_interviews', count(*),
        'completed_interviews', count(*) FILTER (WHERE i.status = 'completed'),
        'cancelled_interviews', count(*) FILTER (WHERE i.status = 'cancelled'),
        'completed_feedback', count(DISTINCT fb.id),
        'average_interview_rating', round(avg(fb.overall_rating)::numeric, 1)
    ) INTO v_interview_metrics
    FROM public.interviews i
    LEFT JOIN public.interview_feedback fb ON fb.interview_id = i.id
    WHERE i.organization_id = p_organization_id
      AND (p_job_id IS NULL OR i.job_id = p_job_id)
      AND (p_date_from IS NULL OR i.created_at >= p_date_from)
      AND (p_date_to IS NULL OR i.created_at <= p_date_to);

    -- 7. Candidate Sources Breakdown
    SELECT COALESCE(jsonb_object_agg(source, cnt), '{}'::jsonb) INTO v_source_metrics
    FROM (
        SELECT a.source, count(*) AS cnt
        FROM public.applications a
        WHERE a.organization_id = p_organization_id
          AND (p_job_id IS NULL OR a.job_id = p_job_id)
          AND (p_date_from IS NULL OR a.submitted_at >= p_date_from)
          AND (p_date_to IS NULL OR a.submitted_at <= p_date_to)
        GROUP BY a.source
    ) source_data;

    -- 8. Client Portal Collaboration (from Task 10)
    SELECT jsonb_build_object(
        'candidates_presented', count(DISTINCT cs.id),
        'candidates_reviewed', count(DISTINCT ccf.id),
        'interview_requests', count(DISTINCT ir.id),
        'client_hires', count(DISTINCT chd.id) FILTER (WHERE chd.decision = 'recommend_hire')
    ) INTO v_client_metrics
    FROM public.client_candidate_shares cs
    JOIN public.applications a ON a.id = cs.application_id
    LEFT JOIN public.client_candidate_feedback ccf ON ccf.client_candidate_share_id = cs.id
    LEFT JOIN public.client_interview_requests ir ON ir.client_candidate_share_id = cs.id
    LEFT JOIN public.client_hiring_decisions chd ON chd.client_candidate_share_id = cs.id
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_date_from IS NULL OR cs.created_at >= p_date_from)
      AND (p_date_to IS NULL OR cs.created_at <= p_date_to);

    -- 9. AI Usage Telemetry (from Task 12)
    SELECT jsonb_build_object(
        'total_ai_actions', count(*),
        'successful_ai_actions', count(*) FILTER (WHERE execution_status = 'success'),
        'total_tokens_consumed', COALESCE(sum(total_tokens), 0),
        'approximate_cost_usd', round(COALESCE(sum(estimated_cost_usd), 0)::numeric, 4)
    ) INTO v_ai_metrics
    FROM public.ai_action_logs
    WHERE organization_id = p_organization_id
      AND (p_date_from IS NULL OR created_at >= p_date_from)
      AND (p_date_to IS NULL OR created_at <= p_date_to);

    -- 10. Communication Outbox (from Task 11)
    SELECT jsonb_build_object(
        'total_messages_queued', count(*),
        'messages_delivered', count(*) FILTER (WHERE status = 'delivered'),
        'messages_failed', count(*) FILTER (WHERE status = 'failed')
    ) INTO v_comm_metrics
    FROM public.notification_outbox
    WHERE organization_id = p_organization_id
      AND (p_date_from IS NULL OR created_at >= p_date_from)
      AND (p_date_to IS NULL OR created_at <= p_date_to);

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
        'candidates_reviewed', count(DISTINCT ccf.id),
        'feedback_pending', count(DISTINCT cs.id) FILTER (WHERE ccf.id IS NULL),
        'interviews_requested', (
            SELECT count(*) FROM public.client_interview_requests cir
            JOIN public.client_candidate_shares cs2 ON cs2.id = cir.client_candidate_share_id
            WHERE cs2.client_organization_id = p_client_org_id
              AND (p_job_id IS NULL OR cs2.job_id = p_job_id)
        ),
        'client_hires', (
            SELECT count(*) FROM public.client_hiring_decisions chd
            JOIN public.client_candidate_shares cs3 ON cs3.id = chd.client_candidate_share_id
            WHERE cs3.client_organization_id = p_client_org_id 
              AND chd.decision = 'recommend_hire'
              AND (p_job_id IS NULL OR cs3.job_id = p_job_id)
        )
    ) INTO v_result
    FROM public.client_job_access cja
    LEFT JOIN public.client_candidate_shares cs ON cs.job_id = cja.job_id AND cs.client_organization_id = p_client_org_id
    LEFT JOIN public.client_candidate_feedback ccf ON ccf.client_candidate_share_id = cs.id
    WHERE cja.client_organization_id = p_client_org_id
      AND (p_job_id IS NULL OR cja.job_id = p_job_id);

    RETURN v_result;
END;
$$;
