-- ============================================================================
-- Hiren Beyond Backend — Migration 20260915002201
-- Fix authenticate_api_key & create_api_key: use gen_random_uuid()
-- ============================================================================

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

    -- Generate cryptographically random secret string using built-in UUIDs
    v_random_secret := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    v_key_prefix := 'hb_live_' || substr(v_random_secret, 1, 8);
    v_raw_key := v_key_prefix || '_' || substr(v_random_secret, 9, 32);
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

    RETURN jsonb_build_object(
        'key_id', v_key_id,
        'application_id', p_application_id,
        'organization_id', v_app.organization_id,
        'name', p_name,
        'key_prefix', v_key_prefix,
        'api_key', v_raw_key,
        'expires_at', v_expires_at,
        'scopes', p_scopes,
        'warning', 'Store this API key safely. You will not be able to see it again.'
    );
END;
$$;

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
    v_request_id TEXT := 'req_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 24);
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
