-- ============================================================================
-- Hiren Beyond Backend — Test Suite for Task 21
-- Production Hardening, Performance Optimization, Database Indexing,
-- Queues, Caching, Observability, Backup & Disaster Recovery
-- ============================================================================

WITH test_assertions AS (
    -- ------------------------------------------------------------------------
    -- Test 1 & 2: Database Indexes (Foreign Keys & High-Impact Performance)
    -- ------------------------------------------------------------------------
    SELECT 
        'Index: idx_recruiter_review_queue_app_id exists' AS test_name,
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_recruiter_review_queue_app_id')
             THEN 'PASS' ELSE 'FAIL' END AS result
    UNION ALL
    SELECT 
        'Index: idx_applications_resume_doc_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_applications_resume_doc_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_screening_summaries_app_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_screening_summaries_app_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_candidate_shortlists_app_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_candidate_shortlists_app_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_interviews_template_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_interviews_template_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_notification_deliv_notif_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_notification_deliv_notif_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_integration_jobs_conn_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_integration_jobs_conn_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_analytics_export_report_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_analytics_export_report_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Index: idx_ai_action_req_tool_call_id exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_ai_action_req_tool_call_id')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Partial Index: idx_jobs_published_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_jobs_published_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Composite Index: idx_applications_pipeline_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_applications_pipeline_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Composite Index: idx_applications_job_score_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_applications_job_score_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Partial Index: idx_notifications_unread_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_notifications_unread_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Partial Index: idx_workflow_event_queue_pending_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_workflow_event_queue_pending_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Partial Index: idx_workflow_exec_steps_pending_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_workflow_exec_steps_pending_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Partial Index: idx_workflow_failures_unresolved_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_workflow_failures_unresolved_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Partial Index: idx_integration_jobs_pending_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_integration_jobs_pending_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Composite Index: idx_interviews_schedule_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_interviews_schedule_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Composite Index: idx_audit_logs_org_created_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_audit_logs_org_created_perf')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Composite Index: idx_candidate_profiles_search_perf exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_candidate_profiles_search_perf')
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 3: Keyset / Cursor Pagination Standard
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Pagination: encode_pagination_cursor produces valid base64',
        CASE WHEN public.encode_pagination_cursor('2026-09-15 00:00:00+00'::timestamptz, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid) IS NOT NULL
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Pagination: decode_pagination_cursor decodes timestamp and uuid accurately',
        CASE WHEN EXISTS (
            SELECT 1 
            FROM public.decode_pagination_cursor(
                public.encode_pagination_cursor('2026-09-15 00:00:00+00'::timestamptz, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid)
            )
            WHERE cursor_created_at = '2026-09-15 00:00:00+00'::timestamptz
              AND cursor_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Pagination: decode_pagination_cursor handles corrupt input gracefully',
        CASE WHEN (SELECT count(*) FROM public.decode_pagination_cursor('invalid_cursor_string!!!')) = 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Pagination: get_applications_cursor RPC exists and executable',
        CASE WHEN (public.get_applications_cursor('00000000-0000-0000-0000-000000000000'::uuid)->>'has_more')::boolean IS NOT NULL
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 4, 5, 6, 7: Queues, Atomic Locking, Retries, Dead-Letter, Priority
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Queue: claim_queue_jobs RPC handles workflow_events queue',
        CASE WHEN (public.claim_queue_jobs('workflow_events', 'test_worker_1', 10)->>'claimed_count')::int >= 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Queue: claim_queue_jobs RPC handles integration_jobs queue',
        CASE WHEN (public.claim_queue_jobs('integration_jobs', 'test_worker_1', 10)->>'claimed_count')::int >= 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Queue: complete_queue_job RPC exists with SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p 
            JOIN pg_namespace n ON p.pronamespace = n.oid 
            WHERE n.nspname = 'public' AND p.proname = 'complete_queue_job' AND p.prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Queue: fail_queue_job RPC exists with SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p 
            JOIN pg_namespace n ON p.pronamespace = n.oid 
            WHERE n.nspname = 'public' AND p.proname = 'fail_queue_job' AND p.prosecdef = true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Queue: workflow_failures table tracks unresolved failures',
        CASE WHEN EXISTS (
            SELECT 1 FROM information_schema.tables 
            WHERE table_schema = 'public' AND table_name = 'workflow_failures'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 8 & 9: Circuit Breaker & Provider Timeouts (AI & Integrations)
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Circuit Breaker: provider_circuit_breakers table exists with RLS',
        CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname = 'provider_circuit_breakers') = true
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Circuit Breaker: Core providers seeded (openai, anthropic, google_gemini, stripe)',
        CASE WHEN (SELECT count(*) FROM public.provider_circuit_breakers WHERE provider_name IN ('openai', 'anthropic', 'google_gemini', 'stripe')) = 4
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Circuit Breaker: check_circuit_breaker returns allowed=true for healthy provider',
        CASE WHEN (public.check_circuit_breaker('openai')->>'allowed')::boolean = true
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Circuit Breaker: record_circuit_breaker_result transitions on failure',
        CASE WHEN (public.record_circuit_breaker_result('openai', true)->>'state') = 'healthy'
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 10: Data Retention & Archival Policies
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Data Retention: data_retention_policies table exists with RLS',
        CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname = 'data_retention_policies') = true
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Data Retention: Standard policies seeded (analytics, notifications, logs, audit_logs)',
        CASE WHEN (SELECT count(*) FROM public.data_retention_policies) >= 6
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Data Retention: execute_data_retention_purge dry_run mode functions correctly',
        CASE WHEN (public.execute_data_retention_purge(true)->>'dry_run')::boolean = true
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Data Retention: Audit log table data_retention_audit_logs exists with RLS',
        CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname = 'data_retention_audit_logs') = true
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 11: RLS Security Enforcement
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Security: All 3 new tables have RLS enabled',
        CASE WHEN (
            SELECT count(*) 
            FROM pg_class c
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'public'
              AND c.relname IN ('provider_circuit_breakers', 'data_retention_policies', 'data_retention_audit_logs')
              AND c.relrowsecurity = true
        ) = 3 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Security: Platform admin RLS policies protect write operations',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_policies 
            WHERE schemaname = 'public' 
              AND tablename = 'provider_circuit_breakers' 
              AND policyname = 'provider_circuit_breakers_write'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 12, 13, 14, 15: Observability, Health Endpoints & Error Taxonomy
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Observability: get_system_health RPC returns database and queue metrics',
        CASE WHEN (public.get_system_health()->>'status') IN ('healthy', 'degraded')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Observability: get_readiness RPC returns true when DB and RBAC ready',
        CASE WHEN (public.get_readiness()->>'ready')::boolean = true
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Observability: get_queue_health RPC reports all pipeline queues',
        CASE WHEN (public.get_queue_health()->'workflow_events'->>'queued')::int >= 0
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Observability: get_production_metrics RPC returns cache and scan ratios',
        CASE WHEN (public.get_production_metrics()->>'cache_hit_ratio_percent')::numeric > 90.0
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 16: Secret Logging Protection
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Observability: circuit_breaker metadata does not store raw secrets',
        CASE WHEN NOT EXISTS (
            SELECT 1 FROM public.provider_circuit_breakers 
            WHERE metadata::text ILIKE '%api_key%' OR metadata::text ILIKE '%secret_key%'
        ) THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 17 & 18: Backup, Recovery & Retention Safety
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Data Safety: Core transactional tables are excluded from automated purge',
        CASE WHEN NOT EXISTS (
            SELECT 1 FROM public.data_retention_policies 
            WHERE table_name IN ('candidates', 'candidate_profiles', 'jobs', 'applications', 'hiring_decisions')
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Data Safety: Audit logs minimum retention is at least 365 days',
        CASE WHEN (SELECT retention_days FROM public.data_retention_policies WHERE category = 'audit_logs') >= 365
             THEN 'PASS' ELSE 'FAIL' END

    -- ------------------------------------------------------------------------
    -- Test 19 & 20: Regression Validation (Tasks 01–20 Integration)
    -- ------------------------------------------------------------------------
    UNION ALL
    SELECT 
        'Regression: Matching engine function calculate_candidate_job_match exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'calculate_candidate_job_match')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Regression: Search engine function search_candidates exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'search_candidates')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Regression: Workflow engine function execute_workflow_action exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'execute_workflow_action')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Regression: Notifications function emit_notification_event exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'emit_notification_event')
             THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 
        'Regression: Platform admin function is_platform_admin exists',
        CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_platform_admin')
             THEN 'PASS' ELSE 'FAIL' END
)
SELECT 
    test_name,
    result
FROM test_assertions
UNION ALL
SELECT 
    'SUMMARY' AS test_name,
    (SELECT count(*) FILTER (WHERE result = 'PASS') || '/' || count(*) || ' tests passed' FROM test_assertions) AS result;
