-- =============================================================================
-- Migration: 20260915000300_candidate_domain.sql
-- Description: Hiren Beyond Candidate Domain
-- Author: Hiren Beyond Engineering
-- Schema: candidates, candidate_profiles, candidate_skills, candidate_languages,
--         candidate_experience, candidate_education, candidate_certifications,
--         candidate_preferences, candidate_documents, storage bucket & policies
-- =============================================================================

-- =============================================================================
-- 1. CANDIDATE DOMAIN TABLES
-- =============================================================================

-- A. CANDIDATES (Core root record for candidates)
CREATE TABLE IF NOT EXISTS public.candidates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended', 'archived')),
    profile_completion_percentage INTEGER NOT NULL DEFAULT 0 CHECK (profile_completion_percentage >= 0 AND profile_completion_percentage <= 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidates_user_id UNIQUE (user_id)
);

-- B. CANDIDATE_PROFILES (Detailed professional background and preferences)
CREATE TABLE IF NOT EXISTS public.candidate_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    headline TEXT,
    professional_summary TEXT,
    current_title TEXT,
    years_of_experience NUMERIC(4, 1) DEFAULT 0 CHECK (years_of_experience >= 0),
    country_code VARCHAR(10),
    city TEXT,
    location_text TEXT,
    remote_preference TEXT NOT NULL DEFAULT 'flexible' CHECK (remote_preference IN ('remote', 'hybrid', 'on_site', 'flexible')),
    job_type_preference TEXT[] NOT NULL DEFAULT ARRAY['full_time'::TEXT],
    availability_status TEXT NOT NULL DEFAULT 'open_to_discussion' CHECK (availability_status IN ('immediately', 'within_two_weeks', 'within_one_month', 'not_available', 'open_to_discussion')),
    available_from DATE,
    salary_min NUMERIC(12, 2) CHECK (salary_min IS NULL OR salary_min >= 0),
    salary_max NUMERIC(12, 2) CHECK (salary_max IS NULL OR salary_max >= 0),
    salary_currency VARCHAR(10) DEFAULT 'USD',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidate_profiles_candidate UNIQUE (candidate_id),
    CONSTRAINT chk_salary_range CHECK (salary_max IS NULL OR salary_min IS NULL OR salary_max >= salary_min)
);

-- C. CANDIDATE_SKILLS (Technical, soft, industry, tool, and domain competencies)
CREATE TABLE IF NOT EXISTS public.candidate_skills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    skill_name TEXT NOT NULL,
    normalized_skill_name TEXT NOT NULL,
    skill_type TEXT NOT NULL DEFAULT 'technical' CHECK (skill_type IN ('technical', 'soft', 'industry', 'tool', 'domain', 'other')),
    proficiency_level TEXT NOT NULL DEFAULT 'intermediate' CHECK (proficiency_level IN ('beginner', 'intermediate', 'advanced', 'expert', 'unknown')),
    years_of_experience NUMERIC(4, 1) CHECK (years_of_experience IS NULL OR years_of_experience >= 0),
    is_verified BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'candidate' CHECK (source IN ('candidate', 'cv_extraction', 'recruiter', 'assessment', 'ai_suggestion')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidate_skill UNIQUE (candidate_id, normalized_skill_name),
    CONSTRAINT chk_ai_skill_unverified CHECK (NOT (source = 'ai_suggestion' AND is_verified = true))
);

