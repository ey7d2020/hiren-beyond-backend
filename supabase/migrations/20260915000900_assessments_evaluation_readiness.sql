-- ============================================================================
-- Hiren Beyond — Task 08: Assessments, Language/Voice Evaluation, Human Review & Candidate Readiness
-- Migration: 20260915000900_assessments_evaluation_readiness.sql
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. SEED ASSESSMENT PERMISSIONS
-- -----------------------------------------------------------------------------
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('assessments.create', 'Create Assessments', 'Create assessment templates, sections, and questions', 'assessments'),
    ('assessments.read', 'Read Assessments', 'View assessment templates, sections, and questions', 'assessments'),
    ('assessments.update', 'Update Assessments', 'Update draft assessment templates, sections, and questions', 'assessments'),
    ('assessments.publish', 'Publish Assessments', 'Publish or archive assessment templates', 'assessments'),
    ('assessments.invite', 'Invite to Assessments', 'Issue assessment invitations to candidates', 'assessments'),
    ('assessments.review', 'Review Assessments', 'Perform human reviews on candidate assessment attempts', 'assessments'),
    ('assessments.score', 'Score Assessments', 'Trigger or modify assessment scoring', 'assessments'),
    ('assessments.override', 'Override Assessment Scores', 'Override AI or automatic scores with audit trail', 'assessments'),
    ('assessments.manage_templates', 'Manage Assessment Templates', 'Manage organization-wide assessment configurations', 'assessments'),
    ('candidate_assessments.read', 'Read Candidate Assessments', 'View candidate assessment attempts and results', 'assessments'),
    ('candidate_assessments.manage', 'Manage Candidate Assessments', 'Cancel, extend, or reset candidate assessment attempts', 'assessments'),
    ('candidate_readiness.read', 'Read Candidate Readiness', 'View candidate readiness evaluations and blocking reasons', 'assessments')
ON CONFLICT (key) DO NOTHING;

-- Grant permissions to admin and recruiter roles
DO $$
DECLARE
    v_admin_id UUID;
    v_recruiter_id UUID;
    v_hm_id UUID;
    r_perm RECORD;
BEGIN
    SELECT id INTO v_admin_id FROM public.roles WHERE key = 'admin' LIMIT 1;
    SELECT id INTO v_recruiter_id FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_hm_id FROM public.roles WHERE key = 'hiring_manager' LIMIT 1;

    FOR r_perm IN SELECT id, key FROM public.permissions WHERE category = 'assessments' LOOP
        IF v_admin_id IS NOT NULL THEN
            INSERT INTO public.role_permissions (role_id, permission_id)
            VALUES (v_admin_id, r_perm.id)
            ON CONFLICT DO NOTHING;
        END IF;

        IF v_recruiter_id IS NOT NULL THEN
            INSERT INTO public.role_permissions (role_id, permission_id)
            VALUES (v_recruiter_id, r_perm.id)
            ON CONFLICT DO NOTHING;
        END IF;

        IF v_hm_id IS NOT NULL AND r_perm.key IN ('assessments.read', 'assessments.review', 'candidate_assessments.read', 'candidate_readiness.read') THEN
            INSERT INTO public.role_permissions (role_id, permission_id)
            VALUES (v_hm_id, r_perm.id)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. RECRUITER CHECK HELPER FUNCTION
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_user_is_recruiter(p_org_id UUID)
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
            WHERE om.organization_id = p_org_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND r.key IN ('admin', 'recruiter', 'hiring_manager')
        )
    );
$$;

-- -----------------------------------------------------------------------------
-- 3. PRIVATE STORAGE BUCKETS
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES 
    ('assessment-audio', 'assessment-audio', false),
    ('assessment-video', 'assessment-video', false),
    ('assessment-files', 'assessment-files', false)
ON CONFLICT (id) DO UPDATE SET public = false;


-- Storage policies: candidate can upload and read their own files; authorized recruiters can read
DROP POLICY IF EXISTS "Candidates can upload assessment audio" ON storage.objects;
CREATE POLICY "Candidates can upload assessment audio"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'assessment-audio' 
    AND (auth.uid()::text = (storage.foldername(name))[1] OR EXISTS (
        SELECT 1 FROM public.candidates c WHERE c.user_id = auth.uid() AND c.id::text = (storage.foldername(name))[1]
    ))
);

DROP POLICY IF EXISTS "Candidates can read own assessment audio" ON storage.objects;
CREATE POLICY "Candidates can read own assessment audio"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'assessment-audio'
    AND (auth.uid()::text = (storage.foldername(name))[1] OR EXISTS (
        SELECT 1 FROM public.candidates c WHERE c.user_id = auth.uid() AND c.id::text = (storage.foldername(name))[1]
    ))
);

DROP POLICY IF EXISTS "Candidates can upload assessment video" ON storage.objects;
CREATE POLICY "Candidates can upload assessment video"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'assessment-video' 
    AND (auth.uid()::text = (storage.foldername(name))[1] OR EXISTS (
        SELECT 1 FROM public.candidates c WHERE c.user_id = auth.uid() AND c.id::text = (storage.foldername(name))[1]
    ))
);

DROP POLICY IF EXISTS "Candidates can read own assessment video" ON storage.objects;
CREATE POLICY "Candidates can read own assessment video"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'assessment-video'
    AND (auth.uid()::text = (storage.foldername(name))[1] OR EXISTS (
        SELECT 1 FROM public.candidates c WHERE c.user_id = auth.uid() AND c.id::text = (storage.foldername(name))[1]
    ))
);

DROP POLICY IF EXISTS "Candidates can upload assessment files" ON storage.objects;
CREATE POLICY "Candidates can upload assessment files"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'assessment-files' 
    AND (auth.uid()::text = (storage.foldername(name))[1] OR EXISTS (
        SELECT 1 FROM public.candidates c WHERE c.user_id = auth.uid() AND c.id::text = (storage.foldername(name))[1]
    ))
);

DROP POLICY IF EXISTS "Candidates can read own assessment files" ON storage.objects;
CREATE POLICY "Candidates can read own assessment files"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'assessment-files'
    AND (auth.uid()::text = (storage.foldername(name))[1] OR EXISTS (
        SELECT 1 FROM public.candidates c WHERE c.user_id = auth.uid() AND c.id::text = (storage.foldername(name))[1]
    ))
);

-- Recruiter read access for all assessment storage
DROP POLICY IF EXISTS "Recruiters can read assessment files" ON storage.objects;
CREATE POLICY "Recruiters can read assessment files"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id IN ('assessment-audio', 'assessment-video', 'assessment-files')
    AND EXISTS (
        SELECT 1 FROM public.organization_members om
        JOIN public.roles r ON r.id = om.role_id
        WHERE om.user_id = auth.uid()
          AND om.status = 'active'
          AND r.key IN ('admin', 'recruiter', 'hiring_manager')
    )
);

-- -----------------------------------------------------------------------------
-- 3. ASSESSMENT TEMPLATES
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    description TEXT,
    assessment_type VARCHAR(50) NOT NULL CHECK (assessment_type IN ('language', 'voice', 'technical', 'translation', 'general', 'ai_training', 'custom')),
    version INT NOT NULL DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
    time_limit_minutes INT,
    passing_score NUMERIC(5,2) DEFAULT 70.00,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_platform BOOLEAN NOT NULL DEFAULT false,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_templates_org ON public.assessment_templates(organization_id);
CREATE INDEX IF NOT EXISTS idx_assessment_templates_type ON public.assessment_templates(assessment_type);
CREATE INDEX IF NOT EXISTS idx_assessment_templates_platform ON public.assessment_templates(is_platform);
CREATE INDEX IF NOT EXISTS idx_assessment_templates_status ON public.assessment_templates(status);

