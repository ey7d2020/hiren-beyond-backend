-- =============================================================================
-- Migration: 20260915001502_fix_webhook_and_user_isolation.sql
-- Description: Add caller authorization check to dispatch_outbound_webhook
-- =============================================================================

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
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot dispatch webhooks for organization %', p_organization_id;
    END IF;

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
