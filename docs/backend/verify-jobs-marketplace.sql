-- =============================================================================
-- Verification Script: docs/backend/verify-jobs-marketplace.sql
-- Description: Comprehensive database integrity and security verification
--              for Hiren Beyond Jobs Marketplace (Supabase PostgreSQL)
-- =============================================================================

-- 1. VERIFY JOBS MARKETPLACE TABLES EXISTENCE
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'job_categories',
    'jobs',
    'job_requirements',
    'job_skills',
    'job_languages',
    'job_questions'
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
    'job_categories',
    'jobs',
    'job_requirements',
    'job_skills',
    'job_languages',
    'job_questions'
  )
ORDER BY c.relname;

-- 3. VERIFY RLS POLICIES
SELECT 
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'job_categories',
    'jobs',
    'job_requirements',
    'job_skills',
    'job_languages',
    'job_questions'
  )
ORDER BY tablename, policyname;

-- 4. VERIFY SEEDED JOB CATEGORIES (Total: 14)
SELECT id, name, slug, sort_order, is_active
FROM public.job_categories
ORDER BY sort_order;

-- 5. VERIFY NEW GRANULAR PERMISSIONS (Total: 10 new, 23 total)
SELECT key, category, name
FROM public.permissions
WHERE category = 'jobs'
ORDER BY key;

-- 6. VERIFY PUBLIC MARKETPLACE VIEW
SELECT table_name, table_type
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name = 'public_active_jobs';

-- 7. VERIFY MARKETPLACE RPC FUNCTIONS
SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'get_active_jobs_count',
    'get_active_jobs',
    'trg_job_lifecycle',
    'can_read_job',
    'can_manage_job'
  )
ORDER BY routine_name;

-- 8. TEST RPC: GET ACTIVE JOBS COUNT
SELECT public.get_active_jobs_count() AS active_jobs_count;

-- 9. TEST RPC: GET ACTIVE JOBS (Empty result with 0 rows on clean db)
SELECT * FROM public.get_active_jobs(page_number => 1, page_size => 10);
