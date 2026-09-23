-- =============================================================================
-- Migration: 20260915001100_client_portal_collaboration.sql
-- Description: Client Portal, Client Feedback, Candidate Presentation & Client Hiring Collaboration
-- Author: Hiren Beyond Engineering
-- Schema: client_relationships, client_contacts, client_job_access,
--         client_candidate_shares, client_candidate_profiles, client_document_access,
--         client_candidate_feedback, client_feedback_history, client_scorecard_templates,
--         client_scorecard_sections, client_scorecard_questions, client_scorecard_responses,
--         client_interview_requests, client_information_requests, client_hiring_decisions,
--         client_activity_events
-- =============================================================================

-- =============================================================================
-- 1. EXTEND ROLES & PERMISSIONS
-- =============================================================================

INSERT INTO public.roles (key, name, description, is_system_role)
VALUES
    ('client_hiring_manager', 'Client Hiring Manager', 'Client departmental lead reviewing candidates, providing feedback, and requesting interviews', true)
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description;

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('clients.create', 'Create Client Relationships', 'Establish new recruitment client partnerships', 'clients'),
    ('clients.read', 'Read Client Relationships', 'View client organizations and relationship statuses', 'clients'),
    ('clients.update', 'Update Client Relationships', 'Modify terms, contacts, and account ownership for clients', 'clients'),
    ('clients.manage', 'Manage Client Relationships', 'Full lifecycle management of client partnerships', 'clients'),
    ('client_jobs.share', 'Share Jobs With Clients', 'Expose job requisitions to authorized client organizations', 'clients'),
    ('client_jobs.revoke', 'Revoke Client Job Access', 'Revoke client access to previously shared job openings', 'clients'),
    ('client_candidates.share', 'Share Candidates With Clients', 'Present selected candidate profiles to client reviewers', 'clients'),
    ('client_candidates.manage', 'Manage Client Candidate Shares', 'Modify visibility, presentation status, and access rights', 'clients'),
    ('client_feedback.read', 'Read Client Feedback', 'Inspect evaluations, scorecards, and comments from clients', 'clients'),
    ('client_feedback.manage', 'Manage Client Feedback', 'Triage client feedback, inquiries, and next steps', 'clients'),
    ('client_interview_requests.manage', 'Manage Interview Requests', 'Accept, schedule, or decline client interview requests', 'clients'),
    ('client_hiring_collaboration.manage', 'Manage Client Collaboration', 'Oversee client hiring recommendations and workflow sync', 'clients'),
    ('client_scorecards.manage', 'Manage Client Scorecards', 'Configure client-specific evaluation rubrics and questions', 'clients'),
    ('client_portal.view', 'View Client Portal', 'Access the client portal workspace and assigned jobs', 'client_portal'),
    ('client_candidates.view', 'View Shared Candidates', 'View client-safe candidate presentation profiles', 'client_portal'),
    ('client_candidates.review', 'Review Shared Candidates', 'Submit feedback, ratings, and questions on presented candidates', 'client_portal'),
    ('client_feedback.create', 'Submit Client Feedback', 'Record candidate evaluations and scorecard ratings', 'client_portal'),
    ('client_interview_requests.create', 'Request Candidate Interviews', 'Request interview sessions for promising candidates', 'client_portal'),
    ('client_decisions.create', 'Submit Client Decisions', 'Submit client-level hiring recommendations', 'client_portal')
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;

-- Map permissions to roles
WITH new_mappings (role_key, perm_key) AS (
    VALUES
        -- Platform Admin
        ('platform_admin', 'clients.create'),
        ('platform_admin', 'clients.read'),
        ('platform_admin', 'clients.update'),
        ('platform_admin', 'clients.manage'),
        ('platform_admin', 'client_jobs.share'),
        ('platform_admin', 'client_jobs.revoke'),
        ('platform_admin', 'client_candidates.share'),
        ('platform_admin', 'client_candidates.manage'),
        ('platform_admin', 'client_feedback.read'),
        ('platform_admin', 'client_feedback.manage'),
        ('platform_admin', 'client_interview_requests.manage'),
        ('platform_admin', 'client_hiring_collaboration.manage'),
        ('platform_admin', 'client_scorecards.manage'),

        -- Recruiter Manager & Recruiter
        ('recruiter_manager', 'clients.create'),
        ('recruiter_manager', 'clients.read'),
        ('recruiter_manager', 'clients.update'),
        ('recruiter_manager', 'clients.manage'),
        ('recruiter_manager', 'client_jobs.share'),
        ('recruiter_manager', 'client_jobs.revoke'),
        ('recruiter_manager', 'client_candidates.share'),
        ('recruiter_manager', 'client_candidates.manage'),
        ('recruiter_manager', 'client_feedback.read'),
        ('recruiter_manager', 'client_feedback.manage'),
        ('recruiter_manager', 'client_interview_requests.manage'),
        ('recruiter_manager', 'client_hiring_collaboration.manage'),
        ('recruiter_manager', 'client_scorecards.manage'),

        ('recruiter', 'clients.read'),
        ('recruiter', 'client_jobs.share'),
        ('recruiter', 'client_candidates.share'),
        ('recruiter', 'client_candidates.manage'),
        ('recruiter', 'client_feedback.read'),
        ('recruiter', 'client_interview_requests.manage'),
        ('recruiter', 'client_scorecards.manage'),

        -- Client Admin
        ('client_admin', 'client_portal.view'),
        ('client_admin', 'client_candidates.view'),
        ('client_admin', 'client_candidates.review'),
        ('client_admin', 'client_feedback.create'),
        ('client_admin', 'client_interview_requests.create'),
        ('client_admin', 'client_decisions.create'),
        ('client_admin', 'client_scorecards.manage'),

        -- Client Reviewer & Client Hiring Manager
        ('client_reviewer', 'client_portal.view'),
        ('client_reviewer', 'client_candidates.view'),
        ('client_reviewer', 'client_candidates.review'),
        ('client_reviewer', 'client_feedback.create'),
        ('client_reviewer', 'client_interview_requests.create'),
        ('client_reviewer', 'client_decisions.create'),

        ('client_hiring_manager', 'client_portal.view'),
        ('client_hiring_manager', 'client_candidates.view'),
        ('client_hiring_manager', 'client_candidates.review'),
        ('client_hiring_manager', 'client_feedback.create'),
        ('client_hiring_manager', 'client_interview_requests.create'),
        ('client_hiring_manager', 'client_decisions.create')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings nm
JOIN public.roles r ON r.key = nm.role_key
JOIN public.permissions p ON p.key = nm.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. HELPER FUNCTIONS: CLIENT TENANCY VERIFICATION
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_user_is_client_member(p_client_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = p_client_org_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND r.key IN ('client_admin', 'client_reviewer', 'client_hiring_manager')
        )
    );
$$;

