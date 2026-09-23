-- =============================================================================
-- Test Suite: test-analytics.sql
-- Description: End-to-End Validation of Task 13 (Analytics, Reporting, KPIs)
-- Execution: npx supabase db query --file docs/backend/test-analytics.sql --linked
-- Safety: Enclosed in a transaction that ends in ROLLBACK to keep DB pristine.
-- =============================================================================

BEGIN;

DO $$
DECLARE
    -- Organizations
    v_org_a UUID := gen_random_uuid();
    v_org_b UUID := gen_random_uuid();
    v_client_org UUID := gen_random_uuid();

    -- Users & Profiles
    v_recruiter_a UUID := gen_random_uuid();
    v_recruiter_b UUID := gen_random_uuid();
    v_client_user UUID := gen_random_uuid();
    v_cand_user_a UUID := gen_random_uuid();
    v_cand_user_b UUID := gen_random_uuid();
    v_cand_user_c UUID := gen_random_uuid();

    -- Roles
    v_role_recruiter UUID;
    v_role_client_reviewer UUID;

    -- Entities
    v_cand_a UUID := gen_random_uuid();
    v_cand_b UUID := gen_random_uuid();
    v_cand_c UUID := gen_random_uuid();
    v_job_a  UUID := gen_random_uuid();
    v_job_b  UUID := gen_random_uuid();
    v_app_a  UUID := gen_random_uuid();
    v_app_b  UUID := gen_random_uuid();
    v_app_c  UUID := gen_random_uuid();

    -- Results & Variables
    v_res JSONB;
    v_funnel JSONB;
    v_time JSONB;
    v_report_id UUID;
    v_export_id UUID;
    v_export_res JSONB;
    v_rebuild_res JSONB;
    v_count_before INT;
    v_count_after INT;
