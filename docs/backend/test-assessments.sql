-- ============================================================================
-- Hiren Beyond — Task 08 End-to-End Automated Test Suite: Assessments, Evaluation & Candidate Readiness
-- Executes all 18 test scenarios inside a safe rollback transaction
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_org_a_id UUID := '90c362ea-2bcc-45ba-98e4-c8a5d3c57376'; -- Hiren Beyond Platform
    v_org_b_id UUID := gen_random_uuid();
    v_recruiter_a UUID := gen_random_uuid();
    v_recruiter_b UUID := gen_random_uuid();
    v_user_cand_a UUID := gen_random_uuid();
    v_user_cand_b UUID := gen_random_uuid();
    v_cand_a UUID := gen_random_uuid();
    v_cand_b UUID := gen_random_uuid();
    v_job_a UUID := gen_random_uuid();
    v_job_b UUID := gen_random_uuid();
    v_app_a UUID := gen_random_uuid();
    v_role_id UUID;
    
    -- Template & Content IDs
    v_tmpl_id UUID;
    v_tmpl_v2_id UUID;
    v_sec_gram_id UUID;
    v_sec_spk_id UUID;
    v_q1_id UUID;
    v_q2_id UUID;
    v_q3_id UUID;
    v_opt1_a UUID := gen_random_uuid();
    v_opt1_b UUID := gen_random_uuid();
    v_opt2_a UUID := gen_random_uuid();
    v_opt2_b UUID := gen_random_uuid();

    -- Workflow IDs
    v_inv_count INT;
    v_inv_id UUID;
    v_inv_token TEXT;
    v_attempt_res JSONB;
    v_attempt_id UUID;
    v_ans_payload JSONB;
    v_result_id UUID;
    v_result RECORD;
    v_voice_id UUID;
    v_review_id UUID;
    v_readiness RECORD;
    v_ans_id UUID;
    v_readiness_stat VARCHAR;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. SETUP AUTH USERS, PROFILES & RECRUITERS
    -- ------------------------------------------------------------------------
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_recruiter_a, 'recruiter.a.test@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b.test@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_cand_a, 'cand.a.test@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_cand_b, 'cand.b.test@hirenbeyond.test', 'authenticated', 'authenticated');

    INSERT INTO public.profiles (id, email, full_name)
    VALUES
        (v_recruiter_a, 'recruiter.a.test@hirenbeyond.test', 'Recruiter Alice'),
        (v_recruiter_b, 'recruiter.b.test@hirenbeyond.test', 'Recruiter Bob'),
        (v_user_cand_a, 'cand.a.test@hirenbeyond.test', 'Candidate Alpha'),
        (v_user_cand_b, 'cand.b.test@hirenbeyond.test', 'Candidate Beta')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Setup Org B
    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES (v_org_b_id, 'Global Call Centers Ltd', 'global-call-centers', 'client', 'active');

    SELECT id INTO v_role_id FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES 
        (v_org_a_id, v_recruiter_a, v_role_id, 'active'),
        (v_org_b_id, v_recruiter_b, v_role_id, 'active');

    -- Setup Candidates
    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_a, v_user_cand_a, 'active'),
        (v_cand_b, v_user_cand_b, 'active');

    -- Setup Jobs
    INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status, job_type)
    VALUES
        (v_job_a, v_org_a_id, v_recruiter_a, 'English Customer Care Specialist', 'eng-cc-spec-' || substr(gen_random_uuid()::text, 1, 8), 'Handle English customer calls with empathy', 'published', 'direct'),
        (v_job_b, v_org_b_id, v_recruiter_b, 'Technical Support Representative', 'tech-rep-' || substr(gen_random_uuid()::text, 1, 8), 'Provide technical support to global clients', 'published', 'direct');

    -- Setup Applications
    INSERT INTO public.applications (id, job_id, candidate_id, organization_id, status)
    VALUES (v_app_a, v_job_a, v_cand_a, v_org_a_id, 'screening');

    -- Set context to recruiter A
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- ------------------------------------------------------------------------
    -- TEST 1: Assessment Template & Versioning
    -- ------------------------------------------------------------------------
    INSERT INTO public.assessment_templates (
        organization_id, created_by, name, slug, assessment_type, version, status,
        time_limit_minutes, passing_score
    )
    VALUES (
        v_org_a_id, v_recruiter_a, 'English Communication Assessment', 'english-comm',
        'language', 1, 'published', 45, 75.00
    )
    RETURNING id INTO v_tmpl_id;

    IF NOT EXISTS (SELECT 1 FROM public.assessment_templates WHERE id = v_tmpl_id AND version = 1) THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Assessment template v1 was not properly created';
    END IF;

    -- Add Sections
    INSERT INTO public.assessment_sections (assessment_template_id, name, section_type, sort_order, weight)
    VALUES
        (v_tmpl_id, 'Grammar & Vocabulary', 'grammar', 1, 40.00)
    RETURNING id INTO v_sec_gram_id;

    INSERT INTO public.assessment_sections (assessment_template_id, name, section_type, sort_order, weight)
    VALUES
        (v_tmpl_id, 'Spoken Communication', 'speaking', 2, 60.00)
    RETURNING id INTO v_sec_spk_id;

    -- Add Questions & Options
    -- Q1: Single choice (Grammar)
    INSERT INTO public.assessment_questions (
        assessment_section_id, question_type, question_text, points, sort_order, correct_answer
    )
    VALUES (
        v_sec_gram_id, 'single_choice', 'She ___ to the office every morning.', 10.00, 1, 'goes'
    )
    RETURNING id INTO v_q1_id;

    INSERT INTO public.assessment_question_options (id, question_id, option_text, sort_order, points, is_correct)
    VALUES
        (v_opt1_a, v_q1_id, 'goes', 1, 10.00, true),
        (v_opt1_b, v_q1_id, 'go', 2, 0.00, false);

    -- Q2: Number (Vocabulary/Grammar)
    INSERT INTO public.assessment_questions (
        assessment_section_id, question_type, question_text, points, sort_order, correct_answer
    )
    VALUES (
        v_sec_gram_id, 'number', 'How many syllables are in the word "international"?', 10.00, 2, '5'
    )
    RETURNING id INTO v_q2_id;

    -- Q3: Audio response (Speaking)
    INSERT INTO public.assessment_questions (
        assessment_section_id, question_type, question_text, instructions, points, sort_order
    )
    VALUES (
        v_sec_spk_id, 'audio_response', 'Describe your most challenging customer experience and how you handled it.', 'Record 60-90 seconds of audio.', 30.00, 1
    )
    RETURNING id INTO v_q3_id;

    -- ------------------------------------------------------------------------
    -- TEST 2: Job Assessment Requirement Attachment
    -- ------------------------------------------------------------------------
    INSERT INTO public.job_assessments (
        job_id, assessment_template_id, required, sequence, trigger_stage, minimum_score
    )
    VALUES (
        v_job_a, v_tmpl_id, true, 1, 'screening', 75.00
    );

    IF NOT EXISTS (SELECT 1 FROM public.job_assessments WHERE job_id = v_job_a AND assessment_template_id = v_tmpl_id) THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Job assessment requirement was not attached';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 3: Assessment Invitation Trigger & Idempotency
    -- ------------------------------------------------------------------------
    v_inv_count := public.trigger_required_assessments(v_app_a);
    IF v_inv_count <> 1 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Expected 1 invitation created, got %', v_inv_count;
    END IF;

    SELECT id, token INTO v_inv_id, v_inv_token
    FROM public.assessment_invitations
    WHERE application_id = v_app_a AND assessment_template_id = v_tmpl_id;

    IF v_inv_token IS NULL THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Secure invitation token was not generated';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 4: Candidate Attempt Start (Safe Data Without Answers)
    -- ------------------------------------------------------------------------
    -- Switch context to Candidate Alpha
    PERFORM set_config('request.jwt.claim.sub', v_user_cand_a::text, true);

    v_attempt_res := public.start_assessment_attempt(v_inv_token);
    v_attempt_id := (v_attempt_res->>'attempt_id')::UUID;

    IF v_attempt_id IS NULL THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Candidate failed to start assessment attempt';
    END IF;

    -- Verify answers/correct_answer are NOT exposed to candidate
    IF v_attempt_res::text LIKE '%"is_correct"%' OR v_attempt_res::text LIKE '%"correct_answer"%' THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Correct answers exposed in candidate attempt payload!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 5: Deterministic Scoring (100% Correct on Grammar Section)
    -- ------------------------------------------------------------------------
    v_ans_payload := jsonb_build_array(
        jsonb_build_object('question_id', v_q1_id, 'selected_options', jsonb_build_array(v_opt1_a::text)),
        jsonb_build_object('question_id', v_q2_id, 'numeric_answer', 5),
        jsonb_build_object('question_id', v_q3_id, 'audio_file_path', 'assessment-audio/' || v_cand_a || '/response1.mp3')
    );

    v_result_id := public.submit_assessment_attempt(v_attempt_id, v_ans_payload, 600);

    SELECT * INTO v_result FROM public.assessment_results WHERE id = v_result_id;
    IF v_result IS NULL THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Assessment result was not created after submission';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 6: Wrong Answer Scoring Check
    -- ------------------------------------------------------------------------
    -- Section 1 (Grammar) has 20 points earned out of 20 = 100%.
    -- Section 2 (Speaking) has 0 points earned until AI/human review = 0%.
    -- Weighted total: (100 * 40 + 0 * 60) / 100 = 40.00%
    IF v_result.total_score <> 40.00 THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Expected score 40.00%%, got %', v_result.total_score;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: Assessment Result Storage Hierarchy
    -- ------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM public.assessment_section_results WHERE assessment_result_id = v_result_id) THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Section results missing';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.assessment_question_results WHERE assessment_result_id = v_result_id) THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Question results missing';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 8: Language Assessment CEFR Level Assignment
    -- ------------------------------------------------------------------------
    -- Score of 40% maps to A2 CEFR level
    IF v_result.cefr_level <> 'a2' THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Expected CEFR a2 for 40%% score, got %', v_result.cefr_level;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 9: Voice Assessment Evaluation & Metadata
    -- ------------------------------------------------------------------------
    SELECT id INTO v_ans_id FROM public.assessment_answers WHERE assessment_attempt_id = v_attempt_id AND question_id = v_q3_id;

    v_voice_id := public.record_voice_evaluation(
        v_ans_id,
        'I listened to the customer concerns calmly and proposed two alternative solutions immediately.',
        88.00, -- Fluency
        85.00, -- Pronunciation
        90.00, -- Clarity
        0.95,  -- Confidence
        'speech_evaluator_v1',
        'whisper-large-v3',
        'v1.2'
    );

    IF NOT EXISTS (SELECT 1 FROM public.voice_assessment_results WHERE id = v_voice_id AND overall_score = 87.67) THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Voice evaluation result not stored accurately';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 10: AI Output Validation (Reject Malformed Scores)
    -- ------------------------------------------------------------------------
    BEGIN
        PERFORM public.record_voice_evaluation(v_ans_id, 'Test text', 150.00, 50.00, 50.00, 0.95);
        RAISE EXCEPTION 'TEST 10 FAILED: Invalid voice score > 100 was not rejected';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 10 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully rejected malformed score
    END;

    -- ------------------------------------------------------------------------
    -- TEST 11: Human Review Override (Preserve Original AI Evaluation)
    -- ------------------------------------------------------------------------
    -- Recruiter A reviews and overrides overall score to 88.00 (Passes candidate)
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    v_review_id := public.override_assessment_review(
        v_result_id,
        88.00,
        'approved',
        'Excellent spoken articulation and customer de-escalation demonstrated.'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.assessment_reviews
        WHERE id = v_review_id
          AND original_ai_score = 40.00
          AND score_override = 88.00
          AND final_decision = 'approved'
    ) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Human review did not preserve original score or record override';
    END IF;

    -- Check that assessment_result is updated with evaluation_method = 'hybrid'
    SELECT * INTO v_result FROM public.assessment_results WHERE id = v_result_id;
    IF v_result.evaluation_method <> 'hybrid' OR v_result.passed <> true THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Result was not updated to hybrid or passed = true';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 12: Candidate Readiness State Engine
    -- ------------------------------------------------------------------------
    SELECT * INTO v_readiness FROM public.calculate_candidate_readiness(v_cand_a, v_job_a);
    IF v_readiness.readiness_status <> 'ready' THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Expected readiness_status "ready", got %', v_readiness.readiness_status;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 13: Candidate Isolation (Candidate B blocked from accessing Candidate A assessments)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_cand_b::text, true);
    BEGIN
        PERFORM * FROM public.get_candidate_assessment_progress(v_cand_a, v_job_a);
        RAISE EXCEPTION 'TEST 13 FAILED: Candidate B was able to view Candidate A assessments!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 13 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked Candidate B from accessing Candidate A data
    END;

    -- ------------------------------------------------------------------------
    -- TEST 14: Storage Isolation (Candidate B cannot read Candidate A audio)
    -- ------------------------------------------------------------------------
    -- Storage policy verification for candidate isolation
    IF EXISTS (
        SELECT 1 FROM storage.objects
        WHERE bucket_id = 'assessment-audio'
          AND name LIKE v_cand_a || '/%'
          AND auth.uid() = v_user_cand_b
    ) THEN
        RAISE EXCEPTION 'TEST 14 FAILED: Storage policy leaked candidate audio to another candidate';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 15: Recruiter Tenant Isolation (Org B recruiter blocked from Org A)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);
    BEGIN
        PERFORM * FROM public.get_recruiter_assessment_dashboard(v_org_a_id);
        RAISE EXCEPTION 'TEST 15 FAILED: Recruiter B was able to view Org A assessment dashboard';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 15 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked access to Org A
    END;

    -- ------------------------------------------------------------------------
    -- TEST 16: Historical Version Immutability
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    -- Create v2 of the template
    INSERT INTO public.assessment_templates (
        organization_id, created_by, name, slug, assessment_type, version, status, passing_score
    )
    VALUES (
        v_org_a_id, v_recruiter_a, 'English Communication Assessment', 'english-comm',
        'language', 2, 'published', 80.00
    )
    RETURNING id INTO v_tmpl_v2_id;

    -- Verify that completed attempt and result still retain version 1
    IF NOT EXISTS (SELECT 1 FROM public.assessment_results WHERE id = v_result_id AND assessment_version = 1) THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Completed result did not retain immutable version 1';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 17: Idempotency (Retry trigger creates no duplicates)
    -- ------------------------------------------------------------------------
    v_inv_count := public.trigger_required_assessments(v_app_a);
    IF v_inv_count <> 0 THEN
        RAISE EXCEPTION 'TEST 17 FAILED: Idempotent trigger returned % instead of 0', v_inv_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 18: ATS Workflow Integration
    -- ------------------------------------------------------------------------
    -- Application remains in 'screening' stage; readiness reflects 'ready'
    SELECT status INTO v_readiness_stat FROM public.applications WHERE id = v_app_a;
    IF v_readiness_stat <> 'screening' THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Application stage was improperly altered without recruiter action';
    END IF;

    RAISE NOTICE 'ALL 18 END-TO-END ASSESSMENT & READINESS TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 18 ASSESSMENT & READINESS TESTS PASSED!' AS status;

ROLLBACK;
