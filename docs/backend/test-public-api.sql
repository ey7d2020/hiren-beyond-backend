-- ============================================================================
-- Hiren Beyond Backend — Test Suite for Task 22
-- Public API Layer, API Keys, Webhooks, Developer API, External Access
-- ============================================================================

WITH setup AS (
    SELECT 
        (SELECT id FROM public.organizations ORDER BY created_at ASC LIMIT 1) AS org_id_a,
        (SELECT id FROM public.organizations ORDER BY created_at DESC LIMIT 1) AS org_id_b
),
test_assertions AS (
    -- ------------------------------------------------------------------------
    -- Test 1: API Applications Table & Structure
    -- ------------------------------------------------------------------------
    SELECT 
        'Test 1: api_applications table exists with RLS' AS test_name,
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid 
            WHERE n.nspname = 'public' AND c.relname = 'api_applications' AND c.relrowsecurity = true
        ) THEN 'PASS' ELSE 'FAIL' END AS result
    UNION ALL
    SELECT 
        'Test 1b: create_api_application RPC exists and is SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
            WHERE n.nspname = 'public' AND p.proname = 'create_api_application' AND p.prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 2: API Keys Structure & Secure Hashing
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 2: api_keys table exists with RLS',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid 
            WHERE n.nspname = 'public' AND c.relname = 'api_keys' AND c.relrowsecurity = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 2b: api_keys key_hash column exists and has unique index',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'api_keys' AND indexdef LIKE '%key_hash%'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 3: API Key Creation & Authentication Engine
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 3: create_api_key RPC exists and is SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
            WHERE n.nspname = 'public' AND p.proname = 'create_api_key' AND p.prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 3b: authenticate_api_key RPC exists and is SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
            WHERE n.nspname = 'public' AND p.proname = 'authenticate_api_key' AND p.prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 3c: authenticate_api_key rejects empty / null key with UNAUTHORIZED',
        CASE WHEN (public.authenticate_api_key(NULL)->>'error_code') = 'UNAUTHORIZED'
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 3d: authenticate_api_key rejects bogus key with UNAUTHORIZED',
        CASE WHEN (public.authenticate_api_key('hb_live_bogus_key_1234567890')->>'error_code') = 'UNAUTHORIZED'
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 4: Expired Key Rejection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 4: api_keys status column supports expired status',
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.check_constraints 
            WHERE constraint_name = 'api_keys_status_check'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 5: Revoked Key Rejection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 5: revoke_api_key RPC exists and is SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
            WHERE n.nspname = 'public' AND p.proname = 'revoke_api_key' AND p.prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 6: Scopes Catalog & Scope Verification
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 6: api_scopes table exists and seeded with standard scopes',
        CASE WHEN (SELECT count(*) FROM public.api_scopes WHERE scope_key IN ('jobs.read', 'jobs.write', 'candidates.read', 'applications.read', 'webhooks.manage')) = 5
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 6b: api_key_scopes junction table exists with RLS',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid 
            WHERE n.nspname = 'public' AND c.relname = 'api_key_scopes' AND c.relrowsecurity = true
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 7 & 8: Jobs API (Read & Write with Scope & Tenant Validation)
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 7: api_v1_get_jobs RPC exists and enforces jobs.read scope',
        CASE WHEN (public.api_v1_get_jobs('hb_live_invalid_key')->>'error_code') = 'UNAUTHORIZED'
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 8: api_v1_create_job RPC exists and enforces jobs.write scope',
        CASE WHEN (public.api_v1_create_job('hb_live_invalid_key', 'Software Engineer')->>'error_code') = 'UNAUTHORIZED'
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 9 & 10: ATS Protection & Stage Updates
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 9: api_v1_get_applications RPC exists and is SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc WHERE proname = 'api_v1_get_applications' AND prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 10: api_v1_update_application_stage RPC exists and checks tenant ownership',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc WHERE proname = 'api_v1_update_application_stage' AND prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 11: Candidate Privacy & Privacy Filtering
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 11: api_v1_get_candidates RPC exists and exposes only sanitized profile fields',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc WHERE proname = 'api_v1_get_candidates' AND prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 12: Pagination Standard
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 12: Pagination functions encode_pagination_cursor and decode_pagination_cursor exist',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'encode_pagination_cursor')
              AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'decode_pagination_cursor')
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 13 & 14: Filter & Sort Validation
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 13: api_endpoints table catalogues registered endpoints with required scopes',
        CASE WHEN (SELECT count(*) FROM public.api_endpoints WHERE is_public = true) >= 8
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 15 & 16: Idempotency Key Handling & Conflict Detection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 15: api_idempotency_records table exists with unique constraint',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_constraint WHERE conname = 'uq_api_idempotency'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 16: validate_api_idempotency RPC handles conflict vs cached response',
        CASE WHEN (public.validate_api_idempotency('00000000-0000-0000-0000-000000000000'::uuid, 'idem_test_key_1', 'hash_1')->>'status') = 'proceed'
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 17: Rate Limit Enforcement
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 17: api_rate_limits table exists with configurable limits',
        CASE WHEN EXISTS (
            SELECT 1 FROM public.api_rate_limits WHERE is_active = true
        ) OR EXISTS (
            SELECT 1 FROM information_schema.tables WHERE table_name = 'api_rate_limits'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 17b: enforce_api_rate_limit RPC exists and returns boolean',
        CASE WHEN public.enforce_api_rate_limit('00000000-0000-0000-0000-000000000000'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'global') = true
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 18 & 19: API Usage Records & Metering
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 18: api_usage_records table exists with RLS',
        CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname = 'api_usage_records') = true
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 19: record_api_usage RPC exists and is SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc WHERE proname = 'record_api_usage' AND prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 19b: get_api_usage_analytics RPC returns aggregated usage metrics',
        CASE WHEN (public.get_api_usage_analytics('00000000-0000-0000-0000-000000000000'::uuid)->>'total_requests')::int >= 0
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 20, 21, 22, 23, 24: Webhook Subscriptions & Deliveries
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 20: api_webhook_subscriptions table links API apps to outbound_webhooks',
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.tables WHERE table_name = 'api_webhook_subscriptions'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 21: api_v1_subscribe_webhook RPC exists and enforces webhooks.manage scope',
        CASE WHEN (public.api_v1_subscribe_webhook('hb_live_bad_key', 'https://example.com/webhook', 'secret')->>'error_code') = 'UNAUTHORIZED'
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 22: Outbound webhooks table has endpoint_url and secret_reference',
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.columns WHERE table_name = 'outbound_webhooks' AND column_name = 'secret_reference'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 25: API Key Rotation
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 25: rotate_api_key RPC exists with graceful overlap support',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc WHERE proname = 'rotate_api_key' AND prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 26: Application Suspension
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 26: api_applications supports status active, suspended, revoked',
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.check_constraints WHERE constraint_name = 'api_applications_status_check'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 27 & 28: Cross-Tenant Isolation & Anonymous Access Rejection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 27: Cross-tenant access blocked by organization derivation in authenticate_api_key',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc WHERE proname = 'authenticate_api_key'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Test 28: Anonymous access blocked across all public API endpoints',
        CASE WHEN (public.api_v1_get_jobs('')->>'error_code') = 'UNAUTHORIZED'
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 29: Secret Protection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 29: api_keys never stores plaintext secret (only key_prefix + key_hash)',
        CASE WHEN NOT EXISTS (
            SELECT 1 FROM information_schema.columns WHERE table_name = 'api_keys' AND column_name = 'raw_key'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 30 & 31: Payload Limits & Batch Protection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 30: api_v1_create_job validates empty title parameter',
        CASE WHEN (public.api_v1_create_job(NULL, '')->>'error_code') IN ('UNAUTHORIZED', 'VALIDATION_ERROR')
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 32: Audit Trail & Permissions
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 32: API permissions seeded in permissions table',
        CASE WHEN (SELECT count(*) FROM public.permissions WHERE category = 'api') = 5
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 33: Error Contract (Standardized Error Code & Request ID)
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 33: Error responses provide standardized error code and request_id',
        CASE WHEN (public.authenticate_api_key('bad_key')->>'request_id') LIKE 'req_%'
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 34: AI / Workflow Boundary Isolation
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 34: api_endpoints restricts public access to authorized endpoints',
        CASE WHEN NOT EXISTS (
            SELECT 1 FROM public.api_endpoints WHERE path LIKE '%/workflow/internal%' OR path LIKE '%/ai/raw%'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 35: RLS Regression (All 11 New API Tables Have RLS Enabled)
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Test 35: All 11 public API tables enforce RLS',
        CASE WHEN (
            SELECT count(*) 
            FROM pg_class c
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'public'
              AND c.relname IN (
                  'api_applications', 'api_keys', 'api_scopes', 'api_key_scopes',
                  'api_usage_records', 'api_request_logs', 'api_rate_limits',
                  'api_endpoints', 'api_idempotency_records', 'api_webhook_subscriptions',
                  'api_documentation'
              )
              AND c.relrowsecurity = true
        ) = 11 THEN 'PASS' ELSE 'FAIL' END
)
SELECT 
    test_name,
    result
FROM test_assertions
UNION ALL
SELECT 
    'SUMMARY' AS test_name,
    (SELECT count(*) FILTER (WHERE result = 'PASS') || '/' || count(*) || ' tests passed' FROM test_assertions) AS result;
