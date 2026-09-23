-- =============================================================================
-- Migration: 20260915000700_matching_engine.sql
-- Description: Candidate <-> Job Matching Engine, Match Score, Explanation & Ranking
-- Author: Hiren Beyond Engineering
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. MATCHING PROFILES (Configurable & Versioned Scoring Weights)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.matching_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_default BOOLEAN NOT NULL DEFAULT false,
    configuration JSONB NOT NULL DEFAULT '{
        "weights": {
            "skills": 35,
            "experience": 25,
            "languages": 15,
            "education": 10,
            "location": 5,
            "career_level": 5,
            "certifications": 5
        },
        "thresholds": {
            "hard_match_min_score": 50,
            "recommended_min_score": 75,
            "strong_match_min_score": 85
        },
        "rules": {
            "require_all_mandatory_skills": true,
            "require_all_mandatory_languages": true,
            "require_mandatory_experience": true,
            "allow_language_level_flexibility": false,
            "treat_missing_as_unknown": true
        }
    }'::jsonb,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_matching_profiles_org ON public.matching_profiles(organization_id);
CREATE INDEX IF NOT EXISTS idx_matching_profiles_default ON public.matching_profiles(is_default) WHERE is_default = true;

-- -----------------------------------------------------------------------------
-- 2. MATCH CRITERIA (Per-Job Custom Requirements & Criteria Overrides)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.match_criteria (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    criterion_type TEXT NOT NULL CHECK (criterion_type IN (
        'skill', 'experience', 'education', 'language', 'location', 
        'certification', 'employment_type', 'workplace_type', 'career_level', 'custom'
    )),
    criterion_key TEXT NOT NULL,
    label TEXT NOT NULL,
    weight NUMERIC NOT NULL DEFAULT 1.0 CHECK (weight >= 0),
    is_required BOOLEAN NOT NULL DEFAULT false,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_match_criteria_job_key UNIQUE (job_id, criterion_type, criterion_key)
);

CREATE INDEX IF NOT EXISTS idx_match_criteria_job ON public.match_criteria(job_id);
CREATE INDEX IF NOT EXISTS idx_match_criteria_type ON public.match_criteria(criterion_type);

-- -----------------------------------------------------------------------------
-- 3. SKILL ALIASES (Taxonomy & Normalization Catalog)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.skill_aliases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    canonical_skill TEXT NOT NULL,
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    category TEXT DEFAULT 'general',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_skill_aliases_normalized UNIQUE (normalized_alias)
);

CREATE INDEX IF NOT EXISTS idx_skill_aliases_canonical ON public.skill_aliases(canonical_skill);
CREATE INDEX IF NOT EXISTS idx_skill_aliases_normalized ON public.skill_aliases(normalized_alias);

-- -----------------------------------------------------------------------------
-- 4. MATCHING RUNS (Immutable, Versioned Evaluation Runs)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.matching_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    matching_profile_id UUID REFERENCES public.matching_profiles(id) ON DELETE SET NULL,
    matching_profile_version INT NOT NULL DEFAULT 1,
    engine_version TEXT NOT NULL DEFAULT 'v1.0.0',
    status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN (
        'queued', 'processing', 'completed', 'failed', 'needs_review'
    )),
    hard_match BOOLEAN NOT NULL DEFAULT true,
    hard_failure_reasons TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    final_score NUMERIC NOT NULL DEFAULT 0.0 CHECK (final_score >= 0 AND final_score <= 100),
    confidence NUMERIC NOT NULL DEFAULT 1.0 CHECK (confidence >= 0 AND confidence <= 1.0),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_matching_runs_candidate ON public.matching_runs(candidate_id);
CREATE INDEX IF NOT EXISTS idx_matching_runs_job ON public.matching_runs(job_id);
CREATE INDEX IF NOT EXISTS idx_matching_runs_application ON public.matching_runs(application_id);
CREATE INDEX IF NOT EXISTS idx_matching_runs_score ON public.matching_runs(final_score DESC);
CREATE INDEX IF NOT EXISTS idx_matching_runs_status ON public.matching_runs(status);
CREATE INDEX IF NOT EXISTS idx_matching_runs_cand_job ON public.matching_runs(candidate_id, job_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 5. MATCH DIMENSION RESULTS (Granular Multi-Dimensional Evaluation)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.match_dimension_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    matching_run_id UUID NOT NULL REFERENCES public.matching_runs(id) ON DELETE CASCADE,
    dimension TEXT NOT NULL CHECK (dimension IN (
        'skills', 'experience', 'education', 'languages', 'location',
        'employment_type', 'workplace_type', 'career_level', 'certifications', 'custom_requirements'
    )),
    score NUMERIC NOT NULL DEFAULT 0.0 CHECK (score >= 0 AND score <= 100),
    weight NUMERIC NOT NULL DEFAULT 0.0 CHECK (weight >= 0),
    weighted_score NUMERIC NOT NULL DEFAULT 0.0 CHECK (weighted_score >= 0),
    status TEXT NOT NULL CHECK (status IN (
        'matched', 'partially_matched', 'not_matched', 'unknown', 'not_applicable'
    )),
    confidence NUMERIC NOT NULL DEFAULT 1.0 CHECK (confidence >= 0 AND confidence <= 1.0),
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    gaps JSONB NOT NULL DEFAULT '{}'::jsonb,
    explanation TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_match_dim_run_dimension UNIQUE (matching_run_id, dimension)
);

CREATE INDEX IF NOT EXISTS idx_match_dim_run ON public.match_dimension_results(matching_run_id);
CREATE INDEX IF NOT EXISTS idx_match_dim_dimension ON public.match_dimension_results(dimension);

-- -----------------------------------------------------------------------------
-- 6. MATCH EXPLANATIONS (Structured Explainability Syntheses)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.match_explanations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    matching_run_id UUID NOT NULL REFERENCES public.matching_runs(id) ON DELETE CASCADE,
    summary TEXT NOT NULL,
    strengths TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    gaps TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    missing_required_items TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    uncertain_items TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    recommendation TEXT NOT NULL CHECK (recommendation IN (
        'strongly_recommend', 'recommend', 'consider', 'not_recommended', 'requires_review'
    )),
    explanation_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_match_explanations_run UNIQUE (matching_run_id)
);

CREATE INDEX IF NOT EXISTS idx_match_explanations_run ON public.match_explanations(matching_run_id);

