-- ============================================================================
-- Hiren Beyond Backend — Migration 20260915002200
-- Task 22: Public API Layer, API Keys, Webhooks, Developer API,
--          External Access & Integration Contracts
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PERMISSIONS SEEDING
-- ----------------------------------------------------------------------------

INSERT INTO public.permissions (key, name, description, category)
VALUES 
    ('api.view', 'View API Applications & Keys', 'Allows viewing developer API keys and applications', 'api'),
    ('api.manage', 'Manage API Applications', 'Allows creating, modifying, and suspending API applications', 'api'),
    ('api.keys.manage', 'Manage API Keys', 'Allows creating, rotating, and revoking API keys', 'api'),
    ('api.webhooks.manage', 'Manage API Webhook Subscriptions', 'Allows subscribing API applications to webhook events', 'api'),
    ('api.analytics.view', 'View API Usage & Metrics', 'Allows viewing API consumption, rate limits, and latency', 'api')
ON CONFLICT (key) DO NOTHING;

-- Grant API permissions to admin roles
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id 
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.name IN ('organization_admin', 'super_admin', 'platform_admin')
  AND p.category = 'api'
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. CORE DEVELOPER PLATFORM TABLES
-- ----------------------------------------------------------------------------

-- A. API Applications
CREATE TABLE IF NOT EXISTS public.api_applications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    client_type     VARCHAR(50) NOT NULL DEFAULT 'server' CHECK (client_type IN ('server', 'web', 'mobile', 'partner', 'internal')),
    status          VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'revoked')),
    created_by      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_apps_org ON public.api_applications (organization_id);
CREATE INDEX IF NOT EXISTS idx_api_apps_status ON public.api_applications (status);

ALTER TABLE public.api_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_applications_select ON public.api_applications
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    );

CREATE POLICY api_applications_write ON public.api_applications
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (
            SELECT om.organization_id 
            FROM public.organization_members om
            JOIN public.role_permissions rp ON om.role_id = rp.role_id
            JOIN public.permissions p ON rp.permission_id = p.id
            WHERE om.user_id = auth.uid() AND p.key = 'api.manage'
        )
    );

-- B. API Keys (Store key_prefix + SHA-256 hash ONLY. Never plaintext!)
CREATE TABLE IF NOT EXISTS public.api_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_application_id  UUID NOT NULL REFERENCES public.api_applications(id) ON DELETE CASCADE,
    organization_id     UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name                VARCHAR(255) NOT NULL,
    key_prefix          VARCHAR(32) NOT NULL,
    key_hash            VARCHAR(128) NOT NULL UNIQUE,
    status              VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
    expires_at          TIMESTAMPTZ,
    last_used_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_api_keys_prefix_hash ON public.api_keys (key_prefix, key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_app ON public.api_keys (api_application_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_org ON public.api_keys (organization_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_status ON public.api_keys (status);

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_keys_select ON public.api_keys
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    );

CREATE POLICY api_keys_write ON public.api_keys
    FOR ALL TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (
            SELECT om.organization_id 
            FROM public.organization_members om
            JOIN public.role_permissions rp ON om.role_id = rp.role_id
            JOIN public.permissions p ON rp.permission_id = p.id
            WHERE om.user_id = auth.uid() AND p.key = 'api.keys.manage'
        )
    );

-- C. API Scopes
CREATE TABLE IF NOT EXISTS public.api_scopes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_key   VARCHAR(100) NOT NULL UNIQUE,
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    risk_level  VARCHAR(50) NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high')),
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.api_scopes ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_scopes_read ON public.api_scopes FOR SELECT TO authenticated USING (true);
CREATE POLICY api_scopes_write ON public.api_scopes FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));

-- Seed API Scopes
INSERT INTO public.api_scopes (scope_key, name, description, risk_level)
VALUES 
    ('jobs.read', 'Read Jobs', 'Allows querying published and active job requisitions', 'low'),
    ('jobs.write', 'Create & Edit Jobs', 'Allows creating and managing job requisitions', 'medium'),
    ('candidates.read', 'Read Candidates', 'Allows viewing candidate profiles and public CV data', 'medium'),
    ('candidates.write', 'Create & Update Candidates', 'Allows submitting candidates and updating work history', 'medium'),
    ('applications.read', 'Read ATS Applications', 'Allows querying job applications and stages', 'medium'),
    ('applications.write', 'Manage Applications', 'Allows submitting applications and advancing stages', 'high'),
    ('interviews.read', 'Read Interviews', 'Allows viewing scheduled interview appointments', 'low'),
    ('interviews.write', 'Schedule Interviews', 'Allows booking and cancelling interviews', 'medium'),
    ('assessments.read', 'Read Assessment Results', 'Allows viewing candidate scorecards and readiness', 'medium'),
    ('analytics.read', 'Read Recruitment Analytics', 'Allows querying recruitment funnels and job metrics', 'low'),
    ('webhooks.manage', 'Manage Webhook Subscriptions', 'Allows subscribing to platform lifecycle events', 'high')
ON CONFLICT (scope_key) DO NOTHING;

-- D. API Key Scopes (Junction)
CREATE TABLE IF NOT EXISTS public.api_key_scopes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_key_id  UUID NOT NULL REFERENCES public.api_keys(id) ON DELETE CASCADE,
    scope_id    UUID NOT NULL REFERENCES public.api_scopes(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_api_key_scopes UNIQUE (api_key_id, scope_id)
);