-- Unique constraint: slug + version per organization (or platform)
CREATE UNIQUE INDEX IF NOT EXISTS idx_assessment_templates_slug_version 
ON public.assessment_templates(COALESCE(organization_id, '00000000-0000-0000-0000-000000000000'::uuid), slug, version);

-- -----------------------------------------------------------------------------
-- 4. ASSESSMENT SECTIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_template_id UUID NOT NULL REFERENCES public.assessment_templates(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    section_type VARCHAR(50) NOT NULL CHECK (section_type IN ('grammar', 'vocabulary', 'reading', 'listening', 'speaking', 'pronunciation', 'technical_knowledge', 'coding', 'translation', 'communication', 'custom')),
    sort_order INT NOT NULL DEFAULT 0,
    weight NUMERIC(5,2) NOT NULL DEFAULT 1.00,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_sections_template ON public.assessment_sections(assessment_template_id);
CREATE INDEX IF NOT EXISTS idx_assessment_sections_order ON public.assessment_sections(assessment_template_id, sort_order);

-- -----------------------------------------------------------------------------
-- 5. ASSESSMENT QUESTIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_section_id UUID NOT NULL REFERENCES public.assessment_sections(id) ON DELETE CASCADE,
    question_type VARCHAR(50) NOT NULL CHECK (question_type IN ('single_choice', 'multiple_choice', 'true_false', 'text', 'long_text', 'number', 'coding', 'translation', 'audio_response', 'video_response', 'file_upload')),
    question_text TEXT NOT NULL,
    instructions TEXT,
    difficulty VARCHAR(50) DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard', 'expert')),
    points NUMERIC(5,2) NOT NULL DEFAULT 1.00,
    is_required BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    correct_answer TEXT, -- Protected answer key
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_questions_section ON public.assessment_questions(assessment_section_id);
CREATE INDEX IF NOT EXISTS idx_assessment_questions_order ON public.assessment_questions(assessment_section_id, sort_order);

-- -----------------------------------------------------------------------------
-- 6. ASSESSMENT QUESTION OPTIONS (For choice questions)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_question_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    question_id UUID NOT NULL REFERENCES public.assessment_questions(id) ON DELETE CASCADE,
    option_text TEXT NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    points NUMERIC(5,2) DEFAULT 0.00,
    is_correct BOOLEAN NOT NULL DEFAULT false, -- Protected
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_options_question ON public.assessment_question_options(question_id);
CREATE INDEX IF NOT EXISTS idx_assessment_options_order ON public.assessment_question_options(question_id, sort_order);

-- -----------------------------------------------------------------------------
-- 7. JOB ASSESSMENT REQUIREMENTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.job_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    assessment_template_id UUID NOT NULL REFERENCES public.assessment_templates(id) ON DELETE CASCADE,
    required BOOLEAN NOT NULL DEFAULT true,
    sequence INT NOT NULL DEFAULT 1,
    trigger_stage VARCHAR(50) NOT NULL DEFAULT 'screening' CHECK (trigger_stage IN ('application', 'screening', 'shortlisted', 'pre_interview', 'custom')),
    deadline_hours INT DEFAULT 72,
    minimum_score NUMERIC(5,2) DEFAULT 70.00,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (job_id, assessment_template_id)
);

CREATE INDEX IF NOT EXISTS idx_job_assessments_job ON public.job_assessments(job_id);
CREATE INDEX IF NOT EXISTS idx_job_assessments_template ON public.job_assessments(assessment_template_id);
CREATE INDEX IF NOT EXISTS idx_job_assessments_stage ON public.job_assessments(job_id, trigger_stage);

-- -----------------------------------------------------------------------------
-- 8. ASSESSMENT INVITATIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_template_id UUID NOT NULL REFERENCES public.assessment_templates(id) ON DELETE CASCADE,
    job_id UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    issued_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'opened', 'in_progress', 'completed', 'expired', 'cancelled')),
    token VARCHAR(128) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_invitations_candidate ON public.assessment_invitations(candidate_id);
CREATE INDEX IF NOT EXISTS idx_assessment_invitations_job ON public.assessment_invitations(job_id);
CREATE INDEX IF NOT EXISTS idx_assessment_invitations_app ON public.assessment_invitations(application_id);
CREATE INDEX IF NOT EXISTS idx_assessment_invitations_status ON public.assessment_invitations(status);
CREATE INDEX IF NOT EXISTS idx_assessment_invitations_token ON public.assessment_invitations(token);

-- Idempotency constraint: 1 active invitation per candidate, job, template
CREATE UNIQUE INDEX IF NOT EXISTS idx_assessment_invitations_unique_active
ON public.assessment_invitations(COALESCE(job_id, '00000000-0000-0000-0000-000000000000'::uuid), assessment_template_id, candidate_id)
WHERE status IN ('pending', 'opened', 'in_progress', 'completed');

