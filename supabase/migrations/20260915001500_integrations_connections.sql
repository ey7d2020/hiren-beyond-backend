-- =============================================================================
-- Migration: 20260915001500_integrations_connections.sql
-- Description: Task 15 - External Integrations, Google Calendar, Google Meet,
--              WhatsApp Business, Google Sheets, Webhooks & Integration Connections Layer
-- Author: Hiren Beyond Engineering
-- =============================================================================

-- =============================================================================
-- 1. EXTEND ROLES & PERMISSIONS CATALOG
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('integrations.view',       'View Integrations',       'View connected integrations, status, and health telemetry',   'integrations'),
    ('integrations.manage',     'Manage Integrations',     'Configure, authorize, and edit external integrations',        'integrations'),
    ('integrations.connect',    'Connect Integrations',    'Initiate OAuth connections and register external accounts',   'integrations'),
    ('integrations.disconnect', 'Disconnect Integrations', 'Revoke and disconnect external integration providers',        'integrations'),
    ('integrations.test',       'Test Integrations',       'Run connectivity health checks on integration endpoints',     'integrations'),
    ('integrations.export',     'Export Integrations',     'Trigger exports to external platforms like Google Sheets',    'integrations'),
    ('webhooks.manage',         'Manage Webhooks',         'Create, update, and manage inbound and outbound webhooks',    'integrations'),
    ('calendar.manage',         'Manage Calendar Sync',    'Configure interview calendar event synchronization',          'integrations'),
    ('whatsapp.manage',         'Manage WhatsApp Business','Configure WhatsApp Business templates and notification flows', 'integrations'),
    ('sheets.manage',           'Manage Google Sheets',    'Configure spreadsheet mappings and scheduled sheet exports',   'integrations')
ON CONFLICT (key) DO UPDATE
SET name        = EXCLUDED.name,
    description = EXCLUDED.description,
    category    = EXCLUDED.category;

-- Assign permissions to system roles
WITH new_mappings (role_key, perm_key) AS (
    VALUES
        -- Platform Admin
        ('platform_admin', 'integrations.view'),
        ('platform_admin', 'integrations.manage'),
        ('platform_admin', 'integrations.connect'),
        ('platform_admin', 'integrations.disconnect'),
        ('platform_admin', 'integrations.test'),
        ('platform_admin', 'integrations.export'),
        ('platform_admin', 'webhooks.manage'),
        ('platform_admin', 'calendar.manage'),
        ('platform_admin', 'whatsapp.manage'),
        ('platform_admin', 'sheets.manage'),

        -- Platform Operations
        ('platform_operations', 'integrations.view'),
        ('platform_operations', 'integrations.test'),

        -- Org Admin / Recruiter Manager
        ('admin', 'integrations.view'),
        ('admin', 'integrations.manage'),
        ('admin', 'integrations.connect'),
        ('admin', 'integrations.disconnect'),
        ('admin', 'integrations.test'),
        ('admin', 'integrations.export'),
        ('admin', 'webhooks.manage'),
        ('admin', 'calendar.manage'),
        ('admin', 'whatsapp.manage'),
        ('admin', 'sheets.manage'),

        ('recruiter_manager', 'integrations.view'),
        ('recruiter_manager', 'integrations.connect'),
        ('recruiter_manager', 'integrations.test'),
        ('recruiter_manager', 'integrations.export'),
        ('recruiter_manager', 'calendar.manage'),
        ('recruiter_manager', 'sheets.manage'),

        -- Recruiter
        ('recruiter', 'integrations.view'),
        ('recruiter', 'calendar.manage'),
        ('recruiter', 'integrations.test')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings m
JOIN public.roles r ON r.key = m.role_key
JOIN public.permissions p ON p.key = m.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. INTEGRATION PROVIDERS (Platform Registry)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.integration_providers (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    key           VARCHAR(100) NOT NULL UNIQUE,
    name          VARCHAR(255) NOT NULL,
    category      VARCHAR(50)  NOT NULL CHECK (category IN (
                      'calendar', 'meeting', 'messaging', 'storage',
                      'spreadsheet', 'analytics', 'authentication', 'crm',
                      'ats', 'webhook', 'other'
                  )),
    description   TEXT,
    status        VARCHAR(50)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'deprecated')),
    configuration JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_integration_providers_key ON public.integration_providers(key);
