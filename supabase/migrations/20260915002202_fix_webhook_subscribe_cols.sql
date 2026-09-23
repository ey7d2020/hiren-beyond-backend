-- ============================================================================
-- Hiren Beyond Backend — Migration 20260915002202
-- Fix api_v1_subscribe_webhook column references for outbound_webhooks
-- ============================================================================

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
        organization_id, name, endpoint_url, secret_reference, events, status
    ) VALUES (
        v_org_id, 'API App Webhook', p_target_url, encode(sha256(p_secret::bytea), 'hex'), p_event_types, 'active'
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
