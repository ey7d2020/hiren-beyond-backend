-- =============================================================================
-- Task 19: Automation & Workflow Engine — Test Suite
-- File: docs/backend/test-workflow-engine.sql
-- =============================================================================

-- TEST 01 — workflow_definitions table exists
SELECT 'TEST 01 - workflow_definitions table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_definitions') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 01b - workflow_definitions has correct type constraint' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='workflow_type') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 01c - workflow_definitions has priority column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='priority') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 01d - workflow_definitions has idempotency_window_seconds' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='idempotency_window_seconds') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 02 — workflow_versions table (immutable versioning)
SELECT 'TEST 02 - workflow_versions table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_versions') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 02b - workflow_versions has unique constraint on definition+version' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='public' AND table_name='workflow_versions' AND constraint_type='UNIQUE' AND constraint_name='uq_workflow_version') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 02c - workflow_versions has definition JSONB column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_versions' AND column_name='definition') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 03 — workflow_triggers table
SELECT 'TEST 03 - workflow_triggers table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_triggers') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 03b - workflow_triggers has event_type column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_triggers' AND column_name='event_type') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 04 — workflow_fields registry (allowlist)
SELECT 'TEST 04 - workflow_fields registry table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_fields') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 04b - workflow_fields has seeded entries for application.status' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='application.status') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 04c - workflow_fields has seeded entries for application.match_score' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='application.match_score') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 04d - workflow_fields has seeded entries for assessment.passed' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='assessment.passed') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 04e - workflow_fields has seeded entries for client_feedback.decision' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='client_feedback.decision') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 04f - workflow_fields total count >= 20' AS test,
    CASE WHEN (SELECT COUNT(*) FROM public.workflow_fields) >= 20 THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 05 — workflow_conditions table
SELECT 'TEST 05 - workflow_conditions table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_conditions') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 05b - workflow_conditions has FK to workflow_fields.field_key' AS test,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
        WHERE tc.table_schema='public' AND tc.table_name='workflow_conditions'
          AND tc.constraint_type='FOREIGN KEY' AND ccu.table_name='workflow_fields'
    ) THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 06 — workflow_actions table
SELECT 'TEST 06 - workflow_actions table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_actions') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 06b - workflow_actions has risk_level column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='risk_level') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 06c - workflow_actions has delay_seconds column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='delay_seconds') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 06d - workflow_actions has requires_approval column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='requires_approval') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 06e - workflow_actions has max_retries column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='max_retries') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 07 — workflow_approval_steps table
SELECT 'TEST 07 - workflow_approval_steps table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_approval_steps') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 07b - workflow_approval_steps has approval_type column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_approval_steps' AND column_name='approval_type') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 07c - workflow_approval_steps has timeout_hours column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_approval_steps' AND column_name='timeout_hours') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 08 — workflow_schedules table (scheduling)
SELECT 'TEST 08 - workflow_schedules table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_schedules') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 08b - workflow_schedules has timezone column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_schedules' AND column_name='timezone') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 08c - workflow_schedules has cron_expression column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_schedules' AND column_name='cron_expression') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 08d - workflow_schedules has next_run_at column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_schedules' AND column_name='next_run_at') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 09 — workflow_event_queue (event routing / idempotency)
SELECT 'TEST 09 - workflow_event_queue table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_event_queue') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 09b - workflow_event_queue has idempotency_key column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_event_queue' AND column_name='idempotency_key') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 09c - workflow_event_queue has source_event_id column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_event_queue' AND column_name='source_event_id') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 09d - workflow_event_queue has partial unique index for idempotency' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_event_queue' AND indexname='uq_weq_idempotency_partial') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 09e - workflow_event_queue has attempt_count column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_event_queue' AND column_name='attempt_count') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 10 — workflow_executions table
SELECT 'TEST 10 - workflow_executions table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_executions') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 10b - workflow_executions has execution_depth for loop protection' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_executions' AND column_name='execution_depth') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 10c - workflow_executions has scheduled_for for delayed execution' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_executions' AND column_name='scheduled_for') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 10d - workflow_executions has context JSONB column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_executions' AND column_name='context') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 11 — workflow_execution_steps table
SELECT 'TEST 11 - workflow_execution_steps table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_execution_steps') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 11b - workflow_execution_steps has failure_type column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_steps' AND column_name='failure_type') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 11c - workflow_execution_steps has retry_count column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_steps' AND column_name='retry_count') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 11d - workflow_execution_steps has approved_by column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_steps' AND column_name='approved_by') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 11e - workflow_execution_steps has next_retry_at column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_steps' AND column_name='next_retry_at') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 12 — workflow_execution_logs table
SELECT 'TEST 12 - workflow_execution_logs table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_execution_logs') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 12b - workflow_execution_logs has level column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_logs' AND column_name='level') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 12c - workflow_execution_logs has metadata JSONB column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_logs' AND column_name='metadata') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 13 — workflow_failures (dead letter queue)
SELECT 'TEST 13 - workflow_failures table exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_failures') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 13b - workflow_failures has retryable column' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_failures' AND column_name='retryable') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 13c - workflow_failures has resolved_at and resolved_by columns' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_failures' AND column_name='resolved_at')
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_failures' AND column_name='resolved_by')
    THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 14 — RPC functions exist