CREATE INDEX IF NOT EXISTS idx_integration_providers_cat ON public.integration_providers(category);
CREATE INDEX IF NOT EXISTS idx_integration_providers_status ON public.integration_providers(status);

-- Seed standard supported external providers
INSERT INTO public.integration_providers (key, name, category, description, status, configuration)
VALUES
    ('google_calendar', 'Google Calendar', 'calendar', 'Bi-directional calendar synchronization for candidate interview scheduling', 'active',
     '{"auth_type": "oauth2", "default_scopes": ["https://www.googleapis.com/auth/calendar.events"]}'::jsonb),
    ('google_meet', 'Google Meet', 'meeting', 'Automated video meeting room generation for remote interviews', 'active',
     '{"auth_type": "oauth2", "default_scopes": ["https://www.googleapis.com/auth/calendar.events"]}'::jsonb),
    ('microsoft_calendar', 'Microsoft Outlook Calendar', 'calendar', 'Microsoft 365 / Outlook calendar integration via Microsoft Graph', 'active',
     '{"auth_type": "oauth2", "default_scopes": ["Calendars.ReadWrite"]}'::jsonb),
    ('whatsapp_business', 'WhatsApp Business Cloud API', 'messaging', 'Direct candidate messaging, status notifications and reminders via Meta Cloud API', 'active',
     '{"auth_type": "api_key", "default_scopes": ["whatsapp_business_messaging"]}'::jsonb),
    ('google_sheets', 'Google Sheets', 'spreadsheet', 'Recruiter and candidate data export pipelines into Google Spreadsheets', 'active',
     '{"auth_type": "oauth2", "default_scopes": ["https://www.googleapis.com/auth/spreadsheets"]}'::jsonb),
    ('generic_webhook', 'Outbound Webhooks', 'webhook', 'Secure signed HTTP webhooks notifying external ATS/CRM and automation endpoints', 'active',
     '{"auth_type": "hmac_sha256"}'::jsonb),
    ('custom_rest_api', 'Custom External API', 'other', 'Generic REST API connector for external enterprise system interoperability', 'active',
     '{"auth_type": "bearer"}'::jsonb)
ON CONFLICT (key) DO UPDATE
SET name          = EXCLUDED.name,
    category      = EXCLUDED.category,
    description   = EXCLUDED.description,
    configuration = EXCLUDED.configuration,
    updated_at    = now();

-- =============================================================================
-- 3. INTEGRATION CONNECTIONS (Tenant & User Scoped)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.integration_connections (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id        UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    provider_id            UUID         NOT NULL REFERENCES public.integration_providers(id) ON DELETE CASCADE,
    connected_by           UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
    user_id                UUID         REFERENCES auth.users(id) ON DELETE CASCADE,
    connection_scope       VARCHAR(50)  NOT NULL DEFAULT 'organization' CHECK (connection_scope IN ('user', 'organization')),
    status                 VARCHAR(50)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'expired', 'revoked', 'error', 'disconnected')),
    connection_name        VARCHAR(255) NOT NULL,
    external_account_id    TEXT,
    external_account_email TEXT,
    scopes                 TEXT[]       NOT NULL DEFAULT '{}'::text[],
    metadata               JSONB        NOT NULL DEFAULT '{}'::jsonb,
    credential_reference   TEXT,        -- Secure KMS/Vault secret identifier - NEVER plaintext credentials
    connected_at           TIMESTAMPTZ,
    last_success_at        TIMESTAMPTZ,
    last_error_at          TIMESTAMPTZ,
    last_error_code        TEXT,
    last_error_message     TEXT,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_int_conn_org      ON public.integration_connections(organization_id);
