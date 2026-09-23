-- =============================================================================
-- Migration: 20260915001301_fix_dispatch_exception_audit.sql
--
-- Fix: dispatch_ai_tool_call EXCEPTION block re-raise rolls back the UPDATE
--      that marks a tool call as execution_status = 'failed'.
--
-- Root Cause: In PL/pgSQL an EXCEPTION block runs inside a sub-transaction.
--   When the block ends with RAISE (re-raise), that sub-transaction is rolled
--   back — taking any DML done inside the block (e.g. the UPDATE) with it.
--
-- Solution: Remove the final RAISE; from the EXCEPTION block.  Return a
--   structured error JSONB instead.  The UPDATE inside the block then commits
--   normally when the block exits without raising.
--
--   Pre-execution safety guards (recursive depth, auth barriers, unknown tool)
--   still use RAISE EXCEPTION because they execute BEFORE the ai_tool_calls
--   INSERT, so there is nothing to roll back.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.dispatch_ai_tool_call(
    p_conversation_id UUID,
    p_tool_name       TEXT,
    p_arguments       JSONB DEFAULT '{}'::jsonb,
    p_call_depth      INT   DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_conv          RECORD;
    v_ast           RECORD;
    v_tool          RECORD;
    v_tool_call_id  UUID;
    v_action_req_id UUID;
    v_result        JSONB := '{}'::jsonb;
    v_cand_id       UUID;
    v_app_id        UUID;
    v_job_id        UUID;
BEGIN
    -- -------------------------------------------------------------------------
    -- Recursive Tool Protection
    -- Fires BEFORE any INSERT so it is safe to RAISE here.
    -- -------------------------------------------------------------------------
    IF p_call_depth > 3 THEN
        RAISE EXCEPTION 'RECURSIVE_TOOL_LOOP_DETECTED: Maximum execution depth of 3 exceeded';
    END IF;

    -- Retrieve conversation
    SELECT * INTO v_conv FROM public.ai_conversations WHERE id = p_conversation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
    END IF;

    SELECT * INTO v_ast FROM public.ai_assistants WHERE id = v_conv.assistant_id;

    -- -------------------------------------------------------------------------
    -- Tool registry check
    -- -------------------------------------------------------------------------
    SELECT * INTO v_tool FROM public.ai_tools WHERE name = p_tool_name AND is_active = true;
    IF NOT FOUND THEN
        INSERT INTO public.ai_tool_calls (
            conversation_id, tool_name, arguments,
            authorization_status, execution_status, result_summary, call_depth
        ) VALUES (
            p_conversation_id, p_tool_name, p_arguments,
            'denied', 'failed', 'Tool does not exist or is inactive', p_call_depth
        );
        RAISE EXCEPTION 'Tool % is not recognized or is inactive', p_tool_name;
    END IF;

    -- -------------------------------------------------------------------------
    -- Assistant-type authorization
    -- -------------------------------------------------------------------------
    IF NOT (v_ast.assistant_type = ANY(v_tool.assistant_types)) THEN
        INSERT INTO public.ai_tool_calls (
            conversation_id, tool_name, arguments,
            authorization_status, execution_status, result_summary, call_depth
        ) VALUES (
            p_conversation_id, p_tool_name, p_arguments,
            'denied', 'failed', 'Tool unauthorized for assistant type', p_call_depth
        );
        RAISE EXCEPTION 'Tool % is not permitted for assistant type %', p_tool_name, v_ast.assistant_type;
    END IF;

    -- -------------------------------------------------------------------------
    -- User authorization barrier
    -- -------------------------------------------------------------------------
    IF v_ast.assistant_type = 'recruiter_copilot' THEN
        IF NOT public.check_user_is_recruiter(v_conv.organization_id)
           AND NOT public.is_platform_admin(auth.uid()) THEN
            INSERT INTO public.ai_tool_calls (
                conversation_id, tool_name, arguments,
                authorization_status, execution_status, result_summary, call_depth
            ) VALUES (
                p_conversation_id, p_tool_name, p_arguments,
                'denied', 'failed', 'Unauthorized recruiter access', p_call_depth
            );
            RAISE EXCEPTION 'Unauthorized: Caller is not an authorized recruiter for this session';
        END IF;
    ELSIF v_ast.assistant_type = 'candidate_career' THEN
        IF v_conv.user_id <> auth.uid() THEN
            INSERT INTO public.ai_tool_calls (
                conversation_id, tool_name, arguments,
                authorization_status, execution_status, result_summary, call_depth
            ) VALUES (
                p_conversation_id, p_tool_name, p_arguments,
                'denied', 'failed', 'Unauthorized candidate session access', p_call_depth
            );
            RAISE EXCEPTION 'Unauthorized: Cannot execute tools in another user session';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- High-risk action interception (requires human approval)
    -- -------------------------------------------------------------------------
    IF v_tool.requires_confirmation IS TRUE THEN
        v_app_id := (p_arguments->>'application_id')::uuid;

        INSERT INTO public.ai_tool_calls (
            conversation_id, tool_name, arguments,
            authorization_status, execution_status, result_summary, call_depth
        ) VALUES (
            p_conversation_id, p_tool_name, p_arguments,
            'requires_approval', 'queued', 'Awaiting human confirmation', p_call_depth
        ) RETURNING id INTO v_tool_call_id;

        INSERT INTO public.ai_action_requests (
            conversation_id, tool_call_id, requested_by, action_type,
            target_type, target_id, arguments, risk_level, status, idempotency_key
        ) VALUES (
            p_conversation_id, v_tool_call_id, auth.uid(), p_tool_name,
            CASE WHEN v_app_id IS NOT NULL THEN 'application' ELSE 'job' END,
            COALESCE(v_app_id, v_conv.job_id, v_conv.id),
            p_arguments, v_tool.risk_level, 'pending',
            'action:' || v_tool_call_id::text
        ) RETURNING id INTO v_action_req_id;

        RETURN jsonb_build_object(
            'status',            'requires_approval',
            'action_request_id', v_action_req_id,
            'message',           'This action requires explicit human confirmation. An action request has been created.'
        );
    END IF;

    -- -------------------------------------------------------------------------
    -- Safe Execution Engine
    -- Insert the tool call in 'running' state BEFORE executing the handler.
    -- The EXCEPTION block below updates it to 'failed' WITHOUT re-raising, so
    -- that UPDATE is committed instead of being rolled back.
    -- -------------------------------------------------------------------------
    INSERT INTO public.ai_tool_calls (
        conversation_id, tool_name, arguments,
        authorization_status, execution_status, call_depth
    ) VALUES (
        p_conversation_id, p_tool_name, p_arguments,
        'authorized', 'running', p_call_depth
    ) RETURNING id INTO v_tool_call_id;

    -- Tool handlers
    IF p_tool_name = 'get_my_profile' THEN
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        SELECT jsonb_build_object(
            'candidate_id',     c.id,
            'headline',         cp.headline,
            'bio',              cp.professional_summary,
            'location_city',    cp.city,
            'location_country', cp.country_code,
            'status',           c.status
        ) INTO v_result
        FROM public.candidates c
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        WHERE c.id = v_cand_id;

    ELSIF p_tool_name = 'get_my_skills' THEN
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        SELECT jsonb_build_object(
            'skills', COALESCE(jsonb_agg(jsonb_build_object(
                'skill_name',  cs.skill_name,
                'proficiency', cs.proficiency_level,
                'verified',    cs.is_verified
            )), '[]'::jsonb)
        ) INTO v_result
        FROM public.candidate_skills cs
        WHERE cs.candidate_id = v_cand_id;

    ELSIF p_tool_name = 'get_my_match_results' THEN
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        v_job_id := (p_arguments->>'job_id')::uuid;
        SELECT jsonb_build_object(
            'job_id',            mr.job_id,
            'candidate_id',      v_cand_id,
            'overall_score',     mr.overall_score,
            'ai_recommendation', mr.ai_recommendation,
            'dimension_scores',  mr.dimension_scores
        ) INTO v_result
        FROM public.matching_runs mr
        WHERE mr.candidate_id = v_cand_id
          AND (v_job_id IS NULL OR mr.job_id = v_job_id)
        ORDER BY mr.created_at DESC LIMIT 1;

        IF v_result IS NULL THEN
            v_result := jsonb_build_object('message', 'No matching results found for this job');
        END IF;

    ELSIF p_tool_name = 'search_candidates' THEN
        v_job_id := (p_arguments->>'job_id')::uuid;
        SELECT jsonb_build_object(
            'total_found', count(*),
            'candidates',  COALESCE(jsonb_agg(jsonb_build_object(
                'application_id', a.id,
                'candidate_id',   a.candidate_id,
                'job_id',         a.job_id,
                'status',         a.status,
                'created_at',     a.created_at
            )), '[]'::jsonb)
        ) INTO v_result
        FROM public.applications a
        WHERE (v_job_id IS NULL OR a.job_id = v_job_id)
          AND EXISTS (
              SELECT 1 FROM public.jobs j
              WHERE j.id = a.job_id
                AND j.organization_id = v_conv.organization_id
          );

    ELSIF p_tool_name = 'rank_candidates_for_job' THEN
        v_job_id := (p_arguments->>'job_id')::uuid;
        IF v_job_id IS NULL THEN v_job_id := v_conv.job_id; END IF;

        -- This RAISE is caught by the EXCEPTION block below.
        -- The EXCEPTION block does NOT re-raise, so execution_status = 'failed'
        -- is durably committed to ai_tool_calls.
        IF NOT EXISTS (
            SELECT 1 FROM public.jobs
            WHERE id = v_job_id AND organization_id = v_conv.organization_id
        ) THEN
            RAISE EXCEPTION 'Job % does not belong to your organization', v_job_id;
        END IF;

        SELECT jsonb_build_object(
            'job_id', v_job_id,
            'ranked_candidates', COALESCE(jsonb_agg(jsonb_build_object(
                'application_id', a.id,
                'candidate_id',   a.candidate_id,
                'status',         a.status,
                'match_score',    mr.overall_score,
                'recommendation', mr.ai_recommendation
            ) ORDER BY COALESCE(mr.overall_score, 0) DESC), '[]'::jsonb)
        ) INTO v_result
        FROM public.applications a
        LEFT JOIN LATERAL (
            SELECT overall_score, ai_recommendation
            FROM public.matching_runs mr_sub
            WHERE mr_sub.job_id = a.job_id
              AND mr_sub.candidate_id = a.candidate_id
            ORDER BY mr_sub.created_at DESC LIMIT 1
        ) mr ON true
        WHERE a.job_id = v_job_id;

    ELSIF p_tool_name = 'get_job_details' THEN
        v_job_id := (p_arguments->>'job_id')::uuid;
        IF v_job_id IS NULL THEN v_job_id := v_conv.job_id; END IF;

        SELECT jsonb_build_object(
            'id',              j.id,
            'title',           j.title,
            'status',          j.status,
            'employment_type', j.employment_type,
            'workplace_type',  j.workplace_type,
            'description',     j.description
        ) INTO v_result
        FROM public.jobs j
        WHERE j.id = v_job_id
          AND (j.organization_id = v_conv.organization_id OR j.status = 'published');

    ELSE
        v_result := jsonb_build_object('status', 'executed', 'tool', p_tool_name);
    END IF;

    -- Mark success
    UPDATE public.ai_tool_calls
    SET execution_status = 'completed',
        result_summary   = substr(v_result::text, 1, 500),
        completed_at     = now()
    WHERE id = v_tool_call_id;

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    -- -------------------------------------------------------------------------
    -- KEY FIX: Do NOT re-raise.
    -- Returning normally from the EXCEPTION block commits the sub-transaction
    -- (including the UPDATE below).  Previously, RAISE here caused the sub-
    -- transaction rollback so no 'failed' row was ever persisted.
    -- -------------------------------------------------------------------------
    IF v_tool_call_id IS NOT NULL THEN
        UPDATE public.ai_tool_calls
        SET execution_status = 'failed',
            result_summary   = left(SQLERRM, 500),
            completed_at     = now()
        WHERE id = v_tool_call_id;
    END IF;

    RETURN jsonb_build_object(
        'status',  'error',
        'tool',    p_tool_name,
        'message', SQLERRM
    );
END;
$$;
