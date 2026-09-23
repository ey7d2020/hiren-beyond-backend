-- =============================================================================
-- Migration: 20260915000600_cv_intelligence.sql
-- Description: CV Processing, AI CV Analysis & Structured Candidate Intelligence
-- Author: Hiren Beyond Engineering
-- Schema: cv_processing_jobs, cv_extracted_content, cv_processing_metadata,
--         candidate_cv_profiles, candidate_cv_ai_analysis, candidate_cv_review_items
--         + provenance columns on existing candidate sub-tables
--         + candidate_intelligence_summary view
-- =============================================================================

-- =============================================================================
-- 1. PERMISSIONS — CV INTELLIGENCE OPERATIONS
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('cv.process',             'Process CV',                    'Trigger CV text extraction and AI analysis pipeline', 'cv'),
    ('cv.view_extracted',      'View Extracted CV Content',     'Read raw extracted text and metadata from candidate CVs', 'cv'),
    ('cv.view_analysis',       'View CV AI Analysis',           'Read AI-generated CV analysis and structured intelligence', 'cv'),
    ('cv.review',              'Review CV Extractions',         'Approve, correct or reject AI-extracted candidate fields', 'cv'),
    ('cv.reprocess',           'Reprocess CV',                  'Trigger reprocessing of a previously analysed CV', 'cv'),
    ('candidates.read',        'Read Candidate Profiles',       'View candidate profile data within authorized scope', 'candidates'),
    ('candidates.manage',      'Manage Candidate Profiles',     'Edit candidate profile data within authorized scope', 'candidates')
ON CONFLICT (key) DO UPDATE
SET name        = EXCLUDED.name,
    description = EXCLUDED.description,
    category    = EXCLUDED.category;

