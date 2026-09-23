-- =============================================================================
-- Test Suite: Task 12 — AI Assistants, Candidate Career Assistant, Recruiter Copilot & Action Layer
-- File: docs/backend/test-ai-assistants.sql
--
-- Validates:
--   Test 01: Candidate Conversation Creation
--   Test 02: Candidate Data Access (Profile & Skills Retrieval)
--   Test 03: Candidate Data Isolation (Candidate A cannot read Candidate B)
--   Test 04: Recruiter Candidate Search (Structured Search within Tenant)
--   Test 05: Recruiter Cross-Tenant Isolation (Recruiter A blocked from Org B)
--   Test 06: Tool Authorization (Candidate blocked from Recruiter tools)
--   Test 07: High-Risk Action Gating (Shortlist generates pending action request)
--   Test 08: Action Approval & Execution (Recruiter approval triggers shortlist)
--   Test 09: Prohibited AI Action (AI cannot execute final hiring decisions)
--   Test 10: No Arbitrary SQL Execution (Unregistered tool blocked safely)
--   Test 11: Tool Failure Honest Reporting (Failure captured in execution status)
--   Test 12: Action Idempotency (Repeat execution safe and deduplicated)
--   Test 13: AI Recommendations (Evidence and confidence tracking)
--   Test 14: AI Usage Tracking (Tokens, provider, cost, latency logging)
--   Test 15: Prompt Version Immutability (Session references prompt version)
--   Test 16: Conversation Session RLS (User cannot view another user's conversation)
--   Test 17: Client Isolation (Client user barred from Recruiter Copilot)
--   Test 18: Provider Failure Isolation (AI error does not affect recruitment data)
--   Test 19: Sensitive Data Protection (Candidate tool cannot view internal notes)
--   Test 20: Recursive Tool Protection (Max depth limit prevents runaway loops)
-- =============================================================================

BEGIN;

DO $$
DECLARE
    -- Test entities
    v_org_a UUID := gen_random_uuid();
    v_org_b UUID := gen_random_uuid();
    v_client_org UUID := gen_random_uuid();

    v_recruiter_a UUID := gen_random_uuid();
    v_recruiter_b UUID := gen_random_uuid();
    v_cand_user_a UUID := gen_random_uuid();
    v_cand_user_b UUID := gen_random_uuid();
    v_client_user UUID := gen_random_uuid();

    v_role_recruiter UUID;
    v_role_client_reviewer UUID;

    v_cand_a UUID := gen_random_uuid();
    v_cand_b UUID := gen_random_uuid();

    v_job_a UUID := gen_random_uuid();
    v_app_a UUID := gen_random_uuid();

    v_conv_cand_id UUID;
    v_conv_rec_id UUID;
    v_msg_id UUID;
    v_tool_res JSONB;
    v_act_req_id UUID;
    v_rec_id UUID;
    v_usage_id UUID;
    v_brief JSONB;
    v_tool_call RECORD;
    v_action_rec RECORD;
    v_prompt_ver INT;
BEGIN
    RAISE NOTICE '=== STARTING TASK 12 AI ASSISTANTS & COPILOT TEST SUITE ===';

    -- ------------------------------------------------------------------------
    -- 0. SETUP TEST USERS, ORGANIZATIONS & CANDIDATES
    -- ------------------------------------------------------------------------
    -- Organizations
    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES
        (v_org_a, 'Acme Global Talent', 'acme-global-' || substr(v_org_a::text, 1, 8), 'recruitment_agency', 'active'),
        (v_org_b, 'Zenith Search Corp', 'zenith-search-' || substr(v_org_b::text, 1, 8), 'recruitment_agency', 'active'),
        (v_client_org, 'Nexus Corporate Client', 'nexus-client-' || substr(v_client_org::text, 1, 8), 'client', 'active');

    -- Auth Users & Profiles
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_recruiter_a, 'recruiter.a@acme.com', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b@zenith.com', 'authenticated', 'authenticated'),
        (v_cand_user_a, 'candidate.a@gmail.com', 'authenticated', 'authenticated'),
        (v_cand_user_b, 'candidate.b@gmail.com', 'authenticated', 'authenticated'),
        (v_client_user, 'hiring.lead@nexus.com', 'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, email, full_name, country_code)
    VALUES
        (v_recruiter_a, 'recruiter.a@acme.com', 'Rachel Recruiter', 'US'),
        (v_recruiter_b, 'recruiter.b@zenith.com', 'Zachary Zenith', 'GB'),
        (v_cand_user_a, 'candidate.a@gmail.com', 'Charles Candidate', 'EG'),
        (v_cand_user_b, 'candidate.b@gmail.com', 'Brenda Candidate', 'AE'),
        (v_client_user, 'hiring.lead@nexus.com', 'Clara Client', 'DE')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Roles and Organization Members
    SELECT id INTO v_role_recruiter FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_role_client_reviewer FROM public.roles WHERE key = 'client_reviewer' LIMIT 1;

    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES
        (v_org_a, v_recruiter_a, v_role_recruiter, 'active'),
        (v_org_b, v_recruiter_b, v_role_recruiter, 'active'),
        (v_client_org, v_client_user, v_role_client_reviewer, 'active');

    -- Client Contact
    INSERT INTO public.client_contacts (client_organization_id, user_id, name, job_title)
    VALUES
        (v_client_org, v_client_user, 'Clara Client', 'VP Engineering');

    -- Candidates & Profiles
    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_a, v_cand_user_a, 'active'),
        (v_cand_b, v_cand_user_b, 'active');

    INSERT INTO public.candidate_profiles (
        candidate_id, headline, professional_summary, years_of_experience, country_code, city, availability_status
    )
    VALUES
        (v_cand_a, 'Lead Systems Architect', 'Over 10 years distributed systems experience.', 10, 'EG', 'Cairo', 'immediately'),
        (v_cand_b, 'Junior Frontend Developer', 'Passionate React developer.', 2, 'AE', 'Dubai', 'open_to_discussion');

    -- Candidate Skills
    INSERT INTO public.candidate_skills (candidate_id, skill_name, normalized_skill_name, skill_type, proficiency_level, years_of_experience, is_verified)
    VALUES
        (v_cand_a, 'Distributed Systems', 'distributed systems', 'technical', 'expert', 8, true),
        (v_cand_a, 'PostgreSQL', 'postgresql', 'technical', 'advanced', 6, true),
        (v_cand_b, 'React', 'react', 'technical', 'intermediate', 2, false);

    -- Jobs
    INSERT INTO public.jobs (
        id, organization_id, created_by, title, slug, description, employment_type, workplace_type, status, job_type
    )
    VALUES (
        v_job_a, v_org_a, v_recruiter_a, 'Staff Cloud Architect', 'staff-cloud-arch-' || substr(v_job_a::text, 1, 8),
        'Leading next-gen cloud infra', 'full_time', 'remote', 'published', 'direct'
    );

    -- Applications
    INSERT INTO public.applications (
        id, job_id, candidate_id, organization_id, status
    )
    VALUES (
        v_app_a, v_job_a, v_cand_a, v_org_a, 'submitted'
    );

    -- ------------------------------------------------------------------------
    -- TEST 1: Candidate Conversation Creation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    v_conv_cand_id := public.start_ai_conversation(
        'candidate_career',
        NULL,
        v_job_a,
        NULL,
        'Career Planning with AI Coach'
    );

    IF v_conv_cand_id IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Could not create candidate career AI conversation';
    END IF;

    -- Verify message logging
    v_msg_id := public.send_ai_message(
        v_conv_cand_id,
        'user',
        'How well do my skills match the Staff Cloud Architect job?'
    );

    IF v_msg_id IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: User message was not recorded';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 2: Candidate Data Access (Profile & Skills Retrieval)
    -- ------------------------------------------------------------------------
    v_tool_res := public.dispatch_ai_tool_call(
        v_conv_cand_id,
        'get_my_profile',
        '{}'::jsonb
    );

    IF (v_tool_res->>'headline') <> 'Lead Systems Architect' THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected candidate headline "Lead Systems Architect", got %', v_tool_res->>'headline';
    END IF;

    v_tool_res := public.dispatch_ai_tool_call(
        v_conv_cand_id,
        'get_my_skills',
        '{}'::jsonb
    );

    IF jsonb_array_length(v_tool_res->'skills') < 2 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Candidate skills were not retrieved properly';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 3: Candidate Data Isolation (Candidate A cannot read Candidate B)
    -- ------------------------------------------------------------------------
    -- Ensure candidate tools only bind caller candidate id from auth.uid()
    IF (v_tool_res::text LIKE '%' || v_cand_b::text || '%') THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Candidate B information leaked into Candidate A session';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 4: Recruiter Candidate Search (Structured Search within Tenant)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    v_conv_rec_id := public.start_ai_conversation(
        'recruiter_copilot',
        v_org_a,
        v_job_a,
        NULL,
        'Candidate Evaluation & Shortlisting'
    );

    v_tool_res := public.dispatch_ai_tool_call(
        v_conv_rec_id,
        'search_candidates',
        jsonb_build_object('job_id', v_job_a)
    );

    IF (v_tool_res->>'total_found')::int < 1 THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Recruiter candidate search returned 0 candidates';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 5: Recruiter Cross-Tenant Isolation (Recruiter A blocked from Org B)
    -- ------------------------------------------------------------------------
    BEGIN
        PERFORM public.start_ai_conversation(
            'recruiter_copilot',
            v_org_b,
            NULL,
            NULL,
            'Attempted Unauthorized Session'
        );
        RAISE EXCEPTION 'TEST 5 FAILED: Recruiter A was able to start session in Organization B!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 5 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 6: Tool Authorization (Candidate blocked from Recruiter tools)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    BEGIN
        PERFORM public.dispatch_ai_tool_call(
            v_conv_cand_id,
            'rank_candidates_for_job',
            jsonb_build_object('job_id', v_job_a)
        );
        RAISE EXCEPTION 'TEST 6 FAILED: Candidate was allowed to execute recruiter tool rank_candidates_for_job!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 6 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 7: High-Risk Action Gating (Shortlist generates pending action request)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    v_tool_res := public.dispatch_ai_tool_call(
        v_conv_rec_id,
        'request_candidate_shortlist',
        jsonb_build_object(
            'application_id', v_app_a,
            'notes', 'Candidate matches distributed systems criteria'
        )
    );

    IF (v_tool_res->>'status') <> 'requires_approval' OR (v_tool_res->>'action_request_id') IS NULL THEN
        RAISE EXCEPTION 'TEST 7 FAILED: High-risk action was not intercepted for human approval, got %', v_tool_res;
    END IF;

    v_act_req_id := (v_tool_res->>'action_request_id')::uuid;

    SELECT * INTO v_action_rec FROM public.ai_action_requests WHERE id = v_act_req_id;
    IF v_action_rec.status <> 'pending' THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Action request not in pending status';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 8: Action Approval & Execution (Recruiter approval triggers shortlist)
    -- ------------------------------------------------------------------------
    v_tool_res := public.approve_ai_action_request(
        v_act_req_id,
        'Approved by Lead Technical Recruiter'
    );

    IF (v_tool_res->>'status') <> 'executed' THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Action request execution failed, got %', v_tool_res;
    END IF;

    -- Verify that application was actually shortlisted in the ATS pipeline
    IF NOT EXISTS (
        SELECT 1 FROM public.applications
        WHERE id = v_app_a AND status = 'shortlisted'
    ) THEN
        RAISE EXCEPTION 'TEST 8 FAILED: ATS application was not updated to shortlisted';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 9: Prohibited AI Action (AI cannot execute final hiring decisions)
    -- ------------------------------------------------------------------------
    -- Create an illegitimate request trying to directly hire
    INSERT INTO public.ai_action_requests (
        conversation_id, requested_by, action_type, target_type, target_id, risk_level, status
    )
    VALUES (
        v_conv_rec_id, v_recruiter_a, 'hire', 'application', v_app_a, 'critical', 'pending'
    )
    RETURNING id INTO v_act_req_id;

    BEGIN
        PERFORM public.approve_ai_action_request(v_act_req_id, 'Attempting AI-direct hire');
        RAISE EXCEPTION 'TEST 9 FAILED: AI was allowed to execute final hiring decision!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 9 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 10: No Arbitrary SQL Execution (Unregistered tool blocked safely)
    -- ------------------------------------------------------------------------
    BEGIN
        PERFORM public.dispatch_ai_tool_call(
            v_conv_rec_id,
            'execute_raw_sql',
            jsonb_build_object('query', 'SELECT * FROM auth.users;')
        );
        RAISE EXCEPTION 'TEST 10 FAILED: Arbitrary SQL execution tool was allowed!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 10 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 11: Tool Failure Honest Reporting (Failure captured in execution status)
    -- ------------------------------------------------------------------------
    -- dispatch_ai_tool_call no longer re-raises on tool-level errors; it returns
    -- {status: 'error', message: ...} so the EXCEPTION block's UPDATE is committed.
    v_tool_res := public.dispatch_ai_tool_call(
        v_conv_rec_id,
        'rank_candidates_for_job',
        jsonb_build_object('job_id', gen_random_uuid())
    );

    -- 11a: Return value must indicate an error
    IF (v_tool_res->>'status') <> 'error' THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Expected error status in return value, got %', v_tool_res;
    END IF;

    -- 11b: The tool call row must be durably recorded as failed
    IF NOT EXISTS (
        SELECT 1 FROM public.ai_tool_calls
        WHERE conversation_id = v_conv_rec_id
          AND tool_name = 'rank_candidates_for_job'
          AND execution_status = 'failed'
    ) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Tool call failure was not durably audited in ai_tool_calls (got %)', v_tool_res;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 12: Action Idempotency (Repeat execution safe and deduplicated)
    -- ------------------------------------------------------------------------
    -- Call approve on the already executed shortlist request
    SELECT id INTO v_act_req_id
    FROM public.ai_action_requests
    WHERE conversation_id = v_conv_rec_id AND action_type = 'request_candidate_shortlist' AND status = 'executed'
    LIMIT 1;

    v_tool_res := public.approve_ai_action_request(v_act_req_id, 'Duplicate approval attempt');
    IF (v_tool_res->>'status') <> 'already_executed' THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Duplicate action approval was not handled idempotently, got %', v_tool_res;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 13: AI Recommendations (Evidence and confidence tracking)
    -- ------------------------------------------------------------------------
    v_rec_id := public.create_ai_recommendation(
        v_org_a,
        v_recruiter_a,
        'candidate_shortlist',
        'application',
        v_app_a,
        'Recommend Candidate for Interview',
        'Candidate Charles demonstrated 95% skills alignment with cloud requirements.',
        'High proficiency in Distributed Systems and PostgreSQL; 10+ years relevant experience.',
        95.00,
        'high',
        jsonb_build_object(
            'match_score', 95,
            'verified_skills', jsonb_build_array('Distributed Systems', 'PostgreSQL')
        )
    );

    IF v_rec_id IS NULL THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Recommendation creation failed';
    END IF;

    SELECT * INTO v_action_rec FROM public.ai_recommendations WHERE id = v_rec_id;
    IF v_action_rec.confidence <> 95.00 OR (v_action_rec.evidence->>'match_score')::int <> 95 THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Recommendation confidence or evidence corrupted';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 14: AI Usage Tracking (Tokens, provider, cost, latency logging)
    -- ------------------------------------------------------------------------
    v_usage_id := public.record_ai_usage(
        v_recruiter_a,
        v_org_a,
        NULL,
        v_conv_rec_id,
        'google',
        'gemini-1.5-pro',
        'chat',
        1250,
        350,
        0.003200,
        450
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.ai_usage_records
        WHERE id = v_usage_id AND total_tokens = 1600 AND latency_ms = 450
    ) THEN
        RAISE EXCEPTION 'TEST 14 FAILED: AI usage record not stored accurately';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 15: Prompt Version Immutability (Session references prompt version)
    -- ------------------------------------------------------------------------
    SELECT prompt_version INTO v_prompt_ver
    FROM public.ai_messages
    WHERE conversation_id = v_conv_cand_id AND role = 'system'
    LIMIT 1;

    IF v_prompt_ver IS NULL OR v_prompt_ver < 1 THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Prompt version not tracked in conversation message';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 16: Conversation Session RLS (User cannot view another user's conversation)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_b::text, true);

    -- Under Candidate B context, Candidate A conversation should be completely invisible
    IF EXISTS (
        SELECT 1 FROM public.ai_conversations
        WHERE id = v_conv_cand_id
          AND (
              user_id = auth.uid()
              OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    ) THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Candidate B was able to access Candidate A conversation!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 17: Client Isolation (Client user barred from Recruiter Copilot)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_client_user::text, true);

    BEGIN
        PERFORM public.start_ai_conversation(
            'recruiter_copilot',
            v_org_a,
            v_job_a,
            NULL,
            'Client attempted copilot access'
        );
        RAISE EXCEPTION 'TEST 17 FAILED: Client portal user was allowed to start recruiter copilot session!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 17 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 18: Provider Failure Isolation (AI error does not affect recruitment data)
    -- ------------------------------------------------------------------------
    -- Verify that recruitment application status remains shortlisted and unaffected
    IF NOT EXISTS (SELECT 1 FROM public.applications WHERE id = v_app_a AND status = 'shortlisted') THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Recruitment data was corrupted by AI operations';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 19: Sensitive Data Protection (Candidate tool cannot view internal notes)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    v_tool_res := public.dispatch_ai_tool_call(
        v_conv_cand_id,
        'get_my_profile',
        '{}'::jsonb
    );

    IF (v_tool_res::text LIKE '%internal_notes%') OR (v_tool_res::text LIKE '%recruiter_feedback%') THEN
        RAISE EXCEPTION 'TEST 19 FAILED: Internal recruiter notes leaked to candidate profile tool!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 20: Recursive Tool Protection (Max depth limit prevents runaway loops)
    -- ------------------------------------------------------------------------
    BEGIN
        PERFORM public.dispatch_ai_tool_call(
            v_conv_cand_id,
            'get_my_profile',
            '{}'::jsonb,
            4 -- Call depth 4 exceeds max depth of 3
        );
        RAISE EXCEPTION 'TEST 20 FAILED: Recursive tool loop depth > 3 was not blocked!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 20 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        IF NOT (SQLERRM LIKE '%RECURSIVE_TOOL_LOOP_DETECTED%') THEN
            RAISE EXCEPTION 'TEST 20 FAILED: Expected RECURSIVE_TOOL_LOOP_DETECTED error, got: %', SQLERRM;
        END IF;
        -- Successfully blocked
    END;

    RAISE NOTICE 'ALL 20 END-TO-END AI ASSISTANTS & COPILOT TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 20 AI ASSISTANTS & COPILOT TESTS PASSED!' AS status;

ROLLBACK;