CREATE INDEX IF NOT EXISTS idx_api_key_scopes_key ON public.api_key_scopes (api_key_id);

ALTER TABLE public.api_key_scopes ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_key_scopes_read ON public.api_key_scopes
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.api_keys k 
            WHERE k.id = api_key_id 
              AND (public.is_platform_admin(auth.uid()) OR k.organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid()))
        )
    );

CREATE POLICY api_key_scopes_write ON public.api_key_scopes
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.api_keys k 
            WHERE k.id = api_key_id 
              AND (public.is_platform_admin(auth.uid()) OR k.organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid()))
        )
    );

-- E. API Usage Records & Metering
CREATE TABLE IF NOT EXISTS public.api_usage_records (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    api_application_id  UUID NOT NULL REFERENCES public.api_applications(id) ON DELETE CASCADE,
    api_key_id          UUID REFERENCES public.api_keys(id) ON DELETE SET NULL,
    endpoint            VARCHAR(255) NOT NULL,
    http_method         VARCHAR(20) NOT NULL,
    status_code         INT NOT NULL,
    request_id          VARCHAR(100) NOT NULL,
    latency_ms          INT NOT NULL DEFAULT 0,
    rate_limit_group    VARCHAR(100) DEFAULT 'default',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_usage_org_created ON public.api_usage_records (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_usage_app_created ON public.api_usage_records (api_application_id, created_at DESC);

ALTER TABLE public.api_usage_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_usage_records_select ON public.api_usage_records
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    );

-- F. API Request Logs (Controlled Operational Audit)
CREATE TABLE IF NOT EXISTS public.api_request_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    api_key_id      UUID REFERENCES public.api_keys(id) ON DELETE SET NULL,
    request_id      VARCHAR(100) NOT NULL,
    endpoint        VARCHAR(255) NOT NULL,
    method          VARCHAR(20) NOT NULL,
    status_code     INT NOT NULL,
    duration_ms     INT NOT NULL DEFAULT 0,
    error_code      VARCHAR(100),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_req_logs_org_req ON public.api_request_logs (organization_id, request_id);
CREATE INDEX IF NOT EXISTS idx_api_req_logs_created ON public.api_request_logs (created_at DESC);

ALTER TABLE public.api_request_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_request_logs_select ON public.api_request_logs
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    );

-- G. API Rate Limits
CREATE TABLE IF NOT EXISTS public.api_rate_limits (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    api_application_id  UUID REFERENCES public.api_applications(id) ON DELETE CASCADE,
    scope_key           VARCHAR(100) NOT NULL DEFAULT 'global',
    requests_per_minute INT NOT NULL DEFAULT 60,
    requests_per_hour   INT NOT NULL DEFAULT 1000,
    requests_per_day    INT NOT NULL DEFAULT 10000,
    burst_limit         INT NOT NULL DEFAULT 20,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_api_rate_limits UNIQUE (organization_id, api_application_id, scope_key)
);

ALTER TABLE public.api_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_rate_limits_select ON public.api_rate_limits
    FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid()) OR 
        organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    );

CREATE POLICY api_rate_limits_write ON public.api_rate_limits
    FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()));

-- H. API Endpoints Registry
CREATE TABLE IF NOT EXISTS public.api_endpoints (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version         VARCHAR(20) NOT NULL DEFAULT 'v1',
    method          VARCHAR(20) NOT NULL,
    path            VARCHAR(255) NOT NULL,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    required_scopes TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
    risk_level      VARCHAR(50) NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high')),
    is_public       BOOLEAN NOT NULL DEFAULT true,
    status          VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'deprecated', 'disabled')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_api_endpoints_v_m_p UNIQUE (version, method, path)
);

ALTER TABLE public.api_endpoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_endpoints_read ON public.api_endpoints FOR SELECT TO authenticated USING (true);
CREATE POLICY api_endpoints_write ON public.api_endpoints FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));

-- Seed v1 Public API Registry
INSERT INTO public.api_endpoints (version, method, path, name, description, required_scopes, risk_level)
VALUES 
    ('v1', 'GET', '/api/v1/jobs', 'List Jobs', 'Query active jobs with pagination and filters', ARRAY['jobs.read'], 'low'),
    ('v1', 'GET', '/api/v1/jobs/{id}', 'Get Job Details', 'Retrieve single job requisition', ARRAY['jobs.read'], 'low'),
    ('v1', 'POST', '/api/v1/jobs', 'Create Job', 'Create a new job requisition', ARRAY['jobs.write'], 'medium'),
    ('v1', 'GET', '/api/v1/candidates', 'List Candidates', 'Query candidates with privacy filtering', ARRAY['candidates.read'], 'medium'),
    ('v1', 'GET', '/api/v1/applications', 'List Applications', 'Query job applications for an organization', ARRAY['applications.read'], 'medium'),
    ('v1', 'POST', '/api/v1/applications/{id}/stage', 'Update Stage', 'Advance or move application stage', ARRAY['applications.write'], 'high'),
    ('v1', 'GET', '/api/v1/interviews', 'List Interviews', 'Query scheduled interviews', ARRAY['interviews.read'], 'low'),
    ('v1', 'GET', '/api/v1/assessments', 'List Assessments', 'Query candidate readiness and assessment status', ARRAY['assessments.read'], 'medium'),
    ('v1', 'GET', '/api/v1/analytics', 'Get Recruitment Analytics', 'Query recruitment KPIs and funnels', ARRAY['analytics.read'], 'low'),
    ('v1', 'POST', '/api/v1/webhooks/subscriptions', 'Subscribe Webhook', 'Subscribe application to platform webhooks', ARRAY['webhooks.manage'], 'high')