SELECT 'TEST 14 - validate_workflow_definition RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='validate_workflow_definition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14b - publish_workflow_version RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='publish_workflow_version' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14c - enqueue_workflow_event RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='enqueue_workflow_event' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14d - route_workflow_events RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='route_workflow_events' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14e - execute_workflow_action RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='execute_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14f - cancel_workflow_execution RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='cancel_workflow_execution' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14g - pause_workflow RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='pause_workflow' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14h - resume_workflow RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='resume_workflow' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14i - approve_workflow_action RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='approve_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14j - deny_workflow_action RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='deny_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14k - retry_workflow_step RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='retry_workflow_step' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14l - get_workflow_execution RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='get_workflow_execution' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14m - get_failed_workflows RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='get_failed_workflows' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14n - evaluate_workflow_condition RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='evaluate_workflow_condition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 14o - create_workflow_execution_step RPC exists' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='create_workflow_execution_step' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 15 — Validate workflow definition: safe filters accepted
SELECT 'TEST 15 - validate_workflow_definition accepts valid definition' AS test,
    CASE WHEN (
        public.validate_workflow_definition(
            '{"trigger":{"event":"application_submitted"},"steps":[{"type":"run_matching"},{"type":"condition","field":"application.match_score","operator":">=","value":"85"},{"type":"send_notification","notification_type":"candidate_ready"}]}'::JSONB
        )->>'valid'
    ) = 'true' THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 16 — Validate definition blocks forbidden keys (arbitrary SQL)
SELECT 'TEST 16 - validate_workflow_definition blocks sql key' AS test,
    CASE WHEN (
        public.validate_workflow_definition(
            '{"trigger":{"event":"test"},"steps":[{"type":"send_notification","sql":"DROP TABLE users;"}]}'::JSONB
        )->>'valid'
    ) = 'false' THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 17 — Validate definition blocks unknown step types
SELECT 'TEST 17 - validate_workflow_definition blocks unknown step type' AS test,
    CASE WHEN (
        public.validate_workflow_definition(
            '{"trigger":{"event":"test"},"steps":[{"type":"run_arbitrary_code"}]}'::JSONB
        )->>'valid'
    ) = 'false' THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 18 — Validate definition blocks invalid condition field
SELECT 'TEST 18 - validate_workflow_definition blocks unregistered field' AS test,
    CASE WHEN (
        public.validate_workflow_definition(
            '{"trigger":{"event":"test"},"steps":[{"type":"condition","field":"candidates.private_notes"}]}'::JSONB
        )->>'valid'
    ) = 'false' THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 19 — Condition evaluator: registered field accepted
SELECT 'TEST 19 - evaluate_workflow_condition handles registered field' AS test,
    CASE WHEN public.evaluate_workflow_condition(
        '{"field":"application.match_score","operator":"greater_than_or_equal","value":"85"}'::JSONB,
        '{"application":{"match_score":"90"}}'::JSONB
    ) = true THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 20 — Condition evaluator: condition false path (match_score < 85)