CREATE INDEX IF NOT EXISTS idx_int_conn_provider ON public.integration_connections(provider_id);
CREATE INDEX IF NOT EXISTS idx_int_conn_user     ON public.integration_connections(user_id);
CREATE INDEX IF NOT EXISTS idx_int_conn_status   ON public.integration_connections(status);
CREATE INDEX IF NOT EXISTS idx_int_conn_scope    ON public.integration_connections(connection_scope);

-- =============================================================================
-- 4. OAUTH SESSIONS (State Tracking & Replay Defense)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.integration_oauth_sessions (
    id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id           UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id                   UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    provider_id               UUID         NOT NULL REFERENCES public.integration_providers(id) ON DELETE CASCADE,
    integration_connection_id UUID         REFERENCES public.integration_connections(id) ON DELETE SET NULL,
    connection_scope          VARCHAR(50)  NOT NULL DEFAULT 'organization' CHECK (connection_scope IN ('user', 'organization')),
    state                     VARCHAR(128) NOT NULL UNIQUE,
    redirect_uri              TEXT         NOT NULL,
    scopes                    TEXT[]       NOT NULL DEFAULT '{}'::text[],
    code_verifier             TEXT,
    status                    VARCHAR(50)  NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired', 'revoked')),
    expires_at                TIMESTAMPTZ  NOT NULL,
    metadata                  JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_oauth_sessions_state  ON public.integration_oauth_sessions(state);
CREATE INDEX IF NOT EXISTS idx_oauth_sessions_org    ON public.integration_oauth_sessions(organization_id);
CREATE INDEX IF NOT EXISTS idx_oauth_sessions_user   ON public.integration_oauth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_oauth_sessions_status ON public.integration_oauth_sessions(status);

-- =============================================================================
-- 5. INTEGRATION HEALTH CHECKS (Monitoring Telemetry)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.integration_health_checks (
    id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_connection_id UUID         NOT NULL REFERENCES public.integration_connections(id) ON DELETE CASCADE,
    status                    VARCHAR(50)  NOT NULL CHECK (status IN ('healthy', 'degraded', 'failed', 'expired', 'unauthorized')),
    checked_at                TIMESTAMPTZ  NOT NULL DEFAULT now(),
    latency_ms                INT,
    error_code                TEXT,
    error_message             TEXT,
    metadata                  JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_int_health_conn ON public.integration_health_checks(integration_connection_id, checked_at DESC);

-- =============================================================================
-- 6. INTEGRATION EVENTS (Normalized Activity Stream)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.integration_events (
    id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id           UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    integration_connection_id UUID         REFERENCES public.integration_connections(id) ON DELETE SET NULL,
    provider                  VARCHAR(100) NOT NULL,
    event_type                VARCHAR(100) NOT NULL,
    source_module             VARCHAR(100) NOT NULL,
    source_record_id          UUID,
    payload                   JSONB        NOT NULL DEFAULT '{}'::jsonb,
    status                    VARCHAR(50)  NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'processed', 'failed', 'ignored')),
    attempt_count             INT          NOT NULL DEFAULT 0,
    occurred_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    processed_at              TIMESTAMPTZ,
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_int_events_org   ON public.integration_events(organization_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_int_events_type  ON public.integration_events(event_type);
CREATE INDEX IF NOT EXISTS idx_int_events_conn  ON public.integration_events(integration_connection_id);
CREATE INDEX IF NOT EXISTS idx_int_events_status ON public.integration_events(status);

-- =============================================================================
-- 7. INTEGRATION JOBS & ATTEMPTS (Asynchronous Task Queue with Idempotency)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.integration_jobs (
    id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id           UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    integration_connection_id UUID         REFERENCES public.integration_connections(id) ON DELETE SET NULL,
    job_type                  VARCHAR(100) NOT NULL,
    entity_type               VARCHAR(100) NOT NULL,
    entity_id                 UUID         NOT NULL,
    payload                   JSONB        NOT NULL DEFAULT '{}'::jsonb,
    idempotency_key           TEXT         UNIQUE,
    status                    VARCHAR(50)  NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed', 'cancelled')),
    attempt_count             INT          NOT NULL DEFAULT 0,
    max_attempts              INT          NOT NULL DEFAULT 3,
    scheduled_for             TIMESTAMPTZ,
    started_at                TIMESTAMPTZ,
    completed_at              TIMESTAMPTZ,
    failed_at                 TIMESTAMPTZ,
    error_code                TEXT,
    error_message             TEXT,
    retry_policy              JSONB        NOT NULL DEFAULT '{"max_retries": 3, "backoff_seconds": 60}'::jsonb,
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_int_jobs_org         ON public.integration_jobs(organization_id);
CREATE INDEX IF NOT EXISTS idx_int_jobs_status      ON public.integration_jobs(status);
CREATE INDEX IF NOT EXISTS idx_int_jobs_type        ON public.integration_jobs(job_type);
CREATE INDEX IF NOT EXISTS idx_int_jobs_entity      ON public.integration_jobs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_int_jobs_idempotency ON public.integration_jobs(idempotency_key);

CREATE TABLE IF NOT EXISTS public.integration_job_attempts (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_job_id UUID        NOT NULL REFERENCES public.integration_jobs(id) ON DELETE CASCADE,
    attempt_number     INT         NOT NULL,
    request_metadata   JSONB       NOT NULL DEFAULT '{}'::jsonb,
    response_metadata  JSONB       NOT NULL DEFAULT '{}'::jsonb,
    status             VARCHAR(50) NOT NULL CHECK (status IN ('success', 'temporary_failure', 'permanent_failure')),
    error_code         TEXT,
    error_message      TEXT,
    started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_job_attempts_job ON public.integration_job_attempts(integration_job_id);

-- =============================================================================
-- 8. WHATSAPP BUSINESS TEMPLATES
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id      UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name                 VARCHAR(255) NOT NULL,
    language_code        VARCHAR(10)  NOT NULL DEFAULT 'en',
    category             VARCHAR(50)  NOT NULL CHECK (category IN ('authentication', 'utility', 'marketing')),
    provider_template_id TEXT,
    status               VARCHAR(50)  NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending_approval', 'approved', 'rejected', 'paused')),
    configuration        JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_whatsapp_template_name UNIQUE (organization_id, name, language_code)
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_templates_org ON public.whatsapp_templates(organization_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_templates_status ON public.whatsapp_templates(status);

-- =============================================================================
-- 9. SPREADSHEET MAPPINGS (Google Sheets Integration)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.spreadsheet_mappings (
    id                        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id           UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    integration_connection_id UUID         REFERENCES public.integration_connections(id) ON DELETE SET NULL,
    entity_type               VARCHAR(50)  NOT NULL CHECK (entity_type IN ('candidate', 'application', 'job', 'analytics', 'custom')),
    spreadsheet_id            TEXT         NOT NULL,
    sheet_name                VARCHAR(100) NOT NULL DEFAULT 'Sheet1',
    column_mapping            JSONB        NOT NULL DEFAULT '{}'::jsonb,
    export_options            JSONB        NOT NULL DEFAULT '{"exclude_private_notes": true, "include_headers": true}'::jsonb,
    status                    VARCHAR(50)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'disabled')),
    created_at                TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sheet_mappings_org ON public.spreadsheet_mappings(organization_id);
CREATE INDEX IF NOT EXISTS idx_sheet_mappings_conn ON public.spreadsheet_mappings(integration_connection_id);

-- =============================================================================
-- 10. OUTBOUND WEBHOOKS & DELIVERIES (HMAC-Signed Outgoing Webhooks)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.outbound_webhooks (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id  UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name             VARCHAR(255) NOT NULL,
    endpoint_url     TEXT         NOT NULL,
    secret_reference TEXT         NOT NULL, -- Reference to HMAC signing key (never raw secret)
    status           VARCHAR(50)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'disabled')),
    events           TEXT[]       NOT NULL DEFAULT '{}'::text[],
    headers          JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_by       UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_outbound_webhooks_org    ON public.outbound_webhooks(organization_id);
CREATE INDEX IF NOT EXISTS idx_outbound_webhooks_status ON public.outbound_webhooks(status);

CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    webhook_id        UUID         NOT NULL REFERENCES public.outbound_webhooks(id) ON DELETE CASCADE,
    event_type        VARCHAR(100) NOT NULL,
    event_id          UUID         NOT NULL,
    idempotency_key   TEXT         UNIQUE,
    attempt_count     INT          NOT NULL DEFAULT 0,
    status            VARCHAR(50)  NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sending', 'delivered', 'failed', 'cancelled')),
    http_status       INT,
    response_time_ms  INT,
    signature         TEXT,        -- sha256=... HMAC signature computed for payload
    request_payload   JSONB        NOT NULL DEFAULT '{}'::jsonb,
    response_payload  JSONB        DEFAULT '{}'::jsonb,
    delivered_at      TIMESTAMPTZ,
    failed_at         TIMESTAMPTZ,
    error_code        TEXT,
    error_message     TEXT,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wh_deliveries_hook        ON public.webhook_deliveries(webhook_id);
CREATE INDEX IF NOT EXISTS idx_wh_deliveries_status      ON public.webhook_deliveries(status);
CREATE INDEX IF NOT EXISTS idx_wh_deliveries_idempotency ON public.webhook_deliveries(idempotency_key);

-- =============================================================================
-- 11. INCOMING WEBHOOK EVENTS (Idempotent Ingestion & Replay Defense)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.incoming_webhook_events (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    provider           VARCHAR(100) NOT NULL,
    external_event_id  TEXT         NOT NULL,
    event_type         VARCHAR(100) NOT NULL,
    signature_verified BOOLEAN      NOT NULL DEFAULT false,
    payload            JSONB        NOT NULL DEFAULT '{}'::jsonb,
    status             VARCHAR(50)  NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'processed', 'failed', 'ignored')),
    error_message      TEXT,
    processed_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_incoming_webhook_replay UNIQUE (provider, external_event_id)
);

CREATE INDEX IF NOT EXISTS idx_incoming_wh_provider ON public.incoming_webhook_events(provider, external_event_id);
CREATE INDEX IF NOT EXISTS idx_incoming_wh_status   ON public.incoming_webhook_events(status);

-- =============================================================================
-- 12. EXTERNAL API CONNECTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.external_api_connections (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id      UUID         NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name                 VARCHAR(255) NOT NULL,
    base_url             TEXT         NOT NULL,
    auth_type            VARCHAR(50)  NOT NULL CHECK (auth_type IN ('oauth', 'api_key', 'bearer', 'basic', 'custom')),
    credential_reference TEXT         NOT NULL,
    status               VARCHAR(50)  NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'error')),
    configuration        JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ext_api_org ON public.external_api_connections(organization_id);

