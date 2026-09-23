-- ============================================================================
-- Hiren Beyond Database Architecture Verification Report
-- Run this against the real Supabase database after applying migrations.
-- ============================================================================

-- 1. Total table count
SELECT 'Total tables in public schema' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) = 192 THEN 'PASS' ELSE 'WARN: expected 192 from local migration audit' END AS status
FROM pg_tables WHERE schemaname = 'public';

-- 2. RLS coverage
SELECT 'Tables with RLS enabled' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) = 192 THEN 'PASS' ELSE 'FAIL: some public tables missing RLS' END AS status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relrowsecurity = true;

-- 3. Comment coverage (domain tags).
-- The organization migration comments important/root tables only; it does
-- not require every table to have a comment.
SELECT 'Tables with domain comments' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) >= 60 THEN 'PASS' ELSE 'WARN: expected comments on important/root tables' END AS status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_description d ON d.objoid = c.oid AND d.objsubid = 0
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND d.description IS NOT NULL
  AND d.description LIKE '[DOMAIN:%]%';

-- 4. Function count. pg_proc rows include overloads and can differ from
-- the local unique function-name audit.
SELECT 'Functions in public schema' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) >= 236 THEN 'PASS' ELSE 'WARN: fewer than local unique function-name audit' END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public';

-- 5. Security-definer RPC count
SELECT 'SECURITY DEFINER functions' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) > 50 THEN 'PASS' ELSE 'WARN' END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prosecdef = true;

-- 6. Task 23 frontend RPCs present
SELECT 'Task 23 frontend RPCs (11 expected)' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) = 11 THEN 'PASS' ELSE 'FAIL' END AS status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN (
    'get_user_organizations','get_user_permissions','get_my_profile',
    'update_my_profile','get_notification_badge_count','get_frontend_config',
    'mark_notification_read','mark_all_notifications_read','list_notifications',
    'get_organization_summary','get_dashboard_metrics'
  )
  AND p.prosecdef = true;

-- 7. Storage buckets. Local migrations explicitly insert three buckets.
-- If the remote project has more buckets created outside migrations, review
-- them before documenting as deployed.
SELECT 'Storage buckets (at least 3 expected from migrations)' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARN: fewer buckets than local migrations insert' END AS status
FROM storage.buckets;

-- 8. Applied migrations
SELECT 'Applied migrations (40+ expected after organization comments)' AS check_name,
       COUNT(*)::TEXT AS result,
       CASE WHEN COUNT(*) >= 40 THEN 'PASS' ELSE 'WARN' END AS status
FROM supabase_migrations.schema_migrations;

-- 9. Domain breakdown by table count
SELECT
    CASE
        WHEN obj_description(c.oid) LIKE '[DOMAIN:IDENTITY]%' THEN '01_IDENTITY'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:GLOBALIZATION]%' THEN '02_GLOBALIZATION'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:CANDIDATES]%' THEN '03_CANDIDATES'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:CV_AI]%' THEN '04_CV_AI'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:JOBS]%' THEN '05_JOBS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:APPLICATIONS]%' THEN '06_APPLICATIONS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:MATCHING]%' THEN '07_MATCHING'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:ASSESSMENTS]%' THEN '08_ASSESSMENTS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:INTERVIEWS]%' THEN '09_INTERVIEWS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:HIRING]%' THEN '10_HIRING'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:CLIENTS]%' THEN '11_CLIENTS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:NOTIFICATIONS]%' THEN '12_NOTIFICATIONS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:AI]%' THEN '13_AI'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:INTEGRATIONS]%' THEN '14_INTEGRATIONS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:SEARCH]%' THEN '15_SEARCH'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:WORKFLOWS]%' THEN '16_WORKFLOWS'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:PUBLIC_API]%' THEN '17_PUBLIC_API'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:ADMIN]%' THEN '18_ADMIN'
        WHEN obj_description(c.oid) LIKE '[DOMAIN:ANALYTICS]%' THEN '19_ANALYTICS'
        ELSE 'UNCLASSIFIED'
    END AS domain,
    COUNT(*) AS table_count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
GROUP BY 1
ORDER BY 1;

-- 10. Tables without any policies (should be 0)
SELECT 'Tables with zero RLS policies' AS check_name,
       STRING_AGG(c.relname, ', ') AS tables,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'REVIEW REQUIRED' END AS status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relrowsecurity = true
  AND (SELECT COUNT(*) FROM pg_policy WHERE polrelid = c.oid) = 0;
