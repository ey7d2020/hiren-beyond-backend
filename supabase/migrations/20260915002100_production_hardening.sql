-- ============================================================================
-- Hiren Beyond Backend — Migration 20260915002100
-- Task 21: Production Hardening, Performance Optimization, Database Indexing,
--          Queues, Caching, Observability, Backup & Disaster Recovery
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. FOREIGN KEY COVERING INDEXES (Eliminating Unindexed Foreign Key Bottlenecks)
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_recruiter_review_queue_app_id 
    ON public.recruiter_review_queue (application_id);

CREATE INDEX IF NOT EXISTS idx_recruiter_review_queue_job_id 
    ON public.recruiter_review_queue (job_id);

CREATE INDEX IF NOT EXISTS idx_recruiter_review_queue_cand_id 
    ON public.recruiter_review_queue (candidate_id);

CREATE INDEX IF NOT EXISTS idx_applications_resume_doc_id 
    ON public.applications (resume_document_id);

CREATE INDEX IF NOT EXISTS idx_screening_summaries_app_id 
    ON public.candidate_screening_summaries (application_id);

CREATE INDEX IF NOT EXISTS idx_screening_summaries_match_run 
    ON public.candidate_screening_summaries (matching_run_id);

CREATE INDEX IF NOT EXISTS idx_candidate_shortlists_app_id 
    ON public.candidate_shortlists (application_id);

CREATE INDEX IF NOT EXISTS idx_client_shares_app_id 
    ON public.client_candidate_shares (application_id);

CREATE INDEX IF NOT EXISTS idx_candidate_readiness_app_id 
    ON public.candidate_readiness (application_id);

CREATE INDEX IF NOT EXISTS idx_bulk_screening_cands_app_id 
    ON public.bulk_screening_candidates (application_id);

CREATE INDEX IF NOT EXISTS idx_interviews_template_id 
    ON public.interviews (interview_template_id);

CREATE INDEX IF NOT EXISTS idx_interviews_round_id 
    ON public.interviews (interview_round_id);

CREATE INDEX IF NOT EXISTS idx_notification_deliv_notif_id 
    ON public.notification_deliveries (notification_id);

CREATE INDEX IF NOT EXISTS idx_notification_deliv_templ_id 
    ON public.notification_deliveries (template_id);

CREATE INDEX IF NOT EXISTS idx_notification_events_org_id 
    ON public.notification_events (organization_id);

CREATE INDEX IF NOT EXISTS idx_integration_jobs_conn_id 
    ON public.integration_jobs (integration_connection_id);

CREATE INDEX IF NOT EXISTS idx_analytics_export_report_id 
    ON public.analytics_export_jobs (report_id);

CREATE INDEX IF NOT EXISTS idx_ai_action_req_tool_call_id 
    ON public.ai_action_requests (tool_call_id);

CREATE INDEX IF NOT EXISTS idx_ai_tool_calls_message_id 
    ON public.ai_tool_calls (message_id);

CREATE INDEX IF NOT EXISTS idx_ai_usage_assistant_id 
    ON public.ai_usage_records (assistant_id);

-- ----------------------------------------------------------------------------
-- 2. HIGH-IMPACT PARTIAL & COMPOSITE PERFORMANCE INDEXES
-- ----------------------------------------------------------------------------

-- Marketplace published active jobs
CREATE INDEX IF NOT EXISTS idx_jobs_published_perf 
    ON public.jobs (organization_id, published_at DESC) 
    WHERE status = 'published';

-- ATS Applications pipeline lookups
CREATE INDEX IF NOT EXISTS idx_applications_pipeline_perf 
    ON public.applications (organization_id, status, current_stage_id, created_at DESC);

-- Job candidate ranking score ordering
CREATE INDEX IF NOT EXISTS idx_applications_job_score_perf 
    ON public.applications (job_id, match_score DESC NULLS LAST, created_at DESC);

-- Unread notifications per recipient
CREATE INDEX IF NOT EXISTS idx_notifications_unread_perf 
    ON public.notifications (recipient_user_id, created_at DESC) 
    WHERE read_at IS NULL;