CREATE OR REPLACE FUNCTION public.check_user_is_client_admin(p_client_org_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = p_client_org_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND r.key = 'client_admin'
        )
    );
$$;

-- =============================================================================
-- 3. SCHEMA DEFINITION: 16 TABLES
-- =============================================================================

-- 3.1 Client Relationships
CREATE TABLE IF NOT EXISTS public.client_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recruitment_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    client_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('prospect', 'active', 'paused', 'closed')),
    relationship_type VARCHAR(50) NOT NULL DEFAULT 'direct_client' CHECK (relationship_type IN ('recruitment_partner', 'staffing_client', 'direct_client', 'outsourcing_client', 'other')),
    account_owner UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_relationships UNIQUE (recruitment_organization_id, client_organization_id),
    CONSTRAINT chk_client_rel_different_orgs CHECK (recruitment_organization_id <> client_organization_id)
);

-- 3.2 Client Contacts
CREATE TABLE IF NOT EXISTS public.client_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    job_title TEXT,
    phone TEXT,
    email TEXT,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.3 Client Job Access
CREATE TABLE IF NOT EXISTS public.client_job_access (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    client_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('pending', 'active', 'paused', 'closed', 'revoked')),
    shared_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    shared_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    expires_at TIMESTAMPTZ,
    visibility VARCHAR(50) NOT NULL DEFAULT 'full' CHECK (visibility IN ('full', 'limited', 'candidate_review_only')),
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_job_access UNIQUE (job_id, client_organization_id)
);

-- 3.4 Client Candidate Shares
CREATE TABLE IF NOT EXISTS public.client_candidate_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    application_id UUID NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    shared_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'shared' CHECK (status IN ('shared', 'hidden', 'revoked', 'expired')),
    shared_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    visibility_config JSONB NOT NULL DEFAULT '{"show_name": true, "show_email": false, "show_phone": false, "show_salary": false, "show_cv": false, "show_match_score": true, "show_match_explanation": true, "show_experience": true, "show_education": true, "show_languages": true}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_candidate_shares UNIQUE (job_id, client_organization_id, candidate_id)
);

