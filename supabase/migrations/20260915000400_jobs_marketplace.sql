-- =============================================================================
-- Migration: 20260915000400_jobs_marketplace.sql
-- Description: Jobs Marketplace, Categories, Requirements & Opportunities
-- Author: Hiren Beyond Engineering
-- Schema: job_categories, jobs, job_requirements, job_skills,
--         job_languages, job_questions, public_active_jobs, marketplace RPCs
-- =============================================================================

-- =============================================================================
-- 1. EXTEND PERMISSIONS CATALOG FOR GRANULAR JOBS LIFECYCLE
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('jobs.create', 'Create Jobs', 'Create draft job postings within the organization', 'jobs'),
    ('jobs.update', 'Update Jobs', 'Edit job details, descriptions, and settings', 'jobs'),
    ('jobs.delete', 'Delete Jobs', 'Remove unposted draft job requisitions', 'jobs'),
    ('jobs.submit_review', 'Submit Job Review', 'Submit draft job requisitions for manager approval', 'jobs'),
    ('jobs.publish', 'Publish Jobs', 'Approve and publish job requisitions to the marketplace', 'jobs'),
    ('jobs.pause', 'Pause Jobs', 'Temporarily pause applications for an active job', 'jobs'),
    ('jobs.close', 'Close Jobs', 'Close job requisition when vacancies are filled', 'jobs'),
    ('jobs.archive', 'Archive Jobs', 'Archive closed or expired job postings', 'jobs'),
    ('job_categories.manage', 'Manage Job Categories', 'Create, update, and sort marketplace job categories', 'jobs'),
    ('job_requirements.manage', 'Manage Job Requirements', 'Configure required skills, screening questions, and credentials', 'jobs')
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;

-- Map new granular permissions to system roles
WITH new_mappings (role_key, perm_key) AS (
    VALUES
        -- Platform Admin: All new permissions
        ('platform_admin', 'jobs.create'),
        ('platform_admin', 'jobs.update'),
        ('platform_admin', 'jobs.delete'),
        ('platform_admin', 'jobs.submit_review'),
        ('platform_admin', 'jobs.publish'),
        ('platform_admin', 'jobs.pause'),
        ('platform_admin', 'jobs.close'),
        ('platform_admin', 'jobs.archive'),
        ('platform_admin', 'job_categories.manage'),
        ('platform_admin', 'job_requirements.manage'),

        -- Platform Operations
        ('platform_operations', 'jobs.publish'),
        ('platform_operations', 'jobs.pause'),
        ('platform_operations', 'jobs.close'),
        ('platform_operations', 'jobs.archive'),
        ('platform_operations', 'job_categories.manage'),
        ('platform_operations', 'job_requirements.manage'),

        -- Recruiter Manager: Full tenant job lifecycle
        ('recruiter_manager', 'jobs.create'),
        ('recruiter_manager', 'jobs.update'),
        ('recruiter_manager', 'jobs.delete'),
        ('recruiter_manager', 'jobs.submit_review'),
        ('recruiter_manager', 'jobs.publish'),
        ('recruiter_manager', 'jobs.pause'),
        ('recruiter_manager', 'jobs.close'),
        ('recruiter_manager', 'jobs.archive'),
        ('recruiter_manager', 'job_requirements.manage'),

        -- Recruiter: Drafting, editing, and submitting for review
        ('recruiter', 'jobs.create'),
        ('recruiter', 'jobs.update'),
        ('recruiter', 'jobs.submit_review'),
        ('recruiter', 'job_requirements.manage'),

        -- Client Admin: Organization jobs management
        ('client_admin', 'jobs.create'),
        ('client_admin', 'jobs.update'),
        ('client_admin', 'jobs.submit_review'),
        ('client_admin', 'jobs.pause'),
        ('client_admin', 'jobs.close'),
        ('client_admin', 'job_requirements.manage')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings m
JOIN public.roles r ON r.key = m.role_key
JOIN public.permissions p ON p.key = m.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. JOB CATEGORIES
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.job_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES public.job_categories(id) ON DELETE SET NULL,
    icon TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_job_categories_slug UNIQUE (slug),
    CONSTRAINT chk_job_category_parent CHECK (parent_id IS NULL OR parent_id != id)
);