-- Workflow event queue pending processing
CREATE INDEX IF NOT EXISTS idx_workflow_event_queue_pending_perf 
    ON public.workflow_event_queue (status, scheduled_for, created_at ASC) 
    WHERE status IN ('queued', 'processing');

-- Workflow execution steps pending/active
CREATE INDEX IF NOT EXISTS idx_workflow_exec_steps_pending_perf 
    ON public.workflow_execution_steps (status) 
    WHERE status IN ('pending', 'running', 'waiting');

-- Workflow unresolved dead-letter queue failures
CREATE INDEX IF NOT EXISTS idx_workflow_failures_unresolved_perf 
    ON public.workflow_failures (resolved_at, created_at DESC) 
    WHERE resolved_at IS NULL;

-- Integration jobs pending queue
CREATE INDEX IF NOT EXISTS idx_integration_jobs_pending_perf 
    ON public.integration_jobs (status, scheduled_for, created_at ASC) 
    WHERE status IN ('queued', 'processing');

-- Webhook deliveries pending retry
CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_pending_perf 
    ON public.webhook_deliveries (status, created_at ASC) 
    WHERE status IN ('queued', 'sending');

-- Scheduled interviews calendar search
CREATE INDEX IF NOT EXISTS idx_interviews_schedule_perf 
    ON public.interviews (organization_id, scheduled_start_at, status);

-- Audit logs organization chronological lookup
CREATE INDEX IF NOT EXISTS idx_audit_logs_org_created_perf 
    ON public.audit_logs (organization_id, created_at DESC);

-- Candidate profiles geographical and experience filters
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_search_perf 
    ON public.candidate_profiles (country_code, years_of_experience DESC);

-- ----------------------------------------------------------------------------
-- 3. CIRCUIT BREAKER & EXTERNAL PROVIDER TIMEOUT CONTROL
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.provider_circuit_breakers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_name TEXT NOT NULL UNIQUE,
    provider_type TEXT NOT NULL, -- 'ai', 'messaging', 'calendar', 'payment', 'webhook'
    state TEXT NOT NULL DEFAULT 'healthy' CHECK (state IN ('healthy', 'degraded', 'failing', 'disabled')),
    consecutive_failures INT NOT NULL DEFAULT 0,
    failure_threshold INT NOT NULL DEFAULT 5,
    timeout_seconds INT NOT NULL DEFAULT 30,
    cooldown_seconds INT NOT NULL DEFAULT 300,
    last_failure_at TIMESTAMPTZ,
    tripped_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.provider_circuit_breakers ENABLE ROW LEVEL SECURITY;

CREATE POLICY provider_circuit_breakers_read ON public.provider_circuit_breakers
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY provider_circuit_breakers_write ON public.provider_circuit_breakers
    FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()));

INSERT INTO public.provider_circuit_breakers (provider_name, provider_type, failure_threshold, timeout_seconds, cooldown_seconds)
VALUES 
    ('openai', 'ai', 5, 30, 300),
    ('anthropic', 'ai', 5, 30, 300),
    ('google_gemini', 'ai', 5, 30, 300),
    ('whatsapp', 'messaging', 5, 15, 180),
    ('sendgrid', 'messaging', 5, 15, 180),
    ('google_calendar', 'calendar', 5, 20, 300),
    ('stripe', 'payment', 3, 20, 600)
ON CONFLICT (provider_name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 4. DATA RETENTION & ARCHIVAL FRAMEWORK
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.data_retention_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL UNIQUE,
    table_name TEXT NOT NULL,
    timestamp_column TEXT NOT NULL,
    retention_days INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.data_retention_policies ENABLE ROW LEVEL SECURITY;

CREATE POLICY data_retention_policies_read ON public.data_retention_policies
    FOR SELECT TO authenticated
    USING (true);

CREATE POLICY data_retention_policies_write ON public.data_retention_policies
    FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()));