-- 3.5 Client Candidate Profiles (Client-Safe Presentation Projection)
CREATE TABLE IF NOT EXISTS public.client_candidate_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_share_id UUID NOT NULL REFERENCES public.client_candidate_shares(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    headline TEXT,
    professional_summary TEXT,
    location TEXT,
    country TEXT,
    city TEXT,
    years_of_experience NUMERIC(4,1) DEFAULT 0,
    key_skills JSONB NOT NULL DEFAULT '[]'::jsonb,
    languages JSONB NOT NULL DEFAULT '[]'::jsonb,
    education_summary JSONB NOT NULL DEFAULT '[]'::jsonb,
    experience_summary JSONB NOT NULL DEFAULT '[]'::jsonb,
    availability TEXT,
    match_score NUMERIC(5,2),
    match_summary TEXT,
    presentation_status VARCHAR(50) NOT NULL DEFAULT 'ready' CHECK (presentation_status IN ('draft', 'ready', 'presented', 'withdrawn')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_candidate_profiles UNIQUE (candidate_share_id)
);

-- 3.6 Client Document Access (Controlled CV / Attachments)
CREATE TABLE IF NOT EXISTS public.client_document_access (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_candidate_share_id UUID NOT NULL REFERENCES public.client_candidate_shares(id) ON DELETE CASCADE,
    candidate_document_id UUID NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    access_type VARCHAR(50) NOT NULL DEFAULT 'view' CHECK (access_type IN ('view', 'download')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

-- 3.7 Client Candidate Feedback
CREATE TABLE IF NOT EXISTS public.client_candidate_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_candidate_share_id UUID NOT NULL REFERENCES public.client_candidate_shares(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    feedback_type VARCHAR(50) NOT NULL DEFAULT 'candidate_review' CHECK (feedback_type IN ('general', 'candidate_review', 'interview', 'technical', 'final')),
    rating NUMERIC(3,2) CHECK (rating IS NULL OR (rating >= 1.0 AND rating <= 5.0)),
    comments TEXT,
    decision VARCHAR(50) NOT NULL CHECK (decision IN ('interested', 'maybe', 'not_interested', 'request_interview', 'request_more_information')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_candidate_feedback UNIQUE (client_candidate_share_id, author_id, feedback_type)
);

-- 3.8 Client Feedback History
CREATE TABLE IF NOT EXISTS public.client_feedback_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feedback_id UUID NOT NULL REFERENCES public.client_candidate_feedback(id) ON DELETE CASCADE,
    previous_decision VARCHAR(50),
    new_decision VARCHAR(50) NOT NULL,
    changed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.9 Client Scorecard Templates
CREATE TABLE IF NOT EXISTS public.client_scorecard_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    version INT NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_scorecard_template_version UNIQUE (client_organization_id, name, version)
);

-- 3.10 Client Scorecard Sections
CREATE TABLE IF NOT EXISTS public.client_scorecard_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES public.client_scorecard_templates(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    weight NUMERIC(5,2) NOT NULL DEFAULT 100.00 CHECK (weight >= 0),
    sort_order INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.11 Client Scorecard Questions
CREATE TABLE IF NOT EXISTS public.client_scorecard_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id UUID NOT NULL REFERENCES public.client_scorecard_sections(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    response_type VARCHAR(50) NOT NULL CHECK (response_type IN ('rating', 'yes_no', 'text', 'choice')),
    is_required BOOLEAN NOT NULL DEFAULT false,
    sort_order INT NOT NULL DEFAULT 1,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.12 Client Scorecard Responses
CREATE TABLE IF NOT EXISTS public.client_scorecard_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feedback_id UUID NOT NULL REFERENCES public.client_candidate_feedback(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES public.client_scorecard_questions(id) ON DELETE CASCADE,
    rating_value NUMERIC(3,2) CHECK (rating_value IS NULL OR (rating_value >= 1.0 AND rating_value <= 5.0)),
    text_value TEXT,
    choice_value TEXT,
    yes_no_value BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_client_scorecard_responses UNIQUE (feedback_id, question_id)
);

-- 3.13 Client Interview Requests
CREATE TABLE IF NOT EXISTS public.client_interview_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_candidate_share_id UUID NOT NULL REFERENCES public.client_candidate_shares(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    request_type VARCHAR(50) NOT NULL DEFAULT 'interview' CHECK (request_type IN ('interview', 'additional_interview', 'follow_up')),
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'scheduled', 'cancelled')),
    preferred_timeframes JSONB NOT NULL DEFAULT '[]'::jsonb,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- 3.14 Client Information Requests
CREATE TABLE IF NOT EXISTS public.client_information_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_candidate_share_id UUID NOT NULL REFERENCES public.client_candidate_shares(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    question TEXT NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'general',
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'answered', 'declined')),
    response TEXT,
    responded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    responded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.15 Client Hiring Decisions (Client Hiring Recommendations)
CREATE TABLE IF NOT EXISTS public.client_hiring_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_candidate_share_id UUID NOT NULL REFERENCES public.client_candidate_shares(id) ON DELETE CASCADE,
    decision VARCHAR(50) NOT NULL CHECK (decision IN ('recommend_hire', 'recommend_reject', 'request_final_interview', 'hold')),
    reason TEXT,
    submitted_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3.16 Client Activity Events (Portal Timeline Audit)
CREATE TABLE IF NOT EXISTS public.client_activity_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
    candidate_share_id UUID REFERENCES public.client_candidate_shares(id) ON DELETE SET NULL,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 4. PERFORMANCE INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_client_rel_recruiter ON public.client_relationships(recruitment_organization_id);
CREATE INDEX IF NOT EXISTS idx_client_rel_client ON public.client_relationships(client_organization_id);
CREATE INDEX IF NOT EXISTS idx_client_job_access_job ON public.client_job_access(job_id);
CREATE INDEX IF NOT EXISTS idx_client_job_access_client ON public.client_job_access(client_organization_id);
CREATE INDEX IF NOT EXISTS idx_client_job_access_status ON public.client_job_access(client_organization_id, status);
CREATE INDEX IF NOT EXISTS idx_client_cand_shares_job ON public.client_candidate_shares(job_id);
CREATE INDEX IF NOT EXISTS idx_client_cand_shares_client ON public.client_candidate_shares(client_organization_id);
CREATE INDEX IF NOT EXISTS idx_client_cand_shares_cand ON public.client_candidate_shares(candidate_id);
CREATE INDEX IF NOT EXISTS idx_client_cand_shares_status ON public.client_candidate_shares(status);
CREATE INDEX IF NOT EXISTS idx_client_feedback_share ON public.client_candidate_feedback(client_candidate_share_id);
CREATE INDEX IF NOT EXISTS idx_client_interview_req_share ON public.client_interview_requests(client_candidate_share_id);
CREATE INDEX IF NOT EXISTS idx_client_info_req_share ON public.client_information_requests(client_candidate_share_id);
CREATE INDEX IF NOT EXISTS idx_client_activity_org ON public.client_activity_events(client_organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_activity_job ON public.client_activity_events(job_id, created_at DESC);

-- =============================================================================
-- 5. ROW LEVEL SECURITY POLICIES
-- =============================================================================

ALTER TABLE public.client_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_job_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_candidate_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_candidate_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_document_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_candidate_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_feedback_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_interview_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_information_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_hiring_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_activity_events ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.client_relationships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_contacts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_job_access FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_candidate_shares FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_candidate_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_document_access FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_candidate_feedback FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_feedback_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_sections FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_questions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_scorecard_responses FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_interview_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_information_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_hiring_decisions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.client_activity_events FORCE ROW LEVEL SECURITY;

-- 5.1 Client Relationships
CREATE POLICY "Recruiters manage client relationships"
ON public.client_relationships FOR ALL
TO authenticated
USING (public.check_user_is_recruiter(recruitment_organization_id))
WITH CHECK (public.check_user_is_recruiter(recruitment_organization_id));

CREATE POLICY "Clients read own relationships"
ON public.client_relationships FOR SELECT
TO authenticated
USING (public.check_user_is_client_member(client_organization_id));

-- 5.2 Client Contacts
CREATE POLICY "Recruiters read client contacts"
ON public.client_contacts FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_relationships cr
        WHERE cr.client_organization_id = client_organization_id
          AND public.check_user_is_recruiter(cr.recruitment_organization_id)
    )
);

CREATE POLICY "Clients manage own contacts"
ON public.client_contacts FOR ALL
TO authenticated
USING (public.check_user_is_client_member(client_organization_id))
WITH CHECK (public.check_user_is_client_admin(client_organization_id));

-- 5.3 Client Job Access
CREATE POLICY "Recruiters manage client job access"
ON public.client_job_access FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Clients read active shared jobs"
ON public.client_job_access FOR SELECT
TO authenticated
USING (
    public.check_user_is_client_member(client_organization_id)
    AND status = 'active'
    AND (expires_at IS NULL OR expires_at > now())
    AND EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.id = job_id AND j.status = 'published'
    )
);

-- 5.4 Client Candidate Shares
CREATE POLICY "Recruiters manage candidate shares"
ON public.client_candidate_shares FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Clients read active candidate shares"
ON public.client_candidate_shares FOR SELECT
TO authenticated
USING (
    public.check_user_is_client_member(client_organization_id)
    AND status = 'shared'
    AND (expires_at IS NULL OR expires_at > now())
    AND EXISTS (
        SELECT 1 FROM public.client_job_access cja
        JOIN public.jobs j ON j.id = cja.job_id
        WHERE cja.job_id = client_candidate_shares.job_id
          AND cja.client_organization_id = client_candidate_shares.client_organization_id
          AND cja.status = 'active'
          AND (cja.expires_at IS NULL OR cja.expires_at > now())
          AND j.status = 'published'
    )
);

-- 5.5 Client Candidate Profiles (Projection)
CREATE POLICY "Recruiters read client candidate profiles"
ON public.client_candidate_profiles FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = candidate_share_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Clients read active candidate profiles"
ON public.client_candidate_profiles FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        WHERE ccs.id = candidate_share_id
          AND public.check_user_is_client_member(ccs.client_organization_id)
          AND ccs.status = 'shared'
          AND (ccs.expires_at IS NULL OR ccs.expires_at > now())
    )
);

-- 5.6 Client Document Access
CREATE POLICY "Recruiters manage document access"
ON public.client_document_access FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id AND public.check_user_is_recruiter(j.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Clients read valid document access"
ON public.client_document_access FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        WHERE ccs.id = client_candidate_share_id
          AND public.check_user_is_client_member(ccs.client_organization_id)
          AND ccs.status = 'shared'
          AND (ccs.expires_at IS NULL OR ccs.expires_at > now())
    )
    AND (expires_at > now())
    AND revoked_at IS NULL
);

-- 5.7 Client Candidate Feedback
CREATE POLICY "Recruiters read client feedback"
ON public.client_candidate_feedback FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Clients manage own feedback"
ON public.client_candidate_feedback FOR ALL
TO authenticated
USING (
    author_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        WHERE ccs.id = client_candidate_share_id
          AND public.check_user_is_client_admin(ccs.client_organization_id)
    )
)
WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        WHERE ccs.id = client_candidate_share_id
          AND public.check_user_is_client_member(ccs.client_organization_id)
          AND ccs.status = 'shared'
          AND (ccs.expires_at IS NULL OR ccs.expires_at > now())
    )
);

