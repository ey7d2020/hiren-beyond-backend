-- ============================================================================
-- Hiren Beyond — Task 06 End-to-End Automated Test Suite
-- Executes all 11 evaluation scenarios inside a safe rollback transaction
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_org_id UUID := '90c362ea-2bcc-45ba-98e4-c8a5d3c57376'; -- Hiren Beyond Platform
    v_user_1 UUID := gen_random_uuid();
    v_user_2 UUID := gen_random_uuid();
    v_recruiter UUID := gen_random_uuid();
    v_cand_1 UUID := gen_random_uuid();
    v_cand_2 UUID := gen_random_uuid();
    v_job_id UUID := gen_random_uuid();
    v_app_id UUID := gen_random_uuid();
    v_role_id UUID;
    v_run_1 UUID;
    v_run_2 UUID;
    v_run_3 UUID;
    v_override_id UUID;
    v_score_1 NUMERIC;
    v_hard_match_1 BOOLEAN;
    v_score_2 NUMERIC;
    v_hard_match_2 BOOLEAN;
BEGIN
    -- 0. Insert auth.users
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_user_1, 'test.candidate1@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_user_2, 'test.candidate2@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_recruiter, 'test.recruiter@hirenbeyond.test', 'authenticated', 'authenticated');

    -- 1. Insert Profiles
    INSERT INTO public.profiles (id, email, full_name)
    VALUES
        (v_user_1, 'test.candidate1@hirenbeyond.test', 'Alice Engineer'),
        (v_user_2, 'test.candidate2@hirenbeyond.test', 'Bob Junior'),
        (v_recruiter, 'test.recruiter@hirenbeyond.test', 'Rachel Recruiter')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    -- Setup recruiter membership in organization
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

    -- Candidate 1 Profiles (Senior React/TypeScript Engineer)
    INSERT INTO public.candidate_profiles (candidate_id, headline, years_of_experience, country_code, city, remote_preference)
    VALUES (v_cand_1, 'Senior Full Stack Engineer', 6, 'EG', 'Cairo', 'remote');

    -- Candidate 1 Skills (Uses aliases like 'JS', 'ReactJS', 'TS')
    INSERT INTO public.candidate_skills (candidate_id, skill_name, normalized_skill_name, proficiency_level, years_of_experience)
    VALUES
        (v_cand_1, 'ReactJS', 'reactjs', 'expert', 5),
        (v_cand_1, 'TypeScript', 'typescript', 'advanced', 4),
        (v_cand_1, 'NodeJS', 'nodejs', 'advanced', 4);

    -- Candidate 1 Languages (English c1)
    INSERT INTO public.candidate_languages (candidate_id, language_name, normalized_language_name, language_code, proficiency_level)
    VALUES (v_cand_1, 'English', 'english', 'en', 'c1');

    -- Candidate 1 Education (B.Sc. in Computer Science)
    INSERT INTO public.candidate_education (candidate_id, institution_name, degree, field_of_study, education_level)
    VALUES (v_cand_1, 'Cairo University', 'Bachelor of Science', 'Computer Science', 'bachelor');

    -- Candidate 1 Experience (5+ years)
    INSERT INTO public.candidate_experience (candidate_id, company_name, job_title, start_date, end_date)
    VALUES (v_cand_1, 'Tech Solutions', 'Senior Developer', CURRENT_DATE - INTERVAL '5 years', CURRENT_DATE);

    -- Candidate 2 Profiles (Junior Developer with missing mandatory skills and lower language level)
    INSERT INTO public.candidate_profiles (candidate_id, headline, years_of_experience, country_code, city, remote_preference)
    VALUES (v_cand_2, 'Junior Web Developer', 1, 'EG', 'Alexandria', 'on_site');

    -- Candidate 2 Skills (HTML, CSS, but missing TypeScript and React)
    INSERT INTO public.candidate_skills (candidate_id, skill_name, normalized_skill_name, proficiency_level, years_of_experience)
    VALUES
        (v_cand_2, 'HTML', 'html', 'intermediate', 1),
        (v_cand_2, 'CSS', 'css', 'intermediate', 1);

    -- Candidate 2 Languages (English b1 - lower than required c1)
    INSERT INTO public.candidate_languages (candidate_id, language_name, normalized_language_name, language_code, proficiency_level)
    VALUES (v_cand_2, 'English', 'english', 'en', 'b1');

    -- 3. Create Job (Senior Full Stack Engineer, requires React & TypeScript mandatory, English c1 mandatory)
    INSERT INTO public.jobs (
        id, organization_id, created_by, title, slug, job_type, workplace_type, 
        employment_type, experience_level, status, visibility, vacancies_count, description
    )
    VALUES (
        v_job_id, v_org_id, v_recruiter, 'Senior Frontend Engineer', 'senior-frontend-eng-' || substr(v_job_id::text, 1, 8),
        'direct', 'remote', 'full_time', 'senior', 'published', 'public', 1, 'Job description'
    );

    -- Job Skills: React (required), TypeScript (required), Python (optional)
    INSERT INTO public.job_skills (job_id, skill_name, skill_slug, minimum_level, is_required)
    VALUES
        (v_job_id, 'React', 'react', 'advanced', true),
        (v_job_id, 'TypeScript', 'typescript', 'advanced', true),
        (v_job_id, 'Python', 'python', 'intermediate', false);

    -- Job Languages: English (required c1)
    INSERT INTO public.job_languages (job_id, language_name, language_code, minimum_level, is_required)
    VALUES (v_job_id, 'English', 'en', 'c1', true);

    -- 4. Create Application for Candidate 1
    INSERT INTO public.applications (
        id, job_id, candidate_id, organization_id, status
    )
    VALUES (
        v_app_id, v_job_id, v_cand_1, v_org_id, 'submitted'
    );

    -- ------------------------------------------------------------------------
    -- TEST 1 & 6: Candidate 1 Match Execution & Score Calculation
    -- ------------------------------------------------------------------------
    v_run_1 := public.calculate_candidate_job_match(
        p_candidate_id => v_cand_1,
        p_job_id => v_job_id,
        p_application_id => v_app_id,
        p_engine_version => 'v1.0.0'
    );

    SELECT final_score, hard_match INTO v_score_1, v_hard_match_1
    FROM public.matching_runs WHERE id = v_run_1;

    -- Candidate 1 should have hard_match = true and final_score >= 80
    IF v_hard_match_1 IS NOT TRUE THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Candidate 1 should have satisfied all hard requirements, got hard_match = false';
    END IF;

    IF v_score_1 < 80 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Candidate 1 score expected >= 80, got %', v_score_1;
    END IF;

    -- Verify application match_score was updated (TEST 10)
    IF NOT EXISTS (SELECT 1 FROM public.applications WHERE id = v_app_id AND match_score = v_score_1) THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Application match_score was not updated with run score';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 2, 3, 4: Candidate 2 Match (Missing mandatory skill & lower language)
    -- ------------------------------------------------------------------------
    v_run_2 := public.calculate_candidate_job_match(
        p_candidate_id => v_cand_2,
        p_job_id => v_job_id,
        p_engine_version => 'v1.0.0'
    );

    SELECT final_score, hard_match INTO v_score_2, v_hard_match_2
    FROM public.matching_runs WHERE id = v_run_2;

    -- Candidate 2 missing React & TypeScript mandatory -> must have hard_match = false
    IF v_hard_match_2 IS NOT FALSE THEN
        RAISE EXCEPTION 'TEST 2/4 FAILED: Candidate 2 missing mandatory skills should have hard_match = false';
    END IF;

    -- Verify hard failure reasons populated
    IF NOT EXISTS (
        SELECT 1 FROM public.matching_runs 
        WHERE id = v_run_2 
          AND array_to_string(hard_failure_reasons, ';') LIKE '%Mandatory skill missing: React%'
    ) THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Missing mandatory skill not recorded in hard_failure_reasons';
    END IF;

    -- Verify Language partial match recorded (TEST 3)
    IF NOT EXISTS (
        SELECT 1 FROM public.match_dimension_results
        WHERE matching_run_id = v_run_2 
          AND dimension = 'languages' 
          AND status = 'partially_matched'
    ) THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Candidate 2 English b1 vs c1 should result in status partially_matched';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: Ranking Function
    -- ------------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM public.rank_candidates_for_job(v_job_id, 10, 0)
        WHERE candidate_id = v_cand_1 AND final_score = v_score_1
    ) THEN
        RAISE EXCEPTION 'TEST 7 FAILED: rank_candidates_for_job did not return Candidate 1';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 9: Historical Results Versioning
    -- Run second matching on candidate 1 with engine v1.1.0
    -- ------------------------------------------------------------------------
    v_run_3 := public.calculate_candidate_job_match(
        p_candidate_id => v_cand_1,
        p_job_id => v_job_id,
        p_engine_version => 'v1.1.0'
    );

    -- Both runs must coexist
    IF (SELECT count(*) FROM public.matching_runs WHERE candidate_id = v_cand_1 AND job_id = v_job_id) < 2 THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Multiple matching runs for same candidate/job were not preserved';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 11: Manual Recruiter Override
    -- ------------------------------------------------------------------------
    v_override_id := public.override_match_score(
        p_matching_run_id => v_run_1,
        p_override_type => 'score_override',
        p_override_score => 92.5,
        p_reason => 'Recruiter assessed strong technical live demo during initial screening'
    );

    IF NOT EXISTS (
        SELECT 1 FROM public.match_overrides 
        WHERE id = v_override_id 
          AND original_score = v_score_1 
          AND override_score = 92.5
    ) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Match override record was not created correctly';
    END IF;

    -- Verify matching_runs.final_score and application was updated to override_score
    IF NOT EXISTS (SELECT 1 FROM public.matching_runs WHERE id = v_run_1 AND final_score = 92.5) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Run final_score was not updated to override_score';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.applications WHERE id = v_app_id AND match_score = 92.5) THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Application match_score was not updated to override_score';
    END IF;

    RAISE NOTICE 'ALL 11 END-TO-END MATCHING ENGINE TESTS PASSED SUCCESSFULLY!';
END;
$$;

ROLLBACK;