-- -----------------------------------------------------------------------------
-- 9. CANDIDATE ASSESSMENT ATTEMPTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_invitation_id UUID NOT NULL REFERENCES public.assessment_invitations(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    assessment_version INT NOT NULL DEFAULT 1,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    submitted_at TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'in_progress' CHECK (status IN ('not_started', 'in_progress', 'submitted', 'scoring', 'completed', 'needs_review', 'failed')),
    attempt_number INT NOT NULL DEFAULT 1,
    score NUMERIC(5,2),
    passing_score NUMERIC(5,2),
    passed BOOLEAN,
    time_spent_seconds INT NOT NULL DEFAULT 0,
    evaluation_status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (evaluation_status IN ('pending', 'automatic_scored', 'ai_evaluated', 'needs_human_review', 'completed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_attempts_inv ON public.assessment_attempts(assessment_invitation_id);
CREATE INDEX IF NOT EXISTS idx_assessment_attempts_cand ON public.assessment_attempts(candidate_id);
CREATE INDEX IF NOT EXISTS idx_assessment_attempts_status ON public.assessment_attempts(status);

-- -----------------------------------------------------------------------------
-- 10. CANDIDATE ANSWERS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_attempt_id UUID NOT NULL REFERENCES public.assessment_attempts(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES public.assessment_questions(id) ON DELETE CASCADE,
    answer_text TEXT,
    selected_options UUID[] DEFAULT '{}'::uuid[],
    numeric_answer NUMERIC(10,2),
    file_path TEXT,
    audio_file_path TEXT,
    video_file_path TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_attempt_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_assessment_answers_attempt ON public.assessment_answers(assessment_attempt_id);
CREATE INDEX IF NOT EXISTS idx_assessment_answers_question ON public.assessment_answers(question_id);

-- -----------------------------------------------------------------------------
-- 11. ASSESSMENT RESULTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_attempt_id UUID NOT NULL REFERENCES public.assessment_attempts(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    assessment_template_id UUID NOT NULL REFERENCES public.assessment_templates(id) ON DELETE CASCADE,
    assessment_version INT NOT NULL,
    total_score NUMERIC(5,2) NOT NULL,
    normalized_score NUMERIC(5,2) NOT NULL,
    passed BOOLEAN NOT NULL,
    confidence NUMERIC(4,2) NOT NULL DEFAULT 1.00,
    evaluation_method VARCHAR(50) NOT NULL DEFAULT 'automatic' CHECK (evaluation_method IN ('automatic', 'ai', 'human', 'hybrid')),
    evaluation_status VARCHAR(50) NOT NULL DEFAULT 'scored' CHECK (evaluation_status IN ('pending', 'scored', 'needs_review', 'finalized', 'failed')),
    cefr_level VARCHAR(10) CHECK (cefr_level IS NULL OR cefr_level IN ('a1', 'a2', 'b1', 'b2', 'c1', 'c2', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2')),
    result_summary TEXT,
    strengths JSONB NOT NULL DEFAULT '[]'::jsonb,
    gaps JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_results_attempt ON public.assessment_results(assessment_attempt_id);
CREATE INDEX IF NOT EXISTS idx_assessment_results_candidate ON public.assessment_results(candidate_id);
CREATE INDEX IF NOT EXISTS idx_assessment_results_app ON public.assessment_results(application_id);
CREATE INDEX IF NOT EXISTS idx_assessment_results_template ON public.assessment_results(assessment_template_id);
CREATE INDEX IF NOT EXISTS idx_assessment_results_passed ON public.assessment_results(passed);

-- -----------------------------------------------------------------------------
-- 12. SECTION RESULTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_section_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_result_id UUID NOT NULL REFERENCES public.assessment_results(id) ON DELETE CASCADE,
    assessment_section_id UUID NOT NULL REFERENCES public.assessment_sections(id) ON DELETE CASCADE,
    score NUMERIC(5,2) NOT NULL,
    max_score NUMERIC(5,2) NOT NULL,
    normalized_score NUMERIC(5,2) NOT NULL,
    weight NUMERIC(5,2) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'passed' CHECK (status IN ('passed', 'failed', 'needs_review')),
    feedback TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_section_results_res ON public.assessment_section_results(assessment_result_id);
CREATE INDEX IF NOT EXISTS idx_section_results_sec ON public.assessment_section_results(assessment_section_id);

-- -----------------------------------------------------------------------------
-- 13. QUESTION RESULTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_question_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_result_id UUID NOT NULL REFERENCES public.assessment_results(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES public.assessment_questions(id) ON DELETE CASCADE,
    raw_score NUMERIC(5,2) NOT NULL,
    max_score NUMERIC(5,2) NOT NULL,
    normalized_score NUMERIC(5,2) NOT NULL,
    evaluation_method VARCHAR(50) NOT NULL DEFAULT 'automatic' CHECK (evaluation_method IN ('automatic', 'ai', 'human', 'hybrid')),
    confidence NUMERIC(4,2) NOT NULL DEFAULT 1.00,
    feedback TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_question_results_res ON public.assessment_question_results(assessment_result_id);
CREATE INDEX IF NOT EXISTS idx_question_results_q ON public.assessment_question_results(question_id);

-- -----------------------------------------------------------------------------
-- 14. VOICE ASSESSMENT RESULTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.voice_assessment_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_answer_id UUID NOT NULL REFERENCES public.assessment_answers(id) ON DELETE CASCADE,
    audio_duration_seconds NUMERIC(6,2),
    transcription TEXT,
    detected_language VARCHAR(50),
    fluency_score NUMERIC(5,2) CHECK (fluency_score >= 0 AND fluency_score <= 100),
    pronunciation_score NUMERIC(5,2) CHECK (pronunciation_score >= 0 AND pronunciation_score <= 100),
    clarity_score NUMERIC(5,2) CHECK (clarity_score >= 0 AND clarity_score <= 100),
    confidence_score NUMERIC(4,2) CHECK (confidence_score >= 0 AND confidence_score <= 1),
    overall_score NUMERIC(5,2) CHECK (overall_score >= 0 AND overall_score <= 100),
    evaluation_provider VARCHAR(100) NOT NULL DEFAULT 'internal_voice_evaluator',
    model_name VARCHAR(100),
    analysis_version VARCHAR(50) NOT NULL DEFAULT 'v1.0',
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'needs_review', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_voice_results_ans ON public.voice_assessment_results(assessment_answer_id);
CREATE INDEX IF NOT EXISTS idx_voice_results_status ON public.voice_assessment_results(status);

-- -----------------------------------------------------------------------------
-- 15. ASSESSMENT REVIEWS (Human Review & Overrides)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assessment_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_result_id UUID NOT NULL REFERENCES public.assessment_results(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
    review_status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending', 'in_progress', 'completed', 'cancelled')),
    original_ai_score NUMERIC(5,2),
    original_ai_feedback TEXT,
    score_override NUMERIC(5,2),
    reviewer_feedback TEXT,
    final_decision VARCHAR(50) CHECK (final_decision IN ('approved', 'rejected', 'needs_more_evidence')),
    review_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assessment_reviews_res ON public.assessment_reviews(assessment_result_id);
CREATE INDEX IF NOT EXISTS idx_assessment_reviews_rev ON public.assessment_reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS idx_assessment_reviews_status ON public.assessment_reviews(review_status);

-- -----------------------------------------------------------------------------
-- 16. CANDIDATE READINESS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.candidate_readiness (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
    application_id UUID REFERENCES public.applications(id) ON DELETE CASCADE,
    readiness_status VARCHAR(50) NOT NULL DEFAULT 'not_started' CHECK (readiness_status IN ('not_started', 'in_progress', 'ready', 'ready_with_review', 'blocked', 'complete')),
    readiness_score NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    required_assessments INT NOT NULL DEFAULT 0,
    completed_assessments INT NOT NULL DEFAULT 0,
    passed_assessments INT NOT NULL DEFAULT 0,
    failed_assessments INT NOT NULL DEFAULT 0,
    needs_review_count INT NOT NULL DEFAULT 0,
    blocking_reasons TEXT[] NOT NULL DEFAULT '{}'::text[],
    summary TEXT,
    candidate_facing_summary TEXT,
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_candidate_readiness_cand_job
ON public.candidate_readiness(candidate_id, COALESCE(job_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX IF NOT EXISTS idx_candidate_readiness_cand ON public.candidate_readiness(candidate_id);
CREATE INDEX IF NOT EXISTS idx_candidate_readiness_job ON public.candidate_readiness(job_id);
CREATE INDEX IF NOT EXISTS idx_candidate_readiness_status ON public.candidate_readiness(readiness_status);

-- -----------------------------------------------------------------------------
-- 17. ROW LEVEL SECURITY POLICIES
-- -----------------------------------------------------------------------------
ALTER TABLE public.assessment_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_question_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_section_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_question_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.voice_assessment_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assessment_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_readiness ENABLE ROW LEVEL SECURITY;

-- 17.1 Assessment Templates
-- Platform templates readable by any authenticated user. Organization templates readable by org recruiters.
CREATE POLICY "Read assessment templates"
ON public.assessment_templates FOR SELECT
TO authenticated
USING (
    is_platform = true
    OR organization_id IS NULL
    OR public.check_user_is_recruiter(organization_id)
);

CREATE POLICY "Manage assessment templates"
ON public.assessment_templates FOR ALL
TO authenticated
USING (
    organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id)
)
WITH CHECK (
    organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id)
);

-- 17.2 Sections & Questions & Options
-- Candidate can view questions if they hold a valid invitation or attempt. Correct answers are hidden via secure view/RPC.
CREATE POLICY "Read assessment sections"
ON public.assessment_sections FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_templates at
        WHERE at.id = assessment_template_id
          AND (
              at.is_platform = true
              OR at.organization_id IS NULL
              OR public.check_user_is_recruiter(at.organization_id)
              OR EXISTS (
                  SELECT 1 FROM public.assessment_invitations ai
                  JOIN public.candidates c ON c.id = ai.candidate_id
                  WHERE ai.assessment_template_id = at.id
                    AND c.user_id = auth.uid()
                    AND ai.status IN ('opened', 'in_progress')
              )
          )
    )
);

CREATE POLICY "Manage assessment sections"
ON public.assessment_sections FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_templates at
        WHERE at.id = assessment_template_id
          AND at.organization_id IS NOT NULL
          AND public.check_user_is_recruiter(at.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.assessment_templates at
        WHERE at.id = assessment_template_id
          AND at.organization_id IS NOT NULL
          AND public.check_user_is_recruiter(at.organization_id)
    )
);

-- Questions
CREATE POLICY "Read assessment questions"
ON public.assessment_questions FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_sections sec
        JOIN public.assessment_templates at ON at.id = sec.assessment_template_id
        WHERE sec.id = assessment_section_id
          AND (
              at.is_platform = true
              OR at.organization_id IS NULL
              OR public.check_user_is_recruiter(at.organization_id)
              OR EXISTS (
                  SELECT 1 FROM public.assessment_invitations ai
                  JOIN public.candidates c ON c.id = ai.candidate_id
                  WHERE ai.assessment_template_id = at.id
                    AND c.user_id = auth.uid()
                    AND ai.status IN ('opened', 'in_progress')
              )
          )
    )
);

CREATE POLICY "Manage assessment questions"
ON public.assessment_questions FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_sections sec
        JOIN public.assessment_templates at ON at.id = sec.assessment_template_id
        WHERE sec.id = assessment_section_id
          AND at.organization_id IS NOT NULL
          AND public.check_user_is_recruiter(at.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.assessment_sections sec
        JOIN public.assessment_templates at ON at.id = sec.assessment_template_id
        WHERE sec.id = assessment_section_id
          AND at.organization_id IS NOT NULL
          AND public.check_user_is_recruiter(at.organization_id)
    )
);

-- Options (is_correct must only be queried by recruiters or server functions)
CREATE POLICY "Read assessment question options"
ON public.assessment_question_options FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_questions q
        JOIN public.assessment_sections sec ON sec.id = q.assessment_section_id
        JOIN public.assessment_templates at ON at.id = sec.assessment_template_id
        WHERE q.id = question_id
          AND (
              at.is_platform = true
              OR at.organization_id IS NULL
              OR public.check_user_is_recruiter(at.organization_id)
              OR EXISTS (
                  SELECT 1 FROM public.assessment_invitations ai
                  JOIN public.candidates c ON c.id = ai.candidate_id
                  WHERE ai.assessment_template_id = at.id
                    AND c.user_id = auth.uid()
                    AND ai.status IN ('opened', 'in_progress')
              )
          )
    )
);

CREATE POLICY "Manage assessment question options"
ON public.assessment_question_options FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_questions q
        JOIN public.assessment_sections sec ON sec.id = q.assessment_section_id
        JOIN public.assessment_templates at ON at.id = sec.assessment_template_id
        WHERE q.id = question_id
          AND at.organization_id IS NOT NULL
          AND public.check_user_is_recruiter(at.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.assessment_questions q
        JOIN public.assessment_sections sec ON sec.id = q.assessment_section_id
        JOIN public.assessment_templates at ON at.id = sec.assessment_template_id
        WHERE q.id = question_id
          AND at.organization_id IS NOT NULL
          AND public.check_user_is_recruiter(at.organization_id)
    )
);

-- 17.3 Job Assessments
CREATE POLICY "Read job assessments"
ON public.job_assessments FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.jobs j
        WHERE j.id = job_id
          AND (
              j.status = 'published'
              OR public.check_user_is_recruiter(j.organization_id)
          )
    )
);

