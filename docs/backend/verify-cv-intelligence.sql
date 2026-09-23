-- ============================================================================
-- Hiren Beyond — Task 05 Verification Script: CV Intelligence & Processing
-- ============================================================================

-- 1. Checking Tables & Views
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'cv_processing_jobs',
    'cv_extracted_content',
    'cv_processing_metadata',
    'candidate_cv_profiles',
    'candidate_cv_ai_analysis',
    'candidate_cv_review_items',
    'candidate_intelligence_summary'
  )
ORDER BY table_name;

-- 2. Checking Extended Columns on Candidate Tables
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'candidate_skills',
    'candidate_languages',
    'candidate_experience',
    'candidate_education',
    'candidate_certifications'
  )
  AND column_name IN (
    'source',
    'source_document_id',
    'confidence',
    'verification_status',
    'industry',
    'responsibilities',
    'extracted_achievements',
    'education_level'
  )
ORDER BY table_name, column_name;

-- 3. Checking Stored Procedures (RPC Functions)
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'queue_cv_processing',
    'advance_cv_pipeline_stage',
    'save_cv_extracted_text',
    'save_cv_ai_analysis',
    'get_cv_processing_status',
    'auto_create_cv_processing_job',
    'guard_human_verified_skill'
  )
ORDER BY routine_name;

-- 4. Checking Row Level Security Status
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN (
    'cv_processing_jobs',
    'cv_extracted_content',
    'cv_processing_metadata',
    'candidate_cv_profiles',
    'candidate_cv_ai_analysis',
    'candidate_cv_review_items'
  )
ORDER BY tablename;

-- 5. Checking Security Invoker View
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'candidate_intelligence_summary';

-- 6. Checking Seed Permissions
SELECT key, name, description, category 
FROM permissions 
WHERE category = 'cv'
ORDER BY key;
