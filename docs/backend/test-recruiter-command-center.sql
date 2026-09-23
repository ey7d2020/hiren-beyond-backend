-- ============================================================================
-- Hiren Beyond — Task 07 End-to-End Automated Test Suite: Recruiter Command Center
-- Executes all 15 test scenarios inside a safe rollback transaction
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_org_id UUID := '90c362ea-2bcc-45ba-98e4-c8a5d3c57376'; -- Hiren Beyond Platform
    v_org_b_id UUID := gen_random_uuid();
    v_user_1 UUID := gen_random_uuid();
    v_user_2 UUID := gen_random_uuid();
    v_recruiter UUID := gen_random_uuid();
    v_cand_1 UUID := gen_random_uuid();
    v_cand_2 UUID := gen_random_uuid();
    v_job_id UUID := gen_random_uuid();
    v_app_1 UUID := gen_random_uuid();
    v_app_2 UUID := gen_random_uuid();
    v_role_id UUID;
    v_shortlist_id UUID;
    v_pool_id UUID;
    v_smart_pool_id UUID;
    v_bulk_run_id UUID;
    v_search_id UUID;
    v_review_id UUID;
    v_dash RECORD;
    v_job_dash RECORD;
    v_cand_summary RECORD;
    v_bulk_res RECORD;
    v_pool_eval RECORD;
    v_cand_count INT;