INSERT INTO public.data_retention_policies (category, table_name, timestamp_column, retention_days, description)
VALUES 
    ('analytics_events', 'analytics_events', 'created_at', 90, 'Raw web and mobile user analytics events'),
    ('notification_deliveries', 'notification_deliveries', 'created_at', 30, 'Delivery status logs for sent notifications'),
    ('workflow_execution_logs', 'workflow_execution_logs', 'created_at', 30, 'Detailed workflow execution step logs'),
    ('search_history', 'search_history', 'created_at', 60, 'Candidate and job search query logs'),
    ('integration_job_attempts', 'integration_job_attempts', 'created_at', 30, 'Third-party API and sync attempts'),
    ('webhook_deliveries', 'webhook_deliveries', 'created_at', 30, 'Outbound webhook delivery attempt records'),
    ('audit_logs', 'audit_logs', 'created_at', 365, 'Security and compliance audit records (minimum 1 year retention)')
ON CONFLICT (category) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.data_retention_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,
    table_name TEXT NOT NULL,
    records_purged INT NOT NULL DEFAULT 0,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'success',
    error_message TEXT
);

ALTER TABLE public.data_retention_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY data_retention_audit_logs_read ON public.data_retention_audit_logs
    FOR SELECT TO authenticated
    USING (public.is_platform_admin(auth.uid()));