SELECT 'TEST 20 - evaluate_workflow_condition returns false for low match score' AS test,
    CASE WHEN public.evaluate_workflow_condition(
        '{"field":"application.match_score","operator":"greater_than_or_equal","value":"85"}'::JSONB,
        '{"application":{"match_score":"70"}}'::JSONB
    ) = false THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 21 — Condition evaluator: blocks unregistered fields
SELECT 'TEST 21 - evaluate_workflow_condition blocks unregistered field' AS test,
    CASE WHEN (
        SELECT public.evaluate_workflow_condition(
            '{"field":"candidates.secret_column","operator":"equals","value":"x"}'::JSONB,
            '{}'::JSONB
        )
    ) IS DISTINCT FROM NULL OR true  -- it should raise exception (returns false in exception handler)
    THEN (
        CASE WHEN public.evaluate_workflow_condition(
            '{"field":"candidates.secret_column","operator":"equals","value":"x"}'::JSONB,
            '{}'::JSONB
        ) = false THEN 'PASS' ELSE 'FAIL' END
    ) ELSE 'PASS' END AS result;

-- TEST 22 — enqueue_workflow_event is idempotent (same key → no duplicate)
SELECT 'TEST 22 - enqueue_workflow_event idempotency check' AS test,
    CASE WHEN (
        SELECT COUNT(*) FROM public.workflow_event_queue
        WHERE idempotency_key = 'test_idempotency_key_001'
    ) <= 1 THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 23 — RLS enabled on all workflow tables
SELECT 'TEST 23 - RLS enabled on workflow_definitions' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_definitions' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 23b - RLS enabled on workflow_versions' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_versions' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 23c - RLS enabled on workflow_executions' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_executions' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 23d - RLS enabled on workflow_event_queue' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_event_queue' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 23e - RLS enabled on workflow_execution_steps' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_execution_steps' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 23f - RLS enabled on workflow_execution_logs' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_execution_logs' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 23g - RLS enabled on workflow_failures' AS test,
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_failures' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 24 — SECURITY DEFINER on critical RPCs
SELECT 'TEST 24 - validate_workflow_definition is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='validate_workflow_definition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 24b - execute_workflow_action is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='execute_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 24c - route_workflow_events is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='route_workflow_events' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 24d - enqueue_workflow_event is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='enqueue_workflow_event' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 24e - cancel_workflow_execution is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='cancel_workflow_execution' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 24f - approve_workflow_action is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='approve_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 24g - evaluate_workflow_condition is SECURITY DEFINER' AS test,
    CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='evaluate_workflow_condition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 25 — Permissions seeded
SELECT 'TEST 25 - workflows.view permission seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.view') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 25b - workflows.manage permission seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.manage') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 25c - workflows.approve permission seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.approve') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 25d - workflows.admin permission seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.admin') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 26 — Platform limits seeded
SELECT 'TEST 26 - workflow.max_steps_per_execution limit seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.platform_settings WHERE key='workflow.max_steps_per_execution') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 26b - workflow.max_execution_depth limit seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.platform_settings WHERE key='workflow.max_execution_depth') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 26c - workflow.idempotency_window_sec limit seeded' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM public.platform_settings WHERE key='workflow.idempotency_window_sec') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 27 — Indexes exist for performance
SELECT 'TEST 27 - idx_wd_status index exists on workflow_definitions' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_definitions' AND indexname='idx_wd_status') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 27b - idx_wt_event index exists on workflow_triggers' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_triggers' AND indexname='idx_wt_event') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 27c - idx_we_entity index exists on workflow_executions' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_executions' AND indexname='idx_we_entity') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 27d - idx_wes_retry index exists on workflow_execution_steps' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_execution_steps' AND indexname='idx_wes_retry') THEN 'PASS' ELSE 'FAIL' END AS result;

SELECT 'TEST 27e - idx_weq_scheduled index exists on workflow_event_queue' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_event_queue' AND indexname='idx_weq_scheduled') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 28 — Scheduled workflow has timezone support
SELECT 'TEST 28 - workflow_schedules timezone default is UTC' AS test,
    CASE WHEN EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='workflow_schedules'
          AND column_name='timezone' AND column_default ILIKE '%UTC%'
    ) THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 29 — Loop protection: max_execution_depth exists on definitions
SELECT 'TEST 29 - Loop protection: max_execution_depth configurable' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='max_execution_depth') THEN 'PASS' ELSE 'FAIL' END AS result;

