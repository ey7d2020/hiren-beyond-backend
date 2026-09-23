-- =============================================================================
-- Migration: 20260915001501_fix_integrations_extensions_path.sql
-- Description: Add extensions to search_path and qualify crypto functions
-- =============================================================================

-- A. START OAUTH SESSION
CREATE OR REPLACE FUNCTION public.start_oauth_session(
    p_organization_id  UUID,
    p_provider_key     VARCHAR(100),
    p_redirect_uri     TEXT,
    p_scopes           TEXT[] DEFAULT NULL,
    p_connection_scope VARCHAR(50) DEFAULT 'organization'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_provider     RECORD;
    v_state        TEXT;
    v_session_id   UUID := gen_random_uuid();
    v_scopes       TEXT[];
    v_expires_at   TIMESTAMPTZ := now() + INTERVAL '15 minutes';
    v_auth_url     TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthenticated: Caller must be logged in';
    END IF;

    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(v_user_id) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not an authorized recruiter for organization %', p_organization_id;
    END IF;

    SELECT * INTO v_provider FROM public.integration_providers WHERE key = p_provider_key AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Provider % not found or not active', p_provider_key;
    END IF;

    -- Cryptographically unpredictable state
    v_state := encode(extensions.gen_random_bytes(32), 'hex');

    -- Resolve scopes
    IF p_scopes IS NOT NULL AND array_length(p_scopes, 1) > 0 THEN
        v_scopes := p_scopes;
    ELSE
        SELECT COALESCE(array_agg(e::text), ARRAY[]::text[])
        INTO v_scopes
        FROM jsonb_array_elements_text(v_provider.configuration->'default_scopes') e;
    END IF;

    INSERT INTO public.integration_oauth_sessions (
        id, organization_id, user_id, provider_id, connection_scope,
        state, redirect_uri, scopes, status, expires_at
    ) VALUES (
        v_session_id, p_organization_id, v_user_id, v_provider.id, p_connection_scope,
        v_state, p_redirect_uri, v_scopes, 'pending', v_expires_at
    );

    v_auth_url := 'https://accounts.provider.auth/oauth?client_id=registered&state=' || v_state || '&redirect_uri=' || p_redirect_uri;

    RETURN jsonb_build_object(
        'session_id', v_session_id,
        'state', v_state,
        'provider', p_provider_key,
        'connection_scope', p_connection_scope,
        'scopes', v_scopes,
        'expires_at', v_expires_at,
        'auth_url', v_auth_url
    );
END;
$$;

-- B. COMPLETE OAUTH SESSION
CREATE OR REPLACE FUNCTION public.complete_oauth_session(
    p_state                 VARCHAR(128),
    p_external_account_id   TEXT,
    p_external_account_email TEXT,
    p_granted_scopes        TEXT[],
    p_credential_ref        TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_session     RECORD;
    v_provider    RECORD;
    v_conn_id     UUID;
    v_req_scopes  TEXT[];
    v_scope       TEXT;
    v_missing     TEXT[] := ARRAY[]::text[];
BEGIN
    SELECT * INTO v_session
    FROM public.integration_oauth_sessions
    WHERE state = p_state
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid OAuth state token: session not found or already consumed';
    END IF;

    IF v_session.status <> 'pending' THEN
        RAISE EXCEPTION 'OAuth session is no longer pending (current: %)', v_session.status;
    END IF;

    IF v_session.expires_at < now() THEN
        UPDATE public.integration_oauth_sessions SET status = 'expired' WHERE id = v_session.id;
        RAISE EXCEPTION 'OAuth session has expired at %', v_session.expires_at;
    END IF;

    SELECT * INTO v_provider FROM public.integration_providers WHERE id = v_session.provider_id;

    -- Validate granted scopes vs required scopes
    v_req_scopes := v_session.scopes;
    FOREACH v_scope IN ARRAY v_req_scopes LOOP
        IF NOT (v_scope = ANY(p_granted_scopes)) THEN
            v_missing := array_append(v_missing, v_scope);
        END IF;
    END LOOP;

    IF array_length(v_missing, 1) > 0 THEN
        RAISE EXCEPTION 'Missing required OAuth scopes: %', v_missing;
    END IF;

    -- Create or update connection
    INSERT INTO public.integration_connections (
        organization_id, provider_id, connected_by, user_id, connection_scope,
        status, connection_name, external_account_id, external_account_email,
        scopes, credential_reference, connected_at, last_success_at
    ) VALUES (
        v_session.organization_id, v_session.provider_id, v_session.user_id,
        CASE WHEN v_session.connection_scope = 'user' THEN v_session.user_id ELSE NULL END,
        v_session.connection_scope, 'active',
        v_provider.name || ' (' || COALESCE(p_external_account_email, p_external_account_id, 'Primary') || ')',
        p_external_account_id, p_external_account_email,
        p_granted_scopes, p_credential_ref, now(), now()
    )
    RETURNING id INTO v_conn_id;

    -- Mark session completed (prevents replay attack)
    UPDATE public.integration_oauth_sessions
    SET status                    = 'completed',
        integration_connection_id = v_conn_id
    WHERE id = v_session.id;

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
        v_session.organization_id, v_session.user_id, 'integration_connected', 'integration_connection', v_conn_id,
        jsonb_build_object(
            'provider', v_provider.key,
            'scope', v_session.connection_scope,
            'account_email', p_external_account_email
        )
    );

    RETURN jsonb_build_object(
        'connection_id', v_conn_id,
        'provider', v_provider.key,
        'status', 'active',
        'connection_scope', v_session.connection_scope,
        'external_account_email', p_external_account_email,
        'connected_at', now()
    );
END;
$$;

-- E. SYNC INTERVIEW CALENDAR EVENT
CREATE OR REPLACE FUNCTION public.sync_interview_calendar_event(
    p_interview_id      UUID,
    p_action            VARCHAR(50) DEFAULT 'create',
    p_simulate_failure  BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_interview     RECORD;
    v_job_id        UUID;
    v_idempotency   TEXT;
    v_external_evt  TEXT;
    v_meeting_url   TEXT;
    v_existing_job  RECORD;
BEGIN
    SELECT * INTO v_interview FROM public.interviews WHERE id = p_interview_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    v_idempotency := 'cal_sync_' || p_interview_id || '_' || p_action;

    -- Check if already processed idempotently
    SELECT * INTO v_existing_job
    FROM public.integration_jobs
    WHERE idempotency_key = v_idempotency;

    IF FOUND AND v_existing_job.status = 'completed' THEN
        RETURN jsonb_build_object(
            'status', 'already_processed',
            'interview_id', p_interview_id,
            'action', p_action,
            'calendar_event_id', v_interview.calendar_event_id
        );
    END IF;

    -- Provider Failure Isolation: If provider simulation or outage occurs
    IF p_simulate_failure THEN
        INSERT INTO public.integration_jobs (
            organization_id, job_type, entity_type, entity_id, payload,
            idempotency_key, status, attempt_count, failed_at, error_code, error_message
        ) VALUES (
            v_interview.organization_id, 'calendar_event_sync', 'interview', p_interview_id,
            jsonb_build_object('action', p_action, 'simulated', true),
            v_idempotency, 'failed', 1, now(), 'PROVIDER_TIMEOUT_504',
            'Google Calendar API timed out after 30000ms'
        ) RETURNING id INTO v_job_id;

        -- Notice: We do NOT rollback or alter internal interview status!
        RETURN jsonb_build_object(
            'status', 'failed',
            'interview_id', p_interview_id,
            'job_id', v_job_id,
            'error', 'Google Calendar API timed out after 30000ms',
            'retryable', true
        );
    END IF;

    IF p_action = 'create' THEN
        IF v_interview.calendar_event_id IS NOT NULL THEN
            v_external_evt := v_interview.calendar_event_id;
        ELSE
            v_external_evt := 'gcal_evt_' || substr(v_interview.id::text, 1, 16);
            v_meeting_url  := 'https://meet.google.com/' || substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 3) || '-' ||
                              substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 4) || '-' ||
                              substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 3);

            UPDATE public.interviews
            SET calendar_event_id = v_external_evt,
                calendar_provider = 'google_calendar',
                meeting_url       = v_meeting_url,
                meeting_provider  = 'google_meet',
                updated_at        = now()
            WHERE id = p_interview_id;
        END IF;

    ELSIF p_action = 'update' THEN
        -- Reschedule: Update calendar event, preserving external calendar_event_id
        v_external_evt := v_interview.calendar_event_id;
        UPDATE public.interviews
        SET updated_at = now()
        WHERE id = p_interview_id;

    ELSIF p_action = 'cancel' THEN
        v_external_evt := v_interview.calendar_event_id;
    END IF;

    -- Record completed integration job
    INSERT INTO public.integration_jobs (
        organization_id, job_type, entity_type, entity_id, payload,
        idempotency_key, status, attempt_count, completed_at
    ) VALUES (
        v_interview.organization_id, 'calendar_event_' || p_action, 'interview', p_interview_id,
        jsonb_build_object(
            'action', p_action,
            'calendar_event_id', v_external_evt,
            'start', v_interview.scheduled_start_at,
            'end', v_interview.scheduled_end_at
        ),
        v_idempotency, 'completed', 1, now()
    ) RETURNING id INTO v_job_id;

    RETURN jsonb_build_object(
        'status', 'completed',
        'job_id', v_job_id,
        'interview_id', p_interview_id,
        'action', p_action,
        'calendar_event_id', v_external_evt,
        'meeting_url', v_interview.meeting_url
    );