CREATE POLICY "Manage job assessments"
ON public.job_assessments FOR ALL
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

-- 17.4 Assessment Invitations
CREATE POLICY "Candidate can read own invitations"
ON public.assessment_invitations FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
);

CREATE POLICY "Recruiters can manage invitations"
ON public.assessment_invitations FOR ALL
TO authenticated
USING (
    job_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.jobs j WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
)
WITH CHECK (
    job_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.jobs j WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.5 Assessment Attempts
CREATE POLICY "Candidate can read and manage own attempts"
ON public.assessment_attempts FOR ALL
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
)
WITH CHECK (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
);

CREATE POLICY "Recruiters can view candidate attempts"
ON public.assessment_attempts FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_invitations ai
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE ai.id = assessment_invitation_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.6 Assessment Answers
CREATE POLICY "Candidate can manage own answers"
ON public.assessment_answers FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_attempts aa
        JOIN public.candidates c ON c.id = aa.candidate_id
        WHERE aa.id = assessment_attempt_id
          AND c.user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.assessment_attempts aa
        JOIN public.candidates c ON c.id = aa.candidate_id
        WHERE aa.id = assessment_attempt_id
          AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Recruiters can read answers"
ON public.assessment_answers FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_attempts aa
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE aa.id = assessment_attempt_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.7 Assessment Results
CREATE POLICY "Candidate can view own finalized results"
ON public.assessment_results FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
);

CREATE POLICY "Recruiters can read assessment results"
ON public.assessment_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.applications a
        WHERE a.id = application_id
          AND public.check_user_is_recruiter(a.organization_id)
    )
    OR EXISTS (
        SELECT 1 FROM public.assessment_attempts aa
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE aa.id = assessment_attempt_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.8 Section Results & Question Results
CREATE POLICY "Candidate can view section results"
ON public.assessment_section_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_results ar
        JOIN public.candidates c ON c.id = ar.candidate_id
        WHERE ar.id = assessment_result_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Recruiters can view section results"
ON public.assessment_section_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_results ar
        JOIN public.assessment_attempts aa ON aa.id = ar.assessment_attempt_id
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE ar.id = assessment_result_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

CREATE POLICY "Candidate can view question results"
ON public.assessment_question_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_results ar
        JOIN public.candidates c ON c.id = ar.candidate_id
        WHERE ar.id = assessment_result_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Recruiters can view question results"
ON public.assessment_question_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_results ar
        JOIN public.assessment_attempts aa ON aa.id = ar.assessment_attempt_id
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE ar.id = assessment_result_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.9 Voice Results
CREATE POLICY "Candidate can view own voice results"
ON public.voice_assessment_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_answers ans
        JOIN public.assessment_attempts aa ON aa.id = ans.assessment_attempt_id
        JOIN public.candidates c ON c.id = aa.candidate_id
        WHERE ans.id = assessment_answer_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Recruiters can view voice results"
ON public.voice_assessment_results FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_answers ans
        JOIN public.assessment_attempts aa ON aa.id = ans.assessment_attempt_id
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE ans.id = assessment_answer_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.10 Assessment Reviews
CREATE POLICY "Recruiters can manage reviews"
ON public.assessment_reviews FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.assessment_results ar
        JOIN public.assessment_attempts aa ON aa.id = ar.assessment_attempt_id
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE ar.id = assessment_result_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.assessment_results ar
        JOIN public.assessment_attempts aa ON aa.id = ar.assessment_attempt_id
        JOIN public.assessment_invitations ai ON ai.id = aa.assessment_invitation_id
        JOIN public.jobs j ON j.id = ai.job_id
        WHERE ar.id = assessment_result_id
          AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- 17.11 Candidate Readiness
CREATE POLICY "Candidate can view own readiness"
ON public.candidate_readiness FOR SELECT
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
);

CREATE POLICY "Recruiters can view candidate readiness"
ON public.candidate_readiness FOR SELECT
TO authenticated
USING (
    job_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.jobs j WHERE j.id = job_id AND public.check_user_is_recruiter(j.organization_id)
    )
);

-- -----------------------------------------------------------------------------
-- 18. STORED PROCEDURES (RPC FUNCTIONS)
-- -----------------------------------------------------------------------------