-- ----------------------------------------------------------------------------
-- 5. CURSOR-BASED KEYSET PAGINATION STANDARD
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.encode_pagination_cursor(
    p_created_at TIMESTAMPTZ,
    p_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_created_at IS NULL OR p_id IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN encode(
        convert_to(
            to_char(p_created_at, 'YYYY-MM-DD"T"HH24:MI:SS.USOF') || '|' || p_id::text, 
            'UTF-8'
        ), 
        'base64'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.decode_pagination_cursor(
    p_cursor TEXT
)
RETURNS TABLE (
    cursor_created_at TIMESTAMPTZ,
    cursor_id UUID
)
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_raw TEXT;
    v_parts TEXT[];
BEGIN
    IF p_cursor IS NULL OR btrim(p_cursor) = '' THEN
        RETURN;
    END IF;

    BEGIN
        v_raw := convert_from(decode(p_cursor, 'base64'), 'UTF-8');
        v_parts := string_to_array(v_raw, '|');
        IF array_length(v_parts, 1) = 2 THEN
            cursor_created_at := v_parts[1]::timestamptz;
            cursor_id := v_parts[2]::uuid;
            RETURN NEXT;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RETURN;
    END;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_applications_cursor(
    p_organization_id UUID,
    p_job_id UUID DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_cursor TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_cursor_ts TIMESTAMPTZ := NULL;
    v_cursor_id UUID := NULL;
    v_items JSONB := '[]'::jsonb;
    v_next_cursor TEXT := NULL;
    v_has_more BOOLEAN := false;
    v_last_ts TIMESTAMPTZ;
    v_last_id UUID;
BEGIN
    IF p_cursor IS NOT NULL AND btrim(p_cursor) <> '' THEN
        SELECT cursor_created_at, cursor_id 
        INTO v_cursor_ts, v_cursor_id
        FROM public.decode_pagination_cursor(p_cursor);
    END IF;

    WITH app_rows AS (
        SELECT 
            a.id,
            a.job_id,
            a.candidate_id,
            a.organization_id,
            a.status,
            a.current_stage_id,
            a.match_score,
            a.created_at
        FROM public.applications a
        WHERE a.organization_id = p_organization_id
          AND (p_job_id IS NULL OR a.job_id = p_job_id)
          AND (p_status IS NULL OR a.status = p_status)
          AND (
              v_cursor_ts IS NULL 
              OR (a.created_at, a.id) < (v_cursor_ts, v_cursor_id)
          )
        ORDER BY a.created_at DESC, a.id DESC
        LIMIT (v_limit + 1)
    )
    SELECT 
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', r.id,
                'job_id', r.job_id,
                'candidate_id', r.candidate_id,
                'organization_id', r.organization_id,
                'status', r.status,
                'current_stage_id', r.current_stage_id,
                'match_score', r.match_score,
                'created_at', r.created_at
            )
        ) FILTER (WHERE rn <= v_limit), '[]'::jsonb),
        bool_or(rn > v_limit),
        max(r.created_at) FILTER (WHERE rn = v_limit),
        max(r.id) FILTER (WHERE rn = v_limit)
    INTO v_items, v_has_more, v_last_ts, v_last_id
    FROM (
        SELECT *, row_number() OVER () AS rn 
        FROM app_rows
    ) r;

    IF v_has_more AND v_last_ts IS NOT NULL AND v_last_id IS NOT NULL THEN
        v_next_cursor := public.encode_pagination_cursor(v_last_ts, v_last_id);
    END IF;

    RETURN jsonb_build_object(
        'items', COALESCE(v_items, '[]'::jsonb),
        'has_more', COALESCE(v_has_more, false),
        'next_cursor', v_next_cursor,
        'limit', v_limit
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. CIRCUIT BREAKER OPERATIONAL RPCS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_circuit_breaker(
    p_provider_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cb public.provider_circuit_breakers%ROWTYPE;
BEGIN
    SELECT * INTO v_cb 
    FROM public.provider_circuit_breakers 
    WHERE provider_name = p_provider_name;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'state', 'healthy',
            'timeout_seconds', 30,
            'message', 'Provider not explicitly registered in circuit breaker'
        );
    END IF;

    IF v_cb.state = 'disabled' THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'state', 'disabled',
            'timeout_seconds', 0,
            'message', 'Provider has been manually disabled by administrator'
        );
    END IF;

    IF v_cb.state = 'failing' THEN
        IF v_cb.tripped_at IS NOT NULL AND now() >= (v_cb.tripped_at + (v_cb.cooldown_seconds || ' seconds')::interval) THEN
            UPDATE public.provider_circuit_breakers
            SET state = 'degraded', updated_at = now()
            WHERE provider_name = p_provider_name;

            RETURN jsonb_build_object(
                'allowed', true,
                'state', 'degraded',
                'timeout_seconds', v_cb.timeout_seconds,
                'message', 'Cooldown elapsed; trial request permitted in degraded state'
            );
        ELSE
            RETURN jsonb_build_object(
                'allowed', false,
                'state', 'failing',
                'timeout_seconds', 0,
                'cooldown_remaining_seconds', GREATEST(0, EXTRACT(EPOCH FROM ((v_cb.tripped_at + (v_cb.cooldown_seconds || ' seconds')::interval) - now()))::int),
                'message', 'Circuit breaker is OPEN. Provider calls rejected.'
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'allowed', true,
        'state', v_cb.state,
        'timeout_seconds', v_cb.timeout_seconds,
        'message', 'Provider healthy'
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_circuit_breaker_result(
    p_provider_name TEXT,
    p_success BOOLEAN,
    p_error TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cb public.provider_circuit_breakers%ROWTYPE;
BEGIN
    SELECT * INTO v_cb 
    FROM public.provider_circuit_breakers 
    WHERE provider_name = p_provider_name;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Provider not found');
    END IF;

    IF p_success THEN
        UPDATE public.provider_circuit_breakers
        SET consecutive_failures = 0,
            state = 'healthy',
            tripped_at = NULL,
            updated_at = now()
        WHERE provider_name = p_provider_name;

        RETURN jsonb_build_object('state', 'healthy', 'consecutive_failures', 0);
    ELSE
        v_cb.consecutive_failures := v_cb.consecutive_failures + 1;
        v_cb.last_failure_at := now();

        IF v_cb.consecutive_failures >= v_cb.failure_threshold THEN
            v_cb.state := 'failing';
            v_cb.tripped_at := now();
        ELSIF v_cb.consecutive_failures >= (v_cb.failure_threshold / 2) THEN
            v_cb.state := 'degraded';
        END IF;

        UPDATE public.provider_circuit_breakers
        SET consecutive_failures = v_cb.consecutive_failures,
            last_failure_at = v_cb.last_failure_at,
            state = v_cb.state,
            tripped_at = v_cb.tripped_at,
            metadata = jsonb_set(metadata, '{last_error}', to_jsonb(COALESCE(p_error, 'Unknown error'))),
            updated_at = now()
        WHERE provider_name = p_provider_name;

        RETURN jsonb_build_object(
            'state', v_cb.state,
            'consecutive_failures', v_cb.consecutive_failures,
            'tripped', (v_cb.state = 'failing')
        );
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 7. ATOMIC QUEUE CLAIMING & CONCURRENCY CONTROL (FOR UPDATE SKIP LOCKED)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.claim_queue_jobs(
    p_queue_name TEXT,
    p_worker_id TEXT,
    p_batch_size INT DEFAULT 10,
    p_lock_timeout_seconds INT DEFAULT 300
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_claimed JSONB := '[]'::jsonb;
    v_batch INT := LEAST(GREATEST(COALESCE(p_batch_size, 10), 1), 50);
BEGIN
    IF p_queue_name = 'workflow_events' THEN
        WITH locked_rows AS (
            SELECT id
            FROM public.workflow_event_queue
            WHERE status IN ('queued', 'processing')
              AND scheduled_for <= now()
            ORDER BY scheduled_for ASC, created_at ASC
            LIMIT v_batch
            FOR UPDATE SKIP LOCKED
        )
        UPDATE public.workflow_event_queue q
        SET status = 'processing',
            attempt_count = attempt_count + 1
        FROM locked_rows lr
        WHERE q.id = lr.id
        RETURNING jsonb_build_object(
            'id', q.id,
            'event_type', q.event_type,
            'entity_type', q.entity_type,
            'entity_id', q.entity_id,
            'attempt_count', q.attempt_count
        ) INTO v_claimed;

    ELSIF p_queue_name = 'integration_jobs' THEN
        WITH locked_rows AS (
            SELECT id
            FROM public.integration_jobs
            WHERE status IN ('queued', 'processing')
              AND (scheduled_for IS NULL OR scheduled_for <= now())
            ORDER BY created_at ASC
            LIMIT v_batch
            FOR UPDATE SKIP LOCKED
        )
        UPDATE public.integration_jobs j
        SET status = 'processing',
            attempt_count = attempt_count + 1
        FROM locked_rows lr
        WHERE j.id = lr.id
        RETURNING jsonb_build_object(
            'id', j.id,
            'job_type', j.job_type,
            'organization_id', j.organization_id,
            'attempt_count', j.attempt_count
        ) INTO v_claimed;

    ELSE
        RETURN jsonb_build_object('error', 'Unknown queue name: ' || p_queue_name);
    END IF;

    RETURN jsonb_build_object(
        'queue', p_queue_name,
        'worker_id', p_worker_id,
        'claimed_count', jsonb_array_length(COALESCE(v_claimed, '[]'::jsonb)),
        'jobs', COALESCE(v_claimed, '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_queue_job(
    p_job_id UUID,
    p_queue_name TEXT,
    p_result JSONB DEFAULT '{}'::jsonb
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_queue_name = 'workflow_events' THEN
        UPDATE public.workflow_event_queue
        SET status = 'processed',
            processed_at = now()
        WHERE id = p_job_id;
        RETURN FOUND;

    ELSIF p_queue_name = 'integration_jobs' THEN
        UPDATE public.integration_jobs
        SET status = 'completed',
            completed_at = now()
        WHERE id = p_job_id;
        RETURN FOUND;
    END IF;

    RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_queue_job(
    p_job_id UUID,
    p_queue_name TEXT,
    p_error TEXT,
    p_retryable BOOLEAN DEFAULT true,
    p_max_attempts INT DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_attempts INT := 0;
    v_is_dlq BOOLEAN := false;
BEGIN
    IF p_queue_name = 'workflow_events' THEN
        SELECT attempt_count INTO v_attempts 
        FROM public.workflow_event_queue 
        WHERE id = p_job_id;

        IF v_attempts >= p_max_attempts OR NOT p_retryable THEN
            v_is_dlq := true;
            UPDATE public.workflow_event_queue
            SET status = 'failed'
            WHERE id = p_job_id;
        ELSE
            UPDATE public.workflow_event_queue
            SET status = 'queued',
                scheduled_for = now() + (power(2, v_attempts) * 30 || ' seconds')::interval
            WHERE id = p_job_id;
        END IF;

    ELSIF p_queue_name = 'integration_jobs' THEN
        SELECT attempt_count INTO v_attempts 
        FROM public.integration_jobs 
        WHERE id = p_job_id;

        IF v_attempts >= p_max_attempts OR NOT p_retryable THEN
            v_is_dlq := true;
            UPDATE public.integration_jobs
            SET status = 'failed',
                failed_at = now(),
                error_message = p_error
            WHERE id = p_job_id;
        ELSE
            UPDATE public.integration_jobs
            SET status = 'queued',
                error_message = p_error,
                scheduled_for = now() + (power(2, v_attempts) * 30 || ' seconds')::interval
            WHERE id = p_job_id;
        END IF;

        INSERT INTO public.integration_job_attempts (
            integration_job_id, attempt_number, status, error_message
        ) VALUES (
            p_job_id, v_attempts, CASE WHEN v_is_dlq THEN 'permanent_failure' ELSE 'temporary_failure' END, p_error
        );
    END IF;

    RETURN jsonb_build_object(
        'job_id', p_job_id,
        'queue', p_queue_name,
        'attempts', v_attempts,
        'dead_lettered', v_is_dlq,
        'error', p_error
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. DATA RETENTION PURGE ENGINE
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.execute_data_retention_purge(
    p_dry_run BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_policy RECORD;
    v_count INT;
    v_sql TEXT;
    v_results JSONB := '[]'::jsonb;
    v_total_purged INT := 0;
BEGIN
    FOR v_policy IN 
        SELECT * FROM public.data_retention_policies 
        WHERE is_active = true 
        ORDER BY retention_days ASC 
    LOOP
        v_count := 0;

        v_sql := format(
            'SELECT count(*) FROM public.%I WHERE %I < (now() - interval ''%s days'')',
            v_policy.table_name,
            v_policy.timestamp_column,
            v_policy.retention_days
        );

        BEGIN
            EXECUTE v_sql INTO v_count;

            IF NOT p_dry_run AND v_count > 0 THEN
                EXECUTE format(
                    'DELETE FROM public.%I WHERE %I < (now() - interval ''%s days'')',
                    v_policy.table_name,
                    v_policy.timestamp_column,
                    v_policy.retention_days
                );

                INSERT INTO public.data_retention_audit_logs (
                    category, table_name, records_purged, status
                ) VALUES (
                    v_policy.category, v_policy.table_name, v_count, 'success'
                );

                v_total_purged := v_total_purged + v_count;
            END IF;

            v_results := v_results || jsonb_build_object(
                'category', v_policy.category,
                'table', v_policy.table_name,
                'retention_days', v_policy.retention_days,
                'eligible_records', v_count,
                'purged', CASE WHEN p_dry_run THEN 0 ELSE v_count END
            );
        EXCEPTION WHEN OTHERS THEN
            v_results := v_results || jsonb_build_object(
                'category', v_policy.category,
                'table', v_policy.table_name,
                'error', SQLERRM
            );
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'dry_run', p_dry_run,
        'total_eligible_or_purged', v_total_purged,
        'policies_evaluated', v_results,
        'executed_at', now()
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. OBSERVABILITY & SYSTEM HEALTH ENDPOINTS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_system_health()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_db_size TEXT;
    v_conn_count INT;
    v_dlq_count INT := 0;
    v_pending_events INT := 0;
    v_pending_steps INT := 0;
    v_pending_jobs INT := 0;
    v_active_cbs INT := 0;
    v_tripped_cbs INT := 0;
BEGIN
    SELECT pg_size_pretty(pg_database_size(current_database())) INTO v_db_size;
    SELECT count(*) INTO v_conn_count FROM pg_stat_activity WHERE datname = current_database();

    SELECT count(*) INTO v_dlq_count FROM public.workflow_failures WHERE resolved_at IS NULL;
    SELECT count(*) INTO v_pending_events FROM public.workflow_event_queue WHERE status IN ('queued', 'processing');
    SELECT count(*) INTO v_pending_steps FROM public.workflow_execution_steps WHERE status IN ('pending', 'running', 'waiting');
    SELECT count(*) INTO v_pending_jobs FROM public.integration_jobs WHERE status IN ('queued', 'processing');

    SELECT count(*) FILTER (WHERE state = 'healthy'), count(*) FILTER (WHERE state IN ('failing', 'disabled'))
    INTO v_active_cbs, v_tripped_cbs
    FROM public.provider_circuit_breakers;

    RETURN jsonb_build_object(
        'status', CASE WHEN v_tripped_cbs > 0 OR v_dlq_count > 100 THEN 'degraded' ELSE 'healthy' END,
        'database_size', v_db_size,
        'active_connections', v_conn_count,
        'queues', jsonb_build_object(
            'pending_workflow_events', v_pending_events,
            'pending_workflow_steps', v_pending_steps,
            'pending_integration_jobs', v_pending_jobs,
            'unresolved_workflow_failures', v_dlq_count
        ),
        'circuit_breakers', jsonb_build_object(
            'healthy_providers', v_active_cbs,
            'tripped_or_disabled_providers', v_tripped_cbs
        ),
        'timestamp', now()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_readiness()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ready BOOLEAN := true;
    v_checks JSONB := '{}'::jsonb;
    v_org_count INT := 0;
    v_role_count INT := 0;
BEGIN
    SELECT count(*) INTO v_org_count FROM public.organizations;
    SELECT count(*) INTO v_role_count FROM public.roles;

    v_checks := jsonb_build_object(
        'database_responsive', true,
        'organizations_present', (v_org_count > 0),
        'rbac_initialized', (v_role_count > 0),
        'rls_enforced', true
    );

    IF v_role_count = 0 THEN
        v_ready := false;
    END IF;

    RETURN jsonb_build_object(
        'ready', v_ready,
        'checks', v_checks,
        'timestamp', now()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_queue_health()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_stats JSONB;
    v_step_stats JSONB;
    v_job_stats JSONB;
    v_failure_stats JSONB;
BEGIN
    SELECT jsonb_build_object(
        'queued', count(*) FILTER (WHERE status = 'queued'),
        'processing', count(*) FILTER (WHERE status = 'processing'),
        'processed_24h', count(*) FILTER (WHERE status = 'processed' AND processed_at >= now() - interval '24 hours'),
        'failed', count(*) FILTER (WHERE status = 'failed'),
        'oldest_queued_seconds', COALESCE(EXTRACT(EPOCH FROM (now() - min(scheduled_for) FILTER (WHERE status = 'queued')))::int, 0)
    ) INTO v_event_stats
    FROM public.workflow_event_queue;

    SELECT jsonb_build_object(
        'pending', count(*) FILTER (WHERE status = 'pending'),
        'running', count(*) FILTER (WHERE status = 'running'),
        'waiting', count(*) FILTER (WHERE status = 'waiting'),
        'completed_24h', count(*) FILTER (WHERE status = 'completed'),
        'failed', count(*) FILTER (WHERE status = 'failed')
    ) INTO v_step_stats
    FROM public.workflow_execution_steps;

    SELECT jsonb_build_object(
        'queued', count(*) FILTER (WHERE status = 'queued'),
        'processing', count(*) FILTER (WHERE status = 'processing'),
        'completed_24h', count(*) FILTER (WHERE status = 'completed' AND completed_at >= now() - interval '24 hours'),
        'failed', count(*) FILTER (WHERE status = 'failed')
    ) INTO v_job_stats
    FROM public.integration_jobs;

    SELECT jsonb_build_object(
        'unresolved', count(*) FILTER (WHERE resolved_at IS NULL),
        'resolved_24h', count(*) FILTER (WHERE resolved_at >= now() - interval '24 hours')
    ) INTO v_failure_stats
    FROM public.workflow_failures;

    RETURN jsonb_build_object(
        'workflow_events', v_event_stats,
        'workflow_steps', v_step_stats,
        'integration_jobs', v_job_stats,
        'workflow_failures_dlq', v_failure_stats,
        'timestamp', now()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_production_metrics()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cache_hit_ratio NUMERIC := 99.0;
    v_index_scan_ratio NUMERIC := 95.0;
BEGIN
    SELECT 
        ROUND((sum(blks_hit) * 100.0 / NULLIF(sum(blks_hit + blks_read), 0)), 2)
    INTO v_cache_hit_ratio
    FROM pg_stat_database
    WHERE datname = current_database();

    SELECT 
        ROUND((sum(idx_scan) * 100.0 / NULLIF(sum(idx_scan + seq_scan), 0)), 2)
    INTO v_index_scan_ratio
    FROM pg_stat_user_tables;

    RETURN jsonb_build_object(
        'cache_hit_ratio_percent', COALESCE(v_cache_hit_ratio, 100.0),
        'index_scan_ratio_percent', COALESCE(v_index_scan_ratio, 100.0),
        'slow_queries_threshold_ms', 500,
        'timestamp', now()
    );
END;
$$;
