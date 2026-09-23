-- ============================================================================
-- Hiren Beyond — Task 09 End-to-End Automated Test Suite: Interviews & Hiring
-- Executes all 18 test scenarios inside a safe rollback transaction
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_org_a_id UUID := '90c362ea-2bcc-45ba-98e4-c8a5d3c57376'; -- Hiren Beyond Platform
    v_org_b_id UUID := gen_random_uuid();
    v_recruiter_a UUID := gen_random_uuid();
    v_recruiter_b UUID := gen_random_uuid();
    v_interviewer_1 UUID := gen_random_uuid();
    v_interviewer_2 UUID := gen_random_uuid();
    v_user_cand_a UUID := gen_random_uuid();
    v_user_cand_b UUID := gen_random_uuid();
    v_cand_a UUID := gen_random_uuid();
    v_cand_b UUID := gen_random_uuid();
    v_job_a UUID := gen_random_uuid();
    v_job_b UUID := gen_random_uuid();
    v_app_a UUID := gen_random_uuid();
    v_role_recruiter UUID;
    v_role_hm UUID;
    
    -- Interview & Scorecard IDs
    v_tmpl_id UUID;
    v_round_1_id UUID;
    v_round_2_id UUID;
    v_app_round_1_id UUID;
    v_interview_1 UUID;
    v_interview_2 UUID;
    v_avail_id UUID;
    v_sec_id UUID;
    v_q1_id UUID;
    v_q2_id UUID;
    v_fb_1_id UUID;
    v_fb_2_id UUID;
    v_dec_id UUID;
    v_conflict RECORD;
    v_fb_sum RECORD;
    v_cand_view RECORD;
    v_app_stat TEXT;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. SETUP AUTH USERS, PROFILES, ORGS & ROLES
    -- ------------------------------------------------------------------------
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_recruiter_a, 'recruiter.a.task09@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b.task09@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_interviewer_1, 'interviewer.1.task09@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_interviewer_2, 'interviewer.2.task09@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_cand_a, 'cand.a.task09@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_cand_b, 'cand.b.task09@hirenbeyond.test', 'authenticated', 'authenticated');

    INSERT INTO public.profiles (id, email, full_name)
    VALUES
        (v_recruiter_a, 'recruiter.a.task09@hirenbeyond.test', 'Recruiter Alice'),
        (v_recruiter_b, 'recruiter.b.task09@hirenbeyond.test', 'Recruiter Bob'),
        (v_interviewer_1, 'interviewer.1.task09@hirenbeyond.test', 'Tech Lead Dave'),
        (v_interviewer_2, 'interviewer.2.task09@hirenbeyond.test', 'Engineering Manager Carol'),
        (v_user_cand_a, 'cand.a.task09@hirenbeyond.test', 'Candidate Alex'),
        (v_user_cand_b, 'cand.b.task09@hirenbeyond.test', 'Candidate Beatrice')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Setup Org B
    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES (v_org_b_id, 'Fintech Innovations Inc', 'fintech-innovations', 'client', 'active');

    SELECT id INTO v_role_recruiter FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_role_hm FROM public.roles WHERE key = 'recruiter_manager' LIMIT 1;

    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES 
        (v_org_a_id, v_recruiter_a, v_role_recruiter, 'active'),
        (v_org_b_id, v_recruiter_b, v_role_recruiter, 'active'),
        (v_org_a_id, v_interviewer_1, v_role_hm, 'active'),
        (v_org_a_id, v_interviewer_2, v_role_hm, 'active');

    -- Setup Candidates
    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_a, v_user_cand_a, 'active'),
        (v_cand_b, v_user_cand_b, 'active');

    -- Setup Jobs
    INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status, job_type)
    VALUES
        (v_job_a, v_org_a_id, v_recruiter_a, 'Staff Backend Engineer', 'staff-be-eng-' || substr(gen_random_uuid()::text, 1, 8), 'Build distributed cloud architectures', 'published', 'direct'),
        (v_job_b, v_org_b_id, v_recruiter_b, 'Frontend Architect', 'fe-arch-' || substr(gen_random_uuid()::text, 1, 8), 'Lead design systems', 'published', 'direct');

    -- Setup Applications
    INSERT INTO public.applications (id, job_id, candidate_id, organization_id, status)
    VALUES (v_app_a, v_job_a, v_cand_a, v_org_a_id, 'shortlisted');

    -- Context to Recruiter A
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- ------------------------------------------------------------------------
    -- TEST 1: Interview Template Creation & Versioning
    -- ------------------------------------------------------------------------
    INSERT INTO public.interview_templates (
        organization_id, created_by, name, description, interview_type, duration_minutes, version, status
    )
    VALUES (
        v_org_a_id, v_recruiter_a, 'Technical Deep Dive Template', 'Comprehensive system design and coding evaluation',
        'technical', 60, 1, 'published'
    )
    RETURNING id INTO v_tmpl_id;

    IF NOT EXISTS (SELECT 1 FROM public.interview_templates WHERE id = v_tmpl_id AND version = 1) THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Interview template v1 was not created';
    END IF;

    -- Add Scorecard Section & Questions
    INSERT INTO public.interview_scorecard_sections (interview_template_id, name, description, weight, sort_order)
    VALUES (v_tmpl_id, 'System Architecture', 'Evaluation of scalability and distributed patterns', 60.00, 1)
    RETURNING id INTO v_sec_id;

    INSERT INTO public.interview_scorecard_questions (section_id, question, rating_type, minimum_rating, maximum_rating, sort_order)
    VALUES
        (v_sec_id, 'Knowledge of PostgreSQL concurrency & indexing', 'numeric', 1, 5, 1)
    RETURNING id INTO v_q1_id;

    INSERT INTO public.interview_scorecard_questions (section_id, question, rating_type, minimum_rating, maximum_rating, sort_order)
    VALUES
        (v_sec_id, 'Demonstrates clear problem-solving communication', 'numeric', 1, 5, 2)
    RETURNING id INTO v_q2_id;

    -- ------------------------------------------------------------------------
    -- TEST 2: Job Interview Rounds Configuration
    -- ------------------------------------------------------------------------
    INSERT INTO public.interview_rounds (organization_id, job_id, name, round_type, sequence, duration_minutes, is_required)
    VALUES
        (v_org_a_id, v_job_a, 'Technical Round', 'technical', 1, 60, true)
    RETURNING id INTO v_round_1_id;

    INSERT INTO public.interview_rounds (organization_id, job_id, name, round_type, sequence, duration_minutes, is_required)
    VALUES
        (v_org_a_id, v_job_a, 'Leadership & Team Fit', 'manager', 2, 45, true)
    RETURNING id INTO v_round_2_id;

    IF NOT EXISTS (SELECT 1 FROM public.interview_rounds WHERE job_id = v_job_a AND sequence = 2) THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Interview rounds not properly configured';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 3: Application Interview Round Instantiation
    -- ------------------------------------------------------------------------
    INSERT INTO public.application_interview_rounds (application_id, interview_round_id, status, sequence)
    VALUES (v_app_a, v_round_1_id, 'requested', 1)
    RETURNING id INTO v_app_round_1_id;

    IF NOT EXISTS (SELECT 1 FROM public.application_interview_rounds WHERE id = v_app_round_1_id AND status = 'requested') THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Application interview round not instantiated';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 4: Interview Creation
    -- ------------------------------------------------------------------------
    INSERT INTO public.interviews (
        application_id, job_id, candidate_id, organization_id, interview_round_id,
        interview_template_id, title, description, interview_type, status, timezone
    )
    VALUES (
        v_app_a, v_job_a, v_cand_a, v_org_a_id, v_round_1_id,
        v_tmpl_id, 'Technical Round — Alex Backend Evaluation', 'System design interview',
        'technical', 'requested', 'Africa/Cairo'
    )
    RETURNING id INTO v_interview_1;

    IF NOT EXISTS (SELECT 1 FROM public.interviews WHERE id = v_interview_1 AND status = 'requested') THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Interview record not created';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 5: Multiple Interviewer Assignments
    -- ------------------------------------------------------------------------
    INSERT INTO public.interview_participants (interview_id, user_id, participant_type, is_required, response_status)
    VALUES
        (v_interview_1, v_interviewer_1, 'interviewer', true, 'accepted'),
        (v_interview_1, v_interviewer_2, 'hiring_manager', true, 'accepted');

    IF (SELECT count(*) FROM public.interview_participants WHERE interview_id = v_interview_1) <> 2 THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Multiple interviewers not properly assigned';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 6: Candidate Availability Submission
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_cand_a::text, true);

    INSERT INTO public.candidate_availability (candidate_id, start_at, end_at, timezone, status)
    VALUES (
        v_cand_a,
        '2026-09-20 10:00:00+00',
        '2026-09-20 12:00:00+00',
        'Africa/Cairo',
        'available'
    )
    RETURNING id INTO v_avail_id;

    IF NOT EXISTS (SELECT 1 FROM public.candidate_availability WHERE id = v_avail_id) THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Candidate availability not stored';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: Conflict Detection (Double-Booking Blocked)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- Schedule Interview 1 for 10:00 - 11:00 UTC
    PERFORM public.schedule_interview(
        v_interview_1,
        '2026-09-20 10:00:00+00',
        '2026-09-20 11:00:00+00',
        'Africa/Cairo',
        'Google Meet',
        'https://meet.google.com/abc-defg-hij',
        'google_meet'
    );

    -- Create Interview 2 for same candidate & interviewers
    INSERT INTO public.interviews (
        application_id, job_id, candidate_id, organization_id, interview_round_id,
        title, interview_type, status, timezone
    )
    VALUES (
        v_app_a, v_job_a, v_cand_a, v_org_a_id, v_round_2_id,
        'Managerial Fit Round', 'manager', 'requested', 'Africa/Cairo'
    )
    RETURNING id INTO v_interview_2;

    INSERT INTO public.interview_participants (interview_id, user_id, participant_type, is_required)
    VALUES (v_interview_2, v_interviewer_1, 'interviewer', true);

    -- Attempt overlapping schedule (10:30 - 11:30 UTC): must be blocked!
    BEGIN
        PERFORM public.schedule_interview(
            v_interview_2,
            '2026-09-20 10:30:00+00',
            '2026-09-20 11:30:00+00',
            'Africa/Cairo'
        );
        RAISE EXCEPTION 'TEST 7 FAILED: Overlapping interview was not blocked by conflict detection';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 7 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked by conflict detection
    END;

    -- ------------------------------------------------------------------------
    -- TEST 8: Successful Conflict-Free Scheduling & ATS Progression
    -- ------------------------------------------------------------------------
    -- Schedule Interview 2 for a non-overlapping slot (14:00 - 15:00 UTC)
    PERFORM public.schedule_interview(
        v_interview_2,
        '2026-09-20 14:00:00+00',
        '2026-09-20 15:00:00+00',
        'Africa/Cairo',
        'Google Meet',
        'https://meet.google.com/xyz-uvwx-rst',
        'google_meet'
    );

    IF NOT EXISTS (SELECT 1 FROM public.interviews WHERE id = v_interview_2 AND status = 'scheduled') THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Interview 2 was not successfully scheduled';
    END IF;

    -- Verify application moved to 'interview' status
    SELECT status INTO v_app_stat FROM public.applications WHERE id = v_app_a;
    IF v_app_stat <> 'interview' THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Application status was not advanced to "interview", got %', v_app_stat;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 9: Rescheduling & Schedule History Preservation
    -- ------------------------------------------------------------------------
    PERFORM public.reschedule_interview(
        v_interview_2,
        '2026-09-20 16:00:00+00',
        '2026-09-20 17:00:00+00',
        'Africa/Cairo',
        'Interviewer emergency reschedule'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.interview_schedule_history
        WHERE interview_id = v_interview_2
          AND previous_start_at = '2026-09-20 14:00:00+00'
          AND new_start_at = '2026-09-20 16:00:00+00'
          AND reason = 'Interviewer emergency reschedule'
    ) THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Reschedule history was not recorded';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 10: Cancellation & Metadata Preservation
    -- ------------------------------------------------------------------------
    PERFORM public.cancel_interview(v_interview_2, 'Position filled by earlier pipeline candidate');

    IF NOT EXISTS (
        SELECT 1 FROM public.interviews
        WHERE id = v_interview_2
          AND status = 'cancelled'
          AND cancellation_reason = 'Position filled by earlier pipeline candidate'
          AND cancelled_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Interview cancellation was not properly recorded';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 11: Scorecard & Feedback Submission
    -- ------------------------------------------------------------------------
    -- Interviewer 1 submits feedback for Interview 1
    PERFORM set_config('request.jwt.claim.sub', v_interviewer_1::text, true);

    v_fb_1_id := public.submit_interview_feedback(
        v_interview_1,
        4.5,
        'strong_hire',
        'Deep mastery of PostgreSQL MVCC, query planning, and distributed streaming.',
        'Slightly nervous at start, quickly gained confidence.',
        'Strong recommendation for immediate technical offer.',
        jsonb_build_array(
            jsonb_build_object('question_id', v_q1_id, 'numeric_value', 5),
            jsonb_build_object('question_id', v_q2_id, 'numeric_value', 4)
        )
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.interview_scorecard_responses
        WHERE feedback_id = v_fb_1_id AND question_id = v_q1_id AND numeric_value = 5
    ) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Scorecard question response was not recorded';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 12: Multiple Interviewer Feedback Aggregation
    -- ------------------------------------------------------------------------
    -- Interviewer 2 submits feedback for Interview 1
    PERFORM set_config('request.jwt.claim.sub', v_interviewer_2::text, true);

    v_fb_2_id := public.submit_interview_feedback(
        v_interview_1,
        4.0,
        'hire',
        'Pragmatic architectural choices and collaborative mindset.',
        'None observed.',
        'Agreed on hiring.',
        jsonb_build_array(
            jsonb_build_object('question_id', v_q1_id, 'numeric_value', 4),
            jsonb_build_object('question_id', v_q2_id, 'numeric_value', 4)
        )
    );

    SELECT * INTO v_fb_sum FROM public.get_interview_feedback_summary(v_interview_1);

    IF v_fb_sum.feedback_count <> 2 OR v_fb_sum.average_rating <> 4.25 THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Expected 2 feedbacks with 4.25 avg rating, got % feedbacks with % rating',
            v_fb_sum.feedback_count, v_fb_sum.average_rating;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 13: Authorized Hiring Decision
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    v_dec_id := public.record_hiring_decision(
        v_app_a,
        'hire',
        'Unanimous strong hire feedback from technical and manager rounds.'
    );

    IF NOT EXISTS (SELECT 1 FROM public.hiring_decisions WHERE id = v_dec_id AND decision = 'hire') THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Hiring decision was not recorded';
    END IF;

    -- Verify application status updated to 'hired'
    SELECT status INTO v_app_stat FROM public.applications WHERE id = v_app_a;
    IF v_app_stat <> 'hired' THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Application status was not updated to "hired", got %', v_app_stat;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 14: Unauthorized Decision Attempt (Candidate Blocked)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_cand_a::text, true);
    BEGIN
        PERFORM public.record_hiring_decision(v_app_a, 'hire', 'Candidate self-hiring attempt');
        RAISE EXCEPTION 'TEST 14 FAILED: Candidate was able to record hiring decision!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 14 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 15: Candidate Privacy Enforcement
    -- ------------------------------------------------------------------------
    -- Candidate querying interview view receives logistics only
    SELECT * INTO v_cand_view FROM public.get_candidate_interview_view(v_interview_1);
    IF v_cand_view.title IS NULL OR v_cand_view.meeting_url IS NULL THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Candidate could not view interview logistics';
    END IF;

    -- Candidate cannot query internal feedback summary
    BEGIN
        PERFORM public.get_interview_feedback_summary(v_interview_1);
        RAISE EXCEPTION 'TEST 15 FAILED: Candidate was able to view interviewer feedback summary!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 15 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 16: Recruiter Tenant Isolation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);
    BEGIN
        PERFORM * FROM public.get_recruiter_interview_dashboard(v_org_a_id);
        RAISE EXCEPTION 'TEST 16 FAILED: Recruiter B was able to view Org A interview dashboard';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 16 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 17: Idempotency & Safe Overwrite of Decisions
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- Update decision to 'hold' due to budget freeze
    PERFORM public.record_hiring_decision(
        v_app_a,
        'hold',
        'Headcount temporarily frozen by executive team'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.hiring_decision_history
        WHERE application_id = v_app_a
          AND previous_decision = 'hire'
          AND new_decision = 'hold'
    ) THEN
        RAISE EXCEPTION 'TEST 17 FAILED: Decision update did not preserve decision history';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 18: Historical Immutability
    -- ------------------------------------------------------------------------
    -- Completed and cancelled interviews remain visible in history
    IF (SELECT count(*) FROM public.interviews WHERE application_id = v_app_a) <> 2 THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Historical interviews were deleted';
    END IF;

    RAISE NOTICE 'ALL 18 END-TO-END INTERVIEWS & HIRING TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 18 INTERVIEW & HIRING TESTS PASSED!' AS status;

ROLLBACK;