CREATE INDEX IF NOT EXISTS idx_job_categories_slug ON public.job_categories(slug);
CREATE INDEX IF NOT EXISTS idx_job_categories_parent ON public.job_categories(parent_id);
CREATE INDEX IF NOT EXISTS idx_job_categories_active ON public.job_categories(is_active);
CREATE INDEX IF NOT EXISTS idx_job_categories_sort ON public.job_categories(sort_order);

CREATE TRIGGER trg_job_categories_updated_at BEFORE UPDATE ON public.job_categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Seed initial industry categories
INSERT INTO public.job_categories (name, slug, description, sort_order, is_active)
VALUES
    ('Call Center', 'call-center', 'Inbound and outbound customer service, telemarketing, and phone support', 1, true),
    ('Customer Support', 'customer-support', 'Multi-channel omnichannel helpdesk, email, chat, and client retention', 2, true),
    ('Translation', 'translation', 'Language interpretation, localization, document translation, and subtitling', 3, true),
    ('Technical', 'technical', 'IT support, infrastructure maintenance, system diagnostics, and hardware helpdesk', 4, true),
    ('AI Training', 'ai-training', 'Model evaluation, prompt engineering, RLHF feedback, and AI workflow testing', 5, true),
    ('Data Annotation', 'data-annotation', 'Computer vision labeling, text classification, audio tagging, and data curation', 6, true),
    ('Sales', 'sales', 'Business development, account management, lead generation, and client acquisition', 7, true),
    ('Marketing', 'marketing', 'Digital growth, content creation, social media strategy, SEO, and paid campaigns', 8, true),
    ('Administration', 'administration', 'Executive assistance, office management, data entry, and record administration', 9, true),
    ('Software and IT', 'software-and-it', 'Frontend, backend, mobile engineering, cloud DevOps, and QA automation', 10, true),
    ('Finance', 'finance', 'Accounting, financial analysis, billing reconciliation, payroll, and bookkeeping', 11, true),
    ('Human Resources', 'human-resources', 'Talent acquisition, employer branding, people operations, and onboarding', 12, true),
    ('Operations', 'operations', 'Logistics coordination, business process management, and operational delivery', 13, true),
    ('Other', 'other', 'Specialized roles and emerging global career opportunities', 14, true)
ON CONFLICT (slug) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active;

-- =============================================================================
-- 3. JOBS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    title TEXT NOT NULL,
    slug TEXT NOT NULL,
    short_description TEXT,
    description TEXT NOT NULL,
    category_id UUID REFERENCES public.job_categories(id) ON DELETE SET NULL,
    job_type TEXT NOT NULL DEFAULT 'direct' CHECK (job_type IN ('direct', 'partner', 'referral')),
    workplace_type TEXT NOT NULL DEFAULT 'remote' CHECK (workplace_type IN ('remote', 'hybrid', 'onsite')),
    location TEXT,
    country VARCHAR(100),
    city VARCHAR(100),
    language VARCHAR(50) DEFAULT 'en',
    employment_type TEXT NOT NULL DEFAULT 'full_time' CHECK (employment_type IN ('full_time', 'part_time', 'contract', 'freelance', 'internship', 'temporary')),
    experience_level TEXT NOT NULL DEFAULT 'mid' CHECK (experience_level IN ('entry', 'junior', 'mid', 'senior', 'lead', 'executive')),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending_review', 'published', 'paused', 'closed', 'archived')),
    visibility TEXT NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'private', 'invite_only')),
    is_featured BOOLEAN NOT NULL DEFAULT false,
    application_deadline TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    vacancies_count INTEGER NOT NULL DEFAULT 1 CHECK (vacancies_count > 0),
    salary_min NUMERIC(12, 2) CHECK (salary_min IS NULL OR salary_min >= 0),
    salary_max NUMERIC(12, 2) CHECK (salary_max IS NULL OR salary_max >= 0),
    salary_currency VARCHAR(10) DEFAULT 'USD',
    salary_period TEXT NOT NULL DEFAULT 'monthly' CHECK (salary_period IN ('hourly', 'weekly', 'monthly', 'yearly')),
    is_salary_visible BOOLEAN NOT NULL DEFAULT true,
    partner_type TEXT NOT NULL DEFAULT 'none' CHECK (partner_type IN ('none', 'ai_training_partner', 'external_partner', 'referral_partner')),
    external_reference TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_jobs_org_slug UNIQUE (organization_id, slug),
    CONSTRAINT chk_job_salary_range CHECK (salary_max IS NULL OR salary_min IS NULL OR salary_max >= salary_min)
);