ON CONFLICT (version, method, path) DO NOTHING;

-- I. API Idempotency Records
CREATE TABLE IF NOT EXISTS public.api_idempotency_records (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_application_id      UUID NOT NULL REFERENCES public.api_applications(id) ON DELETE CASCADE,
    idempotency_key         VARCHAR(255) NOT NULL,
    request_hash            VARCHAR(128) NOT NULL,
    response_status         INT NOT NULL,
    response_body_reference JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
    CONSTRAINT uq_api_idempotency UNIQUE (api_application_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_api_idempotency_lookup 
    ON public.api_idempotency_records (api_application_id, idempotency_key);

ALTER TABLE public.api_idempotency_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_idempotency_select ON public.api_idempotency_records
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.api_applications a 
            WHERE a.id = api_application_id 
              AND (public.is_platform_admin(auth.uid()) OR a.organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid()))
        )
    );

-- J. API Webhook Subscriptions (Connecting API apps to outbound_webhooks)
CREATE TABLE IF NOT EXISTS public.api_webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_application_id  UUID NOT NULL REFERENCES public.api_applications(id) ON DELETE CASCADE,
    webhook_id          UUID NOT NULL REFERENCES public.outbound_webhooks(id) ON DELETE CASCADE,
    event_types         TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
    status              VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'disabled')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.api_webhook_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_webhook_subscriptions_all ON public.api_webhook_subscriptions
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.api_applications a 
            WHERE a.id = api_application_id 
              AND (public.is_platform_admin(auth.uid()) OR a.organization_id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid()))
        )
    );

-- K. API Documentation Metadata
CREATE TABLE IF NOT EXISTS public.api_documentation (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    api_version         VARCHAR(20) NOT NULL UNIQUE,
    title               VARCHAR(255) NOT NULL,
    description         TEXT,
    status              VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'deprecated', 'retired')),
    base_url            TEXT NOT NULL,
    documentation_url   TEXT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.api_documentation ENABLE ROW LEVEL SECURITY;

CREATE POLICY api_documentation_read ON public.api_documentation FOR SELECT TO authenticated USING (true);
CREATE POLICY api_documentation_write ON public.api_documentation FOR ALL TO authenticated USING (public.is_platform_admin(auth.uid()));

INSERT INTO public.api_documentation (api_version, title, description, base_url, documentation_url)
VALUES (
    'v1', 
    'Hiren Beyond Public Developer API v1', 
    'Secure external REST API for jobs, candidates, applications, interviews, and webhooks.',
    'https://api.hirenbeyond.com/api/v1',
    'https://docs.hirenbeyond.com/api/v1'
) ON CONFLICT (api_version) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 3. CORE DEVELOPER PLATFORM RPCS
-- ----------------------------------------------------------------------------

