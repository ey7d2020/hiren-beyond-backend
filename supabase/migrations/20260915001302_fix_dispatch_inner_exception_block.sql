-- =============================================================================
-- Migration: 20260915001302_fix_dispatch_inner_exception_block.sql
--
-- Architectural Fix for dispatch_ai_tool_call:
-- 1. Pre-execution authorization guards (tool registry, assistant-type, user auth,
--    call depth limit) use unhandled RAISE EXCEPTION so that callers receive
--    standard PostgreSQL exceptions for unauthorized operations (Tests 6, 10, 20).
-- 2. Tool handler execution is enclosed in an INNER BEGIN ... EXCEPTION block
--    so that runtime execution failures (e.g. missing job ID) are caught locally,
--    audited with execution_status = 'failed' in ai_tool_calls, and returned as
--    a structured JSON error without rolling back the audit record (Test 11).
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
    -- Recursive Tool Protection (Max depth: 3)
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
    -- Tool call is recorded as 'running' before handler execution begins.
    -- -------------------------------------------------------------------------
    INSERT INTO public.ai_tool_calls (
        conversation_id, tool_name, arguments,
        authorization_status, execution_status, call_depth
    ) VALUES (
        p_conversation_id, p_tool_name, p_arguments,
        'authorized', 'running', p_call_depth
    ) RETURNING id INTO v_tool_call_id;

    -- Inner block: catches runtime exceptions during tool execution
    BEGIN
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

    EXCEPTION WHEN OTHERS THEN
        -- Catches tool runtime failures, marks ai_tool_calls as failed, and commits
        UPDATE public.ai_tool_calls
        SET execution_status = 'failed',
            result_summary   = left(SQLERRM, 500),
            completed_at     = now()
        WHERE id = v_tool_call_id;

        RETURN jsonb_build_object(
            'status',  'error',
            'tool',    p_tool_name,
            'message', SQLERRM
        );
    END;

    RETURN v_result;
END;
$$;