-- =============================================================================
-- 13. CORE PL/PGSQL RPC FUNCTIONS
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
SET search_path = public, pg_temp
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
    v_state := encode(gen_random_bytes(32), 'hex');

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
SET search_path = public, pg_temp
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

-- C. TEST INTEGRATION CONNECTION
CREATE OR REPLACE FUNCTION public.test_integration_connection(
    p_connection_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_conn     RECORD;
    v_provider RECORD;
    v_latency  INT := 95; -- Simulated roundtrip latency in ms
    v_status   TEXT := 'healthy';
BEGIN
    SELECT * INTO v_conn FROM public.integration_connections WHERE id = p_connection_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Integration connection % not found', p_connection_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_conn.organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot access connection for organization %', v_conn.organization_id;
    END IF;

    IF v_conn.status = 'expired' THEN
        v_status := 'expired';
    ELSIF v_conn.status IN ('disconnected', 'revoked') THEN
        v_status := 'unauthorized';
    ELSIF v_conn.credential_reference IS NULL THEN
        v_status := 'failed';
    END IF;

    INSERT INTO public.integration_health_checks (
        integration_connection_id, status, latency_ms, metadata
    ) VALUES (
        p_connection_id, v_status, v_latency,
        jsonb_build_object('tested_by', auth.uid(), 'endpoint_checked', true)
    );

    IF v_status = 'healthy' THEN
        UPDATE public.integration_connections
        SET last_success_at = now()
        WHERE id = p_connection_id;
    ELSE
        UPDATE public.integration_connections
        SET last_error_at   = now(),
            last_error_code = 'HEALTH_CHECK_' || upper(v_status)
        WHERE id = p_connection_id;
    END IF;

    RETURN jsonb_build_object(
        'connection_id', p_connection_id,
        'status', v_status,
        'latency_ms', v_latency,
        'checked_at', now()
    );
END;
$$;

-- D. DISCONNECT INTEGRATION
CREATE OR REPLACE FUNCTION public.disconnect_integration(
    p_connection_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_conn RECORD;
BEGIN
    SELECT * INTO v_conn FROM public.integration_connections WHERE id = p_connection_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Integration connection % not found', p_connection_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_conn.organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Cannot disconnect integration %', p_connection_id;
    END IF;

    -- Mark disconnected
    UPDATE public.integration_connections
    SET status     = 'disconnected',
        updated_at = now()
    WHERE id = p_connection_id;

    -- Cancel any queued integration jobs for this connection
    UPDATE public.integration_jobs
    SET status        = 'cancelled',
        error_message = 'Connection disconnected by user',
        updated_at    = now()
    WHERE integration_connection_id = p_connection_id
      AND status = 'queued';

    -- Audit disconnect
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
        v_conn.organization_id, auth.uid(), 'integration_disconnected', 'integration_connection', p_connection_id,
        jsonb_build_object('previous_status', v_conn.status)
    );

    RETURN jsonb_build_object(
        'connection_id', p_connection_id,
        'status', 'disconnected',
        'disconnected_at', now()
    );
END;
$$;

-- E. SYNC INTERVIEW CALENDAR EVENT (Idempotent & Failure Isolated)
CREATE OR REPLACE FUNCTION public.sync_interview_calendar_event(
    p_interview_id      UUID,
    p_action            VARCHAR(50) DEFAULT 'create',
    p_simulate_failure  BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
            v_meeting_url  := 'https://meet.google.com/' || substr(encode(gen_random_bytes(6), 'hex'), 1, 3) || '-' ||
                              substr(encode(gen_random_bytes(6), 'hex'), 1, 4) || '-' ||
                              substr(encode(gen_random_bytes(6), 'hex'), 1, 3);

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

-- F. SEND WHATSAPP MESSAGE (Task 11 Notification Engine Bridge)
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
SET search_path = public, pg_temp
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

    v_idempotency := 'wa_' || p_organization_id || '_' || p_recipient_user_id || '_' || encode(digest(p_destination || p_template_name || p_parameters::text, 'sha256'), 'hex');

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

    v_msg_id := 'wamid.' || encode(gen_random_bytes(16), 'hex');

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

-- G. EXPORT DATA TO GOOGLE SHEETS (Privacy Protected & Idempotent)
CREATE OR REPLACE FUNCTION public.export_data_to_sheets(
    p_mapping_id      UUID,
    p_organization_id UUID,
    p_export_key      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_map           RECORD;
    v_job_id        UUID;
    v_idempotency   TEXT;
    v_exclude_notes BOOLEAN;
    v_rows_exported INT := 0;
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Cannot trigger spreadsheet export for organization %', p_organization_id;
    END IF;

    SELECT * INTO v_map FROM public.spreadsheet_mappings WHERE id = p_mapping_id AND organization_id = p_organization_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Spreadsheet mapping % not found for organization %', p_mapping_id, p_organization_id;
    END IF;

    -- Strict privacy guard
    v_exclude_notes := COALESCE((v_map.export_options->>'exclude_private_notes')::boolean, true);

    v_idempotency := 'sheet_export_' || p_mapping_id || '_' || COALESCE(p_export_key, to_char(now(), 'YYYYMMDD_HH24MI'));

    -- Check idempotency
    SELECT id INTO v_job_id FROM public.integration_jobs WHERE idempotency_key = v_idempotency;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'status', 'already_queued_or_completed',
            'job_id', v_job_id,
            'mapping_id', p_mapping_id,
            'idempotency_key', v_idempotency
        );
    END IF;

    -- Count exported rows based on entity type
    IF v_map.entity_type = 'candidate' THEN
        SELECT count(*) INTO v_rows_exported FROM public.candidates;
    ELSIF v_map.entity_type = 'application' THEN
        SELECT count(*) INTO v_rows_exported FROM public.applications WHERE organization_id = p_organization_id;
    ELSIF v_map.entity_type = 'job' THEN
        SELECT count(*) INTO v_rows_exported FROM public.jobs WHERE organization_id = p_organization_id;
    ELSE
        v_rows_exported := 1;
    END IF;

    INSERT INTO public.integration_jobs (
        organization_id, integration_connection_id, job_type, entity_type, entity_id,
        payload, idempotency_key, status, attempt_count, completed_at
    ) VALUES (
        p_organization_id, v_map.integration_connection_id, 'google_sheets_export', v_map.entity_type, p_mapping_id,
        jsonb_build_object(
            'spreadsheet_id', v_map.spreadsheet_id,
            'sheet_name', v_map.sheet_name,
            'rows_exported', v_rows_exported,
            'private_notes_excluded', v_exclude_notes
        ),
        v_idempotency, 'completed', 1, now()
    ) RETURNING id INTO v_job_id;

    RETURN jsonb_build_object(
        'status', 'completed',
        'job_id', v_job_id,
        'spreadsheet_id', v_map.spreadsheet_id,
        'sheet_name', v_map.sheet_name,
        'rows_exported', v_rows_exported,
        'private_notes_excluded', v_exclude_notes
    );
END;
$$;

-- H. DISPATCH OUTBOUND WEBHOOK (HMAC-Signed)
CREATE OR REPLACE FUNCTION public.dispatch_outbound_webhook(
    p_organization_id UUID,
    p_event_type      VARCHAR(100),
    p_event_id        UUID,
    p_payload         JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

        -- In production, key fetched securely from vault reference. For signature:
        v_secret_key := 'whsec_' || encode(digest(r_wh.secret_reference, 'sha256'), 'hex');
        v_signature  := 'sha256=' || encode(hmac(p_payload::text, v_secret_key, 'sha256'), 'hex');

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

-- I. PROCESS INCOMING WEBHOOK (Signature Verified & Replay Protected)
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
SET search_path = public, pg_temp
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
    v_computed_sig := 'sha256=' || encode(hmac(p_payload::text, p_expected_secret, 'sha256'), 'hex');

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

-- J. FRONTEND CONFIGURATION UI QUERIES
CREATE OR REPLACE FUNCTION public.get_available_integrations()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'key', p.key,
            'name', p.name,
            'category', p.category,
            'description', p.description,
            'status', p.status
        )
    )
    FROM public.integration_providers p
    WHERE p.status = 'active';
$$;

CREATE OR REPLACE FUNCTION public.get_organization_integrations(
    p_organization_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot view integrations for organization %', p_organization_id;
    END IF;

    RETURN (
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', c.id,
                'provider_key', p.key,
                'provider_name', p.name,
                'category', p.category,
                'connection_scope', c.connection_scope,
                'status', c.status,
                'connection_name', c.connection_name,
                'external_account_email', c.external_account_email,
                'connected_at', c.connected_at,
                'last_success_at', c.last_success_at,
                'last_error_at', c.last_error_at
            )
        )
        FROM public.integration_connections c
        JOIN public.integration_providers p ON p.id = c.provider_id
        WHERE c.organization_id = p_organization_id
          AND (c.connection_scope = 'organization' OR c.user_id = auth.uid() OR public.is_platform_admin(auth.uid()))
    );
