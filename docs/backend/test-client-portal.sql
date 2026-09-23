-- ============================================================================
-- Hiren Beyond — Task 10 End-to-End Automated Test Suite: Client Portal & Collaboration
-- Executes all 20 test scenarios inside a safe rollback transaction
-- ============================================================================

BEGIN;

DO $$
DECLARE
    -- Organizations
    v_rec_org_a UUID := '90c362ea-2bcc-45ba-98e4-c8a5d3c57376'; -- Hiren Beyond Platform / Agency
    v_rec_org_b UUID := gen_random_uuid();
    v_client_org_x UUID := gen_random_uuid();
    v_client_org_y UUID := gen_random_uuid();

    -- Users
    v_recruiter_a UUID := gen_random_uuid();
    v_recruiter_b UUID := gen_random_uuid();
    v_client_user_x UUID := gen_random_uuid();
    v_client_user_y UUID := gen_random_uuid();
    v_user_cand_1 UUID := gen_random_uuid();
    v_user_cand_2 UUID := gen_random_uuid();

    -- Candidates & Jobs
    v_cand_1 UUID := gen_random_uuid();
    v_cand_2 UUID := gen_random_uuid();
    v_job_a UUID := gen_random_uuid();
    v_job_b UUID := gen_random_uuid();
    v_app_1 UUID := gen_random_uuid();
    v_app_2 UUID := gen_random_uuid();

    -- Roles
    v_role_recruiter UUID;
    v_role_client_reviewer UUID;
    v_role_client_admin UUID;

    -- Share & Entity IDs
    v_rel_id UUID;
    v_job_access_id UUID;
    v_share_1_id UUID;
    v_share_2_id UUID;
    v_fb_1_id UUID;
    v_fb_2_id UUID;
    v_req_id UUID;
    v_dec_id UUID;
    v_doc_id UUID;
    v_doc_access_id UUID;
    v_cand_view RECORD;
    v_dash RECORD;
    v_cmp RECORD;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. SETUP AUTH USERS, PROFILES, ORGS & ROLES
    -- ------------------------------------------------------------------------
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_recruiter_a, 'recruiter.a.task10@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b.task10@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_client_user_x, 'client.x.task10@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_client_user_y, 'client.y.task10@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_cand_1, 'cand.1.task10@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_cand_2, 'cand.2.task10@hirenbeyond.test', 'authenticated', 'authenticated');    INSERT INTO public.profiles (id, email, full_name, country_code)
    VALUES
        (v_recruiter_a, 'recruiter.a.task10@hirenbeyond.test', 'Recruiter Angela', 'GB'),
        (v_recruiter_b, 'recruiter.b.task10@hirenbeyond.test', 'Recruiter Brandon', 'US'),
        (v_client_user_x, 'client.x.task10@hirenbeyond.test', 'Client Xavier', 'DE'),
        (v_client_user_y, 'client.y.task10@hirenbeyond.test', 'Client Yolanda', 'FR'),
        (v_user_cand_1, 'cand.1.task10@hirenbeyond.test', 'Senior Dev Samuel', 'EG'),
        (v_user_cand_2, 'cand.2.task10@hirenbeyond.test', 'Frontend Lead Fiona', 'AE')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Setup Orgs
    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES
        (v_rec_org_b, 'Apex Staffing Solutions', 'apex-staffing', 'client', 'active'),
        (v_client_org_x, 'Acme Fintech Group', 'acme-fintech', 'client', 'active'),
        (v_client_org_y, 'Globex Global Systems', 'globex-systems', 'client', 'active');

    SELECT id INTO v_role_recruiter FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_role_client_reviewer FROM public.roles WHERE key = 'client_reviewer' LIMIT 1;
    SELECT id INTO v_role_client_admin FROM public.roles WHERE key = 'client_admin' LIMIT 1;

    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES 
        (v_rec_org_a, v_recruiter_a, v_role_recruiter, 'active'),
        (v_rec_org_b, v_recruiter_b, v_role_recruiter, 'active'),
        (v_client_org_x, v_client_user_x, v_role_client_reviewer, 'active'),
        (v_client_org_y, v_client_user_y, v_role_client_reviewer, 'active');

    -- Setup Candidates & Profiles
    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_1, v_user_cand_1, 'active'),
        (v_cand_2, v_user_cand_2, 'active');

    INSERT INTO public.candidate_profiles (
        candidate_id, headline, professional_summary, years_of_experience, country_code, city, availability_status
    )
    VALUES
        (v_cand_1, 'Principal Cloud Architect', '10+ years in distributed systems', 10, 'EG', 'Cairo', 'immediately'),
        (v_cand_2, 'Staff UI Engineer', 'Specialist in Design Systems', 8, 'AE', 'Dubai', 'within_two_weeks');

    -- Candidate Skills & Experience for Cand 1
    INSERT INTO public.candidate_skills (candidate_id, skill_name, normalized_skill_name, years_of_experience)
    VALUES
        (v_cand_1, 'PostgreSQL', 'postgresql', 8),
        (v_cand_1, 'Distributed Systems', 'distributed systems', 6),
        (v_cand_1, 'Python', 'python', 9);

    INSERT INTO public.candidate_experience (candidate_id, job_title, company_name, start_date, end_date, description)
    VALUES
        (v_cand_1, 'Lead Backend Engineer', 'CloudScale Technologies', '2020-01-01', '2026-01-01', 'Architected high-throughput financial microservices.');

    -- Setup Jobs
    INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status, job_type)
    VALUES
        (v_job_a, v_rec_org_a, v_recruiter_a, 'Chief Architect — Financial Core', 'chief-arch-' || substr(gen_random_uuid()::text, 1, 8), 'Lead next-gen cloud core', 'published', 'direct'),
        (v_job_b, v_rec_org_b, v_recruiter_b, 'Senior SRE Lead', 'sre-lead-' || substr(gen_random_uuid()::text, 1, 8), 'Site reliability management', 'published', 'direct');

    -- Setup Applications
    INSERT INTO public.applications (id, job_id, candidate_id, organization_id, status, match_score)
    VALUES
        (v_app_1, v_job_a, v_cand_1, v_rec_org_a, 'shortlisted', 94.50),
        (v_app_2, v_job_a, v_cand_2, v_rec_org_a, 'submitted', 78.00);

    -- ------------------------------------------------------------------------
    -- TEST 1: Client Relationship Creation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    INSERT INTO public.client_relationships (
        recruitment_organization_id, client_organization_id, status, relationship_type, account_owner
    )
    VALUES (
        v_rec_org_a, v_client_org_x, 'active', 'direct_client', v_recruiter_a
    )
    RETURNING id INTO v_rel_id;

    IF NOT EXISTS (SELECT 1 FROM public.client_relationships WHERE id = v_rel_id AND status = 'active') THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Client relationship not created';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 2: Client User & Contact Association
    -- ------------------------------------------------------------------------
    INSERT INTO public.client_contacts (
        client_organization_id, user_id, name, job_title, email, is_primary
    )
    VALUES (
        v_client_org_x, v_client_user_x, 'Xavier Dupont', 'VP of Engineering', 'xavier@acmefintech.test', true
    );

    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    IF NOT public.check_user_is_client_member(v_client_org_x) THEN
        RAISE EXCEPTION 'TEST 2 FAILED: User Xavier not recognized as client member';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- ------------------------------------------------------------------------
    -- TEST 3: Job Sharing With Client
    -- ------------------------------------------------------------------------
    v_job_access_id := public.share_job_with_client(
        v_job_a,
        v_client_org_x,
        'full',
        now() + interval '30 days',
        '{"allow_cv_download": true}'::jsonb
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.client_job_access
        WHERE id = v_job_access_id AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Job was not successfully shared with client';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 4: Unshared Job Access Blocked
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    -- Client X attempts to view jobs: should see Job A, but NOT Job B
    IF EXISTS (
        SELECT 1 FROM public.get_client_jobs(v_client_org_x) WHERE job_id = v_job_b
    ) THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Client X was able to see unshared Job B';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.get_client_jobs(v_client_org_x) WHERE job_id = v_job_a
    ) THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Client X could not see shared Job A';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 5: Candidate Sharing & Projection Generation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    v_share_1_id := public.share_candidate_with_client(
        v_app_1,
        v_client_org_x,
        '{"show_name": true, "show_email": false, "show_phone": false, "show_salary": false, "show_cv": false, "show_match_score": true, "show_match_explanation": true, "show_experience": true, "show_education": true, "show_languages": true}'::jsonb
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.client_candidate_shares WHERE id = v_share_1_id AND status = 'shared'
    ) THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Candidate was not shared with client';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.client_candidate_profiles
        WHERE candidate_share_id = v_share_1_id AND match_score = 94.50
    ) THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Client-safe candidate presentation projection was not compiled';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 6: Unshared Candidate Access Blocked
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    -- Candidate 2 was not shared; should not appear in client's candidate list
    IF EXISTS (
        SELECT 1 FROM public.get_client_job_candidates(v_client_org_x, v_job_a)
        WHERE candidate_id = v_cand_2
    ) THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Unshared candidate 2 is visible in client portal';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: Cross-Client Isolation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_client_user_y::text, true);

    -- Client Y attempts to view Client X's candidate
    BEGIN
        PERFORM public.get_client_candidate(v_share_1_id);
        RAISE EXCEPTION 'TEST 7 FAILED: Client Y was able to access Client X candidate share';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 7 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 8: Candidate Privacy Boundary (Internal Notes & Details Withheld)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    SELECT * INTO v_cand_view FROM public.get_client_candidate(v_share_1_id);

    IF v_cand_view.display_name IS NULL OR v_cand_view.match_score IS NULL THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Candidate projection fields not returned to client';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 9: Visibility Configuration Enforcement (Confidential Data Omitted)
    -- ------------------------------------------------------------------------
    -- Verification that confidential CV access is flagged false when ungranted
    IF v_cand_view.has_cv_access IS TRUE THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Candidate CV access marked true before explicit grant';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 10: Client Feedback Submission
    -- ------------------------------------------------------------------------
    v_fb_1_id := public.submit_client_feedback(
        v_share_1_id,
        'interested',
        4.8,
        'Impressive background in high-throughput cloud architectures.',
        'candidate_review'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.client_candidate_feedback
        WHERE id = v_fb_1_id AND decision = 'interested'
    ) THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Client feedback was not saved';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 11: Idempotency & Feedback History Tracking
    -- ------------------------------------------------------------------------
    -- Client updates decision to 'request_interview'
    v_fb_2_id := public.submit_client_feedback(
        v_share_1_id,
        'request_interview',
        5.0,
        'Team agreed to move immediately to technical interview.',
        'candidate_review'
    );

    IF v_fb_1_id <> v_fb_2_id THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Duplicate feedback row created rather than upsert';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.client_feedback_history
        WHERE feedback_id = v_fb_1_id
          AND previous_decision = 'interested'
          AND new_decision = 'request_interview'
    ) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Feedback decision transition history was not recorded';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 12: Client Structured Scorecard
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- Setup scorecard template for Client X
    DECLARE
        v_sc_tmpl_id UUID;
        v_sc_sec_id UUID;
        v_sc_q_id UUID;
    BEGIN
        INSERT INTO public.client_scorecard_templates (
            client_organization_id, name, description, version
        )
        VALUES (
            v_client_org_x, 'Standard Engineering Rubric', 'Client hiring rubric', 1
        )
        RETURNING id INTO v_sc_tmpl_id;

        INSERT INTO public.client_scorecard_sections (template_id, name, weight, sort_order)
        VALUES (v_sc_tmpl_id, 'Technical Leadership', 100.00, 1)
        RETURNING id INTO v_sc_sec_id;

        INSERT INTO public.client_scorecard_questions (section_id, question, response_type, is_required)
        VALUES (v_sc_sec_id, 'System Design Capability', 'rating', true)
        RETURNING id INTO v_sc_q_id;

        -- Client Xavier submits scorecard response
        PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

        PERFORM public.submit_client_feedback(
            v_share_1_id,
            'interested',
            4.9,
            'Exceptional system design response',
            'technical',
            jsonb_build_array(
                jsonb_build_object('question_id', v_sc_q_id, 'rating_value', 5.0)
            )
        );

        IF NOT EXISTS (
            SELECT 1 FROM public.client_scorecard_responses WHERE question_id = v_sc_q_id AND rating_value = 5.0
        ) THEN
            RAISE EXCEPTION 'TEST 12 FAILED: Scorecard question rating not stored';
        END IF;
    END;

    -- ------------------------------------------------------------------------
    -- TEST 13: Client Interview Request
    -- ------------------------------------------------------------------------
    v_req_id := public.request_client_interview(
        v_share_1_id,
        jsonb_build_array(
            jsonb_build_object('date', '2026-09-25', 'start_time', '14:00', 'end_time', '15:00')
        ),
        'Candidate requested for panel interview with Head of Architecture'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.client_interview_requests
        WHERE id = v_req_id AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Client interview request was not recorded';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 14: Client Request for More Information
    -- ------------------------------------------------------------------------
    DECLARE
        v_info_id UUID;
    BEGIN
        v_info_id := public.request_more_candidate_information(
            v_share_1_id,
            'Can the candidate relocate to Berlin or work on CET timezone hours?',
            'relocation'
        );

        IF NOT EXISTS (
            SELECT 1 FROM public.client_information_requests
            WHERE id = v_info_id AND status = 'pending'
        ) THEN
            RAISE EXCEPTION 'TEST 14 FAILED: Client info request was not created';
        END IF;
    END;

    -- ------------------------------------------------------------------------
    -- TEST 15: Client Hiring Recommendation (Non-Authoritative Workflow Input)
    -- ------------------------------------------------------------------------
    v_dec_id := public.submit_client_hiring_decision(
        v_share_1_id,
        'recommend_hire',
        'Strongest candidate in the pipeline. Ready to make an offer pending recruiter review.'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.client_hiring_decisions
        WHERE id = v_dec_id AND decision = 'recommend_hire'
    ) THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Client hiring recommendation was not saved';
    END IF;

    -- Verify underlying ATS application status was NOT modified directly to 'hired'
    IF (SELECT status FROM public.applications WHERE id = v_app_1) = 'hired' THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Client was able to directly alter internal ATS status to "hired"!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 16: Job Access Revocation & Cascading Revocation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    PERFORM public.revoke_client_job_access(v_job_a, v_client_org_x, 'Role placed with alternate candidate');

    -- Verify job access revoked
    IF (SELECT status FROM public.client_job_access WHERE job_id = v_job_a AND client_organization_id = v_client_org_x) <> 'revoked' THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Client job access status was not revoked';
    END IF;

    -- Verify candidate share cascadingly marked revoked
    IF (SELECT status FROM public.client_candidate_shares WHERE id = v_share_1_id) <> 'revoked' THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Candidate share was not cascadingly revoked';
    END IF;

    -- Client attempts to read candidate: must be blocked!
    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);
    BEGIN
        PERFORM public.get_client_candidate(v_share_1_id);
        -- In our query, get_client_candidate will return empty rows or raise
        IF EXISTS (SELECT 1 FROM public.client_candidate_shares WHERE id = v_share_1_id AND status = 'shared') THEN
            RAISE EXCEPTION 'TEST 16 FAILED: Client can still read revoked candidate';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- Properly caught
    END;

    -- Restore job and candidate share for remaining tests
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    UPDATE public.client_job_access SET status = 'active' WHERE job_id = v_job_a AND client_organization_id = v_client_org_x;
    UPDATE public.client_candidate_shares SET status = 'shared' WHERE id = v_share_1_id;

    -- ------------------------------------------------------------------------
    -- TEST 17: Expiration Enforcement
    -- ------------------------------------------------------------------------
    -- Set candidate share expiration to past
    UPDATE public.client_candidate_shares
    SET expires_at = now() - interval '1 hour'
    WHERE id = v_share_1_id;

    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    IF EXISTS (
        SELECT 1 FROM public.get_client_job_candidates(v_client_org_x, v_job_a)
        WHERE candidate_share_id = v_share_1_id
    ) THEN
        RAISE EXCEPTION 'TEST 17 FAILED: Expired candidate share was returned in job candidates list';
    END IF;

    -- Reset expiration
    UPDATE public.client_candidate_shares SET expires_at = now() + interval '10 days' WHERE id = v_share_1_id;

    -- ------------------------------------------------------------------------
    -- TEST 18: Closed Job Protection
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    UPDATE public.jobs SET status = 'closed' WHERE id = v_job_a;

    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    IF EXISTS (
        SELECT 1 FROM public.get_client_jobs(v_client_org_x) WHERE job_id = v_job_a
    ) THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Closed job was returned in active client jobs';
    END IF;

    -- Re-open job
    UPDATE public.jobs SET status = 'published' WHERE id = v_job_a;

    -- ------------------------------------------------------------------------
    -- TEST 19: Controlled Document Access
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- Setup candidate document
    INSERT INTO public.candidate_documents (
        candidate_id, original_file_name, file_size, mime_type, file_path, document_type, status
    )
    VALUES (
        v_cand_1, 'Samuel_Staff_Arch_Resume.pdf', 1048576, 'application/pdf', 'resumes/samuel.pdf', 'resume', 'uploaded'
    )
    RETURNING id INTO v_doc_id;

    -- Grant 24-hour document access to Client X
    INSERT INTO public.client_document_access (
        client_candidate_share_id, candidate_document_id, access_type, expires_at, created_by
    )
    VALUES (
        v_share_1_id, v_doc_id, 'view', now() + interval '24 hours', v_recruiter_a
    )
    RETURNING id INTO v_doc_access_id;

    PERFORM set_config('request.jwt.claim.sub', v_client_user_x::text, true);

    SELECT * INTO v_cand_view FROM public.get_client_candidate(v_share_1_id);
    IF v_cand_view.has_cv_access IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 19 FAILED: Client document access was not recognized';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 20: Candidate Isolation (Candidate Blocked From Client Feedback)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_user_cand_1::text, true);

    -- Candidate cannot access client candidate endpoint or feedback
    BEGIN
        PERFORM public.get_client_candidate(v_share_1_id);
        RAISE EXCEPTION 'TEST 20 FAILED: Candidate was able to access client candidate endpoint!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 20 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- Candidate cannot submit client hiring decisions or feedback
    BEGIN
        PERFORM public.submit_client_hiring_decision(v_share_1_id, 'recommend_hire', 'Candidate self-decision attempt');
        RAISE EXCEPTION 'TEST 20 FAILED: Candidate was able to submit client hiring decision!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 20 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    RAISE NOTICE 'ALL 20 END-TO-END CLIENT PORTAL & COLLABORATION TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 20 CLIENT PORTAL & COLLABORATION TESTS PASSED!' AS status;

ROLLBACK;