-- A. Create API Application
CREATE OR REPLACE FUNCTION public.create_api_application(
    p_organization_id UUID,
    p_name TEXT,
    p_description TEXT DEFAULT NULL,
    p_client_type TEXT DEFAULT 'server'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_app_id UUID;
    v_caller_id UUID := auth.uid();
BEGIN
    IF NOT public.is_platform_admin(v_caller_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = p_organization_id AND om.user_id = v_caller_id
        ) THEN
            RAISE EXCEPTION 'UNAUTHORIZED: Caller does not belong to target organization';
        END IF;
    END IF;

    INSERT INTO public.api_applications (
        organization_id, name, description, client_type, created_by
    ) VALUES (
        p_organization_id, p_name, p_description, p_client_type, v_caller_id
    ) RETURNING id INTO v_app_id;

    -- Provision default rate limits
    INSERT INTO public.api_rate_limits (organization_id, api_application_id, scope_key, requests_per_minute, requests_per_hour, requests_per_day)
    VALUES (p_organization_id, v_app_id, 'global', 60, 1000, 10000)
    ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object(
        'application_id', v_app_id,
        'organization_id', p_organization_id,
        'name', p_name,
        'status', 'active',
        'client_type', p_client_type
    );
END;
$$;

-- B. Create API Key (Generate cryptographically random key, return plaintext ONCE)
CREATE OR REPLACE FUNCTION public.create_api_key(
    p_application_id UUID,
    p_name TEXT,
    p_scopes TEXT[] DEFAULT ARRAY['jobs.read', 'applications.read'],
    p_expires_in_days INT DEFAULT 365
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_app public.api_applications%ROWTYPE;
    v_random_secret TEXT;
    v_raw_key TEXT;
    v_key_prefix TEXT;
    v_key_hash TEXT;
    v_key_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_scope_id UUID;
    v_scope TEXT;
BEGIN
    SELECT * INTO v_app FROM public.api_applications WHERE id = p_application_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: API Application not found';
    END IF;

    IF v_app.status <> 'active' THEN
        RAISE EXCEPTION 'FORBIDDEN: API Application is not active';
    END IF;

    -- Generate cryptographically random secret string (32 hex characters)
    v_random_secret := encode(gen_random_bytes(24), 'hex');
    v_key_prefix := 'hb_live_' || substr(v_random_secret, 1, 8);
    v_raw_key := v_key_prefix || '_' || substr(v_random_secret, 9);
    v_key_hash := encode(sha256(v_raw_key::bytea), 'hex');

    IF p_expires_in_days IS NOT NULL AND p_expires_in_days > 0 THEN
        v_expires_at := now() + (p_expires_in_days || ' days')::interval;
    END IF;

    INSERT INTO public.api_keys (
        api_application_id, organization_id, name, key_prefix, key_hash, expires_at
    ) VALUES (
        p_application_id, v_app.organization_id, p_name, v_key_prefix, v_key_hash, v_expires_at
    ) RETURNING id INTO v_key_id;

    -- Assign scopes
    FOREACH v_scope IN ARRAY p_scopes LOOP
        SELECT id INTO v_scope_id FROM public.api_scopes WHERE scope_key = v_scope AND is_active = true;
        IF v_scope_id IS NOT NULL THEN
            INSERT INTO public.api_key_scopes (api_key_id, scope_id)
            VALUES (v_key_id, v_scope_id)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    -- Return raw key strictly once
    RETURN jsonb_build_object(
        'key_id', v_key_id,
        'application_id', p_application_id,
        'organization_id', v_app.organization_id,
        'name', p_name,
        'key_prefix', v_key_prefix,
        'api_key', v_raw_key, -- DISPLAY ONCE TO CONSUMER
        'expires_at', v_expires_at,
        'scopes', p_scopes,
        'warning', 'Store this API key safely. You will not be able to see it again.'
    );
END;
$$;

-- C. Revoke API Key
CREATE OR REPLACE FUNCTION public.revoke_api_key(
    p_key_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.api_keys
    SET status = 'revoked', revoked_at = now()
    WHERE id = p_key_id AND status = 'active';

    RETURN FOUND;
END;
$$;

-- D. Rotate API Key (Generates replacement key and revokes old after overlap)
CREATE OR REPLACE FUNCTION public.rotate_api_key(
    p_old_key_id UUID,
    p_name TEXT,
    p_overlap_hours INT DEFAULT 24
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_old_key public.api_keys%ROWTYPE;
    v_scopes TEXT[];
    v_new_key JSONB;
BEGIN
    SELECT * INTO v_old_key FROM public.api_keys WHERE id = p_old_key_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Key not found';
    END IF;

    -- Collect existing scopes
    SELECT array_agg(s.scope_key) INTO v_scopes
    FROM public.api_key_scopes ks
    JOIN public.api_scopes s ON ks.scope_id = s.id
    WHERE ks.api_key_id = p_old_key_id;

    -- Create new key
    v_new_key := public.create_api_key(v_old_key.api_application_id, p_name, v_scopes, 365);

    -- Set old key to expire after overlap period
    UPDATE public.api_keys
    SET expires_at = now() + (p_overlap_hours || ' hours')::interval
    WHERE id = p_old_key_id;

    RETURN jsonb_build_object(
        'new_key', v_new_key,
        'old_key_id', p_old_key_id,
        'old_key_expires_at', now() + (p_overlap_hours || ' hours')::interval
    );
END;
$$;

-- E. Authenticate API Key & Scope Verification
CREATE OR REPLACE FUNCTION public.authenticate_api_key(
    p_raw_key TEXT,
    p_required_scope TEXT DEFAULT NULL,
    p_endpoint TEXT DEFAULT '/api/v1',
    p_method TEXT DEFAULT 'GET'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_hash TEXT;
    v_key RECORD;
    v_scopes TEXT[];
    v_request_id TEXT := 'req_' || encode(gen_random_bytes(12), 'hex');
    v_rate_limit_ok BOOLEAN := true;
BEGIN
    IF p_raw_key IS NULL OR btrim(p_raw_key) = '' THEN
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Missing API key',
            'request_id', v_request_id
        );
    END IF;

    v_hash := encode(sha256(p_raw_key::bytea), 'hex');

    SELECT 
        k.id AS key_id,
        k.organization_id,
        k.api_application_id,
        k.status AS key_status,
        k.expires_at,
        a.status AS app_status
    INTO v_key
    FROM public.api_keys k
    JOIN public.api_applications a ON k.api_application_id = a.id
    WHERE k.key_hash = v_hash;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'Invalid API key',
            'request_id', v_request_id
        );
    END IF;

    -- Check application suspension
    IF v_key.app_status <> 'active' THEN
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'FORBIDDEN',
            'message', 'API Application is ' || v_key.app_status,
            'request_id', v_request_id
        );
    END IF;

    -- Check key status
    IF v_key.key_status = 'revoked' THEN
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'API key has been revoked',
            'request_id', v_request_id
        );
    END IF;

    -- Check key expiration
    IF v_key.expires_at IS NOT NULL AND v_key.expires_at <= now() THEN
        UPDATE public.api_keys SET status = 'expired' WHERE id = v_key.key_id;
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'UNAUTHORIZED',
            'message', 'API key has expired',
            'request_id', v_request_id
        );
    END IF;

    -- Retrieve assigned scopes
    SELECT array_agg(s.scope_key) INTO v_scopes
    FROM public.api_key_scopes ks
    JOIN public.api_scopes s ON ks.scope_id = s.id
    WHERE ks.api_key_id = v_key.key_id AND s.is_active = true;

    -- Verify scope if requested
    IF p_required_scope IS NOT NULL AND NOT (v_scopes @> ARRAY[p_required_scope]) THEN
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'FORBIDDEN',
            'message', 'API key lacks required scope: ' || p_required_scope,
            'assigned_scopes', COALESCE(v_scopes, ARRAY[]::TEXT[]),
            'request_id', v_request_id
        );
    END IF;

    -- Rate limiting check
    IF NOT (public.enforce_api_rate_limit(v_key.api_application_id, v_key.organization_id, 'global')) THEN
        RETURN jsonb_build_object(
            'authenticated', false,
            'error_code', 'RATE_LIMITED',
            'message', 'Rate limit exceeded for this API key/application',
            'request_id', v_request_id
        );
    END IF;

    -- Update last_used_at
    UPDATE public.api_keys SET last_used_at = now() WHERE id = v_key.key_id;

    RETURN jsonb_build_object(
        'authenticated', true,
        'organization_id', v_key.organization_id,
        'application_id', v_key.api_application_id,
        'key_id', v_key.key_id,
        'scopes', COALESCE(v_scopes, ARRAY[]::TEXT[]),
        'request_id', v_request_id
    );