BEGIN
    -- 0. Insert auth.users
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_user_1, 'alice.recruiter.test@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_2, 'bob.recruiter.test@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_recruiter, 'rachel.recruiter.test@hirenbeyond.test', 'authenticated', 'authenticated');

    -- 1. Insert Profiles
    INSERT INTO public.profiles (id, email, full_name)
    VALUES
        (v_user_1, 'alice.recruiter.test@hirenbeyond.test', 'Alice Engineer'),
        (v_user_2, 'bob.recruiter.test@hirenbeyond.test', 'Bob Junior'),
        (v_recruiter, 'rachel.recruiter.test@hirenbeyond.test', 'Rachel Recruiter')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Setup recruiter membership in organization A
    SELECT id INTO v_role_id FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES (v_org_id, v_recruiter, v_role_id, 'active');

    -- Set mock authenticated context to recruiter
    PERFORM set_config('request.jwt.claim.sub', v_recruiter::text, true);

    -- 2. Insert Candidates
    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_1, v_user_1, 'active'),
        (v_cand_2, v_user_2, 'active');

    -- Candidate 1 Profiles (Senior React Engineer, 6 years, Egypt)
    INSERT INTO public.candidate_profiles (candidate_id, headline, years_of_experience, country_code, city, remote_preference)
    VALUES (v_cand_1, 'Senior Full Stack Engineer', 6, 'EG', 'Cairo', 'remote');

    INSERT INTO public.candidate_skills (candidate_id, skill_name, normalized_skill_name, proficiency_level, years_of_experience)
    VALUES
        (v_cand_1, 'React', 'react', 'expert', 5),
        (v_cand_1, 'TypeScript', 'typescript', 'advanced', 4);

    INSERT INTO public.candidate_languages (candidate_id, language_name, normalized_language_name, language_code, proficiency_level)
    VALUES (v_cand_1, 'English', 'english', 'en', 'c1');

    INSERT INTO public.candidate_education (candidate_id, institution_name, degree, field_of_study, education_level)
    VALUES (v_cand_1, 'Cairo University', 'Bachelor of Science', 'Computer Science', 'bachelor');

    INSERT INTO public.candidate_experience (candidate_id, company_name, job_title, start_date, end_date)
    VALUES (v_cand_1, 'Tech Solutions', 'Senior Developer', CURRENT_DATE - INTERVAL '5 years', CURRENT_DATE);

    -- Candidate 2 Profiles (Junior Developer, 1 year, Egypt)
    INSERT INTO public.candidate_profiles (candidate_id, headline, years_of_experience, country_code, city, remote_preference)
    VALUES (v_cand_2, 'Junior Web Developer', 1, 'EG', 'Alexandria', 'on_site');

    INSERT INTO public.candidate_skills (candidate_id, skill_name, normalized_skill_name, proficiency_level, years_of_experience)
    VALUES
        (v_cand_2, 'HTML', 'html', 'intermediate', 1),
        (v_cand_2, 'CSS', 'css', 'intermediate', 1);

    INSERT INTO public.candidate_languages (candidate_id, language_name, normalized_language_name, language_code, proficiency_level)
    VALUES (v_cand_2, 'English', 'english', 'en', 'b1');

    -- 3. Create Job
    INSERT INTO public.jobs (
        id, organization_id, created_by, title, slug, job_type, workplace_type, 
        employment_type, experience_level, status, visibility, vacancies_count, description
    )
    VALUES (
        v_job_id, v_org_id, v_recruiter, 'Lead React Engineer', 'lead-react-eng-' || substr(v_job_id::text, 1, 8),
        'direct', 'remote', 'full_time', 'senior', 'published', 'public', 1, 'Job description'
    );

    INSERT INTO public.job_skills (job_id, skill_name, skill_slug, minimum_level, is_required)
    VALUES
        (v_job_id, 'React', 'react', 'advanced', true),
        (v_job_id, 'TypeScript', 'typescript', 'advanced', true);

    INSERT INTO public.job_languages (job_id, language_name, language_code, minimum_level, is_required)
    VALUES (v_job_id, 'English', 'en', 'c1', true);

    -- 4. Create Applications
    INSERT INTO public.applications (id, job_id, candidate_id, organization_id, status)
    VALUES
        (v_app_1, v_job_id, v_cand_1, v_org_id, 'submitted'),
        (v_app_2, v_job_id, v_cand_2, v_org_id, 'screening');

    -- ------------------------------------------------------------------------
    -- TEST 1: Dashboard Metrics
    -- ------------------------------------------------------------------------
    SELECT * INTO v_dash FROM public.get_recruiter_dashboard_metrics(v_org_id);
    IF v_dash.active_jobs_count < 1 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected active_jobs_count >= 1, got %', v_dash.active_jobs_count;
    END IF;
    IF v_dash.new_applications_count < 1 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected new_applications_count >= 1, got %', v_dash.new_applications_count;
    END IF;
    IF v_dash.screening_count < 1 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected screening_count >= 1, got %', v_dash.screening_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 2: Job Dashboard
    -- ------------------------------------------------------------------------
    SELECT * INTO v_job_dash FROM public.get_job_recruiter_dashboard(v_job_id);
    IF v_job_dash.applications_count != 2 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected 2 applications for job, got %', v_job_dash.applications_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 3: Ranking Integration
    -- ------------------------------------------------------------------------
    -- Calculate matches for both candidates
    PERFORM public.calculate_candidate_job_match(v_cand_1, v_job_id, v_app_1);
    PERFORM public.calculate_candidate_job_match(v_cand_2, v_job_id, v_app_2);

    SELECT count(*) INTO v_cand_count
    FROM public.rank_candidates_for_job(v_job_id, 10, 0);
    IF v_cand_count < 2 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: rank_candidates_for_job did not return candidates';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 4: Candidate Filters & Search
    -- ------------------------------------------------------------------------
    SELECT count(*) INTO v_cand_count
    FROM public.search_recruiter_candidates(
        v_org_id,
        jsonb_build_object('skill', 'React', 'min_experience', 3)
    );
    IF v_cand_count != 1 THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Search with React and min_experience=3 should return exactly 1 candidate, got %', v_cand_count;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 5: Bulk CV Screening Run
    -- ------------------------------------------------------------------------
    v_bulk_run_id := public.create_bulk_screening_run(v_job_id);
    IF NOT EXISTS (SELECT 1 FROM public.bulk_screening_runs WHERE id = v_bulk_run_id AND candidate_count = 2) THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Bulk screening run did not queue 2 candidates';
    END IF;

    SELECT * INTO v_bulk_res FROM public.process_bulk_screening_run(v_bulk_run_id, 10);
    IF v_bulk_res.processed != 2 THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Expected 2 processed in bulk screening, got %', v_bulk_res.processed;
    END IF;

    -- Verify screening summaries created
    IF NOT EXISTS (SELECT 1 FROM public.candidate_screening_summaries WHERE job_id = v_job_id AND candidate_id = v_cand_1) THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Candidate screening summary not generated for Candidate 1';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 6: Candidate Shortlist
    -- ------------------------------------------------------------------------
    v_shortlist_id := public.shortlist_candidate(v_job_id, v_cand_1, v_app_1, 'Strongest technical alignment');
    IF NOT EXISTS (SELECT 1 FROM public.candidate_shortlists WHERE id = v_shortlist_id AND status = 'active') THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Shortlist record not created';
    END IF;

    -- Verify duplicate shortlist attempt is idempotent
    PERFORM public.shortlist_candidate(v_job_id, v_cand_1, v_app_1, 'Updated shortlist reason');
    IF (SELECT count(*) FROM public.candidate_shortlists WHERE job_id = v_job_id AND candidate_id = v_cand_1) != 1 THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Duplicate shortlist entry was created';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: Bulk Shortlist
    -- ------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM public.bulk_shortlist_candidates(v_job_id, ARRAY[v_cand_2], 'Shortlisted in batch')
        WHERE candidate_id = v_cand_2 AND success = true
    ) THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Bulk shortlist did not succeed for candidate 2';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 8: Manual Talent Pool
    -- ------------------------------------------------------------------------
    INSERT INTO public.talent_pools (id, organization_id, created_by, name, slug, pool_type, is_dynamic)
    VALUES (gen_random_uuid(), v_org_id, v_recruiter, 'Senior Frontend Talent', 'sr-frontend-' || substr(v_job_id::text, 1, 8), 'manual', false)
    RETURNING id INTO v_pool_id;

    PERFORM public.add_candidate_to_talent_pool(v_pool_id, v_cand_1, 'Senior full stack expertise');
    IF NOT EXISTS (SELECT 1 FROM public.talent_pool_members WHERE talent_pool_id = v_pool_id AND candidate_id = v_cand_1 AND status = 'active') THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Manual talent pool member not added';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 9 & 10: Smart & Dynamic Talent Pool Evaluation
    -- ------------------------------------------------------------------------
    INSERT INTO public.talent_pools (id, organization_id, created_by, name, slug, pool_type, is_dynamic)
    VALUES (gen_random_uuid(), v_org_id, v_recruiter, 'React Specialists', 'react-spec-' || substr(v_job_id::text, 1, 8), 'smart', true)
    RETURNING id INTO v_smart_pool_id;

    -- Rule: candidate must have React skill
    INSERT INTO public.talent_pool_rules (talent_pool_id, rule_type, operator, field, value)
    VALUES (v_smart_pool_id, 'skill', 'equals', 'skill_name', 'React');

    -- Rule: candidate must have >= 3 years experience
    INSERT INTO public.talent_pool_rules (talent_pool_id, rule_type, operator, field, value)
    VALUES (v_smart_pool_id, 'experience_years', 'greater_than_or_equal', 'years_of_experience', '3');

    SELECT * INTO v_pool_eval FROM public.evaluate_talent_pool(v_smart_pool_id);
    IF v_pool_eval.added_count < 1 THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Smart pool evaluation did not add Candidate 1 (React 5y)';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.talent_pool_members WHERE talent_pool_id = v_smart_pool_id AND candidate_id = v_cand_1 AND status = 'active') THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Candidate 1 not found in active members of smart pool';
    END IF;

    -- Dynamic exit test: candidate 1 years reduced to 1 year, re-evaluate
    UPDATE public.candidate_profiles SET years_of_experience = 1 WHERE candidate_id = v_cand_1;
    SELECT * INTO v_pool_eval FROM public.evaluate_talent_pool(v_smart_pool_id);
    IF v_pool_eval.removed_count < 1 THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Candidate 1 should have been removed from dynamic smart pool when experience dropped below 3';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 11: Saved Search
    -- ------------------------------------------------------------------------
    INSERT INTO public.recruiter_saved_searches (
        organization_id, created_by, name, filters, is_shared
    )
    VALUES (
        v_org_id, v_recruiter, 'High Match React Talent',
        jsonb_build_object('skill', 'React', 'min_score', 80),
        true
    )
    RETURNING id INTO v_search_id;

    IF NOT EXISTS (SELECT 1 FROM public.recruiter_saved_searches WHERE id = v_search_id) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Recruiter saved search was not created';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 12: Review Queue
    -- ------------------------------------------------------------------------
    INSERT INTO public.recruiter_review_queue (
        organization_id, candidate_id, job_id, application_id, reason, priority
    )
    VALUES (
        v_org_id, v_cand_2, v_job_id, v_app_2, 'Mandatory React skill missing in application', 'high'
    )
    RETURNING id INTO v_review_id;

    PERFORM public.resolve_candidate_review(v_review_id, 'Reviewed with hiring manager and confirmed gap');
    IF NOT EXISTS (SELECT 1 FROM public.recruiter_review_queue WHERE id = v_review_id AND status = 'resolved') THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Review queue item was not resolved';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 13: Tenant Isolation (Org A recruiter cannot view Org B dashboard)
    -- ------------------------------------------------------------------------
    BEGIN
        PERFORM public.get_recruiter_dashboard_metrics(v_org_b_id);
        RAISE EXCEPTION 'TEST 13 FAILED: Organization boundary check failed to block access to Org B dashboard';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 13 FAILED%' THEN
            RAISE EXCEPTION '%', SQLERRM;
        END IF;
        -- Successfully blocked access to Org B
    END;

    -- ------------------------------------------------------------------------
    -- TEST 14: Candidate Privacy (Candidate cannot access recruiter summaries)
    -- ------------------------------------------------------------------------
    -- Switch context to candidate user 1
    PERFORM set_config('request.jwt.claim.sub', v_user_1::text, true);
    BEGIN
        PERFORM public.get_recruiter_dashboard_metrics(v_org_id);
        RAISE EXCEPTION 'TEST 14 FAILED: Candidate user should be blocked from recruiter dashboard';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 14 FAILED%' THEN
            RAISE EXCEPTION '%', SQLERRM;
        END IF;
        -- Successfully blocked candidate access
    END;

    -- ------------------------------------------------------------------------
    -- TEST 15: No Fabrication Validation
    -- ------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM public.candidate_screening_summaries
        WHERE job_id = v_job_id AND candidate_id = v_cand_1 AND summary LIKE '%match score%'
    ) THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Screening summary does not contain verified match score';
    END IF;

    RAISE NOTICE 'ALL 15 END-TO-END RECRUITER COMMAND CENTER TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 15 END-TO-END RECRUITER COMMAND CENTER TESTS PASSED!' AS status;

ROLLBACK;