END;
$$;

-- F. SEND WHATSAPP MESSAGE
CREATE OR REPLACE FUNCTION public.send_whatsapp_message(
    p_organization_id   UUID,
    p_recipient_user_id UUID,
    p_destination       TEXT,
    p_template_name     VARCHAR(255),
    p_parameters        JSONB DEFAULT '{}'::jsonb,
    p_simulate_failure  BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_tmpl        RECORD;
    v_delivery_id UUID;
    v_idempotency TEXT;
    v_msg_id      TEXT;
    v_status      TEXT := 'sent';
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Cannot send WhatsApp message for organization %', p_organization_id;
    END IF;

    SELECT * INTO v_tmpl
    FROM public.whatsapp_templates
    WHERE organization_id = p_organization_id AND name = p_template_name;

    v_idempotency := 'wa_' || p_organization_id || '_' || p_recipient_user_id || '_' || encode(extensions.digest(p_destination || p_template_name || p_parameters::text, 'sha256'), 'hex');

    IF p_simulate_failure THEN
        v_status := 'failed';
        INSERT INTO public.notification_deliveries (
            recipient_user_id, channel, destination, status, provider,
            failure_code, failure_message, idempotency_key
        ) VALUES (
            p_recipient_user_id, 'whatsapp', p_destination, 'failed', 'meta_whatsapp',
            'WHATSAPP_INVALID_RECIPIENT_NUMBER', 'Phone number not registered on WhatsApp', v_idempotency
        ) RETURNING id INTO v_delivery_id;

        RETURN jsonb_build_object(
            'delivery_id', v_delivery_id,
            'status', 'failed',
            'error', 'Phone number not registered on WhatsApp',
            'retryable', false
        );
    END IF;

    v_msg_id := 'wamid.' || encode(extensions.gen_random_bytes(16), 'hex');

    INSERT INTO public.notification_deliveries (
        recipient_user_id, channel, destination, status, provider,
        provider_message_id, idempotency_key, sent_at
    ) VALUES (
        p_recipient_user_id, 'whatsapp', p_destination, 'sent', 'meta_whatsapp',
        v_msg_id, v_idempotency, now()
    ) RETURNING id INTO v_delivery_id;

    RETURN jsonb_build_object(
        'delivery_id', v_delivery_id,
        'provider_message_id', v_msg_id,
        'status', 'sent',
        'channel', 'whatsapp',
        'destination', p_destination
    );
END;
$$;

-- H. DISPATCH OUTBOUND WEBHOOK
CREATE OR REPLACE FUNCTION public.dispatch_outbound_webhook(
    p_organization_id UUID,
    p_event_type      VARCHAR(100),
    p_event_id        UUID,
    p_payload         JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    r_wh           RECORD;
    v_signature    TEXT;
    v_secret_key   TEXT;
    v_deliv_id     UUID;
    v_idempotency  TEXT;
    v_dispatched   INT := 0;
BEGIN
    FOR r_wh IN
        SELECT * FROM public.outbound_webhooks
        WHERE organization_id = p_organization_id
          AND status = 'active'
          AND (p_event_type = ANY(events) OR '*' = ANY(events))
    LOOP
        v_idempotency := 'wh_deliv_' || r_wh.id || '_' || p_event_id;

        v_secret_key := 'whsec_' || encode(extensions.digest(r_wh.secret_reference, 'sha256'), 'hex');
        v_signature  := 'sha256=' || encode(extensions.hmac(p_payload::text, v_secret_key, 'sha256'), 'hex');

        INSERT INTO public.webhook_deliveries (
            webhook_id, event_type, event_id, idempotency_key, attempt_count,
            status, http_status, response_time_ms, signature, request_payload, delivered_at
        ) VALUES (
            r_wh.id, p_event_type, p_event_id, v_idempotency, 1,
            'delivered', 200, 48, v_signature, p_payload, now()
        ) RETURNING id INTO v_deliv_id;

        v_dispatched := v_dispatched + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'event_type', p_event_type,
        'event_id', p_event_id,
        'dispatched_webhooks', v_dispatched
    );
END;
$$;

-- I. PROCESS INCOMING WEBHOOK
CREATE OR REPLACE FUNCTION public.process_incoming_webhook(
    p_provider          VARCHAR(100),
    p_external_event_id TEXT,
    p_event_type        VARCHAR(100),
    p_payload           JSONB,
    p_signature         TEXT,
    p_expected_secret   TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
    v_computed_sig TEXT;
    v_event_id     UUID;
BEGIN
    -- 1. Anti-Replay Defense: Check duplicate
    IF EXISTS (
        SELECT 1 FROM public.incoming_webhook_events
        WHERE provider = p_provider AND external_event_id = p_external_event_id
    ) THEN
        RETURN jsonb_build_object(
            'status', 'ignored',
            'reason', 'duplicate_external_event_id',
            'provider', p_provider,
            'external_event_id', p_external_event_id
        );
    END IF;

    -- 2. Verify HMAC Signature
    v_computed_sig := 'sha256=' || encode(extensions.hmac(p_payload::text, p_expected_secret, 'sha256'), 'hex');

    IF p_signature IS NULL OR p_signature <> v_computed_sig THEN
        INSERT INTO public.incoming_webhook_events (
            provider, external_event_id, event_type, signature_verified, payload, status, error_message
        ) VALUES (
            p_provider, p_external_event_id, p_event_type, false, p_payload, 'failed', 'Invalid HMAC-SHA256 signature'
        ) RETURNING id INTO v_event_id;

        RAISE EXCEPTION 'Webhook signature verification failed for provider % (event %)', p_provider, p_external_event_id;
    END IF;

    -- 3. Ingest verified payload
    INSERT INTO public.incoming_webhook_events (
        provider, external_event_id, event_type, signature_verified, payload, status, processed_at
    ) VALUES (
        p_provider, p_external_event_id, p_event_type, true, p_payload, 'processed', now()
    ) RETURNING id INTO v_event_id;

    RETURN jsonb_build_object(
        'status', 'processed',
        'event_id', v_event_id,
        'provider', p_provider,
        'external_event_id', p_external_event_id,
        'signature_verified', true
    );
END;
$$;