END;
$$;

-- F. Enforce API Rate Limit (Sliding window count)
CREATE OR REPLACE FUNCTION public.enforce_api_rate_limit(
    p_application_id UUID,
    p_organization_id UUID,
    p_endpoint_group TEXT DEFAULT 'global'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit RECORD;
    v_req_count INT := 0;
BEGIN
    SELECT * INTO v_limit
    FROM public.api_rate_limits
    WHERE organization_id = p_organization_id
      AND (api_application_id = p_application_id OR api_application_id IS NULL)
      AND is_active = true
    ORDER BY api_application_id NULLS LAST
    LIMIT 1;

    IF NOT FOUND THEN
        -- Default unconfigured limit: 60 req/min
        SELECT count(*) INTO v_req_count
        FROM public.api_usage_records
        WHERE api_application_id = p_application_id
          AND created_at >= (now() - interval '1 minute');

        RETURN (v_req_count < 60);
    END IF;

    -- Check 1-minute window
    SELECT count(*) INTO v_req_count
    FROM public.api_usage_records
    WHERE api_application_id = p_application_id
      AND created_at >= (now() - interval '1 minute');

    IF v_req_count >= v_limit.requests_per_minute THEN
        RETURN false;
    END IF;

    RETURN true;
END;
$$;

-- G. Idempotency Validation & Recording
CREATE OR REPLACE FUNCTION public.validate_api_idempotency(
    p_application_id UUID,
    p_idempotency_key TEXT,
    p_request_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rec public.api_idempotency_records%ROWTYPE;
BEGIN
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RETURN jsonb_build_object('is_idempotent', false, 'status', 'proceed');
    END IF;

    SELECT * INTO v_rec 
    FROM public.api_idempotency_records
    WHERE api_application_id = p_application_id AND idempotency_key = p_idempotency_key;

    IF FOUND THEN
        IF v_rec.expires_at <= now() THEN
            DELETE FROM public.api_idempotency_records WHERE id = v_rec.id;
            RETURN jsonb_build_object('is_idempotent', false, 'status', 'proceed');
        END IF;

        IF v_rec.request_hash <> p_request_hash THEN
            RETURN jsonb_build_object(
                'is_idempotent', true,
                'status', 'conflict',
                'error_code', 'IDEMPOTENCY_CONFLICT',
                'message', 'Idempotency key provided with different request payload'
            );
        ELSE
            RETURN jsonb_build_object(
                'is_idempotent', true,
                'status', 'cached',
                'response_status', v_rec.response_status,
                'response_body', v_rec.response_body_reference
            );
        END IF;
    END IF;

    RETURN jsonb_build_object('is_idempotent', false, 'status', 'proceed');
END;
$$;

CREATE OR REPLACE FUNCTION public.record_api_idempotency(
    p_application_id UUID,
    p_idempotency_key TEXT,
    p_request_hash TEXT,
    p_response_status INT,
    p_response_ref JSONB DEFAULT '{}'::jsonb
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
        RETURN false;
    END IF;

    INSERT INTO public.api_idempotency_records (
        api_application_id, idempotency_key, request_hash, response_status, response_body_reference
    ) VALUES (
        p_application_id, p_idempotency_key, p_request_hash, p_response_status, p_response_ref
    ) ON CONFLICT (api_application_id, idempotency_key) DO NOTHING;

    RETURN true;
END;
$$;

-- H. API Usage & Request Log Tracking
CREATE OR REPLACE FUNCTION public.record_api_usage(
    p_application_id UUID,
    p_key_id UUID,
    p_organization_id UUID,
    p_endpoint TEXT,
    p_method TEXT,
    p_status_code INT,
    p_latency_ms INT,
    p_request_id TEXT,
    p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.api_usage_records (
        organization_id, api_application_id, api_key_id, endpoint, http_method, status_code, request_id, latency_ms
    ) VALUES (
        p_organization_id, p_application_id, p_key_id, p_endpoint, p_method, p_status_code, p_request_id, p_latency_ms
    );

    IF p_error_code IS NOT NULL OR p_status_code >= 400 THEN
        INSERT INTO public.api_request_logs (
            organization_id, api_key_id, request_id, endpoint, method, status_code, duration_ms, error_code
        ) VALUES (
            p_organization_id, p_key_id, p_request_id, p_endpoint, p_method, p_status_code, p_latency_ms, p_error_code
        );
    END IF;
END;
$$;

-- I. API Usage Dashboard Query
CREATE OR REPLACE FUNCTION public.get_api_usage_analytics(
    p_organization_id UUID,
    p_application_id UUID DEFAULT NULL,
    p_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total_req INT := 0;
    v_success_req INT := 0;
    v_error_req INT := 0;
    v_rate_limit_hits INT := 0;
    v_avg_latency INT := 0;
    v_top_endpoints JSONB := '[]'::jsonb;
BEGIN
    SELECT 
        count(*),
        count(*) FILTER (WHERE status_code >= 200 AND status_code < 400),
        count(*) FILTER (WHERE status_code >= 400),
        count(*) FILTER (WHERE status_code = 429),
        COALESCE(avg(latency_ms)::int, 0)
    INTO v_total_req, v_success_req, v_error_req, v_rate_limit_hits, v_avg_latency
    FROM public.api_usage_records
    WHERE organization_id = p_organization_id
      AND (p_application_id IS NULL OR api_application_id = p_application_id)
      AND created_at >= (now() - (p_days || ' days')::interval);

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object('endpoint', endpoint, 'method', http_method, 'calls', c)
    ), '[]'::jsonb)
    INTO v_top_endpoints
    FROM (
        SELECT endpoint, http_method, count(*) AS c
        FROM public.api_usage_records
        WHERE organization_id = p_organization_id
          AND (p_application_id IS NULL OR api_application_id = p_application_id)
          AND created_at >= (now() - (p_days || ' days')::interval)
        GROUP BY endpoint, http_method
        ORDER BY count(*) DESC
        LIMIT 10
    ) sub;

    RETURN jsonb_build_object(
        'organization_id', p_organization_id,
        'period_days', p_days,
        'total_requests', v_total_req,
        'successful_requests', v_success_req,
        'error_requests', v_error_req,
        'rate_limit_hits', v_rate_limit_hits,
        'average_latency_ms', v_avg_latency,
        'top_endpoints', v_top_endpoints
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. PUBLIC API RESOURCE HANDLERS (/api/v1 Dispatchers)
-- ----------------------------------------------------------------------------

-- A. GET /api/v1/jobs
CREATE OR REPLACE FUNCTION public.api_v1_get_jobs(
    p_api_key TEXT,
    p_limit INT DEFAULT 20,
    p_cursor TEXT DEFAULT NULL,
    p_status TEXT DEFAULT 'published'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_auth JSONB;
    v_org_id UUID;
    v_app_id UUID;
    v_key_id UUID;
    v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
    v_cursor_ts TIMESTAMPTZ := NULL;
    v_cursor_id UUID := NULL;
    v_items JSONB := '[]'::jsonb;
    v_next_cursor TEXT := NULL;
    v_has_more BOOLEAN := false;
    v_last_ts TIMESTAMPTZ;
    v_last_id UUID;
    v_t1 TIMESTAMPTZ := clock_timestamp();
    v_latency INT;
BEGIN
    v_auth := public.authenticate_api_key(p_api_key, 'jobs.read', '/api/v1/jobs', 'GET');
    IF NOT (v_auth->>'authenticated')::boolean THEN
        RETURN v_auth;
    END IF;

    v_org_id := (v_auth->>'organization_id')::uuid;
    v_app_id := (v_auth->>'application_id')::uuid;
    v_key_id := (v_auth->>'key_id')::uuid;

    IF p_cursor IS NOT NULL AND btrim(p_cursor) <> '' THEN
        SELECT cursor_created_at, cursor_id INTO v_cursor_ts, v_cursor_id
        FROM public.decode_pagination_cursor(p_cursor);
    END IF;

    WITH job_rows AS (
        SELECT id, organization_id, title, status, job_type, location, published_at, created_at
        FROM public.jobs
        WHERE organization_id = v_org_id
          AND (p_status IS NULL OR status = p_status)
          AND (v_cursor_ts IS NULL OR (created_at, id) < (v_cursor_ts, v_cursor_id))
        ORDER BY created_at DESC, id DESC
        LIMIT (v_limit + 1)
    )
    SELECT 
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', r.id,
                'title', r.title,
                'status', r.status,
                'job_type', r.job_type,
                'location', r.location,
                'published_at', r.published_at,
                'created_at', r.created_at
            )
        ) FILTER (WHERE rn <= v_limit), '[]'::jsonb),
        bool_or(rn > v_limit),
        max(r.created_at) FILTER (WHERE rn = v_limit),
        (max(r.id::text) FILTER (WHERE rn = v_limit))::uuid
    INTO v_items, v_has_more, v_last_ts, v_last_id
    FROM (SELECT *, row_number() OVER () AS rn FROM job_rows) r;

    IF v_has_more AND v_last_ts IS NOT NULL AND v_last_id IS NOT NULL THEN
        v_next_cursor := public.encode_pagination_cursor(v_last_ts, v_last_id);
    END IF;

    v_latency := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_t1))::int;
    PERFORM public.record_api_usage(v_app_id, v_key_id, v_org_id, '/api/v1/jobs', 'GET', 200, v_latency, v_auth->>'request_id');

    RETURN jsonb_build_object(
        'data', v_items,
        'pagination', jsonb_build_object(
            'has_more', COALESCE(v_has_more, false),
            'next_cursor', v_next_cursor,
            'limit', v_limit
        ),
        'request_id', v_auth->>'request_id'
    );