CREATE INDEX IF NOT EXISTS idx_jobs_org ON public.jobs(organization_id);
CREATE INDEX IF NOT EXISTS idx_jobs_creator ON public.jobs(created_by);
CREATE INDEX IF NOT EXISTS idx_jobs_category ON public.jobs(category_id);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON public.jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_visibility ON public.jobs(visibility);
CREATE INDEX IF NOT EXISTS idx_jobs_published ON public.jobs(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_deadline ON public.jobs(application_deadline);
CREATE INDEX IF NOT EXISTS idx_jobs_workplace ON public.jobs(workplace_type);
CREATE INDEX IF NOT EXISTS idx_jobs_employment ON public.jobs(employment_type);
CREATE INDEX IF NOT EXISTS idx_jobs_exp_level ON public.jobs(experience_level);
CREATE INDEX IF NOT EXISTS idx_jobs_country ON public.jobs(country);
CREATE INDEX IF NOT EXISTS idx_jobs_city ON public.jobs(city);
CREATE INDEX IF NOT EXISTS idx_jobs_featured ON public.jobs(is_featured);

CREATE TRIGGER trg_jobs_updated_at BEFORE UPDATE ON public.jobs
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. STRUCTURED JOB REQUIREMENTS & SCREENERS
-- =============================================================================

-- A. JOB_REQUIREMENTS
CREATE TABLE IF NOT EXISTS public.job_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    requirement_type TEXT NOT NULL DEFAULT 'other' CHECK (requirement_type IN ('education', 'experience', 'availability', 'equipment', 'location', 'language', 'certification', 'other')),
    title TEXT NOT NULL,
    description TEXT,
    is_required BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_job_reqs_job ON public.job_requirements(job_id);
CREATE INDEX IF NOT EXISTS idx_job_reqs_type ON public.job_requirements(requirement_type);

-- B. JOB_SKILLS
CREATE TABLE IF NOT EXISTS public.job_skills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    skill_name TEXT NOT NULL,
    skill_slug TEXT NOT NULL,
    minimum_level TEXT NOT NULL DEFAULT 'intermediate' CHECK (minimum_level IN ('beginner', 'intermediate', 'advanced', 'expert')),
    is_required BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_job_skill UNIQUE (job_id, skill_slug)
);

CREATE INDEX IF NOT EXISTS idx_job_skills_job ON public.job_skills(job_id);
CREATE INDEX IF NOT EXISTS idx_job_skills_slug ON public.job_skills(skill_slug);