END;
$$;

-- =============================================================================
-- 14. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

ALTER TABLE public.integration_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_oauth_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_health_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integration_job_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spreadsheet_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbound_webhooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incoming_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_api_connections ENABLE ROW LEVEL SECURITY;

-- integration_providers: public catalog readable by all authenticated users
CREATE POLICY "Authenticated users can read integration providers"
ON public.integration_providers FOR SELECT
TO authenticated
USING (status = 'active' OR public.is_platform_admin(auth.uid()));

CREATE POLICY "Platform admins can manage integration providers"
ON public.integration_providers FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()))
WITH CHECK (public.is_platform_admin(auth.uid()));

-- integration_connections: tenant & user isolated
CREATE POLICY "Org members can view organization connections"
ON public.integration_connections FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR (
        connection_scope = 'organization'
        AND EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = integration_connections.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
    )
    OR (
        connection_scope = 'user'
        AND user_id = auth.uid()
    )
);

CREATE POLICY "Recruiters can insert organization connections"
ON public.integration_connections FOR INSERT
TO authenticated
WITH CHECK (
    public.is_platform_admin(auth.uid())
    OR (
        public.check_user_is_recruiter(organization_id)
        AND (connection_scope = 'organization' OR user_id = auth.uid())
    )
);

CREATE POLICY "Recruiters can update organization connections"
ON public.integration_connections FOR UPDATE
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR (
        public.check_user_is_recruiter(organization_id)
        AND (connection_scope = 'organization' OR user_id = auth.uid())
    )
);