END;
$$;

-- B. POST /api/v1/jobs (Idempotent job creation)
CREATE OR REPLACE FUNCTION public.api_v1_create_job(
    p_api_key TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_job_type TEXT DEFAULT 'full_time',
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_auth JSONB;
    v_org_id UUID;
    v_app_id UUID;
    v_key_id UUID;
    v_req_hash TEXT;
    v_idem JSONB;
    v_job_id UUID;
    v_result JSONB;
    v_t1 TIMESTAMPTZ := clock_timestamp();
    v_latency INT;
BEGIN
    v_auth := public.authenticate_api_key(p_api_key, 'jobs.write', '/api/v1/jobs', 'POST');
    IF NOT (v_auth->>'authenticated')::boolean THEN
        RETURN v_auth;
    END IF;

    v_org_id := (v_auth->>'organization_id')::uuid;
    v_app_id := (v_auth->>'application_id')::uuid;
    v_key_id := (v_auth->>'key_id')::uuid;

    -- Validate input
    IF p_title IS NULL OR btrim(p_title) = '' THEN
        RETURN jsonb_build_object(
            'error', jsonb_build_object(
                'code', 'VALIDATION_ERROR',
                'message', 'Job title cannot be empty',
                'request_id', v_auth->>'request_id'
            )
        );
    END IF;

    -- Check Idempotency
    IF p_idempotency_key IS NOT NULL THEN
        v_req_hash := encode(sha256((COALESCE(p_title,'') || '|' || COALESCE(p_job_type,''))::bytea), 'hex');
        v_idem := public.validate_api_idempotency(v_app_id, p_idempotency_key, v_req_hash);
        IF (v_idem->>'status') = 'conflict' THEN
            RETURN jsonb_build_object(
                'error', jsonb_build_object(
                    'code', 'IDEMPOTENCY_CONFLICT',
                    'message', 'Idempotency key reused with different parameters',
                    'request_id', v_auth->>'request_id'
                )
            );
        ELSIF (v_idem->>'status') = 'cached' THEN
            RETURN v_idem->'response_body';
        END IF;
    END IF;

    -- Insert Job
    INSERT INTO public.jobs (
        organization_id, title, description, job_type, status, visibility
    ) VALUES (
        v_org_id, p_title, p_description, p_job_type, 'draft', 'public'
    ) RETURNING id INTO v_job_id;

    v_result := jsonb_build_object(
        'data', jsonb_build_object(
            'id', v_job_id,
            'title', p_title,
            'status', 'draft',
            'job_type', p_job_type,
            'created_at', now()
        ),
        'request_id', v_auth->>'request_id'
    );

    IF p_idempotency_key IS NOT NULL THEN
        PERFORM public.record_api_idempotency(v_app_id, p_idempotency_key, v_req_hash, 201, v_result);
    END IF;

    v_latency := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_t1))::int;
    PERFORM public.record_api_usage(v_app_id, v_key_id, v_org_id, '/api/v1/jobs', 'POST', 201, v_latency, v_auth->>'request_id');

    RETURN v_result;