-- C. JOB_LANGUAGES
CREATE TABLE IF NOT EXISTS public.job_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    language_code VARCHAR(10) NOT NULL,
    language_name TEXT NOT NULL,
    minimum_level TEXT NOT NULL DEFAULT 'b2' CHECK (minimum_level IN ('a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'native')),
    is_required BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_job_language UNIQUE (job_id, language_code)
);

CREATE INDEX IF NOT EXISTS idx_job_lang_job ON public.job_languages(job_id);
CREATE INDEX IF NOT EXISTS idx_job_lang_code ON public.job_languages(language_code);

-- D. JOB_QUESTIONS (Pre-screening questions)
CREATE TABLE IF NOT EXISTS public.job_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    question_type TEXT NOT NULL DEFAULT 'text' CHECK (question_type IN ('text', 'single_choice', 'multiple_choice', 'boolean', 'number')),
    is_required BOOLEAN NOT NULL DEFAULT false,
    options JSONB DEFAULT '[]'::jsonb,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_job_questions_job ON public.job_questions(job_id);

-- =============================================================================
-- 5. JOB LIFECYCLE & AUDIT LOGGING TRIGGER
-- =============================================================================

CREATE OR REPLACE FUNCTION public.trg_job_lifecycle()
RETURNS TRIGGER AS $$
BEGIN
    -- Synchronize published_at timestamp
    IF NEW.status = 'published' AND (OLD IS NULL OR OLD.status IS DISTINCT FROM 'published') THEN
        NEW.published_at := COALESCE(NEW.published_at, now());
    END IF;

    -- Synchronize closed_at timestamp
    IF NEW.status IN ('closed', 'archived') AND (OLD IS NULL OR OLD.status NOT IN ('closed', 'archived')) THEN
        NEW.closed_at := COALESCE(NEW.closed_at, now());
    END IF;

    -- Log status changes to audit_logs
    IF OLD IS NOT NULL AND OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.audit_logs (
            actor_user_id,
            organization_id,
            action,
            entity_type,
            entity_id,
            metadata
        ) VALUES (
            auth.uid(),
            NEW.organization_id,
            'job.status_changed',
            'job',
            NEW.id,
            jsonb_build_object(
                'old_status', OLD.status,
                'new_status', NEW.status,
                'title', NEW.title
            )
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_job_status_change ON public.jobs;
CREATE TRIGGER trg_job_status_change
    BEFORE INSERT OR UPDATE ON public.jobs
    FOR EACH ROW EXECUTE FUNCTION public.trg_job_lifecycle();

-- =============================================================================
-- 6. SECURITY HELPERS FOR JOBS ACCESS CONTROL
-- =============================================================================

-- Determine if caller can read a job
CREATE OR REPLACE FUNCTION public.can_read_job(job_row public.jobs, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    -- Public published jobs are accessible to everyone (including anon) if unexpired
    IF job_row.status = 'published'
       AND job_row.visibility = 'public'
       AND (job_row.application_deadline IS NULL OR job_row.application_deadline > now()) THEN
        RETURN true;
    END IF;

    -- If unauthenticated caller and not public/published, reject
    IF check_user_id IS NULL THEN
        RETURN false;
    END IF;

    -- Platform admin can view all jobs
    IF public.is_platform_admin(check_user_id) THEN
        RETURN true;
    END IF;

    -- Organization members can read their organization's internal jobs
    RETURN public.is_org_member(job_row.organization_id, check_user_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Determine if caller has management authority on a job
CREATE OR REPLACE FUNCTION public.can_manage_job(check_org_id UUID, required_perm TEXT, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    IF check_user_id IS NULL OR check_org_id IS NULL THEN
        RETURN false;
    END IF;

    IF public.is_platform_admin(check_user_id) THEN
        RETURN true;
    END IF;

    RETURN public.has_org_permission(check_org_id, required_perm, check_user_id)
        OR public.has_org_permission(check_org_id, 'jobs.manage', check_user_id);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 7. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

ALTER TABLE public.job_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_questions ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- JOB_CATEGORIES POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "job_categories_select"
    ON public.job_categories FOR SELECT
    TO anon, authenticated
    USING (is_active = true OR public.is_platform_admin(auth.uid()));

CREATE POLICY "job_categories_manage"
    ON public.job_categories FOR ALL
    TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- -----------------------------------------------------------------------------
-- JOBS POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "jobs_select_public_or_member"
    ON public.jobs FOR SELECT
    TO anon, authenticated
    USING (
        (status = 'published' AND visibility = 'public' AND (application_deadline IS NULL OR application_deadline > now()))
        OR (auth.uid() IS NOT NULL AND (public.is_org_member(organization_id, auth.uid()) OR public.is_platform_admin(auth.uid())))
    );

CREATE POLICY "jobs_insert_authorized"
    ON public.jobs FOR INSERT
    TO authenticated
    WITH CHECK (
        public.can_manage_job(organization_id, 'jobs.create', auth.uid())
        AND created_by = auth.uid()
    );

CREATE POLICY "jobs_update_authorized"
    ON public.jobs FOR UPDATE
    TO authenticated
    USING (
        public.can_manage_job(organization_id, 'jobs.update', auth.uid())
    )
    WITH CHECK (
        public.can_manage_job(organization_id, 'jobs.update', auth.uid())
    );

CREATE POLICY "jobs_delete_authorized"
    ON public.jobs FOR DELETE
    TO authenticated
    USING (
        public.can_manage_job(organization_id, 'jobs.delete', auth.uid())
    );

-- -----------------------------------------------------------------------------
-- JOB_REQUIREMENTS POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "job_requirements_select"
    ON public.job_requirements FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND (
                  (j.status = 'published' AND j.visibility = 'public' AND (j.application_deadline IS NULL OR j.application_deadline > now()))
                  OR (auth.uid() IS NOT NULL AND (public.is_org_member(j.organization_id, auth.uid()) OR public.is_platform_admin(auth.uid())))
              )
        )
    );

CREATE POLICY "job_requirements_manage"
    ON public.job_requirements FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    );

-- -----------------------------------------------------------------------------
-- JOB_SKILLS POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "job_skills_select"
    ON public.job_skills FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND (
                  (j.status = 'published' AND j.visibility = 'public' AND (j.application_deadline IS NULL OR j.application_deadline > now()))
                  OR (auth.uid() IS NOT NULL AND (public.is_org_member(j.organization_id, auth.uid()) OR public.is_platform_admin(auth.uid())))
              )
        )
    );