-- 18.1 Trigger Required Assessments for an Application
CREATE OR REPLACE FUNCTION public.trigger_required_assessments(p_application_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_app RECORD;
    r_ja RECORD;
    v_token TEXT;
    v_count INT := 0;
    v_expires TIMESTAMPTZ;
BEGIN
    SELECT a.*, j.organization_id INTO v_app
    FROM public.applications a
    JOIN public.jobs j ON j.id = a.job_id
    WHERE a.id = p_application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application % not found', p_application_id;
    END IF;

    -- Inspect job assessments required for the job at the current or earlier stage
    FOR r_ja IN
        SELECT ja.*, at.name AS template_name
        FROM public.job_assessments ja
        JOIN public.assessment_templates at ON at.id = ja.assessment_template_id
        WHERE ja.job_id = v_app.job_id
          AND ja.required = true
          AND (
              ja.trigger_stage IN ('application', 'screening')
              OR ja.trigger_stage = v_app.status
          )
    LOOP
        -- Check if an active invitation already exists (Idempotency)
        IF NOT EXISTS (
            SELECT 1 FROM public.assessment_invitations
            WHERE job_id = v_app.job_id
              AND assessment_template_id = r_ja.assessment_template_id
              AND candidate_id = v_app.candidate_id
              AND status IN ('pending', 'opened', 'in_progress', 'completed')
        ) THEN
            v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
            v_expires := now() + (COALESCE(r_ja.deadline_hours, 72) || ' hours')::interval;

            INSERT INTO public.assessment_invitations (
                assessment_template_id, job_id, application_id, candidate_id,
                issued_by, status, token, expires_at
            )
            VALUES (
                r_ja.assessment_template_id, v_app.job_id, v_app.id, v_app.candidate_id,
                auth.uid(), 'pending', v_token, v_expires
            );

            v_count := v_count + 1;

            -- Audit log
            INSERT INTO public.audit_logs (
                organization_id, actor_user_id, action, entity_type, entity_id, metadata
            )
            VALUES (
                v_app.organization_id, auth.uid(), 'assessment_invitation_created', 'assessment_invitations',
                v_app.id, jsonb_build_object('job_id', v_app.job_id, 'template_id', r_ja.assessment_template_id)
            );
        END IF;
    END LOOP;

    -- Recalculate candidate readiness
    PERFORM public.calculate_candidate_readiness(v_app.candidate_id, v_app.job_id);

    RETURN v_count;
END;
$$;

-- 18.2 Start Candidate Assessment Attempt
CREATE OR REPLACE FUNCTION public.start_assessment_attempt(p_invitation_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_inv RECORD;
    v_attempt_id UUID;
    v_attempt_num INT;
    v_cand RECORD;
    v_template RECORD;
    v_sections JSONB;
BEGIN
    SELECT * INTO v_inv
    FROM public.assessment_invitations
    WHERE token = p_invitation_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment invitation token invalid or not found';
    END IF;

    IF v_inv.status IN ('expired', 'cancelled') THEN
        RAISE EXCEPTION 'Assessment invitation is % and cannot be started', v_inv.status;
    END IF;

    IF v_inv.expires_at < now() THEN
        UPDATE public.assessment_invitations SET status = 'expired', updated_at = now() WHERE id = v_inv.id;
        RAISE EXCEPTION 'Assessment invitation has expired';
    END IF;

    SELECT * INTO v_template FROM public.assessment_templates WHERE id = v_inv.assessment_template_id;

    -- Ensure candidate exists and is active
    SELECT * INTO v_cand FROM public.candidates WHERE id = v_inv.candidate_id;

    -- Check if active attempt already exists
    SELECT id INTO v_attempt_id
    FROM public.assessment_attempts
    WHERE assessment_invitation_id = v_inv.id AND status = 'in_progress';

    IF v_attempt_id IS NULL THEN
        SELECT COALESCE(MAX(attempt_number), 0) + 1 INTO v_attempt_num
        FROM public.assessment_attempts
        WHERE assessment_invitation_id = v_inv.id;

        INSERT INTO public.assessment_attempts (
            assessment_invitation_id, candidate_id, assessment_version, status, attempt_number
        )
        VALUES (
            v_inv.id, v_inv.candidate_id, v_template.version, 'in_progress', v_attempt_num
        )
        RETURNING id INTO v_attempt_id;

        UPDATE public.assessment_invitations
        SET status = 'in_progress', started_at = COALESCE(started_at, now()), updated_at = now()
        WHERE id = v_inv.id;
    END IF;

    -- Construct candidate-safe sections and questions (without answers or is_correct)
    SELECT jsonb_agg(
        jsonb_build_object(
            'section_id', s.id,
            'name', s.name,
            'description', s.description,
            'section_type', s.section_type,
            'sort_order', s.sort_order,
            'questions', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'question_id', q.id,
                        'question_type', q.question_type,
                        'question_text', q.question_text,
                        'instructions', q.instructions,
                        'difficulty', q.difficulty,
                        'points', q.points,
                        'is_required', q.is_required,
                        'sort_order', q.sort_order,
                        'options', (
                            SELECT jsonb_agg(
                                jsonb_build_object(
                                    'option_id', o.id,
                                    'option_text', o.option_text,
                                    'sort_order', o.sort_order
                                ) ORDER BY o.sort_order
                            )
                            FROM public.assessment_question_options o
                            WHERE o.question_id = q.id
                        )
                    ) ORDER BY q.sort_order
                )
                FROM public.assessment_questions q
                WHERE q.assessment_section_id = s.id
            )
        ) ORDER BY s.sort_order
    ) INTO v_sections
    FROM public.assessment_sections s
    WHERE s.assessment_template_id = v_template.id;

    RETURN jsonb_build_object(
        'attempt_id', v_attempt_id,
        'invitation_id', v_inv.id,
        'candidate_id', v_inv.candidate_id,
        'assessment_name', v_template.name,
        'assessment_type', v_template.assessment_type,
        'version', v_template.version,
        'time_limit_minutes', v_template.time_limit_minutes,
        'sections', COALESCE(v_sections, '[]'::jsonb)
    );
END;
$$;