WITH new_mappings (role_key, perm_key) AS (
    VALUES
        ('platform_admin',      'cv.process'),
        ('platform_admin',      'cv.view_extracted'),
        ('platform_admin',      'cv.view_analysis'),
        ('platform_admin',      'cv.review'),
        ('platform_admin',      'cv.reprocess'),
        ('platform_admin',      'candidates.read'),
        ('platform_admin',      'candidates.manage'),
        ('platform_operations', 'cv.process'),
        ('platform_operations', 'cv.view_extracted'),
        ('platform_operations', 'cv.view_analysis'),
        ('platform_operations', 'cv.review'),
        ('platform_operations', 'cv.reprocess'),
        ('platform_operations', 'candidates.read'),
        ('recruiter_manager',   'cv.view_analysis'),
        ('recruiter_manager',   'cv.review'),
        ('recruiter_manager',   'candidates.read'),
        ('recruiter',           'cv.view_analysis'),
        ('recruiter',           'candidates.read'),
        ('candidate',           'candidates.read'),
        ('candidate',           'candidates.manage')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings m
JOIN public.roles r ON r.key = m.role_key
JOIN public.permissions p ON p.key = m.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. EXTEND EXISTING CANDIDATE SUB-TABLES WITH PROVENANCE & CONFIDENCE
--    Only add columns that do not already exist.
-- =============================================================================

-- candidate_skills: add source_document_id, confidence, verification_status
ALTER TABLE public.candidate_skills
    ADD COLUMN IF NOT EXISTS source_document_id      UUID        REFERENCES public.candidate_documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    ADD COLUMN IF NOT EXISTS verification_status     TEXT        NOT NULL DEFAULT 'unverified'
        CHECK (verification_status IN ('unverified','ai_extracted','human_verified','rejected'));

CREATE INDEX IF NOT EXISTS idx_candidate_skills_verif_status
    ON public.candidate_skills(verification_status);
CREATE INDEX IF NOT EXISTS idx_candidate_skills_source_doc
    ON public.candidate_skills(source_document_id);

-- candidate_languages: add source_document_id, confidence, verification_status
ALTER TABLE public.candidate_languages
    ADD COLUMN IF NOT EXISTS source_document_id      UUID        REFERENCES public.candidate_documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    ADD COLUMN IF NOT EXISTS verification_status     TEXT        NOT NULL DEFAULT 'unverified'
        CHECK (verification_status IN ('unverified','ai_extracted','human_verified','rejected'));

CREATE INDEX IF NOT EXISTS idx_candidate_lang_verif_status
    ON public.candidate_languages(verification_status);

-- candidate_experience: add source, source_document_id, confidence, verification_status
ALTER TABLE public.candidate_experience
    ADD COLUMN IF NOT EXISTS source                  TEXT        NOT NULL DEFAULT 'candidate'
        CHECK (source IN ('candidate','cv_extraction','recruiter','ai_suggestion')),
    ADD COLUMN IF NOT EXISTS source_document_id      UUID        REFERENCES public.candidate_documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    ADD COLUMN IF NOT EXISTS verification_status     TEXT        NOT NULL DEFAULT 'unverified'
        CHECK (verification_status IN ('unverified','ai_extracted','human_verified','rejected')),
    ADD COLUMN IF NOT EXISTS industry                TEXT,
    ADD COLUMN IF NOT EXISTS responsibilities        TEXT[],
    ADD COLUMN IF NOT EXISTS extracted_achievements  TEXT[];

CREATE INDEX IF NOT EXISTS idx_candidate_exp_source
    ON public.candidate_experience(source);
CREATE INDEX IF NOT EXISTS idx_candidate_exp_verif_status
    ON public.candidate_experience(verification_status);

-- candidate_education: add source, source_document_id, confidence, verification_status, education_level
ALTER TABLE public.candidate_education
    ADD COLUMN IF NOT EXISTS source                  TEXT        NOT NULL DEFAULT 'candidate'
        CHECK (source IN ('candidate','cv_extraction','recruiter','ai_suggestion')),
    ADD COLUMN IF NOT EXISTS source_document_id      UUID        REFERENCES public.candidate_documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    ADD COLUMN IF NOT EXISTS verification_status     TEXT        NOT NULL DEFAULT 'unverified'
        CHECK (verification_status IN ('unverified','ai_extracted','human_verified','rejected')),
    ADD COLUMN IF NOT EXISTS education_level         TEXT
        CHECK (education_level IS NULL OR education_level IN (
            'high_school','associate','bachelor','master','doctorate','professional','certificate','other'
        ));

CREATE INDEX IF NOT EXISTS idx_candidate_edu_level
    ON public.candidate_education(education_level);
CREATE INDEX IF NOT EXISTS idx_candidate_edu_verif_status
    ON public.candidate_education(verification_status);

-- candidate_certifications: add source, source_document_id, confidence, verification_status
ALTER TABLE public.candidate_certifications
    ADD COLUMN IF NOT EXISTS source                  TEXT        NOT NULL DEFAULT 'candidate'
        CHECK (source IN ('candidate','cv_extraction','recruiter','ai_suggestion')),
    ADD COLUMN IF NOT EXISTS source_document_id      UUID        REFERENCES public.candidate_documents(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    ADD COLUMN IF NOT EXISTS verification_status     TEXT        NOT NULL DEFAULT 'unverified'
        CHECK (verification_status IN ('unverified','ai_extracted','human_verified','rejected'));

CREATE INDEX IF NOT EXISTS idx_candidate_cert_verif_status
    ON public.candidate_certifications(verification_status);

-- =============================================================================
-- 3. CV_PROCESSING_JOBS — PIPELINE STATE MACHINE
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.cv_processing_jobs (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    candidate_document_id   UUID        NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    status                  TEXT        NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','processing','completed','failed','needs_review')),
    processing_type         TEXT        NOT NULL DEFAULT 'full_pipeline'
        CHECK (processing_type IN (
            'text_extraction','structured_extraction','ai_analysis','full_pipeline'
        )),
    attempt_count           INTEGER     NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    max_attempts            INTEGER     NOT NULL DEFAULT 3  CHECK (max_attempts >= 1),
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    failed_at               TIMESTAMPTZ,
    next_retry_at           TIMESTAMPTZ,
    error_code              TEXT,
    error_message           TEXT,
    -- Provider info (no secrets stored here — just identifiers)
    provider                TEXT,
    provider_version        TEXT,
    -- Stage tracking as the job moves through the pipeline
    pipeline_stage          TEXT        NOT NULL DEFAULT 'upload'
        CHECK (pipeline_stage IN (
            'upload','document_validation','text_extraction',
            'text_quality_check','structured_extraction',
            'data_validation','ai_analysis','save_results',
            'update_candidate_intelligence','done'
        )),
    stage_metadata          JSONB       NOT NULL DEFAULT '{}'::JSONB,
    -- Idempotency key: doc_id + processing_type + attempt
    idempotency_key         TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_cv_job_idempotency UNIQUE (idempotency_key),
    CONSTRAINT chk_cv_job_attempt_limit CHECK (attempt_count <= max_attempts),
    CONSTRAINT chk_cv_job_completed_has_time
        CHECK (status != 'completed' OR completed_at IS NOT NULL),
    CONSTRAINT chk_cv_job_failed_has_time
        CHECK (status != 'failed' OR failed_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_cv_jobs_candidate     ON public.cv_processing_jobs(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cv_jobs_document      ON public.cv_processing_jobs(candidate_document_id);
CREATE INDEX IF NOT EXISTS idx_cv_jobs_status        ON public.cv_processing_jobs(status);
CREATE INDEX IF NOT EXISTS idx_cv_jobs_type          ON public.cv_processing_jobs(processing_type);
CREATE INDEX IF NOT EXISTS idx_cv_jobs_created       ON public.cv_processing_jobs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cv_jobs_next_retry    ON public.cv_processing_jobs(next_retry_at) WHERE status = 'failed';
CREATE INDEX IF NOT EXISTS idx_cv_jobs_queued        ON public.cv_processing_jobs(created_at) WHERE status = 'queued';

CREATE TRIGGER trg_cv_jobs_updated_at
    BEFORE UPDATE ON public.cv_processing_jobs
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. CV_EXTRACTED_CONTENT — RAW TEXT EXTRACTED FROM CV DOCUMENT
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.cv_extracted_content (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_document_id   UUID        NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    processing_job_id       UUID        REFERENCES public.cv_processing_jobs(id) ON DELETE SET NULL,
    extracted_text          TEXT        NOT NULL,
    language                VARCHAR(20),             -- BCP-47 language code e.g. 'en', 'ar', 'fr'
    page_count              INTEGER     CHECK (page_count IS NULL OR page_count > 0),
    character_count         INTEGER     CHECK (character_count IS NULL OR character_count >= 0),
    word_count              INTEGER     CHECK (word_count IS NULL OR word_count >= 0),
    extraction_method       TEXT        NOT NULL DEFAULT 'pdf_text'
        CHECK (extraction_method IN ('pdf_text','docx_text','ocr','manual','other')),
    extraction_version      TEXT,        -- e.g. "pdfjs-4.2.1" or "tesseract-5.3"
    extracted_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- A document can have multiple extraction versions; latest is determined by extracted_at
    CONSTRAINT uq_cv_extracted_doc_version UNIQUE (candidate_document_id, extraction_version)
);

CREATE INDEX IF NOT EXISTS idx_cv_extracted_doc      ON public.cv_extracted_content(candidate_document_id);
CREATE INDEX IF NOT EXISTS idx_cv_extracted_cand     ON public.cv_extracted_content(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cv_extracted_job      ON public.cv_extracted_content(processing_job_id);
CREATE INDEX IF NOT EXISTS idx_cv_extracted_method   ON public.cv_extracted_content(extraction_method);
CREATE INDEX IF NOT EXISTS idx_cv_extracted_at       ON public.cv_extracted_content(extracted_at DESC);

CREATE TRIGGER trg_cv_extracted_updated_at
    BEFORE UPDATE ON public.cv_extracted_content
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 5. CV_PROCESSING_METADATA — DOCUMENT QUALITY & STRUCTURAL METADATA
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.cv_processing_metadata (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_document_id   UUID        NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    processing_job_id       UUID        REFERENCES public.cv_processing_jobs(id) ON DELETE SET NULL,
    mime_type               TEXT,
    file_size               BIGINT      CHECK (file_size IS NULL OR file_size > 0),
    checksum                TEXT,        -- SHA-256 hex of original file for dedup/integrity
    page_count              INTEGER     CHECK (page_count IS NULL OR page_count > 0),
    detected_language       VARCHAR(20),
    -- Quality scoring 0.0–1.0
    quality_score           NUMERIC(4,3)
        CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
    is_machine_readable     BOOLEAN,
    requires_ocr            BOOLEAN     NOT NULL DEFAULT false,
    -- Structural warnings as JSONB array of warning codes
    warnings                JSONB       NOT NULL DEFAULT '[]'::JSONB,
    -- e.g. ["low_text_content","scanned_document","poor_formatting",
    --        "multiple_columns","unsupported_structure","missing_contact_section"]
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_cv_metadata_doc UNIQUE (candidate_document_id, processing_job_id)
);

CREATE INDEX IF NOT EXISTS idx_cv_metadata_doc       ON public.cv_processing_metadata(candidate_document_id);
CREATE INDEX IF NOT EXISTS idx_cv_metadata_cand      ON public.cv_processing_metadata(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cv_metadata_quality   ON public.cv_processing_metadata(quality_score);
CREATE INDEX IF NOT EXISTS idx_cv_metadata_readable  ON public.cv_processing_metadata(is_machine_readable);
CREATE INDEX IF NOT EXISTS idx_cv_metadata_ocr       ON public.cv_processing_metadata(requires_ocr);

CREATE TRIGGER trg_cv_metadata_updated_at
    BEFORE UPDATE ON public.cv_processing_metadata
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 6. CANDIDATE_CV_PROFILES — VERSIONED STRUCTURED SNAPSHOT OF CV CONTENT
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.candidate_cv_profiles (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    candidate_document_id   UUID        NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    processing_job_id       UUID        REFERENCES public.cv_processing_jobs(id) ON DELETE SET NULL,
    -- Version: incremented each time the same document is reprocessed
    version                 INTEGER     NOT NULL DEFAULT 1 CHECK (version >= 1),
    -- Extracted contact / identity fields
    full_name               TEXT,
    headline                TEXT,
    summary                 TEXT,
    location                TEXT,
    country                 TEXT,
    city                    TEXT,
    email                   TEXT,
    phone                   TEXT,
    linkedin_url            TEXT,
    portfolio_url           TEXT,
    -- Structured intelligence
    years_of_experience     NUMERIC(4,1) CHECK (years_of_experience IS NULL OR years_of_experience >= 0),
    highest_education_level TEXT
        CHECK (highest_education_level IS NULL OR highest_education_level IN (
            'high_school','associate','bachelor','master','doctorate','professional','certificate','other'
        )),
    primary_industry        TEXT,
    primary_function        TEXT,
    career_level_estimate   TEXT
        CHECK (career_level_estimate IS NULL OR career_level_estimate IN (
            'entry','junior','mid','senior','lead','executive'
        )),
    -- Provenance: who/what produced this record
    source                  TEXT        NOT NULL DEFAULT 'cv'
        CHECK (source IN ('cv','ai_extraction','human_correction')),
    -- Confidence 0.0–1.0 for the overall snapshot
    confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    is_current              BOOLEAN     NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_cv_profile_doc_version UNIQUE (candidate_document_id, version)
);

CREATE INDEX IF NOT EXISTS idx_cv_profiles_candidate     ON public.candidate_cv_profiles(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_document      ON public.candidate_cv_profiles(candidate_document_id);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_current       ON public.candidate_cv_profiles(candidate_id, is_current);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_created       ON public.candidate_cv_profiles(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_career_level  ON public.candidate_cv_profiles(career_level_estimate);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_industry      ON public.candidate_cv_profiles(primary_industry);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_function      ON public.candidate_cv_profiles(primary_function);
CREATE INDEX IF NOT EXISTS idx_cv_profiles_education     ON public.candidate_cv_profiles(highest_education_level);

CREATE TRIGGER trg_cv_profiles_updated_at
    BEFORE UPDATE ON public.candidate_cv_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 7. CANDIDATE_CV_AI_ANALYSIS — VERSIONED AI ANALYSIS RESULTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.candidate_cv_ai_analysis (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    candidate_document_id   UUID        NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    processing_job_id       UUID        REFERENCES public.cv_processing_jobs(id) ON DELETE SET NULL,
    cv_profile_id           UUID        REFERENCES public.candidate_cv_profiles(id) ON DELETE SET NULL,
    -- Versioning: reproducibility
    analysis_version        TEXT        NOT NULL DEFAULT '1.0.0',
    model_provider          TEXT        NOT NULL DEFAULT 'unspecified',
    model_name              TEXT        NOT NULL DEFAULT 'unknown',
    prompt_version          TEXT        NOT NULL DEFAULT '1.0.0',
    -- Analysis status
    analysis_status         TEXT        NOT NULL DEFAULT 'queued'
        CHECK (analysis_status IN ('queued','processing','completed','failed','needs_review')),
    -- Structured AI output — observed evidence, not verified fact
    overall_summary         TEXT,
    strengths               JSONB       NOT NULL DEFAULT '[]'::JSONB,  -- string[]
    potential_gaps          JSONB       NOT NULL DEFAULT '[]'::JSONB,  -- string[]
    career_level_estimate   TEXT
        CHECK (career_level_estimate IS NULL OR career_level_estimate IN (
            'entry','junior','mid','senior','lead','executive'
        )),
    functional_areas        JSONB       NOT NULL DEFAULT '[]'::JSONB,  -- string[]
    industries              JSONB       NOT NULL DEFAULT '[]'::JSONB,  -- string[]
    key_skills              JSONB       NOT NULL DEFAULT '[]'::JSONB,  -- string[]
    experience_summary      JSONB       NOT NULL DEFAULT '{}'::JSONB,
    education_summary       JSONB       NOT NULL DEFAULT '{}'::JSONB,
    language_summary        JSONB       NOT NULL DEFAULT '[]'::JSONB,
    recommendations         JSONB       NOT NULL DEFAULT '[]'::JSONB,
    -- Confidence 0.0–1.0 for this entire analysis
    confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    -- Error details when analysis_status = 'failed'
    error_code              TEXT,
    error_message           TEXT,
    -- Track which extraction version fed this analysis
    source_extraction_id    UUID        REFERENCES public.cv_extracted_content(id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_cv_analysis_doc_version
        UNIQUE (candidate_document_id, analysis_version, prompt_version, model_name)
);

CREATE INDEX IF NOT EXISTS idx_cv_analysis_candidate     ON public.candidate_cv_ai_analysis(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cv_analysis_document      ON public.candidate_cv_ai_analysis(candidate_document_id);
CREATE INDEX IF NOT EXISTS idx_cv_analysis_status        ON public.candidate_cv_ai_analysis(analysis_status);
CREATE INDEX IF NOT EXISTS idx_cv_analysis_job           ON public.candidate_cv_ai_analysis(processing_job_id);
CREATE INDEX IF NOT EXISTS idx_cv_analysis_provider      ON public.candidate_cv_ai_analysis(model_provider, model_name);
CREATE INDEX IF NOT EXISTS idx_cv_analysis_created       ON public.candidate_cv_ai_analysis(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cv_analysis_version       ON public.candidate_cv_ai_analysis(analysis_version);

CREATE TRIGGER trg_cv_analysis_updated_at
    BEFORE UPDATE ON public.candidate_cv_ai_analysis
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 8. CANDIDATE_CV_REVIEW_ITEMS — HUMAN REVIEW QUEUE FOR AI EXTRACTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.candidate_cv_review_items (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    candidate_document_id   UUID        NOT NULL REFERENCES public.candidate_documents(id) ON DELETE CASCADE,
    processing_job_id       UUID        REFERENCES public.cv_processing_jobs(id) ON DELETE SET NULL,
    -- Which field and which table was the extraction from
    target_table            TEXT        NOT NULL,   -- e.g. 'candidate_skills', 'candidate_experience'
    target_record_id        UUID,                   -- the specific row's id, if already inserted
    field_name              TEXT        NOT NULL,   -- e.g. 'skill_name', 'company_name', 'degree'
    ai_value                JSONB,                  -- the raw AI-extracted value
    reviewed_value          JSONB,                  -- the human-corrected value (if any)
    review_status           TEXT        NOT NULL DEFAULT 'pending'
        CHECK (review_status IN ('pending','approved','corrected','rejected')),
    reviewed_by             UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    reviewed_at             TIMESTAMPTZ,
    review_notes            TEXT,
    confidence              NUMERIC(4,3)
        CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cv_review_candidate       ON public.candidate_cv_review_items(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cv_review_document        ON public.candidate_cv_review_items(candidate_document_id);
CREATE INDEX IF NOT EXISTS idx_cv_review_status          ON public.candidate_cv_review_items(review_status);
CREATE INDEX IF NOT EXISTS idx_cv_review_reviewer        ON public.candidate_cv_review_items(reviewed_by);
CREATE INDEX IF NOT EXISTS idx_cv_review_table_field     ON public.candidate_cv_review_items(target_table, field_name);
CREATE INDEX IF NOT EXISTS idx_cv_review_pending         ON public.candidate_cv_review_items(created_at) WHERE review_status = 'pending';

CREATE TRIGGER trg_cv_review_items_updated_at
    BEFORE UPDATE ON public.candidate_cv_review_items
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 9. ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE public.cv_processing_jobs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cv_extracted_content       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cv_processing_metadata     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_cv_profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_cv_ai_analysis   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_cv_review_items  ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------
-- CV_PROCESSING_JOBS
-- -----------------------------------------------------------------------
-- Candidates can view their own processing jobs
CREATE POLICY "cv_jobs_select_own_candidate" ON public.cv_processing_jobs FOR SELECT TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

-- Only privileged roles can INSERT/UPDATE/DELETE processing jobs
CREATE POLICY "cv_jobs_insert_system" ON public.cv_processing_jobs FOR INSERT TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_jobs_update_system" ON public.cv_processing_jobs FOR UPDATE TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_jobs_no_delete" ON public.cv_processing_jobs FOR DELETE TO authenticated
    USING (false);

-- -----------------------------------------------------------------------
-- CV_EXTRACTED_CONTENT
-- -----------------------------------------------------------------------
-- Candidates can view their own extracted content
CREATE POLICY "cv_extracted_select_own" ON public.cv_extracted_content FOR SELECT TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

-- Privileged backend processes / recruiters with cv.view_extracted can insert
CREATE POLICY "cv_extracted_insert_system" ON public.cv_extracted_content FOR INSERT TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- No direct updates from API — reprocessing creates new rows
CREATE POLICY "cv_extracted_no_update" ON public.cv_extracted_content FOR UPDATE TO authenticated
    USING (false);

CREATE POLICY "cv_extracted_no_delete" ON public.cv_extracted_content FOR DELETE TO authenticated
    USING (false);

-- -----------------------------------------------------------------------
-- CV_PROCESSING_METADATA
-- -----------------------------------------------------------------------
CREATE POLICY "cv_metadata_select_own" ON public.cv_processing_metadata FOR SELECT TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "cv_metadata_insert_system" ON public.cv_processing_metadata FOR INSERT TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_metadata_update_system" ON public.cv_processing_metadata FOR UPDATE TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_metadata_no_delete" ON public.cv_processing_metadata FOR DELETE TO authenticated
    USING (false);

-- -----------------------------------------------------------------------
-- CANDIDATE_CV_PROFILES
-- -----------------------------------------------------------------------
CREATE POLICY "cv_profiles_select_own" ON public.candidate_cv_profiles FOR SELECT TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "cv_profiles_insert_system" ON public.candidate_cv_profiles FOR INSERT TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_profiles_update_system" ON public.candidate_cv_profiles FOR UPDATE TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_profiles_no_delete" ON public.candidate_cv_profiles FOR DELETE TO authenticated
    USING (false);

-- -----------------------------------------------------------------------
-- CANDIDATE_CV_AI_ANALYSIS
-- -----------------------------------------------------------------------
CREATE POLICY "cv_analysis_select_own" ON public.candidate_cv_ai_analysis FOR SELECT TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

CREATE POLICY "cv_analysis_insert_system" ON public.candidate_cv_ai_analysis FOR INSERT TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_analysis_update_system" ON public.candidate_cv_ai_analysis FOR UPDATE TO authenticated
    USING (public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_analysis_no_delete" ON public.candidate_cv_ai_analysis FOR DELETE TO authenticated
    USING (false);

-- -----------------------------------------------------------------------
-- CANDIDATE_CV_REVIEW_ITEMS
-- -----------------------------------------------------------------------
-- Candidates can view review items about themselves
CREATE POLICY "cv_review_select_own" ON public.candidate_cv_review_items FOR SELECT TO authenticated
    USING (public.has_candidate_read_access(candidate_id, auth.uid()));

-- Reviewers (platform/recruiter with cv.review) can insert review items
CREATE POLICY "cv_review_insert_system" ON public.candidate_cv_review_items FOR INSERT TO authenticated
    WITH CHECK (public.has_candidate_manage_access(candidate_id, auth.uid()));

-- Only the reviewer or system can update review items
CREATE POLICY "cv_review_update_reviewer" ON public.candidate_cv_review_items FOR UPDATE TO authenticated
    USING (reviewed_by = auth.uid() OR public.has_candidate_manage_access(candidate_id, auth.uid()))
    WITH CHECK (reviewed_by = auth.uid() OR public.has_candidate_manage_access(candidate_id, auth.uid()));

CREATE POLICY "cv_review_no_delete" ON public.candidate_cv_review_items FOR DELETE TO authenticated
    USING (false);

-- =============================================================================
-- 10. TRIGGER: AUTO-CREATE PROCESSING JOB WHEN A CV/RESUME DOCUMENT IS UPLOADED
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auto_create_cv_processing_job()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_idempotency_key TEXT;
BEGIN
    -- Only trigger for cv or resume document types
    IF NEW.document_type NOT IN ('cv', 'resume') THEN
        RETURN NEW;
    END IF;

    -- Build an idempotency key from document_id + processing_type
    v_idempotency_key := NEW.id::TEXT || ':full_pipeline:v1';

    -- Only insert if job does not already exist for this idempotency key
    INSERT INTO public.cv_processing_jobs (
        candidate_id,
        candidate_document_id,
        status,
        processing_type,
        pipeline_stage,
        idempotency_key
    )
    VALUES (
        NEW.candidate_id,
        NEW.id,
        'queued',
        'full_pipeline',
        'upload',
        v_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING;

    -- Update document status to 'processing' (the job will update it to 'processed' on success)
    -- We do NOT change status here — the backend service will transition it.
    -- This trigger only ensures a job is queued.

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_queue_cv_processing
    AFTER INSERT ON public.candidate_documents
    FOR EACH ROW
    WHEN (NEW.document_type IN ('cv', 'resume') AND NEW.status = 'uploaded')
    EXECUTE FUNCTION public.auto_create_cv_processing_job();

-- =============================================================================
-- 11. TRIGGER: PREVENT OVERWRITING HUMAN-VERIFIED VALUES WITH AI EXTRACTIONS
-- =============================================================================

-- Protect candidate_skills: do not let AI extraction overwrite human_verified rows
CREATE OR REPLACE FUNCTION public.guard_human_verified_skill()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- If existing record is human_verified and the new source is ai_extracted, block downgrade
    IF OLD.verification_status = 'human_verified'
       AND NEW.verification_status IN ('ai_extracted', 'unverified')
       AND NEW.source IN ('cv_extraction', 'ai_suggestion') THEN
        RAISE EXCEPTION
            'Cannot downgrade human_verified skill "%" to % via AI extraction.',
            OLD.skill_name, NEW.verification_status
            USING ERRCODE = 'HB001';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_human_verified_skill
    BEFORE UPDATE ON public.candidate_skills
    FOR EACH ROW EXECUTE FUNCTION public.guard_human_verified_skill();

-- Same pattern for languages
CREATE OR REPLACE FUNCTION public.guard_human_verified_language()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.verification_status = 'human_verified'
       AND NEW.verification_status IN ('ai_extracted', 'unverified')
       AND NEW.source IN ('cv_extraction', 'ai_suggestion') THEN
        RAISE EXCEPTION
            'Cannot downgrade human_verified language "%" to % via AI extraction.',
            OLD.language_name, NEW.verification_status
            USING ERRCODE = 'HB002';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_human_verified_language
    BEFORE UPDATE ON public.candidate_languages
    FOR EACH ROW EXECUTE FUNCTION public.guard_human_verified_language();

-- Same pattern for experience
CREATE OR REPLACE FUNCTION public.guard_human_verified_experience()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.verification_status = 'human_verified'
       AND NEW.verification_status IN ('ai_extracted', 'unverified')
       AND NEW.source IN ('cv_extraction', 'ai_suggestion') THEN
        RAISE EXCEPTION
            'Cannot downgrade human_verified experience at "%" to % via AI extraction.',
            OLD.company_name, NEW.verification_status
            USING ERRCODE = 'HB003';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_human_verified_experience
    BEFORE UPDATE ON public.candidate_experience
    FOR EACH ROW EXECUTE FUNCTION public.guard_human_verified_experience();

-- =============================================================================
-- 12. RPC FUNCTIONS — CV INTELLIGENCE PIPELINE
-- =============================================================================

-- A. Create or retrieve a CV processing job (idempotent)
CREATE OR REPLACE FUNCTION public.queue_cv_processing(
    p_candidate_document_id UUID,
    p_processing_type       TEXT    DEFAULT 'full_pipeline',
    p_provider              TEXT    DEFAULT NULL,
    p_provider_version      TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_candidate_id      UUID;
    v_doc               public.candidate_documents%ROWTYPE;
    v_idempotency_key   TEXT;
    v_job_id            UUID;
    v_attempt           INTEGER;
BEGIN
    -- Fetch document and verify it belongs to a valid candidate
    SELECT * INTO v_doc FROM public.candidate_documents WHERE id = p_candidate_document_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Document not found');
    END IF;

    v_candidate_id := v_doc.candidate_id;

    -- Access check: caller must be the candidate owner or platform admin
    IF NOT public.has_candidate_manage_access(v_candidate_id, auth.uid()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;

    -- Determine next attempt count for idempotency key
    SELECT COALESCE(MAX(attempt_count), -1) + 1 INTO v_attempt
    FROM public.cv_processing_jobs
    WHERE candidate_document_id = p_candidate_document_id
      AND processing_type = p_processing_type;

    v_idempotency_key := p_candidate_document_id::TEXT || ':' || p_processing_type || ':v' || v_attempt;

    INSERT INTO public.cv_processing_jobs (
        candidate_id, candidate_document_id, status, processing_type,
        pipeline_stage, idempotency_key, provider, provider_version, attempt_count
    ) VALUES (
        v_candidate_id, p_candidate_document_id, 'queued', p_processing_type,
        'upload', v_idempotency_key, p_provider, p_provider_version, v_attempt
    )
    ON CONFLICT (idempotency_key) DO UPDATE
        SET status      = 'queued',
            updated_at  = now()
    RETURNING id INTO v_job_id;

    RETURN jsonb_build_object(
        'success', true,
        'job_id', v_job_id,
        'candidate_id', v_candidate_id,
        'document_id', p_candidate_document_id,
        'idempotency_key', v_idempotency_key
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- B. Record pipeline stage progression (called by backend service/Edge Function)
CREATE OR REPLACE FUNCTION public.advance_cv_pipeline_stage(
    p_job_id        UUID,
    p_stage         TEXT,
    p_status        TEXT        DEFAULT NULL,
    p_metadata      JSONB       DEFAULT '{}'::JSONB,
    p_error_code    TEXT        DEFAULT NULL,
    p_error_msg     TEXT        DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.cv_processing_jobs%ROWTYPE;
BEGIN
    SELECT * INTO v_job FROM public.cv_processing_jobs WHERE id = p_job_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Job not found');
    END IF;

    -- Only allow system/admin to advance pipeline
    IF NOT public.has_candidate_manage_access(v_job.candidate_id, auth.uid()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;

    UPDATE public.cv_processing_jobs
    SET pipeline_stage  = p_stage,
        status          = COALESCE(p_status, status),
        stage_metadata  = COALESCE(p_metadata, stage_metadata),
        error_code      = COALESCE(p_error_code, error_code),
        error_message   = COALESCE(p_error_msg, error_message),
        started_at      = CASE WHEN p_stage = 'text_extraction' AND started_at IS NULL THEN now() ELSE started_at END,
        completed_at    = CASE WHEN p_status = 'completed' THEN now() ELSE completed_at END,
        failed_at       = CASE WHEN p_status = 'failed' THEN now() ELSE failed_at END,
        next_retry_at   = CASE
            WHEN p_status = 'failed' AND v_job.attempt_count < v_job.max_attempts
            THEN now() + INTERVAL '5 minutes' * POWER(2, v_job.attempt_count)
            ELSE next_retry_at
        END
    WHERE id = p_job_id;

    RETURN jsonb_build_object('success', true, 'job_id', p_job_id, 'stage', p_stage, 'status', COALESCE(p_status, v_job.status));

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- C. Save extracted text (upsert by document_id + extraction_version for idempotency)
CREATE OR REPLACE FUNCTION public.save_cv_extracted_text(
    p_candidate_document_id UUID,
    p_processing_job_id     UUID,
    p_extracted_text        TEXT,
    p_language              TEXT    DEFAULT NULL,
    p_page_count            INTEGER DEFAULT NULL,
    p_extraction_method     TEXT    DEFAULT 'pdf_text',
    p_extraction_version    TEXT    DEFAULT '1.0'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_candidate_id  UUID;
    v_record_id     UUID;
    v_char_count    INTEGER;
    v_word_count    INTEGER;
BEGIN
    SELECT candidate_id INTO v_candidate_id
    FROM public.candidate_documents WHERE id = p_candidate_document_id;

    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Document not found');
    END IF;

    IF NOT public.has_candidate_manage_access(v_candidate_id, auth.uid()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;

    -- Validate extracted text is not empty
    IF p_extracted_text IS NULL OR char_length(trim(p_extracted_text)) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Extracted text cannot be empty');
    END IF;

    v_char_count := char_length(p_extracted_text);
    -- Approximate word count
    v_word_count := array_length(regexp_split_to_array(trim(p_extracted_text), '\s+'), 1);

    INSERT INTO public.cv_extracted_content (
        candidate_document_id, candidate_id, processing_job_id,
        extracted_text, language, page_count,
        character_count, word_count,
        extraction_method, extraction_version, extracted_at
    ) VALUES (
        p_candidate_document_id, v_candidate_id, p_processing_job_id,
        p_extracted_text, p_language, p_page_count,
        v_char_count, v_word_count,
        p_extraction_method, p_extraction_version, now()
    )
    ON CONFLICT (candidate_document_id, extraction_version) DO UPDATE
        SET extracted_text       = EXCLUDED.extracted_text,
            language             = COALESCE(EXCLUDED.language, cv_extracted_content.language),
            page_count           = COALESCE(EXCLUDED.page_count, cv_extracted_content.page_count),
            character_count      = EXCLUDED.character_count,
            word_count           = EXCLUDED.word_count,
            extraction_method    = EXCLUDED.extraction_method,
            processing_job_id    = EXCLUDED.processing_job_id,
            extracted_at         = now(),
            updated_at           = now()
    RETURNING id INTO v_record_id;

    RETURN jsonb_build_object(
        'success', true,
        'extracted_content_id', v_record_id,
        'character_count', v_char_count,
        'word_count', v_word_count
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- D. Save AI analysis result (with validation)
CREATE OR REPLACE FUNCTION public.save_cv_ai_analysis(
    p_candidate_document_id UUID,
    p_processing_job_id     UUID,
    p_cv_profile_id         UUID        DEFAULT NULL,
    p_source_extraction_id  UUID        DEFAULT NULL,
    p_analysis_version      TEXT        DEFAULT '1.0.0',
    p_model_provider        TEXT        DEFAULT 'unspecified',
    p_model_name            TEXT        DEFAULT 'unknown',
    p_prompt_version        TEXT        DEFAULT '1.0.0',
    p_analysis_payload      JSONB       DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_candidate_id      UUID;
    v_record_id         UUID;
    v_confidence        NUMERIC(4,3);
    v_status            TEXT;
    v_career_level      TEXT;
BEGIN
    SELECT candidate_id INTO v_candidate_id
    FROM public.candidate_documents WHERE id = p_candidate_document_id;

    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Document not found');
    END IF;

    IF NOT public.has_candidate_manage_access(v_candidate_id, auth.uid()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;

    -- -----------------------------------------------------------------------
    -- VALIDATE AI OUTPUT before insertion (prevent malformed data)
    -- -----------------------------------------------------------------------
    BEGIN
        -- confidence must be 0–1 if present
        IF p_analysis_payload ? 'confidence' THEN
            v_confidence := (p_analysis_payload->>'confidence')::NUMERIC(4,3);
            IF v_confidence < 0 OR v_confidence > 1 THEN
                RAISE EXCEPTION 'confidence out of range: %', v_confidence;
            END IF;
        END IF;

        -- career_level_estimate must be valid enum if present
        IF p_analysis_payload ? 'career_level_estimate' THEN
            v_career_level := p_analysis_payload->>'career_level_estimate';
            IF v_career_level NOT IN ('entry','junior','mid','senior','lead','executive') THEN
                RAISE EXCEPTION 'invalid career_level_estimate: %', v_career_level;
            END IF;
        END IF;

        -- strengths / gaps / key_skills must be arrays if present
        IF (p_analysis_payload ? 'strengths') AND jsonb_typeof(p_analysis_payload->'strengths') != 'array' THEN
            RAISE EXCEPTION 'strengths must be a JSON array';
        END IF;
        IF (p_analysis_payload ? 'potential_gaps') AND jsonb_typeof(p_analysis_payload->'potential_gaps') != 'array' THEN
            RAISE EXCEPTION 'potential_gaps must be a JSON array';
        END IF;
        IF (p_analysis_payload ? 'key_skills') AND jsonb_typeof(p_analysis_payload->'key_skills') != 'array' THEN
            RAISE EXCEPTION 'key_skills must be a JSON array';
        END IF;

        v_status := 'completed';
    EXCEPTION WHEN OTHERS THEN
        -- Malformed AI output — mark as failed, store safe error
        INSERT INTO public.candidate_cv_ai_analysis (
            candidate_id, candidate_document_id, processing_job_id, cv_profile_id,
            analysis_version, model_provider, model_name, prompt_version,
            analysis_status, error_code, error_message, source_extraction_id
        ) VALUES (
            v_candidate_id, p_candidate_document_id, p_processing_job_id, p_cv_profile_id,
            p_analysis_version, p_model_provider, p_model_name, p_prompt_version,
            'failed', 'VALIDATION_ERROR', left(SQLERRM, 500), p_source_extraction_id
        )
        ON CONFLICT (candidate_document_id, analysis_version, prompt_version, model_name)
        DO UPDATE SET analysis_status = 'failed', error_message = EXCLUDED.error_message, updated_at = now()
        RETURNING id INTO v_record_id;

        RETURN jsonb_build_object('success', false, 'error', 'AI output validation failed', 'analysis_id', v_record_id);
    END;

    -- Insert validated analysis
    INSERT INTO public.candidate_cv_ai_analysis (
        candidate_id, candidate_document_id, processing_job_id, cv_profile_id,
        source_extraction_id, analysis_version, model_provider, model_name, prompt_version,
        analysis_status,
        overall_summary, strengths, potential_gaps, career_level_estimate,
        functional_areas, industries, key_skills,
        experience_summary, education_summary, language_summary, recommendations,
        confidence
    ) VALUES (
        v_candidate_id, p_candidate_document_id, p_processing_job_id, p_cv_profile_id,
        p_source_extraction_id, p_analysis_version, p_model_provider, p_model_name, p_prompt_version,
        'completed',
        p_analysis_payload->>'overall_summary',
        COALESCE(p_analysis_payload->'strengths',       '[]'::JSONB),
        COALESCE(p_analysis_payload->'potential_gaps',  '[]'::JSONB),
        p_analysis_payload->>'career_level_estimate',
        COALESCE(p_analysis_payload->'functional_areas','[]'::JSONB),
        COALESCE(p_analysis_payload->'industries',      '[]'::JSONB),
        COALESCE(p_analysis_payload->'key_skills',      '[]'::JSONB),
        COALESCE(p_analysis_payload->'experience_summary','{}'::JSONB),
        COALESCE(p_analysis_payload->'education_summary', '{}'::JSONB),
        COALESCE(p_analysis_payload->'language_summary',  '[]'::JSONB),
        COALESCE(p_analysis_payload->'recommendations',   '[]'::JSONB),
        v_confidence
    )
    ON CONFLICT (candidate_document_id, analysis_version, prompt_version, model_name)
    DO UPDATE SET
        analysis_status     = 'completed',
        overall_summary     = EXCLUDED.overall_summary,
        strengths           = EXCLUDED.strengths,
        potential_gaps      = EXCLUDED.potential_gaps,
        career_level_estimate = EXCLUDED.career_level_estimate,
        functional_areas    = EXCLUDED.functional_areas,
        industries          = EXCLUDED.industries,
        key_skills          = EXCLUDED.key_skills,
        experience_summary  = EXCLUDED.experience_summary,
        education_summary   = EXCLUDED.education_summary,
        language_summary    = EXCLUDED.language_summary,
        recommendations     = EXCLUDED.recommendations,
        confidence          = EXCLUDED.confidence,
        updated_at          = now()
    RETURNING id INTO v_record_id;

    RETURN jsonb_build_object('success', true, 'analysis_id', v_record_id, 'status', 'completed');

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- E. Get CV processing status for a candidate (candidate-facing summary)
CREATE OR REPLACE FUNCTION public.get_cv_processing_status(
    p_candidate_document_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_candidate_id  UUID;
    v_result        JSONB;
BEGIN
    SELECT candidate_id INTO v_candidate_id
    FROM public.candidate_documents WHERE id = p_candidate_document_id;

    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Document not found');
    END IF;

    IF NOT public.has_candidate_read_access(v_candidate_id, auth.uid()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;

    SELECT jsonb_build_object(
        'document_id',      p_candidate_document_id,
        'processing_jobs',  jsonb_agg(jsonb_build_object(
            'job_id',           j.id,
            'status',           j.status,
            'processing_type',  j.processing_type,
            'pipeline_stage',   j.pipeline_stage,
            'attempt_count',    j.attempt_count,
            'started_at',       j.started_at,
            'completed_at',     j.completed_at,
            'failed_at',        j.failed_at,
            'error_code',       j.error_code,
            'created_at',       j.created_at
        ) ORDER BY j.created_at DESC),
        'has_extracted_text',   (SELECT COUNT(*) > 0 FROM public.cv_extracted_content
                                 WHERE candidate_document_id = p_candidate_document_id),
        'has_ai_analysis',      (SELECT COUNT(*) > 0 FROM public.candidate_cv_ai_analysis
                                 WHERE candidate_document_id = p_candidate_document_id
                                   AND analysis_status = 'completed'),
        'latest_analysis_status', (SELECT analysis_status FROM public.candidate_cv_ai_analysis
                                   WHERE candidate_document_id = p_candidate_document_id
                                   ORDER BY created_at DESC LIMIT 1)
    ) INTO v_result
    FROM public.cv_processing_jobs j
    WHERE j.candidate_document_id = p_candidate_document_id;

    RETURN COALESCE(v_result, jsonb_build_object('document_id', p_candidate_document_id, 'processing_jobs', '[]'::JSONB));

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- =============================================================================
-- 13. CANDIDATE_INTELLIGENCE_SUMMARY VIEW
--     Secure recruiter-facing view — no raw CV text, no contact details exposed
-- =============================================================================

CREATE OR REPLACE VIEW public.candidate_intelligence_summary
WITH (security_invoker = true)
AS
SELECT
    c.id                            AS candidate_id,
    c.profile_completion_percentage AS profile_completion,
    c.status                        AS candidate_status,
    cp.years_of_experience,
    cp.current_title,
    cp.remote_preference,
    cp.availability_status,
    -- Aggregated skills (top 10 by proficiency)
    (
        SELECT jsonb_agg(jsonb_build_object(
            'skill',       cs.skill_name,
            'type',        cs.skill_type,
            'proficiency', cs.proficiency_level,
            'verified',    cs.is_verified
        ))
        FROM (
            SELECT skill_name, skill_type, proficiency_level, is_verified
            FROM public.candidate_skills
            WHERE candidate_id = c.id
              AND verification_status != 'rejected'
            ORDER BY
                CASE proficiency_level
                    WHEN 'expert'       THEN 1
                    WHEN 'advanced'     THEN 2
                    WHEN 'intermediate' THEN 3
                    WHEN 'beginner'     THEN 4
                    ELSE 5
                END
            LIMIT 10
        ) cs
    )                               AS key_skills,
    -- Languages
    (
        SELECT jsonb_agg(jsonb_build_object(
            'language',    cl.language_name,
            'code',        cl.language_code,
            'proficiency', cl.proficiency_level,
            'is_native',   cl.is_native
        ))
        FROM public.candidate_languages cl
        WHERE cl.candidate_id = c.id
          AND cl.verification_status != 'rejected'
    )                               AS languages,
    -- Latest CV profile intelligence
    cvp.highest_education_level,
    cvp.career_level_estimate,
    cvp.primary_function,
    cvp.primary_industry,
    cvp.confidence                  AS cv_profile_confidence,
    -- Latest AI analysis
    cva.analysis_status             AS latest_cv_analysis_status,
    cva.analysis_version            AS latest_cv_analysis_version,
    cva.model_provider              AS latest_analysis_provider,
    cva.confidence                  AS latest_analysis_confidence,
    -- Latest processing job status
    cpj.status                      AS latest_processing_status,
    cpj.pipeline_stage              AS latest_pipeline_stage,
    cpj.completed_at                AS last_processed_at,
    -- Timestamps
    c.created_at,
    c.updated_at
FROM public.candidates c
LEFT JOIN public.candidate_profiles cp
    ON cp.candidate_id = c.id
LEFT JOIN LATERAL (
    SELECT * FROM public.candidate_cv_profiles
    WHERE candidate_id = c.id AND is_current = true
    ORDER BY created_at DESC LIMIT 1
) cvp ON true
LEFT JOIN LATERAL (
    SELECT * FROM public.candidate_cv_ai_analysis
    WHERE candidate_id = c.id AND analysis_status = 'completed'
    ORDER BY created_at DESC LIMIT 1
) cva ON true
LEFT JOIN LATERAL (
    SELECT * FROM public.cv_processing_jobs
    WHERE candidate_id = c.id
    ORDER BY created_at DESC LIMIT 1
) cpj ON true;

-- Note: security_invoker = true means RLS of underlying tables is respected.
-- Recruiters see only what has_candidate_read_access() allows.

-- =============================================================================
-- 14. DOCUMENT: ENVIRONMENT VARIABLE REQUIREMENTS
--     These are NOT stored here. This is documentation only.
--     Required server-side environment variables for the CV processing service:
--
--     AI_PROVIDER          = openai | anthropic | google | custom
--     AI_API_KEY           = <secret — never in SQL or frontend>
--     AI_MODEL             = gpt-4o | claude-3-5-sonnet | gemini-pro | ...
--     AI_PROMPT_VERSION    = 1.0.0
--     EXTRACTION_PROVIDER  = pdfjs | tika | textract | custom
--     EXTRACTION_VERSION   = 4.2.1
--     SUPABASE_SERVICE_ROLE_KEY = <secret — server-side only>
--
--     These must be set in the server environment (e.g. Edge Function secrets,
--     Docker .env, cloud secrets manager). NEVER commit real values.
-- =============================================================================

-- =============================================================================
-- 15. VERIFICATION
-- =============================================================================

DO $$
DECLARE v_count INTEGER;
BEGIN
    -- New tables
    SELECT COUNT(*) INTO v_count FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
          'cv_processing_jobs', 'cv_extracted_content', 'cv_processing_metadata',
          'candidate_cv_profiles', 'candidate_cv_ai_analysis', 'candidate_cv_review_items'
      );
    ASSERT v_count = 6, 'Expected 6 Task-05 tables, found ' || v_count;

    -- Extended columns on candidate_skills
    SELECT COUNT(*) INTO v_count FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'candidate_skills'
      AND column_name IN ('source_document_id','confidence','verification_status');
    ASSERT v_count = 3, 'candidate_skills provenance columns missing';

    -- Extended columns on candidate_experience
    SELECT COUNT(*) INTO v_count FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'candidate_experience'
      AND column_name IN ('source','source_document_id','confidence','verification_status','industry');
    ASSERT v_count = 5, 'candidate_experience provenance columns missing';

    -- RPC functions
    SELECT COUNT(*) INTO v_count FROM information_schema.routines
    WHERE routine_schema = 'public'
      AND routine_name IN (
          'queue_cv_processing', 'advance_cv_pipeline_stage',
          'save_cv_extracted_text', 'save_cv_ai_analysis', 'get_cv_processing_status'
      );
    ASSERT v_count = 5, 'Expected 5 CV intelligence RPC functions, found ' || v_count;

    -- View
    SELECT COUNT(*) INTO v_count FROM information_schema.views
    WHERE table_schema = 'public' AND table_name = 'candidate_intelligence_summary';
    ASSERT v_count = 1, 'candidate_intelligence_summary view missing';

    RAISE NOTICE 'Task 05 -- CV Intelligence: All assertions passed.';
END;
$$;