-- -----------------------------------------------------------------------------
-- 7. MATCH OVERRIDES (Human Recruiter Overrides with Audit Trail)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.match_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    matching_run_id UUID NOT NULL REFERENCES public.matching_runs(id) ON DELETE CASCADE,
    override_type TEXT NOT NULL CHECK (override_type IN (
        'score_override', 'hard_match_override', 'recommendation_override'
    )),
    original_score NUMERIC NOT NULL CHECK (original_score >= 0 AND original_score <= 100),
    override_score NUMERIC NOT NULL CHECK (override_score >= 0 AND override_score <= 100),
    reason TEXT NOT NULL CHECK (length(trim(reason)) >= 10),
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_match_overrides_run ON public.match_overrides(matching_run_id);
CREATE INDEX IF NOT EXISTS idx_match_overrides_creator ON public.match_overrides(created_by);

-- -----------------------------------------------------------------------------
-- 8. SEED PERMISSIONS
-- -----------------------------------------------------------------------------
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('matching.view', 'View Match Results', 'Access candidate-job match scores, dimension breakdowns, and explanations', 'matching'),
    ('matching.run', 'Run Matching Engine', 'Trigger match score calculation and candidate re-ranking', 'matching'),
    ('matching.override', 'Override Match Score', 'Manually adjust match score or qualification recommendation with justification', 'matching'),
    ('matching.configure', 'Configure Matching Profiles', 'Create and modify matching weight profiles and criteria configurations', 'matching')
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;

-- Assign permissions to platform_admin, recruiter_manager, and recruiter
WITH new_perms AS (
    SELECT id, key FROM public.permissions WHERE category = 'matching'
),
target_roles AS (
    SELECT id, key FROM public.roles WHERE key IN ('platform_admin', 'platform_operations', 'recruiter_manager', 'recruiter')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM target_roles r
CROSS JOIN new_perms p
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 9. SEED GLOBAL DEFAULT MATCHING PROFILE
-- -----------------------------------------------------------------------------
INSERT INTO public.matching_profiles (
    id,
    organization_id,
    name,
    description,
    is_default,
    configuration,
    version
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    NULL,
    'Hiren Beyond Standard Multi-Dimensional Match',
    'Global balanced default weighting across skills, experience, language, education, and preferences',
    true,
    '{
        "weights": {
            "skills": 35,
            "experience": 25,
            "languages": 15,
            "education": 10,
            "location": 5,
            "career_level": 5,
            "certifications": 5
        },
        "thresholds": {
            "hard_match_min_score": 50,
            "recommended_min_score": 75,
            "strong_match_min_score": 85
        },
        "rules": {
            "require_all_mandatory_skills": true,
            "require_all_mandatory_languages": true,
            "require_mandatory_experience": true,
            "allow_language_level_flexibility": false,
            "treat_missing_as_unknown": true
        }
    }'::jsonb,
    1
)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    configuration = EXCLUDED.configuration;

-- -----------------------------------------------------------------------------
-- 10. SEED COMMON SKILL ALIASES
-- -----------------------------------------------------------------------------
INSERT INTO public.skill_aliases (canonical_skill, alias, normalized_alias, category)
VALUES
    ('JavaScript', 'JS', 'js', 'frontend'),
    ('JavaScript', 'Javascript', 'javascript', 'frontend'),
    ('JavaScript', 'ECMAScript', 'ecmascript', 'frontend'),
    ('TypeScript', 'TS', 'ts', 'frontend'),
    ('TypeScript', 'Typescript', 'typescript', 'frontend'),
    ('React', 'ReactJS', 'reactjs', 'frontend'),
    ('React', 'React.js', 'react.js', 'frontend'),
    ('React Native', 'ReactNative', 'reactnative', 'mobile'),
    ('Node.js', 'Node', 'node', 'backend'),
    ('Node.js', 'NodeJS', 'nodejs', 'backend'),
    ('Vue.js', 'Vue', 'vue', 'frontend'),
    ('Vue.js', 'VueJS', 'vuejs', 'frontend'),
    ('Angular', 'AngularJS', 'angularjs', 'frontend'),
    ('Python', 'Python3', 'python3', 'backend'),
    ('Python', 'Py', 'py', 'backend'),
    ('Go', 'Golang', 'golang', 'backend'),
    ('PostgreSQL', 'Postgres', 'postgres', 'database'),
    ('PostgreSQL', 'psql', 'psql', 'database'),
    ('MongoDB', 'Mongo', 'mongo', 'database'),
    ('AWS', 'Amazon Web Services', 'amazon web services', 'devops'),
    ('GCP', 'Google Cloud Platform', 'google cloud platform', 'devops'),
    ('Azure', 'Microsoft Azure', 'microsoft azure', 'devops'),
    ('Kubernetes', 'K8s', 'k8s', 'devops'),
    ('Docker', 'Containerization', 'containerization', 'devops'),
    ('CI/CD', 'Continuous Integration', 'continuous integration', 'devops'),
    ('HTML', 'HTML5', 'html5', 'frontend'),
    ('CSS', 'CSS3', 'css3', 'frontend'),
    ('Tailwind CSS', 'Tailwind', 'tailwind', 'frontend'),
    ('Tailwind CSS', 'TailwindCSS', 'tailwindcss', 'frontend'),
    ('REST API', 'RESTful API', 'restful api', 'backend'),
    ('GraphQL', 'Graph QL', 'graph ql', 'backend'),
    ('C#', 'CSharp', 'csharp', 'backend'),
    ('C#', 'C-Sharp', 'c-sharp', 'backend'),
    ('C++', 'Cplusplus', 'cplusplus', 'systems'),
    ('Ruby on Rails', 'Rails', 'rails', 'backend'),
    ('Ruby on Rails', 'RoR', 'ror', 'backend')
ON CONFLICT (normalized_alias) DO UPDATE
SET canonical_skill = EXCLUDED.canonical_skill,
    alias = EXCLUDED.alias,
    category = EXCLUDED.category;

-- -----------------------------------------------------------------------------
-- 11. HELPER & NORMALIZATION FUNCTIONS
-- -----------------------------------------------------------------------------