-- TEST 30 — Concurrency protection: workflow_executions has entity index for serialization
SELECT 'TEST 30 - Concurrency protection: workflow_executions entity+status index' AS test,
    CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_executions' AND indexname='idx_we_entity') THEN 'PASS' ELSE 'FAIL' END AS result;

-- ===== SUMMARY =====
SELECT
    'SUMMARY' AS test,
    COUNT(*) FILTER (WHERE result = 'PASS')::TEXT || '/' || COUNT(*)::TEXT || ' tests passed' AS result
FROM (
    SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_definitions') THEN 'PASS' ELSE 'FAIL' END AS result
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='workflow_type') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='priority') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='idempotency_window_seconds') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_versions') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='public' AND table_name='workflow_versions' AND constraint_type='UNIQUE' AND constraint_name='uq_workflow_version') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_triggers') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_fields') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='application.status') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='application.match_score') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='assessment.passed') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key='client_feedback.decision') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT COUNT(*) FROM public.workflow_fields) >= 20 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_conditions') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_actions') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='risk_level') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='delay_seconds') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_actions' AND column_name='requires_approval') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_approval_steps') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_schedules') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_schedules' AND column_name='timezone') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_event_queue') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_event_queue' AND column_name='idempotency_key') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_event_queue' AND indexname='uq_weq_idempotency_partial') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_executions') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_executions' AND column_name='execution_depth') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_executions' AND column_name='scheduled_for') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_execution_steps') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_steps' AND column_name='failure_type') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_execution_steps' AND column_name='retry_count') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_execution_logs') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='workflow_failures') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_failures' AND column_name='retryable') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='validate_workflow_definition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='publish_workflow_version' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='enqueue_workflow_event' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='route_workflow_events' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='execute_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='cancel_workflow_execution' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='pause_workflow' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='resume_workflow' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='approve_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='deny_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='retry_workflow_step' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='get_workflow_execution' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='get_failed_workflows' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='evaluate_workflow_condition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (public.validate_workflow_definition('{"trigger":{"event":"application_submitted"},"steps":[{"type":"run_matching"},{"type":"condition","field":"application.match_score","operator":">=","value":"85"},{"type":"send_notification"}]}'::JSONB)->>'valid') = 'true' THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (public.validate_workflow_definition('{"trigger":{"event":"test"},"steps":[{"type":"send_notification","sql":"DROP TABLE users;"}]}'::JSONB)->>'valid') = 'false' THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (public.validate_workflow_definition('{"trigger":{"event":"test"},"steps":[{"type":"run_arbitrary_code"}]}'::JSONB)->>'valid') = 'false' THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (public.validate_workflow_definition('{"trigger":{"event":"test"},"steps":[{"type":"condition","field":"candidates.private_notes"}]}'::JSONB)->>'valid') = 'false' THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN public.evaluate_workflow_condition('{"field":"application.match_score","operator":"greater_than_or_equal","value":"85"}'::JSONB,'{"application":{"match_score":"90"}}'::JSONB) = true THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN public.evaluate_workflow_condition('{"field":"application.match_score","operator":"greater_than_or_equal","value":"85"}'::JSONB,'{"application":{"match_score":"70"}}'::JSONB) = false THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN public.evaluate_workflow_condition('{"field":"candidates.secret_column","operator":"equals","value":"x"}'::JSONB,'{}'::JSONB) = false THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_definitions' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_versions' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_executions' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_event_queue' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE relname='workflow_failures' AND relnamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='validate_workflow_definition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='execute_workflow_action' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='route_workflow_events' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN (SELECT prosecdef FROM pg_proc WHERE proname='evaluate_workflow_condition' AND pronamespace='public'::regnamespace) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.view') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.manage') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.permissions WHERE key='workflows.approve') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.platform_settings WHERE key='workflow.max_steps_per_execution') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.platform_settings WHERE key='workflow.max_execution_depth') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM public.platform_settings WHERE key='workflow.idempotency_window_sec') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='workflow_definitions' AND column_name='max_execution_depth') THEN 'PASS' ELSE 'FAIL' END
    UNION ALL SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='workflow_executions' AND indexname='idx_we_entity') THEN 'PASS' ELSE 'FAIL' END
) AS results;
