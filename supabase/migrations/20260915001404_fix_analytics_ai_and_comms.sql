-- =============================================================================
-- Migration: 20260915001404_fix_analytics_ai_and_comms.sql
-- Description: Fix column name mismatches in analytics functions:
--   1. ai_usage_records: estimated_cost_usd -> estimated_cost
--   2. notification_deliveries: drop invalid event_id join, link via notification_id
--   3. notification_outbox table doesn't exist -> use notification_deliveries properly
-- =============================================================================

-- Rewrite get_organization_analytics with all correct column references
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

    -- 4. Assessment Analytics (from Task 08) - using correct column names
    SELECT jsonb_build_object(
        'invitations_sent', count(DISTINCT ai.id),
        'attempts_started', count(DISTINCT att.id),
        'completed_assessments', count(DISTINCT ar.id),
        'average_score', round(avg(ar.normalized_score)::numeric, 2),
        'pass_rate',
            CASE WHEN count(ar.id) > 0 THEN round((count(ar.id) FILTER (WHERE ar.passed = true)::numeric / count(ar.id)) * 100, 2) ELSE NULL END
    ) INTO v_assess_metrics
    FROM public.assessment_invitations ai
    JOIN public.applications a ON a.id = ai.application_id
    LEFT JOIN public.assessment_attempts att ON att.assessment_invitation_id = ai.id
    LEFT JOIN public.assessment_results ar ON ar.assessment_attempt_id = att.id
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

    -- 7. Client Portal Collaboration (from Task 10) - use correct FK column names
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

    -- 8. AI Usage Telemetry (from Task 12) - use correct column: estimated_cost
    SELECT jsonb_build_object(
        'total_requests', count(*),
        'total_tokens', COALESCE(sum(total_tokens), 0),
        'total_estimated_cost_usd', round(COALESCE(sum(estimated_cost), 0)::numeric, 4),
        'average_latency_ms', round(avg(latency_ms)::numeric, 1)
    ) INTO v_ai_metrics
    FROM public.ai_usage_records
    WHERE organization_id = p_organization_id
      AND (p_date_from IS NULL OR created_at >= p_date_from)
      AND (p_date_to IS NULL OR created_at <= p_date_to);

    -- 9. Communications Delivery (from Task 11) - notification_deliveries linked via recipient and org
    --    notification_deliveries has: notification_id -> notifications.recipient_user_id
    --    To scope to org, join through notification_events (organization_id) or use notifications
    --    Simplest correct approach: join notification_events via notifications table
    SELECT jsonb_build_object(
        'total_deliveries', count(DISTINCT nd.id),
        'delivered_count', count(DISTINCT nd.id) FILTER (WHERE nd.status = 'delivered'),
        'failed_count', count(DISTINCT nd.id) FILTER (WHERE nd.status = 'failed'),
        'delivery_rate',
            CASE WHEN count(nd.id) > 0
                 THEN round((count(nd.id) FILTER (WHERE nd.status = 'delivered')::numeric / count(nd.id)) * 100, 2)
                 ELSE NULL END
    ) INTO v_comm_metrics
    FROM public.notification_deliveries nd
    JOIN public.notifications n ON n.id = nd.notification_id
    JOIN public.notification_events ne ON ne.organization_id = p_organization_id
    WHERE nd.recipient_user_id IN (
        SELECT user_id FROM public.organization_members WHERE organization_id = p_organization_id
    )
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
