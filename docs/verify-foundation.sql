-- =============================================================================
-- Verification Script: docs/verify-foundation.sql
-- Description: Comprehensive database integrity and security verification
--              for Hiren Beyond Foundation (Supabase PostgreSQL)
-- =============================================================================

-- 1. VERIFY REQUIRED TABLES EXISTENCE
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'profiles',
    'organizations',
    'roles',
    'permissions',
    'role_permissions',
    'organization_members',
    'audit_logs'
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
    'profiles',
    'organizations',
    'roles',
    'permissions',
    'role_permissions',
    'organization_members',
    'audit_logs'
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
ORDER BY tablename, policyname;

-- 4. VERIFY FOREIGN KEYS AND CONSTRAINTS
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
    'profiles',
    'organizations',
    'roles',
    'permissions',
    'role_permissions',
    'organization_members',
    'audit_logs'
  )
ORDER BY tc.table_name, tc.constraint_name;

-- 5. VERIFY INDEXES
SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles',
    'organizations',
    'roles',
    'permissions',
    'role_permissions',
    'organization_members',
    'audit_logs'
  )
ORDER BY tablename, indexname;

-- 6. VERIFY TRIGGERS
SELECT 
    event_object_table,
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_schema IN ('public', 'auth')
  AND (event_object_table IN ('profiles', 'organizations', 'organization_members', 'users'))
ORDER BY event_object_table, trigger_name;

-- 7. VERIFY HELPER FUNCTIONS
SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'set_updated_at',
    'handle_new_user',
    'is_platform_admin',
    'is_org_member',
    'has_org_permission'
  )
ORDER BY routine_name;

-- 8. VERIFY SEED DATA: ROLES
SELECT id, key, name, is_system_role FROM public.roles ORDER BY key;

-- 9. VERIFY SEED DATA: PERMISSIONS
SELECT id, key, category, name FROM public.permissions ORDER BY category, key;

-- 10. VERIFY SEED DATA: ROLE_PERMISSIONS COUNT
SELECT 
    r.key AS role_key,
    r.name AS role_name,
    COUNT(rp.permission_id) AS permission_count
FROM public.roles r
LEFT JOIN public.role_permissions rp ON rp.role_id = r.id
GROUP BY r.key, r.name
ORDER BY permission_count DESC;

-- 11. VERIFY PLATFORM ORGANIZATION
SELECT id, name, slug, organization_type, status, created_by, created_at
FROM public.organizations
WHERE slug = 'hiren-beyond';