-- 5.8 Client Feedback History
CREATE POLICY "Recruiters read client feedback history"
ON public.client_feedback_history FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_feedback ccf
        JOIN public.client_candidate_shares ccs ON ccs.id = ccf.client_candidate_share_id
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccf.id = feedback_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Clients read own feedback history"
ON public.client_feedback_history FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_feedback ccf
        JOIN public.client_candidate_shares ccs ON ccs.id = ccf.client_candidate_share_id
        WHERE ccf.id = feedback_id AND public.check_user_is_client_member(ccs.client_organization_id)
    )
);

-- 5.9 Client Scorecard Templates & Questions
CREATE POLICY "Clients manage own scorecards"
ON public.client_scorecard_templates FOR ALL
TO authenticated
USING (public.check_user_is_client_member(client_organization_id))
WITH CHECK (public.check_user_is_client_admin(client_organization_id));

CREATE POLICY "Recruiters read client scorecards"
ON public.client_scorecard_templates FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_relationships cr
        WHERE cr.client_organization_id = client_scorecard_templates.client_organization_id
          AND public.check_user_is_recruiter(cr.recruitment_organization_id)
    )
);

CREATE POLICY "Read client scorecard sections"
ON public.client_scorecard_sections FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_scorecard_templates cst
        WHERE cst.id = template_id
          AND (
              public.check_user_is_client_member(cst.client_organization_id)
              OR EXISTS (
                  SELECT 1 FROM public.client_relationships cr
                  WHERE cr.client_organization_id = cst.client_organization_id
                    AND public.check_user_is_recruiter(cr.recruitment_organization_id)
              )
          )
    )
);

CREATE POLICY "Read client scorecard questions"
ON public.client_scorecard_questions FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_scorecard_sections css
        JOIN public.client_scorecard_templates cst ON cst.id = css.template_id
        WHERE css.id = section_id
          AND (
              public.check_user_is_client_member(cst.client_organization_id)
              OR EXISTS (
                  SELECT 1 FROM public.client_relationships cr
                  WHERE cr.client_organization_id = cst.client_organization_id
                    AND public.check_user_is_recruiter(cr.recruitment_organization_id)
              )
          )
    )
);

CREATE POLICY "Manage client scorecard responses"
ON public.client_scorecard_responses FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_feedback ccf
        WHERE ccf.id = feedback_id
          AND (
              ccf.author_id = auth.uid()
              OR EXISTS (
                  SELECT 1 FROM public.client_candidate_shares ccs
                  JOIN public.jobs j ON j.id = ccs.job_id
                  WHERE ccs.id = ccf.client_candidate_share_id
                    AND (
                        public.check_user_is_client_admin(ccs.client_organization_id)
                        OR public.check_user_is_recruiter(j.organization_id)
                    )
              )
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.client_candidate_feedback ccf
        WHERE ccf.id = feedback_id AND ccf.author_id = auth.uid()
    )
);

-- 5.10 Client Requests: Interview, Info & Hiring Decisions
CREATE POLICY "Manage interview requests"
ON public.client_interview_requests FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id
          AND (
              public.check_user_is_client_member(ccs.client_organization_id)
              OR public.check_user_is_recruiter(j.organization_id)
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id
          AND (
              public.check_user_is_client_member(ccs.client_organization_id)
              OR public.check_user_is_recruiter(j.organization_id)
          )
    )
);

CREATE POLICY "Manage information requests"
ON public.client_information_requests FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id
          AND (
              public.check_user_is_client_member(ccs.client_organization_id)
              OR public.check_user_is_recruiter(j.organization_id)
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id
          AND (
              public.check_user_is_client_member(ccs.client_organization_id)
              OR public.check_user_is_recruiter(j.organization_id)
          )
    )
);

CREATE POLICY "Manage client hiring decisions"
ON public.client_hiring_decisions FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        JOIN public.jobs j ON j.id = ccs.job_id
        WHERE ccs.id = client_candidate_share_id
          AND (
              public.check_user_is_client_member(ccs.client_organization_id)
              OR public.check_user_is_recruiter(j.organization_id)
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.client_candidate_shares ccs
        WHERE ccs.id = client_candidate_share_id
          AND public.check_user_is_client_member(ccs.client_organization_id)
    )
);

-- 5.11 Client Activity Events
CREATE POLICY "Read client activity events"
ON public.client_activity_events FOR SELECT
TO authenticated
USING (
    public.check_user_is_client_member(client_organization_id)
    OR EXISTS (
        SELECT 1 FROM public.client_relationships cr
        WHERE cr.client_organization_id = client_activity_events.client_organization_id
          AND public.check_user_is_recruiter(cr.recruitment_organization_id)
    )
);

CREATE POLICY "Insert client activity events"
ON public.client_activity_events FOR INSERT
TO authenticated
WITH CHECK (
    public.check_user_is_client_member(client_organization_id)
    OR EXISTS (
        SELECT 1 FROM public.client_relationships cr
        WHERE cr.client_organization_id = client_activity_events.client_organization_id
          AND public.check_user_is_recruiter(cr.recruitment_organization_id)
    )
);

-- =============================================================================
-- 6. STORED PROCEDURES & BUSINESS LOGIC (14 RPC FUNCTIONS)
-- =============================================================================