CREATE POLICY "job_skills_manage"
    ON public.job_skills FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    );

-- -----------------------------------------------------------------------------
-- JOB_LANGUAGES POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "job_languages_select"
    ON public.job_languages FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND (
                  (j.status = 'published' AND j.visibility = 'public' AND (j.application_deadline IS NULL OR j.application_deadline > now()))
                  OR (auth.uid() IS NOT NULL AND (public.is_org_member(j.organization_id, auth.uid()) OR public.is_platform_admin(auth.uid())))
              )
        )
    );

CREATE POLICY "job_languages_manage"
    ON public.job_languages FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    );

-- -----------------------------------------------------------------------------
-- JOB_QUESTIONS POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "job_questions_select"
    ON public.job_questions FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND (
                  (j.status = 'published' AND j.visibility = 'public' AND (j.application_deadline IS NULL OR j.application_deadline > now()))
                  OR (auth.uid() IS NOT NULL AND (public.is_org_member(j.organization_id, auth.uid()) OR public.is_platform_admin(auth.uid())))
              )
        )
    );

CREATE POLICY "job_questions_manage"
    ON public.job_questions FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_id
              AND public.can_manage_job(j.organization_id, 'job_requirements.manage', auth.uid())
        )
    );

-- =============================================================================
-- 8. PUBLIC MARKETPLACE DATABASE VIEW
-- =============================================================================

CREATE OR REPLACE VIEW public.public_active_jobs AS
SELECT
    j.id,
    j.organization_id,
    o.name AS organization_name,
    o.logo_url AS organization_logo_url,
    j.title,
    j.slug,
    j.short_description,
    j.description,
    j.category_id,
    c.name AS category_name,
    c.slug AS category_slug,
    j.job_type,
    j.workplace_type,
    j.location,
    j.country,
    j.city,
    j.language,
    j.employment_type,
    j.experience_level,
    j.vacancies_count,
    -- Salary Privacy: Masked if is_salary_visible is false
    CASE WHEN j.is_salary_visible THEN j.salary_min ELSE NULL END AS salary_min,
    CASE WHEN j.is_salary_visible THEN j.salary_max ELSE NULL END AS salary_max,
    CASE WHEN j.is_salary_visible THEN j.salary_currency ELSE NULL END AS salary_currency,
    CASE WHEN j.is_salary_visible THEN j.salary_period ELSE NULL END AS salary_period,
    j.is_salary_visible,
    j.is_featured,
    j.published_at,
    j.application_deadline,
    j.partner_type
FROM public.jobs j
JOIN public.organizations o ON o.id = j.organization_id
LEFT JOIN public.job_categories c ON c.id = j.category_id
WHERE j.status = 'published'
  AND j.visibility = 'public'
  AND o.status = 'active'
  AND (j.application_deadline IS NULL OR j.application_deadline > now());

-- Grant read permission on view to anon & authenticated
GRANT SELECT ON public.public_active_jobs TO anon, authenticated;

-- =============================================================================
-- 9. MARKETPLACE RPC FUNCTIONS
-- =============================================================================

-- A. Active Opportunities Count
CREATE OR REPLACE FUNCTION public.get_active_jobs_count()
RETURNS INTEGER AS $$
    SELECT COUNT(*)::INTEGER FROM public.public_active_jobs;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- B. Search and Filter Active Marketplace Opportunities