END;
$$;

-- C. GET /api/v1/candidates (Privacy-Preserved View)
CREATE OR REPLACE FUNCTION public.api_v1_get_candidates(
    p_api_key TEXT,
    p_limit INT DEFAULT 20,
    p_cursor TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_auth JSONB;
    v_org_id UUID;
    v_app_id UUID;
    v_key_id UUID;
    v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
    v_items JSONB := '[]'::jsonb;
    v_t1 TIMESTAMPTZ := clock_timestamp();
    v_latency INT;
BEGIN
    v_auth := public.authenticate_api_key(p_api_key, 'candidates.read', '/api/v1/candidates', 'GET');
    IF NOT (v_auth->>'authenticated')::boolean THEN
        RETURN v_auth;
    END IF;

    v_org_id := (v_auth->>'organization_id')::uuid;
    v_app_id := (v_auth->>'application_id')::uuid;
    v_key_id := (v_auth->>'key_id')::uuid;

    -- Return candidates who have applied to this organization's jobs
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'candidate_id', cp.candidate_id,
            'headline', cp.headline,
            'years_of_experience', cp.years_of_experience,
            'country_code', cp.country_code,
            'availability_status', cp.availability_status
        )
    ), '[]'::jsonb)
    INTO v_items
    FROM (
        SELECT DISTINCT cp.candidate_id, cp.headline, cp.years_of_experience, cp.country_code, cp.availability_status
        FROM public.applications a
        JOIN public.candidate_profiles cp ON a.candidate_id = cp.candidate_id
        WHERE a.organization_id = v_org_id
        LIMIT v_limit
    ) cp;

    v_latency := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_t1))::int;
    PERFORM public.record_api_usage(v_app_id, v_key_id, v_org_id, '/api/v1/candidates', 'GET', 200, v_latency, v_auth->>'request_id');

    RETURN jsonb_build_object(
        'data', v_items,
        'request_id', v_auth->>'request_id'
    );