-- D. CANDIDATE_LANGUAGES (Multilingual proficiencies mapped to CEFR standards)
CREATE TABLE IF NOT EXISTS public.candidate_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    language_name TEXT NOT NULL,
    normalized_language_name TEXT NOT NULL,
    language_code VARCHAR(10) NOT NULL,
    proficiency_level TEXT NOT NULL DEFAULT 'unknown' CHECK (proficiency_level IN ('a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'native', 'unknown')),
    is_native BOOLEAN NOT NULL DEFAULT false,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'candidate' CHECK (source IN ('candidate', 'cv_extraction', 'recruiter', 'assessment', 'ai_suggestion')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidate_language UNIQUE (candidate_id, language_code),
    CONSTRAINT chk_ai_lang_unverified CHECK (NOT (source = 'ai_suggestion' AND is_verified = true))
);

-- E. CANDIDATE_EXPERIENCE (Employment history & career milestones)
CREATE TABLE IF NOT EXISTS public.candidate_experience (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    company_name TEXT NOT NULL,
    job_title TEXT NOT NULL,
    employment_type TEXT NOT NULL DEFAULT 'full_time' CHECK (employment_type IN ('full_time', 'part_time', 'contract', 'freelance', 'temporary', 'internship')),
    start_date DATE NOT NULL,
    end_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT false,
    description TEXT,
    achievements TEXT,
    location TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_experience_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT chk_experience_current CHECK (NOT (is_current = true AND end_date IS NOT NULL))
);

-- F. CANDIDATE_EDUCATION (Academic qualifications & continuous study)
CREATE TABLE IF NOT EXISTS public.candidate_education (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    institution_name TEXT NOT NULL,
    degree TEXT,
    field_of_study TEXT,
    start_date DATE,
    end_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT false,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_education_dates CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

-- G. CANDIDATE_CERTIFICATIONS (Professional credentials & licenses)
CREATE TABLE IF NOT EXISTS public.candidate_certifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    issuing_organization TEXT NOT NULL,
    issue_date DATE,
    expiry_date DATE,
    credential_id TEXT,
    credential_url TEXT,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_certification_dates CHECK (expiry_date IS NULL OR issue_date IS NULL OR expiry_date >= issue_date)
);

-- H. CANDIDATE_PREFERENCES (Relocation, compensation & shift targets)
CREATE TABLE IF NOT EXISTS public.candidate_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    preferred_countries TEXT[] DEFAULT '{}',
    preferred_cities TEXT[] DEFAULT '{}',
    preferred_categories TEXT[] DEFAULT '{}',
    preferred_shifts TEXT[] DEFAULT '{}',
    remote_only BOOLEAN NOT NULL DEFAULT false,
    willing_to_relocate BOOLEAN NOT NULL DEFAULT false,
    minimum_salary NUMERIC(12, 2) CHECK (minimum_salary IS NULL OR minimum_salary >= 0),
    salary_currency VARCHAR(10) DEFAULT 'USD',
    notice_period_days INTEGER CHECK (notice_period_days IS NULL OR notice_period_days >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_candidate_preferences UNIQUE (candidate_id)
);

-- I. CANDIDATE_DOCUMENTS (Resumes, portfolios, cover letters)
CREATE TABLE IF NOT EXISTS public.candidate_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    document_type TEXT NOT NULL CHECK (document_type IN ('cv', 'resume', 'cover_letter', 'certificate', 'portfolio', 'other')),
    file_path TEXT NOT NULL,
    original_file_name TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    storage_bucket TEXT NOT NULL DEFAULT 'candidate-documents',
    status TEXT NOT NULL DEFAULT 'uploaded' CHECK (status IN ('uploaded', 'processing', 'processed', 'failed', 'archived')),
    is_primary BOOLEAN NOT NULL DEFAULT false,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 2. INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_candidates_user_id ON public.candidates(user_id);
CREATE INDEX IF NOT EXISTS idx_candidates_status ON public.candidates(status);
CREATE INDEX IF NOT EXISTS idx_candidates_completion ON public.candidates(profile_completion_percentage);

CREATE INDEX IF NOT EXISTS idx_candidate_profiles_cand ON public.candidate_profiles(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_country ON public.candidate_profiles(country_code);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_city ON public.candidate_profiles(city);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_remote ON public.candidate_profiles(remote_preference);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_avail ON public.candidate_profiles(availability_status);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_salary ON public.candidate_profiles(salary_min, salary_max);

CREATE INDEX IF NOT EXISTS idx_candidate_skills_cand ON public.candidate_skills(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_skills_norm ON public.candidate_skills(normalized_skill_name);
CREATE INDEX IF NOT EXISTS idx_candidate_skills_type ON public.candidate_skills(skill_type);
CREATE INDEX IF NOT EXISTS idx_candidate_skills_prof ON public.candidate_skills(proficiency_level);
CREATE INDEX IF NOT EXISTS idx_candidate_skills_verif ON public.candidate_skills(is_verified);

CREATE INDEX IF NOT EXISTS idx_candidate_lang_cand ON public.candidate_languages(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_lang_code ON public.candidate_languages(language_code);
CREATE INDEX IF NOT EXISTS idx_candidate_lang_prof ON public.candidate_languages(proficiency_level);
CREATE INDEX IF NOT EXISTS idx_candidate_lang_verif ON public.candidate_languages(is_verified);

CREATE INDEX IF NOT EXISTS idx_candidate_exp_cand ON public.candidate_experience(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_exp_dates ON public.candidate_experience(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_candidate_exp_current ON public.candidate_experience(is_current);

CREATE INDEX IF NOT EXISTS idx_candidate_edu_cand ON public.candidate_education(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_cert_cand ON public.candidate_certifications(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_pref_cand ON public.candidate_preferences(candidate_id);

CREATE INDEX IF NOT EXISTS idx_candidate_docs_cand ON public.candidate_documents(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_docs_type ON public.candidate_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_candidate_docs_status ON public.candidate_documents(status);
CREATE INDEX IF NOT EXISTS idx_candidate_docs_primary ON public.candidate_documents(is_primary);

-- =============================================================================
-- 3. TIMESTAMP TRIGGERS
-- =============================================================================

CREATE TRIGGER trg_candidates_updated_at BEFORE UPDATE ON public.candidates
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_profiles_updated_at BEFORE UPDATE ON public.candidate_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_skills_updated_at BEFORE UPDATE ON public.candidate_skills
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_languages_updated_at BEFORE UPDATE ON public.candidate_languages
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_experience_updated_at BEFORE UPDATE ON public.candidate_experience
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_education_updated_at BEFORE UPDATE ON public.candidate_education
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_certifications_updated_at BEFORE UPDATE ON public.candidate_certifications
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_preferences_updated_at BEFORE UPDATE ON public.candidate_preferences
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_candidate_documents_updated_at BEFORE UPDATE ON public.candidate_documents
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. PROFILE COMPLETION ENGINE
-- =============================================================================

CREATE OR REPLACE FUNCTION public.calculate_candidate_profile_completion(candidate_uuid UUID)
RETURNS INTEGER AS $$
DECLARE
    score INTEGER := 0;
    has_profile BOOLEAN := false;
    has_cv BOOLEAN := false;
    skill_count INTEGER := 0;
    lang_count INTEGER := 0;
    exp_count INTEGER := 0;
    edu_count INTEGER := 0;
    has_pref BOOLEAN := false;
BEGIN
    IF candidate_uuid IS NULL THEN
        RETURN 0;
    END IF;

    -- 1. Candidate Profile: up to 25 points
    SELECT (headline IS NOT NULL AND professional_summary IS NOT NULL AND current_title IS NOT NULL)
    INTO has_profile
    FROM public.candidate_profiles
    WHERE candidate_id = candidate_uuid;

    IF has_profile THEN
        score := score + 25;
    END IF;

    -- 2. Primary CV/Resume Document: 20 points
    SELECT EXISTS (
        SELECT 1
        FROM public.candidate_documents
        WHERE candidate_id = candidate_uuid
          AND document_type IN ('cv', 'resume')
          AND status IN ('uploaded', 'processed')
    ) INTO has_cv;

    IF has_cv THEN
        score := score + 20;
    END IF;

    -- 3. Skills: 15 points (at least 3 skills)
    SELECT COUNT(*)
    INTO skill_count
    FROM public.candidate_skills
    WHERE candidate_id = candidate_uuid;

    IF skill_count >= 3 THEN
        score := score + 15;
    ELSIF skill_count > 0 THEN
        score := score + (skill_count * 5);
    END IF;

    -- 4. Languages: 10 points (at least 1 language)
    SELECT COUNT(*)
    INTO lang_count
    FROM public.candidate_languages
    WHERE candidate_id = candidate_uuid;

    IF lang_count >= 1 THEN
        score := score + 10;
    END IF;

    -- 5. Experience: 15 points (at least 1 experience record)
    SELECT COUNT(*)
    INTO exp_count
    FROM public.candidate_experience
    WHERE candidate_id = candidate_uuid;

    IF exp_count >= 1 THEN
        score := score + 15;
    END IF;

    -- 6. Education: 10 points (at least 1 education record)
    SELECT COUNT(*)
    INTO edu_count
    FROM public.candidate_education
    WHERE candidate_id = candidate_uuid;

    IF edu_count >= 1 THEN
        score := score + 10;
    END IF;

    -- 7. Career Preferences: 5 points
    SELECT EXISTS (
        SELECT 1
        FROM public.candidate_preferences
        WHERE candidate_id = candidate_uuid
    ) INTO has_pref;

    IF has_pref THEN
        score := score + 5;
    END IF;

    RETURN LEAST(score, 100);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Trigger function to synchronize profile completion score automatically
CREATE OR REPLACE FUNCTION public.sync_candidate_profile_completion()
RETURNS TRIGGER AS $$
DECLARE
    target_candidate_id UUID;
    new_percentage INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_candidate_id := OLD.candidate_id;
    ELSE
        target_candidate_id := NEW.candidate_id;
    END IF;

    IF target_candidate_id IS NOT NULL THEN
        new_percentage := public.calculate_candidate_profile_completion(target_candidate_id);
        UPDATE public.candidates
        SET profile_completion_percentage = new_percentage,
            updated_at = now()
        WHERE id = target_candidate_id;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Attach completion recalculation trigger to all candidate sub-tables
DROP TRIGGER IF EXISTS trg_sync_completion_profile ON public.candidate_profiles;
CREATE TRIGGER trg_sync_completion_profile
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_profiles
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

DROP TRIGGER IF EXISTS trg_sync_completion_docs ON public.candidate_documents;
CREATE TRIGGER trg_sync_completion_docs
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_documents
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

DROP TRIGGER IF EXISTS trg_sync_completion_skills ON public.candidate_skills;
CREATE TRIGGER trg_sync_completion_skills
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_skills
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

DROP TRIGGER IF EXISTS trg_sync_completion_lang ON public.candidate_languages;
CREATE TRIGGER trg_sync_completion_lang
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_languages
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

DROP TRIGGER IF EXISTS trg_sync_completion_exp ON public.candidate_experience;
CREATE TRIGGER trg_sync_completion_exp
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_experience
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

DROP TRIGGER IF EXISTS trg_sync_completion_edu ON public.candidate_education;
CREATE TRIGGER trg_sync_completion_edu
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_education
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

DROP TRIGGER IF EXISTS trg_sync_completion_pref ON public.candidate_preferences;
CREATE TRIGGER trg_sync_completion_pref
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_preferences
    FOR EACH ROW EXECUTE FUNCTION public.sync_candidate_profile_completion();

-- =============================================================================
-- 5. CANDIDATE SECURITY & ACCESS CONTROL HELPERS
-- =============================================================================

-- Get candidate ID corresponding to a user ID
CREATE OR REPLACE FUNCTION public.get_candidate_id_for_user(user_uuid UUID DEFAULT auth.uid())
RETURNS UUID AS $$
    SELECT id FROM public.candidates WHERE user_id = user_uuid LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- Check whether a user is permitted to read a candidate's data
CREATE OR REPLACE FUNCTION public.has_candidate_read_access(target_candidate_id UUID, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    IF check_user_id IS NULL OR target_candidate_id IS NULL THEN
        RETURN false;
    END IF;

    -- Candidate owner can always read their own record
    IF EXISTS (
        SELECT 1 FROM public.candidates
        WHERE id = target_candidate_id AND user_id = check_user_id
    ) THEN
        RETURN true;
    END IF;

    -- Platform admin holds system-wide access
    IF public.is_platform_admin(check_user_id) THEN
        RETURN true;
    END IF;

    -- Recruiters in active recruitment organizations with 'candidates.read' permission
    RETURN EXISTS (
        SELECT 1
        FROM public.organization_members om
        JOIN public.organizations o ON o.id = om.organization_id
        JOIN public.role_permissions rp ON rp.role_id = om.role_id
        JOIN public.permissions p ON p.id = rp.permission_id
        WHERE om.user_id = check_user_id
          AND om.status = 'active'
          AND o.status = 'active'
          AND o.organization_type IN ('platform', 'recruitment_agency')
          AND p.key IN ('candidates.read', 'candidates.manage')
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Check whether a user is permitted to manage a candidate's data
CREATE OR REPLACE FUNCTION public.has_candidate_manage_access(target_candidate_id UUID, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    IF check_user_id IS NULL OR target_candidate_id IS NULL THEN
        RETURN false;
    END IF;

    -- Candidate owner can manage their own record
    IF EXISTS (
        SELECT 1 FROM public.candidates
        WHERE id = target_candidate_id AND user_id = check_user_id
    ) THEN
        RETURN true;
    END IF;

    -- Platform admin
    IF public.is_platform_admin(check_user_id) THEN
        RETURN true;
    END IF;

    -- Recruiters with 'candidates.manage' permission
    RETURN EXISTS (
        SELECT 1
        FROM public.organization_members om
        JOIN public.organizations o ON o.id = om.organization_id
        JOIN public.role_permissions rp ON rp.role_id = om.role_id
        JOIN public.permissions p ON p.id = rp.permission_id
        WHERE om.user_id = check_user_id
          AND om.status = 'active'
          AND o.status = 'active'
          AND o.organization_type IN ('platform', 'recruitment_agency')
          AND p.key = 'candidates.manage'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

ALTER TABLE public.candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_experience ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_education ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_certifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_documents ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- CANDIDATES
-- -----------------------------------------------------------------------------
CREATE POLICY "candidates_select_owner_or_recruiter"
    ON public.candidates FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(id, auth.uid()));

CREATE POLICY "candidates_insert_self"
    ON public.candidates FOR INSERT
    TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "candidates_update_owner_or_authorized"
    ON public.candidates FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_PROFILES
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_profiles_select"
    ON public.candidate_profiles FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_profiles_insert"
    ON public.candidate_profiles FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_profiles_update"
    ON public.candidate_profiles FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_profiles_delete"
    ON public.candidate_profiles FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_SKILLS
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_skills_select"
    ON public.candidate_skills FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_skills_insert"
    ON public.candidate_skills FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_skills_update"
    ON public.candidate_skills FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_skills_delete"
    ON public.candidate_skills FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_LANGUAGES
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_languages_select"
    ON public.candidate_languages FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_languages_insert"
    ON public.candidate_languages FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_languages_update"
    ON public.candidate_languages FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_languages_delete"
    ON public.candidate_languages FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_EXPERIENCE
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_experience_select"
    ON public.candidate_experience FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_experience_insert"
    ON public.candidate_experience FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_experience_update"
    ON public.candidate_experience FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_experience_delete"
    ON public.candidate_experience FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_EDUCATION
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_education_select"
    ON public.candidate_education FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_education_insert"
    ON public.candidate_education FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_education_update"
    ON public.candidate_education FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_education_delete"
    ON public.candidate_education FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_CERTIFICATIONS
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_certifications_select"
    ON public.candidate_certifications FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_certifications_insert"
    ON public.candidate_certifications FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_certifications_update"
    ON public.candidate_certifications FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_certifications_delete"
    ON public.candidate_certifications FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_PREFERENCES
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_preferences_select"
    ON public.candidate_preferences FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_preferences_insert"
    ON public.candidate_preferences FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_preferences_update"
    ON public.candidate_preferences FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_preferences_delete"
    ON public.candidate_preferences FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- -----------------------------------------------------------------------------
-- CANDIDATE_DOCUMENTS
-- -----------------------------------------------------------------------------
CREATE POLICY "candidate_documents_select"
    ON public.candidate_documents FOR SELECT
    TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_documents_insert"
    ON public.candidate_documents FOR INSERT
    TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_documents_update"
    ON public.candidate_documents FOR UPDATE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "candidate_documents_delete"
    ON public.candidate_documents FOR DELETE
    TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- =============================================================================
-- 7. SUPABASE STORAGE BUCKET & STORAGE RLS POLICIES
-- =============================================================================

-- Ensure candidate-documents bucket exists and is PRIVATE
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'candidate-documents',
    'candidate-documents',
    false,
    20971520, -- 20MB max file size
    ARRAY[
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/jpeg',
        'image/png'
    ]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 20971520,
    allowed_mime_types = ARRAY[
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'image/jpeg',
        'image/png'
    ];

-- Storage Object Policies for candidate-documents bucket
-- Candidates can read their own uploaded files (prefixed with candidate_id)
DROP POLICY IF EXISTS "candidate_storage_select" ON storage.objects;
CREATE POLICY "candidate_storage_select"
    ON storage.objects FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'candidate-documents'
        AND (
            public.has_candidate_read_access(
                (SPLIT_PART(name, '/', 1))::UUID,
                auth.uid()
            )
            OR public.is_platform_admin(auth.uid())
        )
    );

DROP POLICY IF EXISTS "candidate_storage_insert" ON storage.objects;
CREATE POLICY "candidate_storage_insert"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'candidate-documents'
        AND (
            public.has_candidate_manage_access(
                (SPLIT_PART(name, '/', 1))::UUID,
                auth.uid()
            )
            OR public.is_platform_admin(auth.uid())
        )
    );

DROP POLICY IF EXISTS "candidate_storage_update" ON storage.objects;
CREATE POLICY "candidate_storage_update"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'candidate-documents'
        AND (
            public.has_candidate_manage_access(
                (SPLIT_PART(name, '/', 1))::UUID,
                auth.uid()
            )
            OR public.is_platform_admin(auth.uid())
        )
    );

DROP POLICY IF EXISTS "candidate_storage_delete" ON storage.objects;
CREATE POLICY "candidate_storage_delete"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'candidate-documents'
        AND (
            public.has_candidate_manage_access(
                (SPLIT_PART(name, '/', 1))::UUID,
                auth.uid()
            )
            OR public.is_platform_admin(auth.uid())
        )
    );
