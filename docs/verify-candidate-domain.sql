-- =============================================================================
-- Verification Script: docs/verify-candidate-domain.sql
-- Description: Comprehensive database integrity and security verification
--              for Hiren Beyond Candidate Domain (Supabase PostgreSQL)
-- =============================================================================

-- 1. VERIFY CANDIDATE DOMAIN TABLES EXISTENCE
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'candidates',
    'candidate_profiles',
    'candidate_skills',
    'candidate_languages',
    'candidate_experience',
    'candidate_education',
    'candidate_certifications',
    'candidate_preferences',
    'candidate_documents'
  )
ORDER BY table_name;

-- 2. VERIFY ROW LEVEL SECURITY (RLS) STATUS
SELECT 
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'candidates',
    'candidate_profiles',
    'candidate_skills',
    'candidate_languages',
    'candidate_experience',
    'candidate_education',
    'candidate_certifications',
    'candidate_preferences',
    'candidate_documents'
  )
ORDER BY c.relname;

-- 3. VERIFY RLS POLICIES ON CANDIDATE TABLES
SELECT 
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'candidates',
    'candidate_profiles',
    'candidate_skills',
    'candidate_languages',
    'candidate_experience',
    'candidate_education',
    'candidate_certifications',
    'candidate_preferences',
    'candidate_documents'
  )
ORDER BY tablename, policyname;

-- 4. VERIFY FOREIGN KEYS & UNIQUE CONSTRAINTS
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public'
  AND tc.table_name IN (
    'candidates',
    'candidate_profiles',
    'candidate_skills',
    'candidate_languages',
    'candidate_experience',
    'candidate_education',
    'candidate_certifications',
    'candidate_preferences',
    'candidate_documents'
  )
ORDER BY tc.table_name, tc.constraint_name;

-- 5. VERIFY CANDIDATE DOMAIN INDEXES
SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'candidates',
    'candidate_profiles',
    'candidate_skills',
    'candidate_languages',
    'candidate_experience',
    'candidate_education',
    'candidate_certifications',
    'candidate_preferences',
    'candidate_documents'
  )
ORDER BY tablename, indexname;

-- 6. VERIFY FUNCTIONS & TRIGGERS
SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'calculate_candidate_profile_completion',
    'sync_candidate_profile_completion',
    'get_candidate_id_for_user',
    'has_candidate_read_access',
    'has_candidate_manage_access'
  )
ORDER BY routine_name;

-- 7. VERIFY STORAGE BUCKET (candidate-documents)
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'candidate-documents';

-- 8. VERIFY STORAGE POLICIES
SELECT 
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE 'candidate_storage_%'
ORDER BY policyname;