-- 18.3 Submit Candidate Assessment Attempt
CREATE OR REPLACE FUNCTION public.submit_assessment_attempt(
    p_attempt_id UUID,
    p_answers JSONB,
    p_time_spent_seconds INT DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_attempt RECORD;
    v_item JSONB;
    v_qid UUID;
    v_options UUID[];
    v_result_id UUID;
BEGIN
    SELECT * INTO v_attempt FROM public.assessment_attempts WHERE id = p_attempt_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment attempt % not found', p_attempt_id;
    END IF;

    IF v_attempt.status NOT IN ('in_progress') THEN
        RAISE EXCEPTION 'Assessment attempt is % and cannot be submitted', v_attempt.status;
    END IF;

    -- Record answers
    IF p_answers IS NOT NULL AND jsonb_array_length(p_answers) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
            v_qid := (v_item->>'question_id')::UUID;
            
            -- Parse selected options array if provided
            IF v_item ? 'selected_options' AND jsonb_typeof(v_item->'selected_options') = 'array' THEN
                SELECT array_agg(value::text::uuid) INTO v_options
                FROM jsonb_array_elements_text(v_item->'selected_options');
            ELSE
                v_options := '{}'::uuid[];
            END IF;

            INSERT INTO public.assessment_answers (
                assessment_attempt_id, question_id, answer_text, selected_options,
                numeric_answer, file_path, audio_file_path, video_file_path, submitted_at
            )
            VALUES (
                p_attempt_id,
                v_qid,
                v_item->>'answer_text',
                v_options,
                (v_item->>'numeric_answer')::NUMERIC,
                v_item->>'file_path',
                v_item->>'audio_file_path',
                v_item->>'video_file_path',
                now()
            )
            ON CONFLICT (assessment_attempt_id, question_id) DO UPDATE
            SET answer_text = EXCLUDED.answer_text,
                selected_options = EXCLUDED.selected_options,
                numeric_answer = EXCLUDED.numeric_answer,
                file_path = EXCLUDED.file_path,
                audio_file_path = EXCLUDED.audio_file_path,
                video_file_path = EXCLUDED.video_file_path,
                updated_at = now();
        END LOOP;
    END IF;

    UPDATE public.assessment_attempts
    SET status = 'submitted',
        submitted_at = now(),
        time_spent_seconds = p_time_spent_seconds,
        updated_at = now()
    WHERE id = p_attempt_id;

    -- Automatically execute deterministic scoring
    v_result_id := public.score_assessment_attempt(p_attempt_id);

    RETURN v_result_id;
END;
$$;

-- 18.4 Deterministic & Configurable Scoring Engine
CREATE OR REPLACE FUNCTION public.score_assessment_attempt(p_attempt_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_attempt RECORD;
    v_inv RECORD;
    v_template RECORD;
    r_sec RECORD;
    r_q RECORD;
    r_ans RECORD;
    v_result_id UUID;
    v_q_score NUMERIC(5,2);
    v_sec_earned NUMERIC(8,2);
    v_sec_max NUMERIC(8,2);
    v_sec_norm NUMERIC(5,2);
    v_total_weighted_earned NUMERIC(8,2) := 0;
    v_total_weights NUMERIC(8,2) := 0;
    v_final_score NUMERIC(5,2);
    v_passed BOOLEAN;
    v_cefr VARCHAR(10) := NULL;
    v_correct_opts UUID[];
    v_has_manual_review BOOLEAN := false;
BEGIN
    SELECT * INTO v_attempt FROM public.assessment_attempts WHERE id = p_attempt_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment attempt % not found', p_attempt_id;
    END IF;

    SELECT * INTO v_inv FROM public.assessment_invitations WHERE id = v_attempt.assessment_invitation_id;
    SELECT * INTO v_template FROM public.assessment_templates WHERE id = v_inv.assessment_template_id;

    -- Create or reset assessment_results
    INSERT INTO public.assessment_results (
        assessment_attempt_id, candidate_id, application_id, assessment_template_id,
        assessment_version, total_score, normalized_score, passed, evaluation_method, evaluation_status
    )
    VALUES (
        v_attempt.id, v_attempt.candidate_id, v_inv.application_id, v_template.id,
        v_template.version, 0.00, 0.00, false, 'automatic', 'scored'
    )
    RETURNING id INTO v_result_id;

    -- Score sections
    FOR r_sec IN
        SELECT * FROM public.assessment_sections
        WHERE assessment_template_id = v_template.id
        ORDER BY sort_order
    LOOP
        v_sec_earned := 0;
        v_sec_max := 0;

        FOR r_q IN
            SELECT * FROM public.assessment_questions
            WHERE assessment_section_id = r_sec.id
            ORDER BY sort_order
        LOOP
            v_q_score := 0;
            v_sec_max := v_sec_max + r_q.points;

            SELECT * INTO r_ans FROM public.assessment_answers
            WHERE assessment_attempt_id = v_attempt.id AND question_id = r_q.id;

            IF FOUND THEN
                CASE r_q.question_type
                    WHEN 'single_choice', 'true_false' THEN
                        SELECT array_agg(id) INTO v_correct_opts
                        FROM public.assessment_question_options
                        WHERE question_id = r_q.id AND is_correct = true;

                        IF r_ans.selected_options IS NOT NULL 
                           AND array_length(r_ans.selected_options, 1) = 1
                           AND r_ans.selected_options[1] = ANY(v_correct_opts) THEN
                            v_q_score := r_q.points;
                        ELSE
                            v_q_score := 0;
                        END IF;

                    WHEN 'multiple_choice' THEN
                        SELECT array_agg(id ORDER BY id) INTO v_correct_opts
                        FROM public.assessment_question_options
                        WHERE question_id = r_q.id AND is_correct = true;

                        IF r_ans.selected_options IS NOT NULL 
                           AND (SELECT array_agg(elem ORDER BY elem) FROM unnest(r_ans.selected_options) elem) = v_correct_opts THEN
                            v_q_score := r_q.points;
                        ELSE
                            v_q_score := 0;
                        END IF;

                    WHEN 'number' THEN
                        IF r_q.correct_answer IS NOT NULL AND r_ans.numeric_answer = (r_q.correct_answer)::NUMERIC THEN
                            v_q_score := r_q.points;
                        ELSE
                            v_q_score := 0;
                        END IF;

                    WHEN 'text', 'translation' THEN
                        IF r_q.correct_answer IS NOT NULL AND lower(trim(r_ans.answer_text)) = lower(trim(r_q.correct_answer)) THEN
                            v_q_score := r_q.points;
                        ELSE
                            -- Open-ended or pending review
                            v_q_score := 0;
                            v_has_manual_review := true;
                        END IF;

                    WHEN 'audio_response', 'video_response' THEN
                        -- Audio/voice responses require AI or human evaluation
                        v_q_score := 0;
                        v_has_manual_review := true;

                    ELSE
                        v_q_score := 0;
                END CASE;
            END IF;

            v_sec_earned := v_sec_earned + v_q_score;

            -- Record question result
            INSERT INTO public.assessment_question_results (
                assessment_result_id, question_id, raw_score, max_score, normalized_score, evaluation_method
            )
            VALUES (
                v_result_id, r_q.id, v_q_score, r_q.points,
                CASE WHEN r_q.points > 0 THEN round((v_q_score / r_q.points) * 100, 2) ELSE 0 END,
                'automatic'
            );
        END LOOP;

        IF v_sec_max > 0 THEN
            v_sec_norm := round((v_sec_earned / v_sec_max) * 100, 2);
        ELSE
            v_sec_norm := 0;
        END IF;

        -- Record section result
        INSERT INTO public.assessment_section_results (
            assessment_result_id, assessment_section_id, score, max_score, normalized_score, weight, status
        )
        VALUES (
            v_result_id, r_sec.id, v_sec_earned, v_sec_max, v_sec_norm, r_sec.weight,
            CASE WHEN v_sec_norm >= COALESCE(v_template.passing_score, 70) THEN 'passed' ELSE 'failed' END
        );

        v_total_weighted_earned := v_total_weighted_earned + (v_sec_norm * r_sec.weight);
        v_total_weights := v_total_weights + r_sec.weight;
    END LOOP;

    IF v_total_weights > 0 THEN
        v_final_score := round(v_total_weighted_earned / v_total_weights, 2);
    ELSE
        v_final_score := 0;
    END IF;

    v_passed := (v_final_score >= COALESCE(v_template.passing_score, 70));

    -- Assign CEFR if language assessment
    IF v_template.assessment_type = 'language' THEN
        IF v_final_score >= 90 THEN v_cefr := 'c2';
        ELSIF v_final_score >= 80 THEN v_cefr := 'c1';
        ELSIF v_final_score >= 65 THEN v_cefr := 'b2';
        ELSIF v_final_score >= 50 THEN v_cefr := 'b1';
        ELSIF v_final_score >= 35 THEN v_cefr := 'a2';
        ELSE v_cefr := 'a1';
        END IF;
    END IF;

    -- Update assessment_results
    UPDATE public.assessment_results
    SET total_score = v_final_score,
        normalized_score = v_final_score,
        passed = v_passed,
        cefr_level = v_cefr,
        evaluation_status = CASE WHEN v_has_manual_review THEN 'needs_review' ELSE 'finalized' END,
        result_summary = 'Assessment completed with score ' || v_final_score || '%' || CASE WHEN v_cefr IS NOT NULL THEN ' (CEFR: ' || upper(v_cefr) || ')' ELSE '' END,
        updated_at = now()
    WHERE id = v_result_id;

    -- Update attempt
    UPDATE public.assessment_attempts
    SET score = v_final_score,
        passing_score = v_template.passing_score,
        passed = v_passed,
        status = 'completed',
        evaluation_status = CASE WHEN v_has_manual_review THEN 'needs_human_review' ELSE 'completed' END,
        updated_at = now()
    WHERE id = v_attempt.id;

    -- Update invitation
    UPDATE public.assessment_invitations
    SET status = 'completed', completed_at = now(), updated_at = now()
    WHERE id = v_inv.id;

    -- Recalculate Candidate Readiness
    PERFORM public.calculate_candidate_readiness(v_attempt.candidate_id, v_inv.job_id);

    RETURN v_result_id;
END;
$$;

-- 18.5 Record Voice Evaluation (Speech, Fluency, Clarity)
CREATE OR REPLACE FUNCTION public.record_voice_evaluation(
    p_answer_id UUID,
    p_transcription TEXT,
    p_fluency NUMERIC,
    p_pronunciation NUMERIC,
    p_clarity NUMERIC,
    p_confidence NUMERIC DEFAULT 0.95,
    p_provider TEXT DEFAULT 'internal_voice_evaluator',
    p_model TEXT DEFAULT 'whisper-eval-v1',
    p_version TEXT DEFAULT 'v1.0'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ans RECORD;
    v_voice_id UUID;
    v_overall NUMERIC(5,2);
    v_status VARCHAR(50) := 'completed';
    v_org_id UUID;
    v_cand_id UUID;
    v_job_id UUID;
    v_app_id UUID;
BEGIN
    -- Validate numeric ranges
    IF p_fluency < 0 OR p_fluency > 100 OR p_pronunciation < 0 OR p_pronunciation > 100 OR p_clarity < 0 OR p_clarity > 100 THEN
        RAISE EXCEPTION 'Voice evaluation scores must be between 0 and 100';
    END IF;

    IF p_confidence < 0 OR p_confidence > 1 THEN
        RAISE EXCEPTION 'Confidence score must be between 0.0 and 1.0';
    END IF;

    SELECT a.*, att.candidate_id, inv.job_id, inv.application_id, j.organization_id
    INTO v_ans
    FROM public.assessment_answers a
    JOIN public.assessment_attempts att ON att.id = a.assessment_attempt_id
    JOIN public.assessment_invitations inv ON inv.id = att.assessment_invitation_id
    LEFT JOIN public.jobs j ON j.id = inv.job_id
    WHERE a.id = p_answer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment answer % not found', p_answer_id;
    END IF;

    v_overall := round((p_fluency + p_pronunciation + p_clarity) / 3.0, 2);

    IF p_confidence < 0.70 THEN
        v_status := 'needs_review';
    END IF;

    INSERT INTO public.voice_assessment_results (
        assessment_answer_id, transcription, fluency_score, pronunciation_score,
        clarity_score, confidence_score, overall_score, evaluation_provider,
        model_name, analysis_version, status
    )
    VALUES (
        p_answer_id, p_transcription, p_fluency, p_pronunciation,
        p_clarity, p_confidence, v_overall, p_provider,
        p_model, p_version, v_status
    )
    RETURNING id INTO v_voice_id;

    -- If low confidence or needs review, bridge to recruiter_review_queue
    IF v_status = 'needs_review' AND v_ans.organization_id IS NOT NULL THEN
        INSERT INTO public.recruiter_review_queue (
            organization_id, candidate_id, job_id, application_id,
            reason, priority, status
        )
        VALUES (
            v_ans.organization_id, v_ans.candidate_id, v_ans.job_id, v_ans.application_id,
            'Low confidence voice evaluation (' || round(p_confidence * 100) || '% confidence)', 'high', 'pending'
        );
    END IF;

    RETURN v_voice_id;
END;
$$;

-- 18.6 Human Review Override (Preserving Original AI Evaluation)
CREATE OR REPLACE FUNCTION public.override_assessment_review(
    p_result_id UUID,
    p_new_score NUMERIC,
    p_decision TEXT,
    p_notes TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_res RECORD;
    v_template RECORD;
    v_review_id UUID;
    v_passed BOOLEAN;
BEGIN
    SELECT * INTO v_res FROM public.assessment_results WHERE id = p_result_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assessment result % not found', p_result_id;
    END IF;

    SELECT * INTO v_template FROM public.assessment_templates WHERE id = v_res.assessment_template_id;

    IF p_new_score < 0 OR p_new_score > 100 THEN
        RAISE EXCEPTION 'Override score must be between 0 and 100';
    END IF;

    IF p_decision NOT IN ('approved', 'rejected', 'needs_more_evidence') THEN
        RAISE EXCEPTION 'Invalid final decision: %', p_decision;
    END IF;

    v_passed := (p_new_score >= COALESCE(v_template.passing_score, 70));

    -- Insert into assessment_reviews preserving original score
    INSERT INTO public.assessment_reviews (
        assessment_result_id, reviewer_id, review_status, original_ai_score,
        original_ai_feedback, score_override, reviewer_feedback, final_decision,
        review_notes, reviewed_at
    )
    VALUES (
        p_result_id, auth.uid(), 'completed', v_res.total_score,
        v_res.result_summary, p_new_score, p_notes, p_decision,
        p_notes, now()
    )
    RETURNING id INTO v_review_id;

    -- Update assessment_results with provenance = 'hybrid'
    UPDATE public.assessment_results
    SET total_score = p_new_score,
        normalized_score = p_new_score,
        passed = v_passed,
        evaluation_method = 'hybrid',
        evaluation_status = 'finalized',
        result_summary = 'Human reviewed (' || p_decision || ') with score ' || p_new_score || '%',
        updated_at = now()
    WHERE id = p_result_id;

    -- Recalculate Candidate Readiness
    PERFORM public.calculate_candidate_readiness(v_res.candidate_id, NULL);

    RETURN v_review_id;
END;
$$;

-- 18.7 Candidate Readiness Calculation Engine
CREATE OR REPLACE FUNCTION public.calculate_candidate_readiness(
    p_candidate_id UUID,
    p_job_id UUID DEFAULT NULL
)
RETURNS TABLE (
    readiness_status VARCHAR(50),
    readiness_score NUMERIC(5,2),
    required_assessments INT,
    completed_assessments INT,
    passed_assessments INT,
    failed_assessments INT,
    needs_review_count INT,
    blocking_reasons TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req_count INT := 0;
    v_comp_count INT := 0;
    v_pass_count INT := 0;
    v_fail_count INT := 0;
    v_rev_count INT := 0;
    v_status VARCHAR(50) := 'not_started';
    v_score NUMERIC(5,2) := 0;
    v_reasons TEXT[] := '{}'::text[];
    v_summary TEXT;
    v_cand_summary TEXT;
    r_ja RECORD;
    v_latest_res RECORD;
BEGIN
    -- If job specified, inspect required job assessments
    IF p_job_id IS NOT NULL THEN
        FOR r_ja IN
            SELECT ja.*, at.name AS template_name
            FROM public.job_assessments ja
            JOIN public.assessment_templates at ON at.id = ja.assessment_template_id
            WHERE ja.job_id = p_job_id AND ja.required = true
        LOOP
            v_req_count := v_req_count + 1;

            -- Find latest result for this candidate and template
            SELECT ar.* INTO v_latest_res
            FROM public.assessment_results ar
            JOIN public.assessment_attempts att ON att.id = ar.assessment_attempt_id
            JOIN public.assessment_invitations inv ON inv.id = att.assessment_invitation_id
            WHERE ar.candidate_id = p_candidate_id
              AND ar.assessment_template_id = r_ja.assessment_template_id
            ORDER BY ar.created_at DESC
            LIMIT 1;

            IF FOUND THEN
                v_comp_count := v_comp_count + 1;
                IF v_latest_res.passed THEN
                    v_pass_count := v_pass_count + 1;
                ELSE
                    v_fail_count := v_fail_count + 1;
                    v_reasons := array_append(v_reasons, 'Required assessment failed: ' || r_ja.template_name);
                END IF;

                IF v_latest_res.evaluation_status = 'needs_review' THEN
                    v_rev_count := v_rev_count + 1;
                    v_reasons := array_append(v_reasons, 'Human review pending: ' || r_ja.template_name);
                END IF;
            ELSE
                v_reasons := array_append(v_reasons, 'Required assessment pending: ' || r_ja.template_name);
            END IF;
        END LOOP;

        IF v_req_count = 0 THEN
            v_status := 'ready';
            v_score := 100.00;
            v_summary := 'No assessments required for this requisition';
            v_cand_summary := 'Profile ready for consideration';
        ELSIF v_fail_count > 0 THEN
            v_status := 'blocked';
            v_score := round((v_pass_count::NUMERIC / v_req_count::NUMERIC) * 100, 2);
            v_summary := 'Candidate blocked due to failed required assessments';
            v_cand_summary := 'Assessment criteria not met';
        ELSIF v_comp_count < v_req_count THEN
            v_status := 'in_progress';
            v_score := round((v_pass_count::NUMERIC / v_req_count::NUMERIC) * 100, 2);
            v_summary := 'Candidate has pending required assessments';
            v_cand_summary := 'Assessments in progress';
        ELSIF v_rev_count > 0 THEN
            v_status := 'ready_with_review';
            v_score := round((v_pass_count::NUMERIC / v_req_count::NUMERIC) * 100, 2);
            v_summary := 'Candidate completed assessments but requires human review';
            v_cand_summary := 'Assessments completed; evaluation under review';
        ELSE
            v_status := 'ready';
            v_score := 100.00;
            v_summary := 'All required assessments completed and passed';
            v_cand_summary := 'Assessment stage completed successfully';
        END IF;

    ELSE
        -- General candidate readiness across all completed assessments
        SELECT COUNT(*), 
               COUNT(*) FILTER (WHERE ar.passed = true),
               COUNT(*) FILTER (WHERE ar.passed = false),
               COUNT(*) FILTER (WHERE ar.evaluation_status = 'needs_review')
        INTO v_comp_count, v_pass_count, v_fail_count, v_rev_count
        FROM public.assessment_results ar
        WHERE ar.candidate_id = p_candidate_id;

        IF v_comp_count = 0 THEN
            v_status := 'not_started';
            v_score := 0;
            v_summary := 'No assessments taken';
            v_cand_summary := 'No assessments recorded';
        ELSIF v_rev_count > 0 THEN
            v_status := 'ready_with_review';
            v_score := round((v_pass_count::NUMERIC / v_comp_count::NUMERIC) * 100, 2);
            v_summary := 'Candidate assessments under review';
            v_cand_summary := 'Assessments under review';
        ELSE
            v_status := 'ready';
            v_score := round((v_pass_count::NUMERIC / v_comp_count::NUMERIC) * 100, 2);
            v_summary := 'Candidate assessments evaluated';
            v_cand_summary := 'Assessments completed';
        END IF;
    END IF;

    -- Upsert candidate_readiness using IF EXISTS
    IF EXISTS (
        SELECT 1 FROM public.candidate_readiness
        WHERE candidate_id = p_candidate_id
          AND (job_id = p_job_id OR (job_id IS NULL AND p_job_id IS NULL))
    ) THEN
        UPDATE public.candidate_readiness
        SET readiness_status = v_status,
            readiness_score = v_score,
            required_assessments = v_req_count,
            completed_assessments = v_comp_count,
            passed_assessments = v_pass_count,
            failed_assessments = v_fail_count,
            needs_review_count = v_rev_count,
            blocking_reasons = v_reasons,
            summary = v_summary,
            candidate_facing_summary = v_cand_summary,
            calculated_at = now(),
            updated_at = now()
        WHERE candidate_id = p_candidate_id
          AND (job_id = p_job_id OR (job_id IS NULL AND p_job_id IS NULL));
    ELSE
        INSERT INTO public.candidate_readiness (
            candidate_id, job_id, readiness_status, readiness_score,
            required_assessments, completed_assessments, passed_assessments,
            failed_assessments, needs_review_count, blocking_reasons,
            summary, candidate_facing_summary, calculated_at
        )
        VALUES (
            p_candidate_id, p_job_id, v_status, v_score,
            v_req_count, v_comp_count, v_pass_count,
            v_fail_count, v_rev_count, v_reasons,
            v_summary, v_cand_summary, now()
        );
    END IF;

    RETURN QUERY SELECT v_status, v_score, v_req_count, v_comp_count, v_pass_count, v_fail_count, v_rev_count, v_reasons;
END;
$$;

-- 18.8 Candidate Assessment Progress
CREATE OR REPLACE FUNCTION public.get_candidate_assessment_progress(
    p_candidate_id UUID,
    p_job_id UUID DEFAULT NULL
)
RETURNS TABLE (
    assessment_id UUID,
    assessment_name VARCHAR(255),
    assessment_type VARCHAR(50),
    invitation_status VARCHAR(50),
    attempt_status VARCHAR(50),
    score NUMERIC(5,2),
    passed BOOLEAN,
    readiness_status VARCHAR(50),
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        at.id AS assessment_id,
        at.name AS assessment_name,
        at.assessment_type,
        ai.status AS invitation_status,
        att.status AS attempt_status,
        att.score,
        att.passed,
        COALESCE(cr.readiness_status, 'not_started') AS readiness_status,
        ai.expires_at
    FROM public.assessment_invitations ai
    JOIN public.assessment_templates at ON at.id = ai.assessment_template_id
    LEFT JOIN public.assessment_attempts att ON att.assessment_invitation_id = ai.id
    LEFT JOIN public.candidate_readiness cr ON cr.candidate_id = ai.candidate_id AND (cr.job_id = ai.job_id OR (cr.job_id IS NULL AND ai.job_id IS NULL))
    WHERE ai.candidate_id = p_candidate_id
      AND (p_job_id IS NULL OR ai.job_id = p_job_id);
END;
$$;

-- 18.9 Recruiter Assessment Dashboard
CREATE OR REPLACE FUNCTION public.get_recruiter_assessment_dashboard(
    p_org_id UUID,
    p_job_id UUID DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    invitation_id UUID,
    candidate_id UUID,
    candidate_name TEXT,
    job_title TEXT,
    assessment_name VARCHAR(255),
    assessment_type VARCHAR(50),
    invitation_status VARCHAR(50),
    attempt_status VARCHAR(50),
    score NUMERIC(5,2),
    passed BOOLEAN,
    evaluation_status VARCHAR(50),
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.check_user_is_recruiter(p_org_id) THEN
        RAISE EXCEPTION 'Access denied: user is not an authorized recruiter for organization %', p_org_id;
    END IF;

    RETURN QUERY
    SELECT 
        ai.id AS invitation_id,
        c.id AS candidate_id,
        p.full_name AS candidate_name,
        j.title AS job_title,
        at.name AS assessment_name,
        at.assessment_type,
        ai.status AS invitation_status,
        att.status AS attempt_status,
        att.score,
        att.passed,
        att.evaluation_status,
        ai.created_at
    FROM public.assessment_invitations ai
    JOIN public.candidates c ON c.id = ai.candidate_id
    JOIN public.profiles p ON p.id = c.user_id
    JOIN public.jobs j ON j.id = ai.job_id
    JOIN public.assessment_templates at ON at.id = ai.assessment_template_id
    LEFT JOIN public.assessment_attempts att ON att.assessment_invitation_id = ai.id
    WHERE j.organization_id = p_org_id
      AND (p_job_id IS NULL OR ai.job_id = p_job_id)
      AND (p_status IS NULL OR ai.status = p_status)
    ORDER BY ai.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;
