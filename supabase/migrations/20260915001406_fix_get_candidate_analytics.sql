-- =============================================================================
-- Migration: 20260915001406_fix_get_candidate_analytics.sql
-- Fix: Replace cr.evaluated_at with cr.calculated_at in get_candidate_analytics
-- =============================================================================

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
        SELECT id INTO v_cand_id FROM public.candidates WHERE id = p_candidate_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Candidate % not found', p_candidate_id;
        END IF;

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
            JOIN public.assessment_attempts att ON att.assessment_invitation_id = ai.id
            JOIN public.assessment_results ar ON ar.assessment_attempt_id = att.id
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
            ORDER BY cr.calculated_at DESC LIMIT 1
        )
    ) INTO v_result
    FROM public.applications a
    LEFT JOIN public.matching_runs mr ON mr.candidate_id = v_cand_id
    WHERE a.candidate_id = v_cand_id;

    RETURN v_result;
END;
$$;