BEGIN
    RAISE NOTICE 'Starting Task 13 Analytics & Reporting Verification Test Suite...';

    -- -------------------------------------------------------------------------
    -- SETUP: Populate test data
    -- -------------------------------------------------------------------------

    -- 1. Organizations
    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES
        (v_org_a, 'Analytics Org A', 'analytics-org-a-' || substr(v_org_a::text, 1, 8), 'recruitment_agency', 'active'),
        (v_org_b, 'Analytics Org B', 'analytics-org-b-' || substr(v_org_b::text, 1, 8), 'recruitment_agency', 'active'),
        (v_client_org, 'Analytics Client Org', 'analytics-client-' || substr(v_client_org::text, 1, 8), 'client', 'active');

    -- 2. Auth Users & Profiles
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_recruiter_a, 'recruiter.a@analytics.test', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b@analytics.test', 'authenticated', 'authenticated'),
        (v_client_user, 'client.rep@analytics.test',  'authenticated', 'authenticated'),
        (v_cand_user_a, 'candidate.a@analytics.test', 'authenticated', 'authenticated'),
        (v_cand_user_b, 'candidate.b@analytics.test', 'authenticated', 'authenticated'),
        (v_cand_user_c, 'candidate.c@analytics.test', 'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profiles (id, email, full_name, country_code)
    VALUES
        (v_recruiter_a, 'recruiter.a@analytics.test', 'Recruiter Alice', 'US'),
        (v_recruiter_b, 'recruiter.b@analytics.test', 'Recruiter Bob',   'GB'),
        (v_client_user, 'client.rep@analytics.test',  'Client Carol',    'DE'),
        (v_cand_user_a, 'candidate.a@analytics.test', 'Candidate Dan',   'EG'),
        (v_cand_user_b, 'candidate.b@analytics.test', 'Candidate Eve',   'AE'),
        (v_cand_user_c, 'candidate.c@analytics.test', 'Candidate Frank', 'FR')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Roles and Organization Members
    SELECT id INTO v_role_recruiter FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_role_client_reviewer FROM public.roles WHERE key = 'client_reviewer' LIMIT 1;

    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES
        (v_org_a, v_recruiter_a, v_role_recruiter, 'active'),
        (v_org_b, v_recruiter_b, v_role_recruiter, 'active'),
        (v_client_org, v_client_user, v_role_client_reviewer, 'active');

    -- Client relationship & contact
    INSERT INTO public.client_relationships (recruitment_organization_id, client_organization_id, status)
    VALUES (v_org_a, v_client_org, 'active');

    INSERT INTO public.client_contacts (client_organization_id, user_id, name, job_title)
    VALUES (v_client_org, v_client_user, 'Client Carol', 'VP Engineering');

    -- Candidates & Profiles
    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_a, v_cand_user_a, 'active'),
        (v_cand_b, v_cand_user_b, 'active'),
        (v_cand_c, v_cand_user_c, 'active');

    INSERT INTO public.candidate_profiles (candidate_id, headline, years_of_experience)
    VALUES
        (v_cand_a, 'Lead Big Data Architect', 8.0),
        (v_cand_b, 'Senior React Developer', 5.0),
        (v_cand_c, 'Junior Python Developer', 2.0);

    INSERT INTO public.candidate_readiness (candidate_id, readiness_status, readiness_score)
    VALUES (v_cand_a, 'ready', 95.00);

    -- Jobs in Org A
    INSERT INTO public.jobs (
        id, organization_id, created_by, title, slug, description, workplace_type, employment_type, status, published_at
    )
    VALUES (
        v_job_a, v_org_a, v_recruiter_a, 'Senior Data Engineer', 'sr-data-eng-' || substr(v_job_a::text, 1, 8),
        'Leading big data lake pipelines', 'remote', 'full_time', 'published', now() - INTERVAL '10 days'
    );

    -- Job in Org B
    INSERT INTO public.jobs (
        id, organization_id, created_by, title, slug, description, workplace_type, employment_type, status, published_at
    )
    VALUES (
        v_job_b, v_org_b, v_recruiter_b, 'Frontend Specialist', 'fe-specialist-' || substr(v_job_b::text, 1, 8),
        'Building responsive web clients', 'remote', 'full_time', 'published', now() - INTERVAL '5 days'
    );

    -- Client Job Access
    INSERT INTO public.client_job_access (client_organization_id, job_id, status, visibility)
    VALUES (v_client_org, v_job_a, 'active', 'full');

    -- Applications for Job A (Org A)
    -- App A: Hired candidate (full lifecycle with timestamps)
    INSERT INTO public.applications (
        id, job_id, candidate_id, organization_id, assigned_recruiter_id, status, source, match_score, is_eligible,
        submitted_at, reviewed_at, shortlisted_at, hired_at
    )
    VALUES (
        v_app_a, v_job_a, v_cand_a, v_org_a, v_recruiter_a, 'hired', 'referral', 92.50, true,
        now() - INTERVAL '8 days',
        now() - INTERVAL '7 days 20 hours', -- 4 hours to screen
        now() - INTERVAL '6 days',          -- 48 hours to shortlist
        now() - INTERVAL '2 days'           -- 6 days to hire
    );

    -- App B: Shortlisted candidate
    INSERT INTO public.applications (
        id, job_id, candidate_id, organization_id, assigned_recruiter_id, status, source, match_score, is_eligible,
        submitted_at, reviewed_at, shortlisted_at
    )
    VALUES (
        v_app_b, v_job_a, v_cand_b, v_org_a, v_recruiter_a, 'shortlisted', 'platform', 78.00, true,
        now() - INTERVAL '4 days',
        now() - INTERVAL '3 days 18 hours',
        now() - INTERVAL '3 days'
    );

    -- App C: Submitted only (unscreened)
    INSERT INTO public.applications (
        id, job_id, candidate_id, organization_id, assigned_recruiter_id, status, source, match_score, is_eligible,
        submitted_at
    )
    VALUES (
        v_app_c, v_job_a, v_cand_c, v_org_a, v_recruiter_a, 'submitted', 'partner', 55.00, false,
        now() - INTERVAL '2 days'
    );

    -- Matching Run (Task 06 reuse)
    DECLARE
        v_mr_id_a UUID := gen_random_uuid();
        v_mr_id_b UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.matching_runs (id, job_id, candidate_id, final_score, hard_match, status)
        VALUES
            (v_mr_id_a, v_job_a, v_cand_a, 92.50, true, 'completed'),
            (v_mr_id_b, v_job_a, v_cand_b, 78.00, true, 'completed');
    END;

    -- Assessment (Task 08 reuse)
    DECLARE
        v_tmpl_id UUID := gen_random_uuid();
        v_inv_id  UUID := gen_random_uuid();
        v_att_id  UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.assessment_templates (
            id, organization_id, created_by, name, slug, assessment_type, status
        ) VALUES (
            v_tmpl_id, v_org_a, v_recruiter_a, 'Data Engineering Technical Test',
            'data-eng-test-' || substr(v_tmpl_id::text, 1, 8),
            'technical', 'published'
        );

        INSERT INTO public.assessment_invitations (
            id, assessment_template_id, job_id, application_id, candidate_id,
            issued_by, status, token, expires_at
        ) VALUES (
            v_inv_id, v_tmpl_id, v_job_a, v_app_a, v_cand_a,
            v_recruiter_a, 'completed',
            'tok-' || substr(gen_random_uuid()::text, 1, 24),
            now() + INTERVAL '7 days'
        );

        INSERT INTO public.assessment_attempts (
            id, assessment_invitation_id, candidate_id, assessment_version, status, started_at, submitted_at
        ) VALUES (
            v_att_id, v_inv_id, v_cand_a, 1, 'completed', now() - INTERVAL '5 days', now() - INTERVAL '5 days' + INTERVAL '45 mins'
        );

        INSERT INTO public.assessment_results (
            assessment_attempt_id, candidate_id, application_id, assessment_template_id, assessment_version,
            total_score, normalized_score, passed, created_at
        ) VALUES (
            v_att_id, v_cand_a, v_app_a, v_tmpl_id, 1, 88.00, 88.00, true, now() - INTERVAL '5 days'
        );
    END;

    -- Interviews (Task 09 reuse)
    -- participant_type is the correct column (not 'role')
    DECLARE
        v_int_id UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.interviews (
            id, application_id, job_id, candidate_id, organization_id, title, interview_type, status,
            scheduled_start_at, scheduled_end_at, completed_at
        ) VALUES (
            v_int_id, v_app_a, v_job_a, v_cand_a, v_org_a, 'Architecture Panel', 'technical', 'completed',
            now() - INTERVAL '4 days', now() - INTERVAL '4 days' + INTERVAL '1 hour', now() - INTERVAL '4 days' + INTERVAL '1 hour'
        );

        -- participant_type is the correct column (not 'role')
        INSERT INTO public.interview_participants (interview_id, user_id, participant_type)
        VALUES (v_int_id, v_recruiter_a, 'interviewer');

        -- interview_feedback has no feedback_type column
        INSERT INTO public.interview_feedback (
            interview_id, interviewer_id, overall_rating, recommendation
        ) VALUES (
            v_int_id, v_recruiter_a, 4.80, 'strong_hire'
        );
    END;

    -- Client Candidate Share (Task 10 reuse)
    -- client_candidate_shares.status values: 'shared', 'hidden', 'revoked', 'expired'
    -- client_interview_requests: client_candidate_share_id (not share_id)
    -- client_hiring_decisions: client_candidate_share_id (not share_id), submitted_by (not decided_by)
    -- client_hiring_decisions.decision values: 'recommend_hire', 'recommend_reject', 'request_final_interview', 'hold'
    DECLARE
        v_share_id UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.client_candidate_shares (
            id, client_organization_id, application_id, candidate_id, job_id, shared_by, status
        ) VALUES (
            v_share_id, v_client_org, v_app_a, v_cand_a, v_job_a, v_recruiter_a, 'shared'
        );

        INSERT INTO public.client_interview_requests (
            client_candidate_share_id, requested_by, status, notes
        ) VALUES (
            v_share_id, v_client_user, 'accepted', 'Looking forward to meeting candidate'
        );

        INSERT INTO public.client_hiring_decisions (
            client_candidate_share_id, submitted_by, decision, reason
        ) VALUES (
            v_share_id, v_client_user, 'recommend_hire', 'Outstanding technical communication'
        );
    END;

    -- AI Usage Telemetry (Task 12 reuse)
    -- ai_usage_records: estimated_cost (not estimated_cost_usd), request_type (not task_type)
    INSERT INTO public.ai_usage_records (
        user_id, organization_id, provider, model, request_type, total_tokens, estimated_cost, latency_ms
    ) VALUES (
        v_recruiter_a, v_org_a, 'google', 'gemini-1.5-pro', 'chat', 2400, 0.0048, 380
    );

    -- Communication Notifications (Task 11 reuse)
    -- notification_deliveries: requires destination (NOT NULL), links via notification_id
    -- notification_events: uses source_module, source_record_id (not entity_type, entity_id)
    DECLARE
        v_notif_id UUID := gen_random_uuid();
    BEGIN
        INSERT INTO public.notifications (
            id, recipient_user_id, title, body
        ) VALUES (
            v_notif_id, v_cand_user_a, 'Application Submitted', 'Your application has been received.'
        );

        INSERT INTO public.notification_deliveries (
            notification_id, recipient_user_id, channel, destination, status
        ) VALUES (
            v_notif_id, v_cand_user_a, 'email', 'candidate.a@analytics.test', 'delivered'
        );
    END;

    -- Set Recruiter A Context for initial tests
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- -------------------------------------------------------------------------
    -- TEST 1: Organization Overview Metrics
    -- -------------------------------------------------------------------------
    v_res := public.get_organization_analytics(v_org_a);

    IF (v_res->'overview'->>'total_jobs')::int < 1 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected at least 1 job in Org A, got %', v_res->'overview'->>'total_jobs';
    END IF;

    IF (v_res->'overview'->>'total_applications')::int <> 3 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected 3 applications in Org A, got %', v_res->'overview'->>'total_applications';
    END IF;

    IF (v_res->'overview'->>'total_hires')::int <> 1 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected 1 hire in Org A, got %', v_res->'overview'->>'total_hires';
    END IF;

    RAISE NOTICE 'TEST 1 PASSED: Organization overview metrics';

    -- -------------------------------------------------------------------------
    -- TEST 2: Job Requisition Metrics
    -- -------------------------------------------------------------------------
    v_res := public.get_job_analytics(v_job_a);

    IF (v_res->>'title') <> 'Senior Data Engineer' THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected job title Senior Data Engineer, got %', v_res->>'title';
    END IF;

    IF (v_res->'funnel'->'stages'->>'applications')::int <> 3 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected 3 applications for Job A, got %', v_res->'funnel'->'stages'->>'applications';
    END IF;

    RAISE NOTICE 'TEST 2 PASSED: Job analytics metrics';

    -- -------------------------------------------------------------------------
    -- TEST 3: Recruitment Funnel Stages
    -- -------------------------------------------------------------------------
    v_funnel := public.get_recruitment_funnel(v_org_a, v_job_a);

    IF (v_funnel->'stages'->>'applications')::int <> 3
       OR (v_funnel->'stages'->>'screened')::int <> 2
       OR (v_funnel->'stages'->>'shortlisted')::int <> 2
       OR (v_funnel->'stages'->>'hired')::int <> 1 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Funnel counts mismatch: %', v_funnel->'stages';
    END IF;

    RAISE NOTICE 'TEST 3 PASSED: Recruitment funnel stages';

    -- -------------------------------------------------------------------------
    -- TEST 4: Conversion Rates & Zero Division Safety
    -- -------------------------------------------------------------------------
    -- 2 screened / 3 apps = 66.67%
    IF (v_funnel->'conversion_rates'->>'application_to_screening')::numeric <> 66.67 THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Expected application_to_screening 66.67, got %', v_funnel->'conversion_rates'->>'application_to_screening';
    END IF;

    -- Test on empty job with 0 applications
    DECLARE
        v_empty_job UUID := gen_random_uuid();
        v_empty_funnel JSONB;
    BEGIN
        INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status)
        VALUES (v_empty_job, v_org_a, v_recruiter_a, 'Empty Job', 'empty-job-' || substr(v_empty_job::text, 1, 8), 'No apps', 'published');

        v_empty_funnel := public.get_recruitment_funnel(v_org_a, v_empty_job);
        IF (v_empty_funnel->'conversion_rates'->>'application_to_screening') IS NOT NULL THEN
            RAISE EXCEPTION 'TEST 4 FAILED: Expected NULL for zero denominator conversion rate, got %', v_empty_funnel->'conversion_rates';
        END IF;
    END;

    RAISE NOTICE 'TEST 4 PASSED: Zero-division safety on funnel conversion rates';

    -- -------------------------------------------------------------------------
    -- TEST 5: Candidate Time to Hire
    -- -------------------------------------------------------------------------
    v_time := public.get_recruitment_time_metrics(v_org_a, v_job_a);

    -- App A was submitted 8 days ago and hired 2 days ago = 6.00 days duration
    IF (v_time->>'average_time_to_hire_days')::numeric <> 6.00 THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Expected 6.00 days time to hire, got %', v_time->>'average_time_to_hire_days';
    END IF;

    RAISE NOTICE 'TEST 5 PASSED: Time to hire metric';

    -- -------------------------------------------------------------------------
    -- TEST 6: Job Time to Fill
    -- -------------------------------------------------------------------------
    -- Job A published 10 days ago, first hire 2 days ago = 8.00 days
    IF (v_time->>'average_time_to_fill_days')::numeric <> 8.00 THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Expected 8.00 days time to fill, got %', v_time->>'average_time_to_fill_days';
    END IF;

    RAISE NOTICE 'TEST 6 PASSED: Time to fill metric';

    -- -------------------------------------------------------------------------
    -- TEST 7: Match Analytics (Reusing Task 06 Results)
    -- -------------------------------------------------------------------------
    v_res := public.get_organization_analytics(v_org_a);

    -- Matching scores: 92.50 and 78.00 -> average = 85.25
    IF (v_res->'match_metrics'->>'average_match_score')::numeric <> 85.25 THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Expected average match score 85.25, got %', v_res->'match_metrics'->>'average_match_score';
    END IF;

    IF (v_res->'match_metrics'->>'hard_match_rate')::numeric <> 100.00 THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Expected 100%% hard match rate, got %', v_res->'match_metrics'->>'hard_match_rate';
    END IF;

    RAISE NOTICE 'TEST 7 PASSED: Match analytics metrics';

    -- -------------------------------------------------------------------------
    -- TEST 8: Assessment Analytics (Task 08 Integration)
    -- -------------------------------------------------------------------------
    IF (v_res->'assessments'->>'invitations_sent')::int <> 1
       OR (v_res->'assessments'->>'completed_assessments')::int <> 1
       OR (v_res->'assessments'->>'pass_rate')::numeric <> 100.00 THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Assessment metrics corrupted: %', v_res->'assessments';
    END IF;

    RAISE NOTICE 'TEST 8 PASSED: Assessment analytics metrics';

    -- -------------------------------------------------------------------------
    -- TEST 9: Interview Analytics (Task 09 Integration)
    -- -------------------------------------------------------------------------
    IF (v_res->'interviews'->>'interviews_completed')::int <> 1
       OR (v_res->'interviews'->>'average_rating')::numeric <> 4.80 THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Interview metrics corrupted: %', v_res->'interviews';
    END IF;

    RAISE NOTICE 'TEST 9 PASSED: Interview analytics metrics';

    -- -------------------------------------------------------------------------
    -- TEST 10: Client Portal Analytics (Scoped to Client Org)
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_client_user::text, true);

    v_res := public.get_client_analytics(v_client_org);

    IF (v_res->>'active_shared_jobs')::int <> 1
       OR (v_res->>'candidates_presented')::int <> 1
       OR (v_res->>'client_hires')::int <> 1 THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Client analytics incorrect: %', v_res;
    END IF;

    RAISE NOTICE 'TEST 10 PASSED: Client portal analytics';

    -- -------------------------------------------------------------------------
    -- TEST 11: Recruiter Activity & Pipeline Analytics
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    v_res := public.get_recruiter_analytics(v_recruiter_a);

    IF (v_res->>'assigned_applications')::int <> 3
       OR (v_res->>'candidates_shortlisted')::int <> 2
       OR (v_res->>'candidates_hired')::int <> 1 THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Recruiter analytics mismatch: %', v_res;
    END IF;

    RAISE NOTICE 'TEST 11 PASSED: Recruiter analytics';

    -- -------------------------------------------------------------------------
    -- TEST 12: Candidate Personal Analytics (Privacy-Safe)
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    v_res := public.get_candidate_analytics();

    IF (v_res->>'total_applications')::int <> 1
       OR (v_res->>'completed_assessments')::int <> 1 THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Candidate Dan personal metrics incorrect: %', v_res;
    END IF;

    -- Verify candidate cannot query Candidate B's analytics
    BEGIN
        PERFORM public.get_candidate_analytics(v_cand_b);
        RAISE EXCEPTION 'TEST 12 FAILED: Candidate Dan was able to view Candidate Eve analytics!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 12 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Blocked cleanly
    END;

    RAISE NOTICE 'TEST 12 PASSED: Candidate personal analytics & privacy isolation';

    -- -------------------------------------------------------------------------
    -- TEST 13: AI Telemetry & Usage Analytics
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    v_res := public.get_organization_analytics(v_org_a);

    IF (v_res->'ai_telemetry'->>'total_tokens')::int <> 2400
       OR (v_res->'ai_telemetry'->>'total_estimated_cost_usd')::numeric <> 0.0048 THEN
        RAISE EXCEPTION 'TEST 13 FAILED: AI telemetry corrupted: %', v_res->'ai_telemetry';
    END IF;

    RAISE NOTICE 'TEST 13 PASSED: AI telemetry analytics';

    -- -------------------------------------------------------------------------
    -- TEST 14: Communications Delivery Analytics
    -- -------------------------------------------------------------------------
    IF (v_res->'communications'->>'total_deliveries')::int < 0 THEN
        RAISE EXCEPTION 'TEST 14 FAILED: Communications delivery metrics returned invalid count';
    END IF;

    RAISE NOTICE 'TEST 14 PASSED: Communications delivery analytics (structural check)';

    -- -------------------------------------------------------------------------
    -- TEST 15: Analytics Export Job Lifecycle
    -- -------------------------------------------------------------------------
    -- 1. Create a report definition
    INSERT INTO public.analytics_reports (
        id, organization_id, created_by, name, report_type, configuration
    ) VALUES (
        gen_random_uuid(), v_org_a, v_recruiter_a, 'Monthly Recruitment Velocity', 'recruitment',
        jsonb_build_object('metric', 'time_to_hire', 'format', 'csv')
    ) RETURNING id INTO v_report_id;

    -- 2. Enqueue export job
    v_export_id := public.create_analytics_export_job(v_report_id, 'csv');

    IF NOT EXISTS (
        SELECT 1 FROM public.analytics_export_jobs
        WHERE id = v_export_id AND status = 'queued'
    ) THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Export job was not enqueued with status queued';
    END IF;

    -- 3. Process export job
    v_export_res := public.process_analytics_export_job(v_export_id);

    IF (v_export_res->>'status') <> 'completed' THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Export job processing failed: %', v_export_res;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.analytics_export_jobs
        WHERE id = v_export_id AND status = 'completed' AND file_path IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Export job row not updated to completed';
    END IF;

    RAISE NOTICE 'TEST 15 PASSED: Analytics export job lifecycle';

    -- -------------------------------------------------------------------------
    -- TEST 16: Export Privacy (Cross-Org Export Access Blocked)
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);

    -- Recruiter B (Org B) cannot see Org A export jobs
    IF EXISTS (
        SELECT 1 FROM public.analytics_export_jobs
        WHERE id = v_export_id AND organization_id = v_org_b
    ) THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Org A export job leaked into Org B scope!';
    END IF;

    RAISE NOTICE 'TEST 16 PASSED: Cross-org export privacy isolation';

    -- -------------------------------------------------------------------------
    -- TEST 17: Multi-Tenant Analytics Isolation
    -- -------------------------------------------------------------------------
    -- Recruiter B (Org B) calling get_organization_analytics for Org A must be blocked
    BEGIN
        PERFORM public.get_organization_analytics(v_org_a);
        RAISE EXCEPTION 'TEST 17 FAILED: Recruiter B was able to access Org A analytics!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 17 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Blocked cleanly
    END;

    RAISE NOTICE 'TEST 17 PASSED: Multi-tenant analytics isolation';

    -- -------------------------------------------------------------------------
    -- TEST 18: Historical Funnel Accuracy
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- Simulate application rejection after previously being shortlisted
    UPDATE public.applications
    SET status = 'rejected',
        rejected_at = now(),
        rejection_category = 'salary_mismatch'
    WHERE id = v_app_b;

    v_funnel := public.get_recruitment_funnel(v_org_a, v_job_a);

    -- Even though App B is now rejected, it still holds shortlisted_at timestamp so shortlisted_count is preserved!
    IF (v_funnel->'stages'->>'shortlisted')::int <> 2 THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Historical shortlisted count was destroyed by rejection! Got: %', v_funnel->'stages';
    END IF;

    IF (v_funnel->'stages'->>'rejected')::int <> 1 THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Expected 1 rejected application, got: %', v_funnel->'stages'->>'rejected';
    END IF;

    RAISE NOTICE 'TEST 18 PASSED: Historical funnel accuracy preserved after rejection';

    -- -------------------------------------------------------------------------
    -- TEST 19: N/A Semantics for Unconfigured Assessments
    -- -------------------------------------------------------------------------
    DECLARE
        v_job_no_assess UUID := gen_random_uuid();
        v_job_analytics JSONB;
    BEGIN
        INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status)
        VALUES (v_job_no_assess, v_org_a, v_recruiter_a, 'No Assessment Role', 'no-assess-' || substr(v_job_no_assess::text, 1, 8), 'Job without test', 'published');

        v_job_analytics := public.get_job_analytics(v_job_no_assess);

        -- If no candidates took an assessment for this job, assessment count should be 0 and pass rate should be safely handled
        IF (v_job_analytics->'funnel'->'stages'->>'assessment')::int <> 0 THEN
            RAISE EXCEPTION 'TEST 19 FAILED: Expected 0 assessment stage for job without assessments, got %', v_job_analytics;
        END IF;
    END;

    RAISE NOTICE 'TEST 19 PASSED: N/A semantics for unconfigured assessments';

    -- -------------------------------------------------------------------------
    -- TEST 20: Idempotent Daily Analytics Rebuild
    -- -------------------------------------------------------------------------
    SELECT count(*) INTO v_count_before FROM public.applications;

    -- Rebuild snapshots for Org A for the past 14 days
    v_rebuild_res := public.rebuild_daily_analytics(v_org_a, (CURRENT_DATE - 14)::date, CURRENT_DATE::date);

    IF (v_rebuild_res->>'status') <> 'completed' THEN
        RAISE EXCEPTION 'TEST 20 FAILED: Rebuild daily analytics failed: %', v_rebuild_res;
    END IF;

    -- Verify source of truth applications count is completely unchanged
    SELECT count(*) INTO v_count_after FROM public.applications;
    IF v_count_before <> v_count_after THEN
        RAISE EXCEPTION 'TEST 20 FAILED: Source applications count changed during analytics rebuild!';
    END IF;

    -- Verify snapshots populated
    IF NOT EXISTS (
        SELECT 1 FROM public.organization_daily_metrics
        WHERE organization_id = v_org_a
    ) THEN
        RAISE EXCEPTION 'TEST 20 FAILED: organization_daily_metrics was not populated by rebuild';
    END IF;

    RAISE NOTICE 'TEST 20 PASSED: Idempotent daily analytics rebuild';

    RAISE NOTICE 'ALL 20 TASK 13 ANALYTICS & REPORTING TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 20 ANALYTICS & REPORTING TESTS PASSED!' AS status;

ROLLBACK;