CREATE OR REPLACE FUNCTION public.get_active_jobs(
    search_query TEXT DEFAULT NULL,
    filter_category_id UUID DEFAULT NULL,
    filter_category_slug TEXT DEFAULT NULL,
    filter_country TEXT DEFAULT NULL,
    filter_city TEXT DEFAULT NULL,
    filter_workplace_type TEXT DEFAULT NULL,
    filter_employment_type TEXT DEFAULT NULL,
    filter_experience_level TEXT DEFAULT NULL,
    filter_language TEXT DEFAULT NULL,
    filter_partner_type TEXT DEFAULT NULL,
    filter_is_featured BOOLEAN DEFAULT NULL,
    sort_by TEXT DEFAULT 'newest',
    page_number INTEGER DEFAULT 1,
    page_size INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    organization_id UUID,
    organization_name TEXT,
    organization_logo_url TEXT,
    title TEXT,
    slug TEXT,
    short_description TEXT,
    description TEXT,
    category_id UUID,
    category_name TEXT,
    category_slug TEXT,
    job_type TEXT,
    workplace_type TEXT,
    location TEXT,
    country VARCHAR(100),
    city VARCHAR(100),
    language VARCHAR(50),
    employment_type TEXT,
    experience_level TEXT,
    vacancies_count INTEGER,
    salary_min NUMERIC(12, 2),
    salary_max NUMERIC(12, 2),
    salary_currency VARCHAR(10),
    salary_period TEXT,
    is_salary_visible BOOLEAN,
    is_featured BOOLEAN,
    published_at TIMESTAMPTZ,
    application_deadline TIMESTAMPTZ,
    partner_type TEXT,
    total_count BIGINT
) AS $$
DECLARE
    calc_offset INTEGER;
BEGIN
    calc_offset := GREATEST(0, (page_number - 1) * page_size);

    RETURN QUERY
    WITH filtered AS (
        SELECT
            j.*,
            COUNT(*) OVER() AS full_count
        FROM public.public_active_jobs j
        WHERE
            (search_query IS NULL OR (
                j.title ILIKE '%' || search_query || '%'
                OR j.short_description ILIKE '%' || search_query || '%'
                OR j.description ILIKE '%' || search_query || '%'
            ))
            AND (filter_category_id IS NULL OR j.category_id = filter_category_id)
            AND (filter_category_slug IS NULL OR j.category_slug = filter_category_slug)
            AND (filter_country IS NULL OR j.country ILIKE filter_country)
            AND (filter_city IS NULL OR j.city ILIKE filter_city)
            AND (filter_workplace_type IS NULL OR j.workplace_type = filter_workplace_type)
            AND (filter_employment_type IS NULL OR j.employment_type = filter_employment_type)
            AND (filter_experience_level IS NULL OR j.experience_level = filter_experience_level)
            AND (filter_language IS NULL OR j.language ILIKE filter_language)
            AND (filter_partner_type IS NULL OR j.partner_type = filter_partner_type)
            AND (filter_is_featured IS NULL OR j.is_featured = filter_is_featured)
    )
    SELECT
        f.id,
        f.organization_id,
        f.organization_name,
        f.organization_logo_url,
        f.title,
        f.slug,
        f.short_description,
        f.description,
        f.category_id,
        f.category_name,
        f.category_slug,
        f.job_type,
        f.workplace_type,
        f.location,
        f.country,
        f.city,
        f.language,
        f.employment_type,
        f.experience_level,
        f.vacancies_count,
        f.salary_min,
        f.salary_max,
        f.salary_currency,
        f.salary_period,
        f.is_salary_visible,
        f.is_featured,
        f.published_at,
        f.application_deadline,
        f.partner_type,
        f.full_count AS total_count
    FROM filtered f
    ORDER BY
        CASE WHEN sort_by = 'featured' THEN f.is_featured END DESC NULLS LAST,
        CASE WHEN sort_by = 'deadline' THEN f.application_deadline END ASC NULLS LAST,
        CASE WHEN sort_by = 'salary_high' THEN f.salary_max END DESC NULLS LAST,
        f.published_at DESC NULLS LAST
    LIMIT page_size
    OFFSET calc_offset;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.get_active_jobs_count() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_active_jobs(
    TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN, TEXT, INTEGER, INTEGER
) TO anon, authenticated;