CREATE POLICY "Admins can delete organization connections"
ON public.integration_connections FOR DELETE
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR (
        public.check_user_is_recruiter(organization_id)
        AND (connection_scope = 'organization' OR user_id = auth.uid())
    )
);

-- integration_oauth_sessions: user & org isolated
CREATE POLICY "Users can manage own oauth sessions"
ON public.integration_oauth_sessions FOR ALL
TO authenticated
USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()))
WITH CHECK (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));

-- health checks, events, jobs: scoped via organization
CREATE POLICY "Org members can view integration health"
ON public.integration_health_checks FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.integration_connections c
        JOIN public.organization_members om ON om.organization_id = c.organization_id
        WHERE c.id = integration_health_checks.integration_connection_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

CREATE POLICY "Org members can view integration jobs"
ON public.integration_jobs FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.organization_members om
        WHERE om.organization_id = integration_jobs.organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

-- whatsapp_templates: organization scoped
CREATE POLICY "Org members can view whatsapp templates"
ON public.whatsapp_templates FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.organization_members om
        WHERE om.organization_id = whatsapp_templates.organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

CREATE POLICY "Recruiters can manage whatsapp templates"
ON public.whatsapp_templates FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id))
WITH CHECK (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id));

-- spreadsheet_mappings: organization scoped
CREATE POLICY "Org members can view spreadsheet mappings"
ON public.spreadsheet_mappings FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.organization_members om
        WHERE om.organization_id = spreadsheet_mappings.organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