-- 6.1 Share Job With Client
CREATE OR REPLACE FUNCTION public.share_job_with_client(
    p_job_id UUID,
    p_client_org_id UUID,
    p_visibility TEXT DEFAULT 'full',
    p_expires_at TIMESTAMPTZ DEFAULT NULL,
    p_config JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
    v_access_id UUID;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_job.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not an authorized recruiter for organization %', v_job.organization_id;
    END IF;

    -- Verify active client relationship exists
    IF NOT EXISTS (
        SELECT 1 FROM public.client_relationships
        WHERE recruitment_organization_id = v_job.organization_id
          AND client_organization_id = p_client_org_id
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Active client relationship not found between org % and client org %', v_job.organization_id, p_client_org_id;
    END IF;

    INSERT INTO public.client_job_access (
        job_id, client_organization_id, status, shared_at, shared_by, expires_at, visibility, configuration
    )
    VALUES (
        p_job_id, p_client_org_id, 'active', now(), auth.uid(), p_expires_at, p_visibility, p_config
    )
    ON CONFLICT (job_id, client_organization_id) DO UPDATE
    SET status = 'active',
        shared_at = now(),
        shared_by = auth.uid(),
        expires_at = EXCLUDED.expires_at,
        visibility = EXCLUDED.visibility,
        configuration = EXCLUDED.configuration,
        updated_at = now()
    RETURNING id INTO v_access_id;

    -- Audit event
    INSERT INTO public.client_activity_events (client_organization_id, job_id, actor_id, event_type, event_data)
    VALUES (p_client_org_id, p_job_id, auth.uid(), 'job_shared', jsonb_build_object('visibility', p_visibility, 'expires_at', p_expires_at));

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_job.organization_id, 'client_job_shared', 'client_job_access', v_access_id, jsonb_build_object('client_org_id', p_client_org_id, 'job_id', p_job_id));

    RETURN v_access_id;
END;
$$;

-- 6.2 Revoke Client Job Access
CREATE OR REPLACE FUNCTION public.revoke_client_job_access(
    p_job_id UUID,
    p_client_org_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
    v_access_id UUID;
BEGIN
    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_job.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller cannot revoke client job access';
    END IF;

    UPDATE public.client_job_access
    SET status = 'revoked', updated_at = now()
    WHERE job_id = p_job_id AND client_organization_id = p_client_org_id
    RETURNING id INTO v_access_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active client job access not found';
    END IF;

    -- Automatically revoke all candidate shares under this job for this client
    UPDATE public.client_candidate_shares
    SET status = 'revoked', updated_at = now()
    WHERE job_id = p_job_id AND client_organization_id = p_client_org_id;

    -- Audit log
    INSERT INTO public.client_activity_events (client_organization_id, job_id, actor_id, event_type, event_data)
    VALUES (p_client_org_id, p_job_id, auth.uid(), 'access_revoked', jsonb_build_object('reason', p_reason));

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_job.organization_id, 'client_job_revoked', 'client_job_access', v_access_id, jsonb_build_object('reason', p_reason));
END;
$$;

-- 6.3 Share Candidate With Client (Builds Safe Presentation Projection)
CREATE OR REPLACE FUNCTION public.share_candidate_with_client(
    p_application_id UUID,
    p_client_org_id UUID,
    p_visibility_config JSONB DEFAULT NULL,
    p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_app RECORD;
    v_cand RECORD;
    v_prof RECORD;
    v_cand_prof RECORD;
    v_match RECORD;
    v_vis JSONB;
    v_share_id UUID;
    v_display_name TEXT;
    v_exp_years NUMERIC(4,1) := 0;
    v_skills JSONB := '[]'::jsonb;
    v_langs JSONB := '[]'::jsonb;
    v_edu JSONB := '[]'::jsonb;
    v_exp JSONB := '[]'::jsonb;
BEGIN
    SELECT * INTO v_app FROM public.applications WHERE id = p_application_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application % not found', p_application_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_app.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not an authorized recruiter for organization %', v_app.organization_id;
    END IF;

    -- Verify job is shared with client
    IF NOT EXISTS (
        SELECT 1 FROM public.client_job_access
        WHERE job_id = v_app.job_id
          AND client_organization_id = p_client_org_id
          AND status = 'active'
          AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'Cannot share candidate: Job % is not actively shared with client %', v_app.job_id, p_client_org_id;
    END IF;

    SELECT * INTO v_cand FROM public.candidates WHERE id = v_app.candidate_id;
    SELECT * INTO v_prof FROM public.profiles WHERE id = v_cand.user_id;
    SELECT * INTO v_cand_prof FROM public.candidate_profiles WHERE candidate_id = v_cand.id;

    -- Merge visibility config
    v_vis := COALESCE(p_visibility_config, '{"show_name": true, "show_email": false, "show_phone": false, "show_salary": false, "show_cv": false, "show_match_score": true, "show_match_explanation": true, "show_experience": true, "show_education": true, "show_languages": true}'::jsonb);

    -- Anonymize name if configured
    IF (v_vis->>'show_name')::boolean IS FALSE THEN
        v_display_name := 'Candidate ' || substr(v_cand.id::text, 1, 8);
    ELSE
        v_display_name := COALESCE(v_prof.full_name, 'Candidate ' || substr(v_cand.id::text, 1, 8));
    END IF;

    -- Aggregate candidate skills
    SELECT jsonb_agg(jsonb_build_object('skill', skill_name, 'years', years_of_experience))
    INTO v_skills
    FROM public.candidate_skills
    WHERE candidate_id = v_app.candidate_id;
    v_skills := COALESCE(v_skills, '[]'::jsonb);

    -- Aggregate candidate languages
    SELECT jsonb_agg(jsonb_build_object('language', language_name, 'proficiency', proficiency_level))
    INTO v_langs
    FROM public.candidate_languages
    WHERE candidate_id = v_app.candidate_id;
    v_langs := COALESCE(v_langs, '[]'::jsonb);

    -- Calculate total years of experience
    SELECT COALESCE(SUM(EXTRACT(YEAR FROM age(COALESCE(end_date, CURRENT_DATE), start_date))), COALESCE(v_cand_prof.years_of_experience, 0), 0)
    INTO v_exp_years
    FROM public.candidate_experience
    WHERE candidate_id = v_app.candidate_id;

    -- Aggregate safe experience summary
    IF (v_vis->>'show_experience')::boolean IS NOT FALSE THEN
        SELECT jsonb_agg(jsonb_build_object('title', job_title, 'company', company_name, 'start_date', start_date, 'end_date', end_date, 'summary', description))
        INTO v_exp
        FROM public.candidate_experience
        WHERE candidate_id = v_app.candidate_id;
    END IF;
    v_exp := COALESCE(v_exp, '[]'::jsonb);

    -- Aggregate safe education summary
    IF (v_vis->>'show_education')::boolean IS NOT FALSE THEN
        SELECT jsonb_agg(jsonb_build_object('institution', institution_name, 'degree', degree, 'field_of_study', field_of_study, 'end_date', end_date))
        INTO v_edu
        FROM public.candidate_education
        WHERE candidate_id = v_app.candidate_id;
    END IF;
    v_edu := COALESCE(v_edu, '[]'::jsonb);

    -- Insert or update candidate share
    INSERT INTO public.client_candidate_shares (
        client_organization_id, job_id, candidate_id, application_id, shared_by, status, shared_at, expires_at, visibility_config
    )
    VALUES (
        p_client_org_id, v_app.job_id, v_app.candidate_id, p_application_id, auth.uid(), 'shared', now(), p_expires_at, v_vis
    )
    ON CONFLICT (job_id, client_organization_id, candidate_id) DO UPDATE
    SET status = 'shared',
        shared_at = now(),
        expires_at = EXCLUDED.expires_at,
        visibility_config = EXCLUDED.visibility_config,
        updated_at = now()
    RETURNING id INTO v_share_id;

    -- Insert or update client-safe projection
    INSERT INTO public.client_candidate_profiles (
        candidate_share_id, display_name, headline, professional_summary, location, country, city,
        years_of_experience, key_skills, languages, education_summary, experience_summary, availability,
        match_score, match_summary, presentation_status
    )
    VALUES (
        v_share_id,
        v_display_name,
        COALESCE(v_cand_prof.headline, 'Professional Candidate'),
        COALESCE(v_cand_prof.professional_summary, 'Experienced specialist presented for this role.'),
        COALESCE(v_cand_prof.city || ', ' || v_cand_prof.country_code, v_cand_prof.location_text, 'Remote / Available'),
        COALESCE(v_cand_prof.country_code, v_prof.country_code),
        v_cand_prof.city,
        v_exp_years,
        v_skills,
        v_langs,
        v_edu,
        v_exp,
        COALESCE(v_cand_prof.availability_status, 'Immediate'),
        CASE WHEN (v_vis->>'show_match_score')::boolean IS NOT FALSE THEN v_app.match_score ELSE NULL END,
        CASE WHEN (v_vis->>'show_match_explanation')::boolean IS NOT FALSE THEN 'Profile meets verified requirements for the role' ELSE NULL END,
        'ready'
    )
    ON CONFLICT (candidate_share_id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        headline = EXCLUDED.headline,
        professional_summary = EXCLUDED.professional_summary,
        location = EXCLUDED.location,
        years_of_experience = EXCLUDED.years_of_experience,
        key_skills = EXCLUDED.key_skills,
        languages = EXCLUDED.languages,
        education_summary = EXCLUDED.education_summary,
        experience_summary = EXCLUDED.experience_summary,
        match_score = EXCLUDED.match_score,
        match_summary = EXCLUDED.match_summary,
        updated_at = now();

    -- Audit activity
    INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type, event_data)
    VALUES (p_client_org_id, v_app.job_id, v_share_id, auth.uid(), 'candidate_shared', jsonb_build_object('candidate_id', v_app.candidate_id, 'display_name', v_display_name));

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_app.organization_id, 'client_candidate_shared', 'client_candidate_shares', v_share_id, jsonb_build_object('client_org_id', p_client_org_id, 'candidate_id', v_app.candidate_id));

    RETURN v_share_id;
END;
$$;

-- 6.4 Revoke Client Candidate Share
CREATE OR REPLACE FUNCTION public.revoke_client_candidate_share(
    p_share_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_share RECORD;
    v_job RECORD;
BEGIN
    SELECT * INTO v_share FROM public.client_candidate_shares WHERE id = p_share_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate share % not found', p_share_id;
    END IF;

    SELECT * INTO v_job FROM public.jobs WHERE id = v_share.job_id;
    IF NOT public.check_user_is_recruiter(v_job.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller cannot revoke candidate share';
    END IF;

    UPDATE public.client_candidate_shares
    SET status = 'revoked', updated_at = now()
    WHERE id = p_share_id;

    -- Update presentation projection
    UPDATE public.client_candidate_profiles
    SET presentation_status = 'withdrawn', updated_at = now()
    WHERE candidate_share_id = p_share_id;

    INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type, event_data)
    VALUES (v_share.client_organization_id, v_share.job_id, p_share_id, auth.uid(), 'candidate_revoked', jsonb_build_object('reason', p_reason));

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_job.organization_id, 'client_candidate_revoked', 'client_candidate_shares', p_share_id, jsonb_build_object('reason', p_reason));
END;
$$;

-- 6.5 Get Client Jobs
CREATE OR REPLACE FUNCTION public.get_client_jobs(p_client_org_id UUID)
RETURNS TABLE (
    job_id UUID,
    job_title TEXT,
    job_slug TEXT,
    status VARCHAR(50),
    shared_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    visibility VARCHAR(50),
    candidates_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.check_user_is_client_member(p_client_org_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', p_client_org_id;
    END IF;

    RETURN QUERY
    SELECT
        j.id AS job_id,
        j.title AS job_title,
        j.slug AS job_slug,
        cja.status,
        cja.shared_at,
        cja.expires_at,
        cja.visibility,
        (
            SELECT count(*)::BIGINT
            FROM public.client_candidate_shares ccs
            WHERE ccs.job_id = j.id
              AND ccs.client_organization_id = p_client_org_id
              AND ccs.status = 'shared'
              AND (ccs.expires_at IS NULL OR ccs.expires_at > now())
        ) AS candidates_count
    FROM public.client_job_access cja
    JOIN public.jobs j ON j.id = cja.job_id
    WHERE cja.client_organization_id = p_client_org_id
      AND cja.status = 'active'
      AND (cja.expires_at IS NULL OR cja.expires_at > now())
      AND j.status = 'published'
    ORDER BY cja.shared_at DESC;
END;
$$;

-- 6.6 Get Client Job Candidates
CREATE OR REPLACE FUNCTION public.get_client_job_candidates(
    p_client_org_id UUID,
    p_job_id UUID,
    p_filter_status TEXT DEFAULT NULL,
    p_sort_by TEXT DEFAULT 'match_score',
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    candidate_share_id UUID,
    candidate_id UUID,
    display_name TEXT,
    headline TEXT,
    location TEXT,
    years_of_experience NUMERIC(4,1),
    key_skills JSONB,
    match_score NUMERIC(5,2),
    shared_at TIMESTAMPTZ,
    client_review_decision VARCHAR(50),
    interview_request_status VARCHAR(50)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.check_user_is_client_member(p_client_org_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', p_client_org_id;
    END IF;

    -- Verify job is actively shared
    IF NOT EXISTS (
        SELECT 1 FROM public.client_job_access
        WHERE job_id = p_job_id
          AND client_organization_id = p_client_org_id
          AND status = 'active'
          AND (expires_at IS NULL OR expires_at > now())
    ) THEN
        RAISE EXCEPTION 'Job % is not actively shared with client %', p_job_id, p_client_org_id;
    END IF;

    RETURN QUERY
    SELECT
        ccs.id AS candidate_share_id,
        ccs.candidate_id,
        ccp.display_name,
        ccp.headline,
        ccp.location,
        ccp.years_of_experience,
        ccp.key_skills,
        ccp.match_score,
        ccs.shared_at,
        (
            SELECT ccf.decision
            FROM public.client_candidate_feedback ccf
            WHERE ccf.client_candidate_share_id = ccs.id
            ORDER BY ccf.created_at DESC LIMIT 1
        ) AS client_review_decision,
        (
            SELECT cir.status
            FROM public.client_interview_requests cir
            WHERE cir.client_candidate_share_id = ccs.id
            ORDER BY cir.created_at DESC LIMIT 1
        ) AS interview_request_status
    FROM public.client_candidate_shares ccs
    JOIN public.client_candidate_profiles ccp ON ccp.candidate_share_id = ccs.id
    WHERE ccs.client_organization_id = p_client_org_id
      AND ccs.job_id = p_job_id
      AND ccs.status = 'shared'
      AND (ccs.expires_at IS NULL OR ccs.expires_at > now())
      AND (p_filter_status IS NULL OR EXISTS (
          SELECT 1 FROM public.client_candidate_feedback ccf
          WHERE ccf.client_candidate_share_id = ccs.id AND ccf.decision = p_filter_status
      ))
    ORDER BY
        CASE WHEN p_sort_by = 'newest' THEN ccs.shared_at END DESC NULLS LAST,
        CASE WHEN p_sort_by = 'experience' THEN ccp.years_of_experience END DESC NULLS LAST,
        ccp.match_score DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 6.7 Get Client Candidate Details
CREATE OR REPLACE FUNCTION public.get_client_candidate(p_share_id UUID)
RETURNS TABLE (
    candidate_share_id UUID,
    job_id UUID,
    display_name TEXT,
    headline TEXT,
    professional_summary TEXT,
    location TEXT,
    years_of_experience NUMERIC(4,1),
    key_skills JSONB,
    languages JSONB,
    education_summary JSONB,
    experience_summary JSONB,
    match_score NUMERIC(5,2),
    match_summary TEXT,
    has_cv_access BOOLEAN,
    client_review_decision VARCHAR(50),
    client_review_comments TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_share RECORD;
BEGIN
    SELECT * INTO v_share FROM public.client_candidate_shares WHERE id = p_share_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate share % not found', p_share_id;
    END IF;

    IF NOT public.check_user_is_client_member(v_share.client_organization_id)
       AND NOT EXISTS (
           SELECT 1 FROM public.jobs j WHERE j.id = v_share.job_id AND public.check_user_is_recruiter(j.organization_id)
       ) THEN
        RAISE EXCEPTION 'Access denied: cannot view candidate share %', p_share_id;
    END IF;

    -- Track activity if viewed by client
    IF public.check_user_is_client_member(v_share.client_organization_id) THEN
        INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type)
        VALUES (v_share.client_organization_id, v_share.job_id, p_share_id, auth.uid(), 'candidate_viewed');
    END IF;

    RETURN QUERY
    SELECT
        ccp.candidate_share_id,
        v_share.job_id,
        ccp.display_name,
        ccp.headline,
        ccp.professional_summary,
        ccp.location,
        ccp.years_of_experience,
        ccp.key_skills,
        ccp.languages,
        ccp.education_summary,
        ccp.experience_summary,
        ccp.match_score,
        ccp.match_summary,
        EXISTS (
            SELECT 1 FROM public.client_document_access cda
            WHERE cda.client_candidate_share_id = p_share_id
              AND cda.expires_at > now()
              AND cda.revoked_at IS NULL
        ) AS has_cv_access,
        ccf.decision AS client_review_decision,
        ccf.comments AS client_review_comments
    FROM public.client_candidate_profiles ccp
    LEFT JOIN public.client_candidate_feedback ccf ON ccf.client_candidate_share_id = ccp.candidate_share_id AND ccf.author_id = auth.uid()
    WHERE ccp.candidate_share_id = p_share_id;
END;
$$;

-- 6.8 Submit Client Feedback & Scorecards
CREATE OR REPLACE FUNCTION public.submit_client_feedback(
    p_share_id UUID,
    p_decision TEXT,
    p_rating NUMERIC DEFAULT NULL,
    p_comments TEXT DEFAULT NULL,
    p_feedback_type TEXT DEFAULT 'candidate_review',
    p_scorecard_responses JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_share RECORD;
    v_fb_id UUID;
    v_prev_decision VARCHAR(50);
    v_resp RECORD;
BEGIN
    SELECT * INTO v_share FROM public.client_candidate_shares WHERE id = p_share_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate share % not found', p_share_id;
    END IF;

    IF NOT public.check_user_is_client_member(v_share.client_organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', v_share.client_organization_id;
    END IF;

    -- Verify share is active and not expired
    IF v_share.status <> 'shared' OR (v_share.expires_at IS NOT NULL AND v_share.expires_at <= now()) THEN
        RAISE EXCEPTION 'Candidate share % is inactive or expired', p_share_id;
    END IF;

    -- Check if previous feedback exists for history tracking
    SELECT decision INTO v_prev_decision
    FROM public.client_candidate_feedback
    WHERE client_candidate_share_id = p_share_id
      AND author_id = auth.uid()
      AND feedback_type = p_feedback_type;

    INSERT INTO public.client_candidate_feedback (
        client_candidate_share_id, author_id, feedback_type, rating, comments, decision
    )
    VALUES (
        p_share_id, auth.uid(), p_feedback_type, p_rating, p_comments, p_decision
    )
    ON CONFLICT (client_candidate_share_id, author_id, feedback_type) DO UPDATE
    SET rating = EXCLUDED.rating,
        comments = EXCLUDED.comments,
        decision = EXCLUDED.decision,
        updated_at = now()
    RETURNING id INTO v_fb_id;

    -- Append history if decision changed
    IF v_prev_decision IS NOT NULL AND v_prev_decision <> p_decision THEN
        INSERT INTO public.client_feedback_history (feedback_id, previous_decision, new_decision, changed_by, reason)
        VALUES (v_fb_id, v_prev_decision, p_decision, auth.uid(), p_comments);
    END IF;

    -- Record scorecard responses if provided
    IF p_scorecard_responses IS NOT NULL AND jsonb_typeof(p_scorecard_responses) = 'array' THEN
        FOR v_resp IN SELECT * FROM jsonb_to_recordset(p_scorecard_responses) AS x(
            question_id UUID, rating_value NUMERIC, text_value TEXT, choice_value TEXT, yes_no_value BOOLEAN
        )
        LOOP
            INSERT INTO public.client_scorecard_responses (
                feedback_id, question_id, rating_value, text_value, choice_value, yes_no_value
            )
            VALUES (
                v_fb_id, v_resp.question_id, v_resp.rating_value, v_resp.text_value, v_resp.choice_value, v_resp.yes_no_value
            )
            ON CONFLICT (feedback_id, question_id) DO UPDATE
            SET rating_value = EXCLUDED.rating_value,
                text_value = EXCLUDED.text_value,
                choice_value = EXCLUDED.choice_value,
                yes_no_value = EXCLUDED.yes_no_value,
                updated_at = now();
        END LOOP;
    END IF;

    -- Audit activity
    INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type, event_data)
    VALUES (v_share.client_organization_id, v_share.job_id, p_share_id, auth.uid(), 'candidate_feedback_submitted', jsonb_build_object('decision', p_decision, 'rating', p_rating));

    RETURN v_fb_id;
END;
$$;

-- 6.9 Request Client Interview
CREATE OR REPLACE FUNCTION public.request_client_interview(
    p_share_id UUID,
    p_preferred_timeframes JSONB DEFAULT '[]'::jsonb,
    p_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_share RECORD;
    v_req_id UUID;
BEGIN
    SELECT * INTO v_share FROM public.client_candidate_shares WHERE id = p_share_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate share % not found', p_share_id;
    END IF;

    IF NOT public.check_user_is_client_member(v_share.client_organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', v_share.client_organization_id;
    END IF;

    INSERT INTO public.client_interview_requests (
        client_candidate_share_id, requested_by, request_type, status, preferred_timeframes, notes
    )
    VALUES (
        p_share_id, auth.uid(), 'interview', 'pending', p_preferred_timeframes, p_notes
    )
    RETURNING id INTO v_req_id;

    -- Record activity
    INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type, event_data)
    VALUES (v_share.client_organization_id, v_share.job_id, p_share_id, auth.uid(), 'candidate_interview_requested', jsonb_build_object('request_id', v_req_id, 'notes', p_notes));

    RETURN v_req_id;
END;
$$;

-- 6.10 Request More Candidate Information
CREATE OR REPLACE FUNCTION public.request_more_candidate_information(
    p_share_id UUID,
    p_question TEXT,
    p_category TEXT DEFAULT 'general'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_share RECORD;
    v_req_id UUID;
BEGIN
    SELECT * INTO v_share FROM public.client_candidate_shares WHERE id = p_share_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate share % not found', p_share_id;
    END IF;

    IF NOT public.check_user_is_client_member(v_share.client_organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', v_share.client_organization_id;
    END IF;

    INSERT INTO public.client_information_requests (
        client_candidate_share_id, requested_by, question, category, status
    )
    VALUES (
        p_share_id, auth.uid(), p_question, p_category, 'pending'
    )
    RETURNING id INTO v_req_id;

    INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type, event_data)
    VALUES (v_share.client_organization_id, v_share.job_id, p_share_id, auth.uid(), 'candidate_information_requested', jsonb_build_object('question', p_question));

    RETURN v_req_id;
END;
$$;

-- 6.11 Submit Client Hiring Recommendation
CREATE OR REPLACE FUNCTION public.submit_client_hiring_decision(
    p_share_id UUID,
    p_decision TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_share RECORD;
    v_dec_id UUID;
BEGIN
    SELECT * INTO v_share FROM public.client_candidate_shares WHERE id = p_share_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Candidate share % not found', p_share_id;
    END IF;

    IF NOT public.check_user_is_client_member(v_share.client_organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', v_share.client_organization_id;
    END IF;

    INSERT INTO public.client_hiring_decisions (
        client_candidate_share_id, decision, reason, submitted_by
    )
    VALUES (
        p_share_id, p_decision, p_reason, auth.uid()
    )
    RETURNING id INTO v_dec_id;

    -- Record activity
    INSERT INTO public.client_activity_events (client_organization_id, job_id, candidate_share_id, actor_id, event_type, event_data)
    VALUES (v_share.client_organization_id, v_share.job_id, p_share_id, auth.uid(), 'client_decision_submitted', jsonb_build_object('decision', p_decision, 'reason', p_reason));

    RETURN v_dec_id;
END;
$$;

-- 6.12 Client Job Dashboard
CREATE OR REPLACE FUNCTION public.get_client_job_dashboard(
    p_client_org_id UUID,
    p_job_id UUID
)
RETURNS TABLE (
    job_title TEXT,
    status VARCHAR(50),
    candidates_presented BIGINT,
    candidates_reviewed BIGINT,
    interested_count BIGINT,
    interview_requested_count BIGINT,
    pending_feedback_count BIGINT,
    hired_recommendations_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job RECORD;
BEGIN
    IF NOT public.check_user_is_client_member(p_client_org_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', p_client_org_id;
    END IF;

    SELECT * INTO v_job FROM public.jobs WHERE id = p_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job % not found', p_job_id;
    END IF;

    RETURN QUERY
    SELECT
        v_job.title,
        cja.status,
        COUNT(ccs.id)::BIGINT AS candidates_presented,
        COUNT(DISTINCT ccf.client_candidate_share_id)::BIGINT AS candidates_reviewed,
        COUNT(DISTINCT CASE WHEN ccf.decision = 'interested' THEN ccs.id END)::BIGINT AS interested_count,
        COUNT(DISTINCT cir.id)::BIGINT AS interview_requested_count,
        (COUNT(ccs.id) - COUNT(DISTINCT ccf.client_candidate_share_id))::BIGINT AS pending_feedback_count,
        COUNT(DISTINCT CASE WHEN chd.decision = 'recommend_hire' THEN chd.id END)::BIGINT AS hired_recommendations_count
    FROM public.client_job_access cja
    LEFT JOIN public.client_candidate_shares ccs ON ccs.job_id = cja.job_id AND ccs.client_organization_id = p_client_org_id AND ccs.status = 'shared'
    LEFT JOIN public.client_candidate_feedback ccf ON ccf.client_candidate_share_id = ccs.id
    LEFT JOIN public.client_interview_requests cir ON cir.client_candidate_share_id = ccs.id
    LEFT JOIN public.client_hiring_decisions chd ON chd.client_candidate_share_id = ccs.id
    WHERE cja.client_organization_id = p_client_org_id AND cja.job_id = p_job_id
    GROUP BY v_job.title, cja.status;
END;
$$;

-- 6.13 Compare Client Candidates
CREATE OR REPLACE FUNCTION public.compare_client_candidates(
    p_client_org_id UUID,
    p_share_ids UUID[]
)
RETURNS TABLE (
    candidate_share_id UUID,
    display_name TEXT,
    headline TEXT,
    years_of_experience NUMERIC(4,1),
    key_skills JSONB,
    languages JSONB,
    education_summary JSONB,
    match_score NUMERIC(5,2),
    client_decision VARCHAR(50),
    latest_rating NUMERIC(3,2)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.check_user_is_client_member(p_client_org_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of client organization %', p_client_org_id;
    END IF;

    RETURN QUERY
    SELECT
        ccs.id AS candidate_share_id,
        ccp.display_name,
        ccp.headline,
        ccp.years_of_experience,
        ccp.key_skills,
        ccp.languages,
        ccp.education_summary,
        ccp.match_score,
        (
            SELECT ccf.decision
            FROM public.client_candidate_feedback ccf
            WHERE ccf.client_candidate_share_id = ccs.id
            ORDER BY ccf.created_at DESC LIMIT 1
        ) AS client_decision,
        (
            SELECT ccf.rating
            FROM public.client_candidate_feedback ccf
            WHERE ccf.client_candidate_share_id = ccs.id
            ORDER BY ccf.created_at DESC LIMIT 1
        ) AS latest_rating
    FROM public.client_candidate_shares ccs
    JOIN public.client_candidate_profiles ccp ON ccp.candidate_share_id = ccs.id
    WHERE ccs.id = ANY(p_share_ids)
      AND ccs.client_organization_id = p_client_org_id
      AND ccs.status = 'shared'
      AND (ccs.expires_at IS NULL OR ccs.expires_at > now())
    ORDER BY ccp.match_score DESC NULLS LAST;
END;
$$;

-- =============================================================================
-- END OF MIGRATION 20260915001100_client_portal_collaboration.sql
-- =============================================================================