END;
$$;

-- D. GET /api/v1/applications
CREATE OR REPLACE FUNCTION public.api_v1_get_applications(
    p_api_key TEXT,
    p_job_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_cursor TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_auth JSONB;
    v_org_id UUID;
    v_app_id UUID;
    v_key_id UUID;
    v_result JSONB;
    v_t1 TIMESTAMPTZ := clock_timestamp();
    v_latency INT;
BEGIN
    v_auth := public.authenticate_api_key(p_api_key, 'applications.read', '/api/v1/applications', 'GET');
    IF NOT (v_auth->>'authenticated')::boolean THEN
        RETURN v_auth;
    END IF;

    v_org_id := (v_auth->>'organization_id')::uuid;
    v_app_id := (v_auth->>'application_id')::uuid;
    v_key_id := (v_auth->>'key_id')::uuid;

    v_result := public.get_applications_cursor(v_org_id, p_job_id, NULL, p_limit, p_cursor);

    v_latency := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_t1))::int;
    PERFORM public.record_api_usage(v_app_id, v_key_id, v_org_id, '/api/v1/applications', 'GET', 200, v_latency, v_auth->>'request_id');

    RETURN jsonb_build_object(
        'data', v_result->'items',
        'pagination', jsonb_build_object(
            'has_more', v_result->'has_more',
            'next_cursor', v_result->'next_cursor'
        ),
        'request_id', v_auth->>'request_id'
    );
END;
$$;

-- E. POST /api/v1/applications/{id}/stage
CREATE OR REPLACE FUNCTION public.api_v1_update_application_stage(
    p_api_key TEXT,
    p_application_id UUID,
    p_target_stage_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_auth JSONB;
    v_org_id UUID;
    v_app_id UUID;
    v_key_id UUID;
    v_app public.applications%ROWTYPE;
    v_t1 TIMESTAMPTZ := clock_timestamp();
    v_latency INT;
BEGIN
    v_auth := public.authenticate_api_key(p_api_key, 'applications.write', '/api/v1/applications/stage', 'POST');
    IF NOT (v_auth->>'authenticated')::boolean THEN
        RETURN v_auth;
    END IF;

    v_org_id := (v_auth->>'organization_id')::uuid;
    v_app_id := (v_auth->>'application_id')::uuid;
    v_key_id := (v_auth->>'key_id')::uuid;

    SELECT * INTO v_app FROM public.applications WHERE id = p_application_id AND organization_id = v_org_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'error', jsonb_build_object(
                'code', 'NOT_FOUND',
                'message', 'Application not found in caller organization',
                'request_id', v_auth->>'request_id'
            )
        );
    END IF;

    -- Update stage
    UPDATE public.applications
    SET current_stage_id = p_target_stage_id, updated_at = now()
    WHERE id = p_application_id;

    v_latency := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_t1))::int;
    PERFORM public.record_api_usage(v_app_id, v_key_id, v_org_id, '/api/v1/applications/stage', 'POST', 200, v_latency, v_auth->>'request_id');

    RETURN jsonb_build_object(
        'success', true,
        'application_id', p_application_id,
        'current_stage_id', p_target_stage_id,
        'request_id', v_auth->>'request_id'
    );
END;
$$;

-- F. Subscribe Webhook (Connect API application to outbound webhooks)
CREATE OR REPLACE FUNCTION public.api_v1_subscribe_webhook(
    p_api_key TEXT,
    p_target_url TEXT,
    p_secret TEXT,
    p_event_types TEXT[] DEFAULT ARRAY['application.created', 'job.published']
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_auth JSONB;
    v_org_id UUID;
    v_app_id UUID;
    v_key_id UUID;
    v_wh_id UUID;
    v_sub_id UUID;
BEGIN
    v_auth := public.authenticate_api_key(p_api_key, 'webhooks.manage', '/api/v1/webhooks/subscriptions', 'POST');
    IF NOT (v_auth->>'authenticated')::boolean THEN
        RETURN v_auth;
    END IF;

    v_org_id := (v_auth->>'organization_id')::uuid;
    v_app_id := (v_auth->>'application_id')::uuid;
    v_key_id := (v_auth->>'key_id')::uuid;

    -- Create Outbound Webhook in Task 15 table
    INSERT INTO public.outbound_webhooks (
        organization_id, name, target_url, secret_hash, subscribed_events, is_active
    ) VALUES (
        v_org_id, 'API App Webhook', p_target_url, encode(sha256(p_secret::bytea), 'hex'), p_event_types, true
    ) RETURNING id INTO v_wh_id;

    -- Link subscription
    INSERT INTO public.api_webhook_subscriptions (
        api_application_id, webhook_id, event_types, status
    ) VALUES (
        v_app_id, v_wh_id, p_event_types, 'active'
    ) RETURNING id INTO v_sub_id;

    RETURN jsonb_build_object(
        'subscription_id', v_sub_id,
        'webhook_id', v_wh_id,
        'target_url', p_target_url,
        'event_types', p_event_types,
        'status', 'active',
        'request_id', v_auth->>'request_id'
    );
END;
$$;