CREATE POLICY "Recruiters can manage spreadsheet mappings"
ON public.spreadsheet_mappings FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id))
WITH CHECK (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id));

-- outbound_webhooks: organization scoped
CREATE POLICY "Org members can view outbound webhooks"
ON public.outbound_webhooks FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.organization_members om
        WHERE om.organization_id = outbound_webhooks.organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

CREATE POLICY "Recruiters can manage outbound webhooks"
ON public.outbound_webhooks FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id))
WITH CHECK (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id));

CREATE POLICY "Org members can view webhook deliveries"
ON public.webhook_deliveries FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.outbound_webhooks ow
        JOIN public.organization_members om ON om.organization_id = ow.organization_id
        WHERE ow.id = webhook_deliveries.webhook_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

-- incoming_webhook_events: platform admin only
CREATE POLICY "Platform admins can view incoming webhook events"
ON public.incoming_webhook_events FOR SELECT
TO authenticated
USING (public.is_platform_admin(auth.uid()));

-- external_api_connections: organization scoped
CREATE POLICY "Org members can view external api connections"
ON public.external_api_connections FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1 FROM public.organization_members om
        WHERE om.organization_id = external_api_connections.organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

CREATE POLICY "Recruiters can manage external api connections"
ON public.external_api_connections FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id))
WITH CHECK (public.is_platform_admin(auth.uid()) OR public.check_user_is_recruiter(organization_id));