-- Normalizes skill strings and looks up aliases
CREATE OR REPLACE FUNCTION public.normalize_skill_text(p_skill TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_clean TEXT;
    v_canonical TEXT;
BEGIN
    IF p_skill IS NULL OR trim(p_skill) = '' THEN
        RETURN '';
    END IF;

    -- Clean string: lowercase, trim, strip special characters except basic separators
    v_clean := lower(trim(p_skill));
    
    -- Lookup in aliases table
    SELECT canonical_skill INTO v_canonical
    FROM public.skill_aliases
    WHERE normalized_alias = v_clean
    LIMIT 1;

    IF v_canonical IS NOT NULL THEN
        RETURN v_canonical;
    END IF;

    -- Fallback: return capitalized cleaned string
    RETURN initcap(v_clean);
END;
$$;

-- Maps CEFR language level to comparable integer (1-7)
CREATE OR REPLACE FUNCTION public.get_cefr_level_numeric(p_level TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_norm TEXT;
BEGIN
    IF p_level IS NULL THEN
        RETURN 0;
    END IF;
    v_norm := upper(trim(p_level));
    CASE v_norm
        WHEN 'A1', 'BEGINNER', 'ELEMENTARY' THEN RETURN 1;
        WHEN 'A2', 'PRE-INTERMEDIATE' THEN RETURN 2;
        WHEN 'B1', 'INTERMEDIATE' THEN RETURN 3;
        WHEN 'B2', 'UPPER-INTERMEDIATE', 'UPPER INTERMEDIATE' THEN RETURN 4;
        WHEN 'C1', 'ADVANCED' THEN RETURN 5;
        WHEN 'C2', 'MASTERY', 'PROFICIENT' THEN RETURN 6;
        WHEN 'NATIVE', 'BILINGUAL' THEN RETURN 7;
        ELSE RETURN 3; -- default to intermediate if unknown level provided
    END CASE;
END;
$$;

-- Maps education degree to comparable numeric rank (1-5)
CREATE OR REPLACE FUNCTION public.get_education_level_numeric(p_degree TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_norm TEXT;
BEGIN
    IF p_degree IS NULL THEN
        RETURN 0;
    END IF;
    v_norm := replace(lower(trim(p_degree)), '.', '');
    IF v_norm LIKE '%phd%' OR v_norm LIKE '%doctor%' OR v_norm LIKE '%doctorate%' THEN
        RETURN 5;
    ELSIF v_norm LIKE '%master%' OR v_norm LIKE '%msc%' OR v_norm LIKE '%mba%' OR v_norm LIKE '%ma%' THEN
        RETURN 4;
    ELSIF v_norm LIKE '%bachelor%' OR v_norm LIKE '%bsc%' OR v_norm LIKE '%ba%' OR v_norm LIKE '%beng%' OR v_norm LIKE '%undergraduate%' THEN
        RETURN 3;
    ELSIF v_norm LIKE '%diploma%' OR v_norm LIKE '%associate%' OR v_norm LIKE '%vocational%' THEN
        RETURN 2;
    ELSIF v_norm LIKE '%high school%' OR v_norm LIKE '%secondary%' THEN
        RETURN 1;
    ELSE
        RETURN 2;
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 12. CORE MATCHING ENGINE (calculate_candidate_job_match)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_candidate_job_match(
    p_candidate_id UUID,
    p_job_id UUID,
    p_application_id UUID DEFAULT NULL,
    p_matching_profile_id UUID DEFAULT NULL,
    p_engine_version TEXT DEFAULT 'v1.0.0'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_run_id UUID;
    v_job RECORD;
    v_candidate RECORD;
    v_cand_profile RECORD;
    v_cand_preferences RECORD;
    v_profile_config JSONB;
    v_profile_version INT := 1;

    -- Weights
    w_skills NUMERIC := 35;
    w_experience NUMERIC := 25;
    w_languages NUMERIC := 15;
    w_education NUMERIC := 10;
    w_location NUMERIC := 5;
    w_career_level NUMERIC := 5;
    w_certifications NUMERIC := 5;

    -- Dimension Scores (0-100)
    s_skills NUMERIC := 100;
    s_experience NUMERIC := 100;
    s_languages NUMERIC := 100;
    s_education NUMERIC := 100;
    s_location NUMERIC := 100;
    s_career_level NUMERIC := 100;
    s_certifications NUMERIC := 100;

    -- Dimension Statuses
    st_skills TEXT := 'matched';
    st_experience TEXT := 'matched';
    st_languages TEXT := 'matched';
    st_education TEXT := 'matched';
    st_location TEXT := 'matched';
    st_career_level TEXT := 'matched';
    st_certifications TEXT := 'matched';

    -- Evidence & Gaps JSONBs
    ev_skills JSONB := '{}'::jsonb;
    gap_skills JSONB := '{}'::jsonb;
    ev_exp JSONB := '{}'::jsonb;
    gap_exp JSONB := '{}'::jsonb;
    ev_lang JSONB := '{}'::jsonb;
    gap_lang JSONB := '{}'::jsonb;
    ev_edu JSONB := '{}'::jsonb;
    gap_edu JSONB := '{}'::jsonb;
    ev_loc JSONB := '{}'::jsonb;
    gap_loc JSONB := '{}'::jsonb;
    ev_career JSONB := '{}'::jsonb;
    gap_career JSONB := '{}'::jsonb;
    ev_cert JSONB := '{}'::jsonb;
    gap_cert JSONB := '{}'::jsonb;

    -- Hard match evaluation
    v_hard_match BOOLEAN := true;
    v_hard_failure_reasons TEXT[] := ARRAY[]::TEXT[];
    v_missing_required_items TEXT[] := ARRAY[]::TEXT[];
    v_uncertain_items TEXT[] := ARRAY[]::TEXT[];
    v_strengths TEXT[] := ARRAY[]::TEXT[];
    v_gaps TEXT[] := ARRAY[]::TEXT[];

    -- Totals
    v_total_weight NUMERIC := 0;
    v_weighted_sum NUMERIC := 0;
    v_final_score NUMERIC := 0;
    v_confidence NUMERIC := 0.95;
    v_recommendation TEXT := 'recommend';
    v_summary TEXT := '';

    -- Temporary helpers
    v_req_count INT := 0;
    v_cand_count INT := 0;
    v_match_count NUMERIC := 0;
    v_cand_years NUMERIC := 0;
    v_req_years NUMERIC := 0;
    v_req_level_num INT := 0;
    v_cand_level_num INT := 0;
    r_item RECORD;
BEGIN
    -- 1. Validate Candidate & Job existence
    SELECT * INTO v_candidate FROM public.candidates WHERE id = p_candidate_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate % does not exist', p_candidate_id;
    END IF;

    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % does not exist', p_job_id;
    END IF;

    SELECT * INTO v_cand_profile FROM public.candidate_profiles WHERE candidate_id = p_candidate_id;
    SELECT * INTO v_cand_preferences FROM public.candidate_preferences WHERE candidate_id = p_candidate_id;

    -- 2. Load Matching Profile configuration
    IF p_matching_profile_id IS NOT NULL THEN
        SELECT configuration, version INTO v_profile_config, v_profile_version
        FROM public.matching_profiles WHERE id = p_matching_profile_id;
    END IF;

    IF v_profile_config IS NULL THEN
        -- Fallback to organization default or global default
        SELECT configuration, version, id INTO v_profile_config, v_profile_version, p_matching_profile_id
        FROM public.matching_profiles
        WHERE (organization_id = v_job.organization_id AND is_default = true)
           OR (organization_id IS NULL AND is_default = true)
        ORDER BY organization_id NULLS LAST
        LIMIT 1;
    END IF;

    IF v_profile_config IS NOT NULL AND v_profile_config ? 'weights' THEN
        w_skills := COALESCE((v_profile_config->'weights'->>'skills')::NUMERIC, w_skills);
        w_experience := COALESCE((v_profile_config->'weights'->>'experience')::NUMERIC, w_experience);
        w_languages := COALESCE((v_profile_config->'weights'->>'languages')::NUMERIC, w_languages);
        w_education := COALESCE((v_profile_config->'weights'->>'education')::NUMERIC, w_education);
        w_location := COALESCE((v_profile_config->'weights'->>'location')::NUMERIC, w_location);
        w_career_level := COALESCE((v_profile_config->'weights'->>'career_level')::NUMERIC, w_career_level);
        w_certifications := COALESCE((v_profile_config->'weights'->>'certifications')::NUMERIC, w_certifications);
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 1: SKILLS MATCHING
    -- -------------------------------------------------------------------------
    v_req_count := 0;
    v_match_count := 0;
    
    -- Evaluate skills defined in job_skills
    FOR r_item IN 
        SELECT js.skill_name, js.is_required, js.minimum_level
        FROM public.job_skills js
        WHERE js.job_id = p_job_id
    LOOP
        v_req_count := v_req_count + 1;
        
        -- Check candidate skills (exact or alias match)
        IF EXISTS (
            SELECT 1 FROM public.candidate_skills cs
            WHERE cs.candidate_id = p_candidate_id
              AND (
                  lower(cs.skill_name) = lower(r_item.skill_name)
                  OR public.normalize_skill_text(cs.skill_name) = public.normalize_skill_text(r_item.skill_name)
              )
        ) THEN
            v_match_count := v_match_count + 1;
            ev_skills := ev_skills || jsonb_build_object(r_item.skill_name, 'matched');
            v_strengths := array_append(v_strengths, 'Skill matched: ' || r_item.skill_name);
        ELSE
            gap_skills := gap_skills || jsonb_build_object(r_item.skill_name, 'missing');
            IF r_item.is_required THEN
                v_hard_match := false;
                v_hard_failure_reasons := array_append(v_hard_failure_reasons, 'Mandatory skill missing: ' || r_item.skill_name);
                v_missing_required_items := array_append(v_missing_required_items, 'Required skill: ' || r_item.skill_name);
                v_gaps := array_append(v_gaps, 'Missing required skill: ' || r_item.skill_name);
            ELSE
                v_gaps := array_append(v_gaps, 'Missing optional skill: ' || r_item.skill_name);
            END IF;
        END IF;
    END LOOP;

    IF v_req_count = 0 THEN
        st_skills := 'not_applicable';
        s_skills := 100;
    ELSE
        s_skills := ROUND((v_match_count::NUMERIC / v_req_count::NUMERIC) * 100, 2);
        IF s_skills = 100 THEN
            st_skills := 'matched';
        ELSIF s_skills > 0 THEN
            st_skills := 'partially_matched';
        ELSE
            st_skills := 'not_matched';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 2: EXPERIENCE MATCHING
    -- -------------------------------------------------------------------------
    -- Compute candidate years of experience
    v_cand_years := COALESCE(v_cand_profile.years_of_experience, 0);
    IF v_cand_years = 0 THEN
        SELECT COALESCE(SUM(
            GREATEST(1, EXTRACT(YEAR FROM age(COALESCE(end_date, CURRENT_DATE), start_date)))
        ), 0)
        INTO v_cand_years
        FROM public.candidate_experience
        WHERE candidate_id = p_candidate_id;
    END IF;

    -- Determine required experience years from job experience_level
    CASE lower(COALESCE(v_job.experience_level, 'mid'))
        WHEN 'entry', 'internship' THEN v_req_years := 0;
        WHEN 'junior' THEN v_req_years := 1;
        WHEN 'mid' THEN v_req_years := 3;
        WHEN 'senior' THEN v_req_years := 5;
        WHEN 'lead', 'manager' THEN v_req_years := 7;
        WHEN 'director', 'executive' THEN v_req_years := 10;
        ELSE v_req_years := 2;
    END CASE;

    ev_exp := jsonb_build_object('candidate_years', v_cand_years, 'required_years', v_req_years);

    IF v_cand_years = 0 AND NOT EXISTS (SELECT 1 FROM public.candidate_experience WHERE candidate_id = p_candidate_id) THEN
        st_experience := 'unknown';
        s_experience := 50; -- neutral uncertainty score
        v_uncertain_items := array_append(v_uncertain_items, 'Work experience could not be confirmed from profile data');
    ELSIF v_req_years = 0 THEN
        st_experience := 'matched';
        s_experience := 100;
    ELSIF v_cand_years >= v_req_years THEN
        st_experience := 'matched';
        s_experience := 100;
        v_strengths := array_append(v_strengths, format('Experience exceeded: %s years recorded (required: %s)', v_cand_years, v_req_years));
    ELSE
        s_experience := ROUND((v_cand_years / v_req_years) * 100, 2);
        st_experience := 'partially_matched';
        v_gaps := array_append(v_gaps, format('Lower experience: %s years recorded (required: %s)', v_cand_years, v_req_years));
        gap_exp := jsonb_build_object('deficit_years', v_req_years - v_cand_years);
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 3: LANGUAGE MATCHING
    -- -------------------------------------------------------------------------
    v_req_count := 0;
    v_match_count := 0;

    FOR r_item IN
        SELECT jl.language_name, jl.language_code, jl.minimum_level, jl.is_required
        FROM public.job_languages jl
        WHERE jl.job_id = p_job_id
    LOOP
        v_req_count := v_req_count + 1;
        v_req_level_num := public.get_cefr_level_numeric(r_item.minimum_level);

        SELECT public.get_cefr_level_numeric(cl.proficiency_level) INTO v_cand_level_num
        FROM public.candidate_languages cl
        WHERE cl.candidate_id = p_candidate_id
          AND (
              lower(cl.language_name) = lower(r_item.language_name)
              OR (r_item.language_code IS NOT NULL AND lower(cl.language_code) = lower(r_item.language_code))
          )
        LIMIT 1;

        IF v_cand_level_num IS NOT NULL THEN
            IF v_cand_level_num >= v_req_level_num THEN
                v_match_count := v_match_count + 1;
                ev_lang := ev_lang || jsonb_build_object(r_item.language_name, 'matched');
                v_strengths := array_append(v_strengths, 'Language requirement satisfied: ' || r_item.language_name);
            ELSE
                -- Partial language match
                v_match_count := v_match_count + 0.6;
                ev_lang := ev_lang || jsonb_build_object(r_item.language_name, 'partially_matched');
                v_gaps := array_append(v_gaps, format('Language proficiency lower than required: %s (requires %s)', r_item.language_name, r_item.minimum_level));
                IF r_item.is_required THEN
                    v_hard_match := false;
                    v_hard_failure_reasons := array_append(v_hard_failure_reasons, 'Mandatory language level not satisfied: ' || r_item.language_name);
                    v_missing_required_items := array_append(v_missing_required_items, 'Required language proficiency: ' || r_item.language_name);
                END IF;
            END IF;
        ELSE
            gap_lang := gap_lang || jsonb_build_object(r_item.language_name, 'not_verified');
            v_uncertain_items := array_append(v_uncertain_items, 'Language proficiency could not be verified: ' || r_item.language_name);
            IF r_item.is_required THEN
                v_hard_match := false;
                v_hard_failure_reasons := array_append(v_hard_failure_reasons, 'Required language not verified: ' || r_item.language_name);
                v_missing_required_items := array_append(v_missing_required_items, 'Required language: ' || r_item.language_name);
            END IF;
        END IF;
    END LOOP;

    IF v_req_count = 0 THEN
        st_languages := 'not_applicable';
        s_languages := 100;
    ELSE
        s_languages := ROUND((v_match_count::NUMERIC / v_req_count::NUMERIC) * 100, 2);
        IF s_languages >= 100 THEN
            st_languages := 'matched';
        ELSIF s_languages > 0 THEN
            st_languages := 'partially_matched';
        ELSE
            st_languages := 'not_matched';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 4: EDUCATION MATCHING
    -- -------------------------------------------------------------------------
    SELECT MAX(public.get_education_level_numeric(degree)) INTO v_cand_level_num
    FROM public.candidate_education
    WHERE candidate_id = p_candidate_id;

    IF v_cand_level_num IS NULL OR v_cand_level_num = 0 THEN
        st_education := 'unknown';
        s_education := 60;
        v_uncertain_items := array_append(v_uncertain_items, 'Highest education degree not recorded in profile');
    ELSIF v_cand_level_num >= 3 THEN -- Bachelors or higher
        st_education := 'matched';
        s_education := 100;
        v_strengths := array_append(v_strengths, 'Holds verified tertiary higher education degree');
        ev_edu := jsonb_build_object('level_numeric', v_cand_level_num);
    ELSE
        st_education := 'partially_matched';
        s_education := 75;
        ev_edu := jsonb_build_object('level_numeric', v_cand_level_num);
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 5: LOCATION & WORKPLACE MATCHING
    -- -------------------------------------------------------------------------
    IF lower(COALESCE(v_job.workplace_type, 'remote')) = 'remote' THEN
        s_location := 100;
        st_location := 'matched';
        ev_loc := jsonb_build_object('job_workplace', 'remote', 'match', 'universal');
        v_strengths := array_append(v_strengths, 'Fully remote job matches global candidate availability');
    ELSE
        -- Onsite or Hybrid: compare country and city
        IF v_cand_profile.country_code IS NOT NULL AND v_job.country IS NOT NULL AND lower(v_cand_profile.country_code) = lower(v_job.country) THEN
            s_location := 100;
            st_location := 'matched';
            v_strengths := array_append(v_strengths, 'Location matched: candidate in same country (' || v_job.country || ')');
        ELSIF v_cand_preferences.willing_to_relocate = true THEN
            s_location := 90;
            st_location := 'partially_matched';
            v_strengths := array_append(v_strengths, 'Candidate willing to relocate for onsite/hybrid position');
        ELSIF v_cand_profile.country_code IS NULL THEN
            s_location := 50;
            st_location := 'unknown';
            v_uncertain_items := array_append(v_uncertain_items, 'Candidate country/location unconfirmed');
        ELSE
            s_location := 30;
            st_location := 'not_matched';
            v_gaps := array_append(v_gaps, 'Location mismatch for onsite role (' || COALESCE(v_job.country, 'specified location') || ')');
            gap_loc := jsonb_build_object('candidate_country', v_cand_profile.country_code, 'job_country', v_job.country);
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 6: CAREER LEVEL MATCHING
    -- -------------------------------------------------------------------------
    IF v_cand_years >= v_req_years THEN
        s_career_level := 100;
        st_career_level := 'matched';
        ev_career := jsonb_build_object('aligned_level', v_job.experience_level);
    ELSE
        s_career_level := GREATEST(30, ROUND((v_cand_years / GREATEST(1, v_req_years)) * 100, 2));
        st_career_level := 'partially_matched';
        gap_career := jsonb_build_object('required_level', v_job.experience_level);
    END IF;

    -- -------------------------------------------------------------------------
    -- DIMENSION 7: CERTIFICATIONS MATCHING
    -- -------------------------------------------------------------------------
    v_req_count := 0;
    v_match_count := 0;

    FOR r_item IN
        SELECT jr.title, jr.is_required
        FROM public.job_requirements jr
        WHERE jr.job_id = p_job_id AND jr.requirement_type = 'certification'
    LOOP
        v_req_count := v_req_count + 1;
        IF EXISTS (
            SELECT 1 FROM public.candidate_certifications cc
            WHERE cc.candidate_id = p_candidate_id
              AND lower(cc.certification_name) LIKE '%' || lower(trim(r_item.title)) || '%'
        ) THEN
            v_match_count := v_match_count + 1;
            ev_cert := ev_cert || jsonb_build_object(r_item.title, 'verified');
            v_strengths := array_append(v_strengths, 'Certification verified: ' || r_item.title);
        ELSE
            gap_cert := gap_cert || jsonb_build_object(r_item.title, 'missing');
            IF r_item.is_required THEN
                v_hard_match := false;
                v_hard_failure_reasons := array_append(v_hard_failure_reasons, 'Mandatory certification missing: ' || r_item.title);
                v_missing_required_items := array_append(v_missing_required_items, 'Required certification: ' || r_item.title);
            ELSE
                v_gaps := array_append(v_gaps, 'Preferred certification not present: ' || r_item.title);
            END IF;
        END IF;
    END LOOP;

    IF v_req_count = 0 THEN
        st_certifications := 'not_applicable';
        s_certifications := 100;
    ELSE
        s_certifications := ROUND((v_match_count::NUMERIC / v_req_count::NUMERIC) * 100, 2);
        IF s_certifications = 100 THEN
            st_certifications := 'matched';
        ELSIF s_certifications > 0 THEN
            st_certifications := 'partially_matched';
        ELSE
            st_certifications := 'not_matched';
        END IF;
    END IF;

    -- -------------------------------------------------------------------------
    -- CALCULATE FINAL WEIGHTED SCORE
    -- -------------------------------------------------------------------------
    v_total_weight := w_skills + w_experience + w_languages + w_education + w_location + w_career_level + w_certifications;
    v_weighted_sum := (s_skills * w_skills) +
                      (s_experience * w_experience) +
                      (s_languages * w_languages) +
                      (s_education * w_education) +
                      (s_location * w_location) +
                      (s_career_level * w_career_level) +
                      (s_certifications * w_certifications);

    v_final_score := ROUND(v_weighted_sum / NULLIF(v_total_weight, 0), 2);

    -- Confidence calculation based on uncertain items
    IF cardinality(v_uncertain_items) > 2 THEN
        v_confidence := 0.70;
    ELSIF cardinality(v_uncertain_items) > 0 THEN
        v_confidence := 0.85;
    ELSE
        v_confidence := 0.95;
    END IF;

    -- Recommendation synthesis
    IF NOT v_hard_match THEN
        v_recommendation := 'not_recommended';
        v_summary := format('Candidate achieved a %s%% numerical match but does not satisfy mandatory job requirements: %s.',
            v_final_score, array_to_string(v_hard_failure_reasons, '; '));
    ELSIF v_final_score >= 85 THEN
        v_recommendation := 'strongly_recommend';
        v_summary := format('Outstanding profile match (%s%%) with strong alignment across required technical competencies and experience.', v_final_score);
    ELSIF v_final_score >= 70 THEN
        v_recommendation := 'recommend';
        v_summary := format('Strong profile match (%s%%) meeting core criteria with manageable gaps.', v_final_score);
    ELSIF v_final_score >= 50 THEN
        v_recommendation := 'consider';
        v_summary := format('Moderate qualification match (%s%%). Review candidate gaps before advancing.', v_final_score);
    ELSE
        v_recommendation := 'not_recommended';
        v_summary := format('Low profile alignment (%s%%) across critical job dimensions.', v_final_score);
    END IF;

    -- -------------------------------------------------------------------------
    -- PERSIST MATCHING RUN
    -- -------------------------------------------------------------------------
    INSERT INTO public.matching_runs (
        candidate_id,
        job_id,
        application_id,
        matching_profile_id,
        matching_profile_version,
        engine_version,
        status,
        hard_match,
        hard_failure_reasons,
        final_score,
        confidence,
        started_at,
        completed_at
    )
    VALUES (
        p_candidate_id,
        p_job_id,
        p_application_id,
        p_matching_profile_id,
        v_profile_version,
        p_engine_version,
        'completed',
        v_hard_match,
        v_hard_failure_reasons,
        v_final_score,
        v_confidence,
        now(),
        now()
    )
    RETURNING id INTO v_run_id;

    -- -------------------------------------------------------------------------
    -- PERSIST DIMENSION BREAKDOWNS
    -- -------------------------------------------------------------------------
    INSERT INTO public.match_dimension_results (
        matching_run_id, dimension, score, weight, weighted_score, status, confidence, evidence, gaps, explanation
    )
    VALUES
        (v_run_id, 'skills', s_skills, w_skills, ROUND((s_skills * w_skills) / 100, 2), st_skills, 0.95, ev_skills, gap_skills, 'Skill inventory evaluation'),
        (v_run_id, 'experience', s_experience, w_experience, ROUND((s_experience * w_experience) / 100, 2), st_experience, 0.90, ev_exp, gap_exp, 'Years and domain experience evaluation'),
        (v_run_id, 'languages', s_languages, w_languages, ROUND((s_languages * w_languages) / 100, 2), st_languages, 0.95, ev_lang, gap_lang, 'Linguistic proficiency evaluation'),
        (v_run_id, 'education', s_education, w_education, ROUND((s_education * w_education) / 100, 2), st_education, 0.85, ev_edu, gap_edu, 'Academic credential evaluation'),
        (v_run_id, 'location', s_location, w_location, ROUND((s_location * w_location) / 100, 2), st_location, 0.90, ev_loc, gap_loc, 'Location and workplace alignment'),
        (v_run_id, 'career_level', s_career_level, w_career_level, ROUND((s_career_level * w_career_level) / 100, 2), st_career_level, 0.85, ev_career, gap_career, 'Seniority level alignment'),
        (v_run_id, 'certifications', s_certifications, w_certifications, ROUND((s_certifications * w_certifications) / 100, 2), st_certifications, 0.95, ev_cert, gap_cert, 'Professional credentials check');

    -- -------------------------------------------------------------------------
    -- PERSIST EXPLANATION
    -- -------------------------------------------------------------------------
    INSERT INTO public.match_explanations (
        matching_run_id, summary, strengths, gaps, missing_required_items, uncertain_items, recommendation, explanation_version
    )
    VALUES (
        v_run_id,
        v_summary,
        v_strengths,
        v_gaps,
        v_missing_required_items,
        v_uncertain_items,
        v_recommendation,
        1
    );

    -- -------------------------------------------------------------------------
    -- UPDATE APPLICATION IF PROVIDED
    -- -------------------------------------------------------------------------
    IF p_application_id IS NOT NULL THEN
        UPDATE public.applications
        SET match_score = v_final_score,
            match_score_computed_at = now(),
            match_score_breakdown = jsonb_build_object(
                'matching_run_id', v_run_id,
                'final_score', v_final_score,
                'hard_match', v_hard_match,
                'recommendation', v_recommendation,
                'dimension_scores', jsonb_build_object(
                    'skills', s_skills,
                    'experience', s_experience,
                    'languages', s_languages,
                    'education', s_education,
                    'location', s_location,
                    'career_level', s_career_level,
                    'certifications', s_certifications
                )
            ),
            is_eligible = v_hard_match,
            ineligibility_reasons = v_hard_failure_reasons,
            ai_recommendation = CASE v_recommendation
                WHEN 'strongly_recommend' THEN 'strong_match'
                WHEN 'recommend' THEN 'good_match'
                WHEN 'consider' THEN 'partial_match'
                WHEN 'not_recommended' THEN 'no_match'
                ELSE 'weak_match'
            END,
            updated_at = now()
        WHERE id = p_application_id;
    END IF;

    -- -------------------------------------------------------------------------
    -- AUDIT LOGGING
    -- -------------------------------------------------------------------------
    INSERT INTO public.audit_logs (
        actor_user_id,
        organization_id,
        action,
        entity_type,
        entity_id,
        metadata
    )
    VALUES (
        auth.uid(),
        v_job.organization_id,
        'matching_run_completed',
        'matching_run',
        v_run_id,
        jsonb_build_object(
            'candidate_id', p_candidate_id,
            'job_id', p_job_id,
            'application_id', p_application_id,
            'final_score', v_final_score,
            'hard_match', v_hard_match,
            'recommendation', v_recommendation
        )
    );

    RETURN v_run_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 13. RANK CANDIDATES FOR JOB (Recruiter Ranking API)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rank_candidates_for_job(
    p_job_id UUID,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0,
    p_hard_match_only BOOLEAN DEFAULT false,
    p_min_score NUMERIC DEFAULT 0,
    p_matching_profile_id UUID DEFAULT NULL
)
RETURNS TABLE (
    matching_run_id UUID,
    candidate_id UUID,
    candidate_name TEXT,
    headline TEXT,
    years_of_experience NUMERIC,
    final_score NUMERIC,
    hard_match BOOLEAN,
    confidence NUMERIC,
    recommendation TEXT,
    summary TEXT,
    strengths TEXT[],
    gaps TEXT[],
    missing_required_items TEXT[],
    completed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job_org_id UUID;
BEGIN
    -- Verify Job access
    SELECT organization_id INTO v_job_org_id
    FROM public.jobs WHERE id = p_job_id;

    IF v_job_org_id IS NULL THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    -- Verify caller authority: Platform admin OR member of organization with jobs/applications permission
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_job_org_id, 'applications.read', auth.uid())
        OR public.has_org_permission(v_job_org_id, 'jobs.manage', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: caller does not have permission to view rankings for job %', p_job_id;
    END IF;

    RETURN QUERY
    WITH latest_runs AS (
        SELECT DISTINCT ON (mr.candidate_id)
            mr.id AS run_id,
            mr.candidate_id,
            mr.final_score,
            mr.hard_match,
            mr.confidence,
            mr.completed_at
        FROM public.matching_runs mr
        WHERE mr.job_id = p_job_id
          AND mr.status = 'completed'
          AND (p_hard_match_only = false OR mr.hard_match = true)
          AND mr.final_score >= p_min_score
        ORDER BY mr.candidate_id, mr.created_at DESC
    )
    SELECT
        lr.run_id,
        lr.candidate_id,
        COALESCE(p.full_name, 'Candidate ' || substr(c.id::text, 1, 8)) AS candidate_name,
        cp.headline,
        cp.years_of_experience,
        lr.final_score,
        lr.hard_match,
        lr.confidence,
        me.recommendation,
        me.summary,
        me.strengths,
        me.gaps,
        me.missing_required_items,
        lr.completed_at
    FROM latest_runs lr
    JOIN public.candidates c ON c.id = lr.candidate_id
    LEFT JOIN public.profiles p ON p.id = c.user_id
    LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
    LEFT JOIN public.match_explanations me ON me.matching_run_id = lr.run_id
    ORDER BY lr.final_score DESC, lr.hard_match DESC, lr.confidence DESC, lr.completed_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- -----------------------------------------------------------------------------
-- 14. GET BEST JOBS FOR CANDIDATE (Candidate Recommendation API)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_best_jobs_for_candidate(
    p_candidate_id UUID,
    p_limit INT DEFAULT 10,
    p_offset INT DEFAULT 0,
    p_min_score NUMERIC DEFAULT 50
)
RETURNS TABLE (
    job_id UUID,
    job_title TEXT,
    company_name TEXT,
    workplace_type TEXT,
    location TEXT,
    final_score NUMERIC,
    hard_match BOOLEAN,
    recommendation TEXT,
    strengths TEXT[],
    published_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Verify authority: caller must be candidate owner, authorized recruiter, or admin
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.get_candidate_id_for_user(auth.uid()) = p_candidate_id
        OR public.has_candidate_read_access(p_candidate_id, auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot view job recommendations for candidate %', p_candidate_id;
    END IF;

    RETURN QUERY
    WITH latest_runs AS (
        SELECT DISTINCT ON (mr.job_id)
            mr.id AS run_id,
            mr.job_id,
            mr.final_score,
            mr.hard_match,
            mr.completed_at
        FROM public.matching_runs mr
        JOIN public.jobs j ON j.id = mr.job_id
        WHERE mr.candidate_id = p_candidate_id
          AND mr.status = 'completed'
          AND mr.final_score >= p_min_score
          AND j.status = 'published'
          AND j.visibility = 'public'
        ORDER BY mr.job_id, mr.created_at DESC
    )
    SELECT
        j.id AS job_id,
        j.title AS job_title,
        org.name AS company_name,
        j.workplace_type,
        j.location,
        lr.final_score,
        lr.hard_match,
        COALESCE(me.recommendation, 'consider') AS recommendation,
        COALESCE(me.strengths, ARRAY[]::TEXT[]) AS strengths,
        j.published_at
    FROM latest_runs lr
    JOIN public.jobs j ON j.id = lr.job_id
    JOIN public.organizations org ON org.id = j.organization_id
    LEFT JOIN public.match_explanations me ON me.matching_run_id = lr.run_id
    ORDER BY lr.final_score DESC, lr.hard_match DESC, j.published_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- -----------------------------------------------------------------------------
-- 15. OVERRIDE MATCH SCORE (Recruiter Human Review API)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.override_match_score(
    p_matching_run_id UUID,
    p_override_type TEXT,
    p_override_score NUMERIC,
    p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_override_id UUID;
    v_run RECORD;
    v_job RECORD;
    v_orig_score NUMERIC;
BEGIN
    IF length(trim(COALESCE(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'An override reason of at least 10 characters is mandatory';
    END IF;

    IF p_override_score < 0 OR p_override_score > 100 THEN
        RAISE EXCEPTION 'Override score must be between 0 and 100';
    END IF;

    SELECT * INTO v_run FROM public.matching_runs WHERE id = p_matching_run_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Matching run % not found', p_matching_run_id;
    END IF;

    SELECT * INTO v_job FROM public.jobs WHERE id = v_run.job_id;

    -- Verify recruiter permission
    IF NOT (
        public.is_platform_admin(auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'applications.manage', auth.uid())
        OR public.has_org_permission(v_job.organization_id, 'matching.override', auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: caller cannot override match score for organization %', v_job.organization_id;
    END IF;

    v_orig_score := v_run.final_score;

    -- Insert override record (preserving original score)
    INSERT INTO public.match_overrides (
        matching_run_id,
        override_type,
        original_score,
        override_score,
        reason,
        created_by
    )
    VALUES (
        p_matching_run_id,
        p_override_type,
        v_orig_score,
        p_override_score,
        trim(p_reason),
        auth.uid()
    )
    RETURNING id INTO v_override_id;

    -- Update run with new score
    UPDATE public.matching_runs
    SET final_score = p_override_score,
        updated_at = now()
    WHERE id = p_matching_run_id;

    -- If attached to an application, update application match score too
    IF v_run.application_id IS NOT NULL THEN
        UPDATE public.applications
        SET match_score = p_override_score,
            updated_at = now()
        WHERE id = v_run.application_id;
    END IF;

    -- Audit log event
    INSERT INTO public.audit_logs (
        actor_user_id,
        organization_id,
        action,
        entity_type,
        entity_id,
        metadata
    )
    VALUES (
        auth.uid(),
        v_job.organization_id,
        'manual_match_override',
        'match_override',
        v_override_id,
        jsonb_build_object(
            'matching_run_id', p_matching_run_id,
            'override_type', p_override_type,
            'original_score', v_orig_score,
            'override_score', p_override_score,
            'reason', p_reason
        )
    );

    RETURN v_override_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 16. ROW LEVEL SECURITY (RLS) POLICIES
-- -----------------------------------------------------------------------------

ALTER TABLE public.matching_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_criteria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matching_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_dimension_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_explanations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.match_overrides ENABLE ROW LEVEL SECURITY;

-- 16.1 matching_profiles:
-- Global profiles (organization_id IS NULL) are readable by all authenticated users
-- Organization-specific profiles are readable/manageable by organization members
CREATE POLICY matching_profiles_select_policy ON public.matching_profiles
    FOR SELECT TO authenticated
    USING (
        organization_id IS NULL
        OR public.is_platform_admin(auth.uid())
        OR public.is_org_member(auth.uid(), organization_id)
    );

CREATE POLICY matching_profiles_modify_policy ON public.matching_profiles
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR (
            organization_id IS NOT NULL 
            AND public.has_org_permission(organization_id, 'matching.configure', auth.uid())
        )
    )
    WITH CHECK (
        public.is_platform_admin(auth.uid())
        OR (
            organization_id IS NOT NULL 
            AND public.has_org_permission(organization_id, 'matching.configure', auth.uid())
        )
    );

-- 16.2 match_criteria:
-- Readable by anyone who can view the job
-- Manageable by recruiters of the organization
CREATE POLICY match_criteria_select_policy ON public.match_criteria
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = match_criteria.job_id
              AND (
                  j.status = 'published'
                  OR public.is_platform_admin(auth.uid())
                  OR public.is_org_member(auth.uid(), j.organization_id)
              )
        )
    );

CREATE POLICY match_criteria_modify_policy ON public.match_criteria
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = match_criteria.job_id
              AND (
                  public.is_platform_admin(auth.uid())
                  OR public.has_org_permission(j.organization_id, 'jobs.manage', auth.uid())
              )
        )
    );

-- 16.3 skill_aliases:
-- Readable by all authenticated users
CREATE POLICY skill_aliases_select_policy ON public.skill_aliases
    FOR SELECT TO authenticated
    USING (true);

-- Manageable only by platform admins
CREATE POLICY skill_aliases_modify_policy ON public.skill_aliases
    FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- 16.4 matching_runs:
-- Candidates can view their own runs
-- Recruiters can view runs for jobs in their organization or where candidate applied
CREATE POLICY matching_runs_select_policy ON public.matching_runs
    FOR SELECT TO authenticated
    USING (
        candidate_id = public.get_candidate_id_for_user(auth.uid())
        OR public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = matching_runs.job_id
              AND public.has_org_permission(j.organization_id, 'applications.read', auth.uid())
        )
        OR public.has_candidate_read_access(candidate_id, auth.uid())
    );

-- 16.5 match_dimension_results:
CREATE POLICY match_dimension_results_select_policy ON public.match_dimension_results
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.matching_runs mr
            WHERE mr.id = match_dimension_results.matching_run_id
              AND (
                  mr.candidate_id = public.get_candidate_id_for_user(auth.uid())
                  OR public.is_platform_admin(auth.uid())
                  OR EXISTS (
                      SELECT 1 FROM public.jobs j
                      WHERE j.id = mr.job_id
                        AND public.has_org_permission(j.organization_id, 'applications.read', auth.uid())
                  )
                  OR public.has_candidate_read_access(mr.candidate_id, auth.uid())
              )
        )
    );

-- 16.6 match_explanations:
CREATE POLICY match_explanations_select_policy ON public.match_explanations
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.matching_runs mr
            WHERE mr.id = match_explanations.matching_run_id
              AND (
                  mr.candidate_id = public.get_candidate_id_for_user(auth.uid())
                  OR public.is_platform_admin(auth.uid())
                  OR EXISTS (
                      SELECT 1 FROM public.jobs j
                      WHERE j.id = mr.job_id
                        AND public.has_org_permission(j.organization_id, 'applications.read', auth.uid())
                  )
                  OR public.has_candidate_read_access(mr.candidate_id, auth.uid())
              )
        )
    );

-- 16.7 match_overrides:
-- Readable by recruiters of the job's organization or platform admin
CREATE POLICY match_overrides_select_policy ON public.match_overrides
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.matching_runs mr
            JOIN public.jobs j ON j.id = mr.job_id
            WHERE mr.id = match_overrides.matching_run_id
              AND public.has_org_permission(j.organization_id, 'applications.read', auth.uid())
        )
    );

-- -----------------------------------------------------------------------------
-- 17. REPAIR APPLICATION AUDIT TRIGGER (Align with audit_logs schema)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_application_to_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), NEW.organization_id, 'application.submitted', 'application', NEW.id, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), NEW.organization_id, 'application.status_changed', 'application', NEW.id,
            jsonb_build_object('old_status', OLD.status, 'new_status', NEW.status)
        );
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

