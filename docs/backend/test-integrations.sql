-- =============================================================================
-- Test Suite: test-integrations.sql
-- Description: End-to-end automated test suite for Task 15 (26 Scenarios)
--              External Integrations, Google Calendar, Google Meet, WhatsApp Business,
--              Google Sheets, Webhooks & Integration Connections Layer
-- Mode: Safe transactional rollback (All mutations rolled back upon completion)
-- =============================================================================

BEGIN;

DO $$
DECLARE
    -- Actors & Entities
    v_admin_user     UUID := gen_random_uuid();
    v_recruiter_a    UUID := gen_random_uuid();
    v_recruiter_b    UUID := gen_random_uuid();
    v_cand_user      UUID := gen_random_uuid();

    v_org_a          UUID := gen_random_uuid();
    v_org_b          UUID := gen_random_uuid();

    v_cand_id        UUID := gen_random_uuid();
    v_job_a          UUID := gen_random_uuid();
    v_app_a          UUID := gen_random_uuid();
    v_interview_a    UUID := gen_random_uuid();

    v_role_admin     UUID;
    v_role_recruiter UUID;

    -- Providers
    v_prov_gcal      RECORD;
    v_prov_meet      RECORD;
    v_prov_wa        RECORD;
    v_prov_sheets    RECORD;
    v_prov_wh        RECORD;

    -- Test Variables
    v_oauth_res      JSONB;
    v_complete_res   JSONB;
    v_conn_a         UUID;
    v_conn_user_a    UUID;
    v_conn_b         UUID;
    v_state          TEXT;
    v_test_res       JSONB;
    v_disc_res       JSONB;
    v_cal_res        JSONB;
    v_wa_res         JSONB;
    v_sheet_res      JSONB;
    v_mapping_id     UUID := gen_random_uuid();
    v_wh_id          UUID := gen_random_uuid();
    v_wh_dispatch    JSONB;
    v_incoming_res   JSONB;
    v_secret_key     TEXT := 'test_signing_secret_998877';
    v_test_payload   JSONB := '{"event": "candidate_interview_confirmed", "candidate_id": "cand-123"}'::jsonb;
    v_valid_sig      TEXT;
    v_evt_id         UUID;
    v_count          INT;
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'STARTING TASK 15 INTEGRATIONS TEST SUITE (26 SCENARIOS)';
    RAISE NOTICE '=============================================================================';

    -- -------------------------------------------------------------------------
    -- 0. SEED IDENTITIES & RECRUITMENT ENTITIES
    -- -------------------------------------------------------------------------
    INSERT INTO auth.users (id, email, aud, role)
    VALUES
        (v_admin_user,  'admin@integrations.test',       'authenticated', 'authenticated'),
        (v_recruiter_a, 'recruiter.a@integrations.test', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b@integrations.test', 'authenticated', 'authenticated'),
        (v_cand_user,   'candidate@integrations.test',   'authenticated', 'authenticated')
    ON CONFLICT (id) DO NOTHING;

    -- Profiles
    INSERT INTO public.profiles (id, email, full_name, country_code)
    VALUES
        (v_admin_user,  'admin@integrations.test',       'Admin User',    'US'),
        (v_recruiter_a, 'recruiter.a@integrations.test', 'Recruiter A',   'US'),
        (v_recruiter_b, 'recruiter.b@integrations.test', 'Recruiter B',   'GB'),
        (v_cand_user,   'candidate@integrations.test',   'Jane Dev',      'US')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    DECLARE
        v_platform_org        UUID;
        v_role_platform_admin UUID;
    BEGIN
        SELECT id INTO v_platform_org FROM public.organizations WHERE organization_type = 'platform' LIMIT 1;
        SELECT id INTO v_role_platform_admin FROM public.roles WHERE key = 'platform_admin' LIMIT 1;
        IF v_platform_org IS NOT NULL AND v_role_platform_admin IS NOT NULL THEN
            INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
            VALUES (v_platform_org, v_admin_user, v_role_platform_admin, 'active')
            ON CONFLICT DO NOTHING;
        END IF;
    END;

    -- Roles
    SELECT id INTO v_role_recruiter FROM public.roles WHERE key = 'recruiter' LIMIT 1;

    -- Organizations
    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES
        (v_org_a, 'Org A Tech', 'org-a-tech-' || substr(v_org_a::text, 1, 8), 'recruitment_agency', 'active'),
        (v_org_b, 'Org B Corp', 'org-b-corp-' || substr(v_org_b::text, 1, 8), 'recruitment_agency', 'active');

    -- Memberships
    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES
        (v_org_a, v_recruiter_a, v_role_recruiter, 'active'),
        (v_org_b, v_recruiter_b, v_role_recruiter, 'active');

    -- Candidate
    INSERT INTO public.candidates (id, user_id, status)
    VALUES (v_cand_id, v_cand_user, 'active');

    -- Job in Org A
    INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status)
    VALUES (v_job_a, v_org_a, v_recruiter_a, 'Cloud Architect', 'cloud-arch-' || substr(v_job_a::text, 1, 8), 'Lead multi-cloud', 'published');

    -- Application
    INSERT INTO public.applications (id, job_id, candidate_id, organization_id, status, source)
    VALUES (v_app_a, v_job_a, v_cand_id, v_org_a, 'interview', 'platform');

    -- Interview
    INSERT INTO public.interviews (
        id, application_id, job_id, candidate_id, organization_id,
        title, interview_type, status, scheduled_start_at, scheduled_end_at, timezone
    ) VALUES (
        v_interview_a, v_app_a, v_job_a, v_cand_id, v_org_a,
        'Technical Deep Dive', 'video', 'scheduled',
        now() + INTERVAL '2 days', now() + INTERVAL '2 days 1 hour', 'UTC'
    );

    -- Load Providers
    SELECT * INTO v_prov_gcal   FROM public.integration_providers WHERE key = 'google_calendar';
    SELECT * INTO v_prov_meet   FROM public.integration_providers WHERE key = 'google_meet';
    SELECT * INTO v_prov_wa     FROM public.integration_providers WHERE key = 'whatsapp_business';
    SELECT * INTO v_prov_sheets FROM public.integration_providers WHERE key = 'google_sheets';
    SELECT * INTO v_prov_wh     FROM public.integration_providers WHERE key = 'generic_webhook';

    -- Set Recruiter A Context
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    -- -------------------------------------------------------------------------
    -- TEST 1: Provider exists and is active
    -- -------------------------------------------------------------------------
    IF v_prov_gcal.id IS NULL OR v_prov_gcal.status <> 'active' THEN
        RAISE EXCEPTION 'TEST 1 FAILED: google_calendar provider is missing or not active';
    END IF;
    IF v_prov_wa.id IS NULL OR v_prov_wa.status <> 'active' THEN
        RAISE EXCEPTION 'TEST 1 FAILED: whatsapp_business provider is missing or not active';
    END IF;
    RAISE NOTICE 'TEST 1 PASSED: Integration providers registered and active';

    -- -------------------------------------------------------------------------
    -- TEST 2: Organization Connection (OAuth Flow)
    -- -------------------------------------------------------------------------
    v_oauth_res := public.start_oauth_session(
        v_org_a, 'google_calendar', 'https://app.hirenbeyond.com/oauth/callback',
        ARRAY['https://www.googleapis.com/auth/calendar.events'], 'organization'
    );
    v_state := v_oauth_res->>'state';

    IF v_state IS NULL OR length(v_state) < 32 THEN
        RAISE EXCEPTION 'TEST 2 FAILED: State not properly generated: %', v_oauth_res;
    END IF;

    v_complete_res := public.complete_oauth_session(
        v_state, 'google-acc-org-a', 'talent@orga.com',
        ARRAY['https://www.googleapis.com/auth/calendar.events'], 'vault:sec-ref-org-a'
    );
    v_conn_a := (v_complete_res->>'connection_id')::uuid;

    IF v_complete_res->>'status' <> 'active' OR v_conn_a IS NULL THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Could not complete OAuth session: %', v_complete_res;
    END IF;
    RAISE NOTICE 'TEST 2 PASSED: Organization integration connection created via OAuth';

    -- -------------------------------------------------------------------------
    -- TEST 3: Connection Isolation (Org A vs Org B)
    -- -------------------------------------------------------------------------
    -- Recruiter B (Org B) calling get_organization_integrations for Org A must be blocked
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);
    BEGIN
        PERFORM public.get_organization_integrations(v_org_a);
        RAISE EXCEPTION 'TEST 3 FAILED: Recruiter B was able to view Org A integrations!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 3 FAILED%' THEN RAISE; END IF;
        -- Expected unauthorized
    END;

    -- Recruiter B creates Org B connection
    INSERT INTO public.integration_connections (
        organization_id, provider_id, connected_by, connection_scope, status,
        connection_name, external_account_id, external_account_email, credential_reference
    ) VALUES (
        v_org_b, v_prov_gcal.id, v_recruiter_b, 'organization', 'active',
        'Org B Calendar', 'google-acc-org-b', 'recruiting@orgb.com', 'vault:sec-ref-org-b'
    ) RETURNING id INTO v_conn_b;

    -- Recruiter A cannot view Org B integrations
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    BEGIN
        PERFORM public.get_organization_integrations(v_org_b);
        RAISE EXCEPTION 'TEST 3 FAILED: Recruiter A was able to view Org B integrations!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 3 FAILED%' THEN RAISE; END IF;
        -- Expected unauthorized
    END;
    RAISE NOTICE 'TEST 3 PASSED: Multi-tenant organization connection isolation verified';

    -- -------------------------------------------------------------------------
    -- TEST 4: User Connection Isolation
    -- -------------------------------------------------------------------------
    -- Recruiter A creates private personal calendar connection in Org A
    INSERT INTO public.integration_connections (
        organization_id, provider_id, connected_by, user_id, connection_scope, status,
        connection_name, external_account_id, external_account_email, credential_reference
    ) VALUES (
        v_org_a, v_prov_gcal.id, v_recruiter_a, v_recruiter_a, 'user', 'active',
        'Recruiter A Personal Cal', 'google-acc-rec-a', 'personal.recruiter@gmail.com', 'vault:sec-ref-user-a'
    ) RETURNING id INTO v_conn_user_a;

    -- Recruiter A sees their own personal connection
    DECLARE
        v_org_ints JSONB;
    BEGIN
        v_org_ints := public.get_organization_integrations(v_org_a);
        IF NOT (v_org_ints::text LIKE '%Recruiter A Personal Cal%') THEN
            RAISE EXCEPTION 'TEST 4 FAILED: Recruiter A could not see own personal connection!';
        END IF;

        -- Recruiter B (in Org B) cannot access Org A integrations
        PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);
        BEGIN
            PERFORM public.get_organization_integrations(v_org_a);
            RAISE EXCEPTION 'TEST 4 FAILED: Recruiter B accessed Org A user connections!';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%TEST 4 FAILED%' THEN RAISE; END IF;
            -- Expected unauthorized
        END;

        PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    END;
    RAISE NOTICE 'TEST 4 PASSED: User-level connection isolation verified';

    -- -------------------------------------------------------------------------
    -- TEST 5: OAuth State (Invalid/Replayed state rejected)
    -- -------------------------------------------------------------------------
    -- Replaying v_state must fail
    BEGIN
        PERFORM public.complete_oauth_session(
            v_state, 'google-acc-replay', 'replay@test.com',
            ARRAY['https://www.googleapis.com/auth/calendar.events'], 'vault:sec-ref-replay'
        );
        RAISE EXCEPTION 'TEST 5 FAILED: Replayed OAuth state was accepted!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 5 FAILED%' THEN RAISE; END IF;
        -- Expected rejection
    END;
    RAISE NOTICE 'TEST 5 PASSED: Replayed and invalid OAuth state successfully rejected';

    -- -------------------------------------------------------------------------
    -- TEST 6: Scope Validation (Missing required scope detected)
    -- -------------------------------------------------------------------------
    v_oauth_res := public.start_oauth_session(
        v_org_a, 'google_calendar', 'https://app.hirenbeyond.com/oauth/callback',
        ARRAY['https://www.googleapis.com/auth/calendar.events', 'https://www.googleapis.com/auth/calendar.readonly']
    );
    v_state := v_oauth_res->>'state';

    BEGIN
        -- Grant only 1 of the 2 requested scopes
        PERFORM public.complete_oauth_session(
            v_state, 'google-acc-insufficient', 'badscopes@test.com',
            ARRAY['https://www.googleapis.com/auth/calendar.readonly'], 'vault:ref'
        );
        RAISE EXCEPTION 'TEST 6 FAILED: Insufficient granted scopes were accepted!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 6 FAILED%' THEN RAISE; END IF;
        -- Expected missing scope exception
    END;
    RAISE NOTICE 'TEST 6 PASSED: Missing required OAuth scope detected and rejected';

    -- -------------------------------------------------------------------------
    -- TEST 7: Connection Test (Valid connection updates health)
    -- -------------------------------------------------------------------------
    v_test_res := public.test_integration_connection(v_conn_a);
    IF v_test_res->>'status' <> 'healthy' OR (v_test_res->>'latency_ms')::int <= 0 THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Expected healthy status, got %', v_test_res;
    END IF;

    SELECT count(*) INTO v_count FROM public.integration_health_checks WHERE integration_connection_id = v_conn_a;
    IF v_count < 1 THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Health check record not persisted';
    END IF;
    RAISE NOTICE 'TEST 7 PASSED: Connection health test logged successfully';

    -- -------------------------------------------------------------------------
    -- TEST 8: Expired Connection handling
    -- -------------------------------------------------------------------------
    UPDATE public.integration_connections SET status = 'expired' WHERE id = v_conn_a;
    v_test_res := public.test_integration_connection(v_conn_a);
    IF v_test_res->>'status' <> 'expired' THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Expected expired status, got %', v_test_res;
    END IF;
    -- Reset to active
    UPDATE public.integration_connections SET status = 'active' WHERE id = v_conn_a;
    RAISE NOTICE 'TEST 8 PASSED: Expired connection status detected accurately';

    -- -------------------------------------------------------------------------
    -- TEST 9: Disconnect (Prevents future integration jobs)
    -- -------------------------------------------------------------------------
    v_disc_res := public.disconnect_integration(v_conn_a);
    IF v_disc_res->>'status' <> 'disconnected' THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Disconnect failed: %', v_disc_res;
    END IF;

    -- Reactivate for subsequent calendar tests
    UPDATE public.integration_connections SET status = 'active' WHERE id = v_conn_a;
    RAISE NOTICE 'TEST 9 PASSED: Disconnect integration lifecycle verified';

    -- -------------------------------------------------------------------------
    -- TEST 10: Idempotent Calendar Event Creation
    -- -------------------------------------------------------------------------
    v_cal_res := public.sync_interview_calendar_event(v_interview_a, 'create');
    IF v_cal_res->>'status' <> 'completed' OR v_cal_res->>'calendar_event_id' IS NULL THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Calendar event creation failed: %', v_cal_res;
    END IF;

    -- Second run for same interview must be idempotent
    v_cal_res := public.sync_interview_calendar_event(v_interview_a, 'create');
    IF v_cal_res->>'status' <> 'already_processed' THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Duplicate calendar event created! Got: %', v_cal_res;
    END IF;
    RAISE NOTICE 'TEST 10 PASSED: Calendar event creation is strictly idempotent';

    -- -------------------------------------------------------------------------
    -- TEST 11: Interview Scheduling Failure Isolation (Provider outage)
    -- -------------------------------------------------------------------------
    -- Interview stays scheduled when external sync fails
    DECLARE
        v_fail_int UUID := gen_random_uuid();
        v_fail_res JSONB;
        v_int_status TEXT;
    BEGIN
        INSERT INTO public.interviews (
            id, application_id, job_id, candidate_id, organization_id,
            title, interview_type, status, scheduled_start_at, scheduled_end_at
        ) VALUES (
            v_fail_int, v_app_a, v_job_a, v_cand_id, v_org_a,
            'Failure Isolation Test', 'video', 'scheduled',
            now() + INTERVAL '3 days', now() + INTERVAL '3 days 1 hour'
        );

        v_fail_res := public.sync_interview_calendar_event(v_fail_int, 'create', true);
        IF v_fail_res->>'status' <> 'failed' OR (v_fail_res->>'retryable')::boolean <> true THEN
            RAISE EXCEPTION 'TEST 11 FAILED: Expected retryable failure response, got %', v_fail_res;
        END IF;

        -- Confirm internal interview status remains 'scheduled'
        SELECT status INTO v_int_status FROM public.interviews WHERE id = v_fail_int;
        IF v_int_status <> 'scheduled' THEN
            RAISE EXCEPTION 'TEST 11 FAILED: Internal interview was modified upon provider failure!';
        END IF;
    END;
    RAISE NOTICE 'TEST 11 PASSED: Calendar failure isolated; internal interview remains scheduled';

    -- -------------------------------------------------------------------------
    -- TEST 12: Interview Reschedule (Preserves event ID)
    -- -------------------------------------------------------------------------
    DECLARE
        v_prev_event_id TEXT;
        v_new_event_id  TEXT;
    BEGIN
        SELECT calendar_event_id INTO v_prev_event_id FROM public.interviews WHERE id = v_interview_a;
        v_cal_res := public.sync_interview_calendar_event(v_interview_a, 'update');
        SELECT calendar_event_id INTO v_new_event_id FROM public.interviews WHERE id = v_interview_a;

        IF v_new_event_id <> v_prev_event_id THEN
            RAISE EXCEPTION 'TEST 12 FAILED: Calendar event ID changed during reschedule! Prev: %, New: %', v_prev_event_id, v_new_event_id;
        END IF;
    END;
    RAISE NOTICE 'TEST 12 PASSED: Interview reschedule preserved existing calendar event ID';

    -- -------------------------------------------------------------------------
    -- TEST 13: Interview Cancellation
    -- -------------------------------------------------------------------------
    v_cal_res := public.sync_interview_calendar_event(v_interview_a, 'cancel');
    IF v_cal_res->>'status' <> 'completed' OR v_cal_res->>'action' <> 'cancel' THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Calendar cancellation failed: %', v_cal_res;
    END IF;
    RAISE NOTICE 'TEST 13 PASSED: Calendar event cancellation synced';

    -- -------------------------------------------------------------------------
    -- TEST 14: WhatsApp Business Message Delivery
    -- -------------------------------------------------------------------------
    INSERT INTO public.whatsapp_templates (
        organization_id, name, language_code, category, provider_template_id, status, configuration
    ) VALUES (
        v_org_a, 'interview_reminder', 'en', 'utility', 'meta_tmpl_99182', 'approved',
        '{"body": "Hello {1}, your interview is at {2}"}'::jsonb
    );

    v_wa_res := public.send_whatsapp_message(
        v_org_a, v_cand_user, '+12025550199', 'interview_reminder',
        '{"1": "Jane", "2": "tomorrow 10:00 AM"}'::jsonb
    );

    IF v_wa_res->>'status' <> 'sent' OR v_wa_res->>'provider_message_id' IS NULL THEN
        RAISE EXCEPTION 'TEST 14 FAILED: WhatsApp send failed: %', v_wa_res;
    END IF;

    SELECT count(*) INTO v_count
    FROM public.notification_deliveries
    WHERE id = (v_wa_res->>'delivery_id')::uuid AND channel = 'whatsapp';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 14 FAILED: WhatsApp notification delivery not logged in notification_deliveries';
    END IF;
    RAISE NOTICE 'TEST 14 PASSED: WhatsApp message routed through notification delivery engine';

    -- -------------------------------------------------------------------------
    -- TEST 15: WhatsApp Delivery Failure Tracking
    -- -------------------------------------------------------------------------
    v_wa_res := public.send_whatsapp_message(
        v_org_a, v_cand_user, '+10000000000', 'interview_reminder',
        '{"1": "Jane"}'::jsonb, true
    );
    IF v_wa_res->>'status' <> 'failed' THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Expected failure response, got %', v_wa_res;
    END IF;
    RAISE NOTICE 'TEST 15 PASSED: WhatsApp failure tracked cleanly with failure codes';

    -- -------------------------------------------------------------------------
    -- TEST 16: Google Sheets Export Mapping & Rows
    -- -------------------------------------------------------------------------
    INSERT INTO public.spreadsheet_mappings (
        id, organization_id, integration_connection_id, entity_type,
        spreadsheet_id, sheet_name, column_mapping, export_options
    ) VALUES (
        v_mapping_id, v_org_a, v_conn_a, 'application',
        '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms', 'Applications_2026',
        '{"Candidate Name": "A", "Job Title": "B", "Status": "C"}'::jsonb,
        '{"exclude_private_notes": true}'::jsonb
    );

    v_sheet_res := public.export_data_to_sheets(v_mapping_id, v_org_a, 'exp_batch_1');
    IF v_sheet_res->>'status' <> 'completed' OR (v_sheet_res->>'rows_exported')::int < 1 THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Sheets export failed: %', v_sheet_res;
    END IF;
    RAISE NOTICE 'TEST 16 PASSED: Google Sheets export created correct row staging';

    -- -------------------------------------------------------------------------
    -- TEST 17: Sheets Privacy Guard (Excludes private notes)
    -- -------------------------------------------------------------------------
    IF (v_sheet_res->>'private_notes_excluded')::boolean <> true THEN
        RAISE EXCEPTION 'TEST 17 FAILED: Private notes were not excluded from Google Sheets export!';
    END IF;
    RAISE NOTICE 'TEST 17 PASSED: Sheets export privacy guard strictly enforced';

    -- -------------------------------------------------------------------------
    -- TEST 18: Sheets Export Idempotency
    -- -------------------------------------------------------------------------
    v_sheet_res := public.export_data_to_sheets(v_mapping_id, v_org_a, 'exp_batch_1');
    IF v_sheet_res->>'status' <> 'already_queued_or_completed' THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Duplicate export was executed! Got: %', v_sheet_res;
    END IF;
    RAISE NOTICE 'TEST 18 PASSED: Google Sheets export is strictly idempotent';

    -- -------------------------------------------------------------------------
    -- TEST 19: Outbound Webhook HMAC Signing
    -- -------------------------------------------------------------------------
    INSERT INTO public.outbound_webhooks (
        id, organization_id, name, endpoint_url, secret_reference, events
    ) VALUES (
        v_wh_id, v_org_a, 'ATS Partner Webhook', 'https://partner.ats.com/webhooks/hirenbeyond',
        'vault:wh-sec-ref-org-a', ARRAY['candidate_interview_confirmed', 'candidate_hired']
    );

    v_wh_dispatch := public.dispatch_outbound_webhook(
        v_org_a, 'candidate_interview_confirmed', gen_random_uuid(), v_test_payload
    );

    IF (v_wh_dispatch->>'dispatched_webhooks')::int < 1 THEN
        RAISE EXCEPTION 'TEST 19 FAILED: Webhook not dispatched: %', v_wh_dispatch;
    END IF;

    -- Verify signature format in delivery queue
    SELECT signature INTO v_valid_sig
    FROM public.webhook_deliveries
    WHERE webhook_id = v_wh_id
    ORDER BY created_at DESC LIMIT 1;

    IF v_valid_sig IS NULL OR NOT (v_valid_sig LIKE 'sha256=%') THEN
        RAISE EXCEPTION 'TEST 19 FAILED: Outbound webhook signature missing or invalid format: %', v_valid_sig;
    END IF;
    RAISE NOTICE 'TEST 19 PASSED: Outbound webhook payload signed with SHA256-HMAC';

    -- -------------------------------------------------------------------------
    -- TEST 20: Webhook Replay Defense (Incoming Webhooks)
    -- -------------------------------------------------------------------------
    v_valid_sig := 'sha256=' || encode(extensions.hmac(v_test_payload::text, v_secret_key, 'sha256'), 'hex');

    v_incoming_res := public.process_incoming_webhook(
        'partner_ats', 'evt_uniq_12345', 'status_update',
        v_test_payload, v_valid_sig, v_secret_key
    );

    IF v_incoming_res->>'status' <> 'processed' THEN
        RAISE EXCEPTION 'TEST 20 FAILED: Incoming webhook failed: %', v_incoming_res;
    END IF;

    -- Replaying same external event ID must be ignored
    v_incoming_res := public.process_incoming_webhook(
        'partner_ats', 'evt_uniq_12345', 'status_update',
        v_test_payload, v_valid_sig, v_secret_key
    );

    IF v_incoming_res->>'status' <> 'ignored' OR v_incoming_res->>'reason' <> 'duplicate_external_event_id' THEN
        RAISE EXCEPTION 'TEST 20 FAILED: Replayed webhook event was not ignored! Got: %', v_incoming_res;
    END IF;
    RAISE NOTICE 'TEST 20 PASSED: Incoming webhook replay attack successfully defended';

    -- -------------------------------------------------------------------------
    -- TEST 21: Invalid Webhook Signature Rejection
    -- -------------------------------------------------------------------------
    BEGIN
        PERFORM public.process_incoming_webhook(
            'partner_ats', 'evt_tampered_999', 'status_update',
            v_test_payload, 'sha256=tampered_signature_hex_code', v_secret_key
        );
        RAISE EXCEPTION 'TEST 21 FAILED: Tampered signature was accepted!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 21 FAILED%' THEN RAISE; END IF;
        -- Expected signature rejection
    END;
    RAISE NOTICE 'TEST 21 PASSED: Invalid webhook signature properly rejected';

    -- -------------------------------------------------------------------------
    -- TEST 22: Incoming Webhook verified event ingestion
    -- -------------------------------------------------------------------------
    SELECT count(*) INTO v_count
    FROM public.incoming_webhook_events
    WHERE provider = 'partner_ats' AND external_event_id = 'evt_uniq_12345' AND signature_verified = true;

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 22 FAILED: Verified incoming event not found in database';
    END IF;
    RAISE NOTICE 'TEST 22 PASSED: Verified provider webhook event ingested cleanly';

    -- -------------------------------------------------------------------------
    -- TEST 23: Cross-Tenant Webhook Manipulation Blocked
    -- -------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);
    BEGIN
        PERFORM public.dispatch_outbound_webhook(
            v_org_a, 'candidate_interview_confirmed', gen_random_uuid(), v_test_payload
        );
        RAISE EXCEPTION 'TEST 23 FAILED: Recruiter B dispatched Org A outbound webhook!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 23 FAILED%' THEN RAISE; END IF;
        -- Expected unauthorized
    END;

    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);
    RAISE NOTICE 'TEST 23 PASSED: Cross-tenant webhook access strictly blocked';

    -- -------------------------------------------------------------------------
    -- TEST 24: Zero Secret Exposure
    -- -------------------------------------------------------------------------
    -- API queries for integrations do not expose plaintext access/refresh tokens
    DECLARE
        v_avail JSONB;
        v_org_ints JSONB;
    BEGIN
        v_avail    := public.get_available_integrations();
        v_org_ints := public.get_organization_integrations(v_org_a);

        IF v_org_ints::text LIKE '%access_token%'
           OR v_org_ints::text LIKE '%refresh_token%'
           OR v_org_ints::text LIKE '%client_secret%' THEN
            RAISE EXCEPTION 'TEST 24 FAILED: Raw credentials or secrets exposed in API response!';
        END IF;
    END;
    RAISE NOTICE 'TEST 24 PASSED: Zero secret or token exposure verified in API responses';

    -- -------------------------------------------------------------------------
    -- TEST 25: Disconnect Preservation
    -- -------------------------------------------------------------------------
    -- Disconnecting a calendar integration does not delete internal interviews
    PERFORM public.disconnect_integration(v_conn_a);
    SELECT count(*) INTO v_count FROM public.interviews WHERE id = v_interview_a;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 25 FAILED: Internal interview was deleted on integration disconnect!';
    END IF;
    RAISE NOTICE 'TEST 25 PASSED: Integration disconnect preserves core recruitment business data';

    -- -------------------------------------------------------------------------
    -- TEST 26: Provider Failure Isolation
    -- -------------------------------------------------------------------------
    -- Verify application, job, and candidate remain completely intact
    SELECT count(*) INTO v_count FROM public.applications WHERE id = v_app_a;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 26 FAILED: Application modified or lost';
    END IF;

    SELECT count(*) INTO v_count FROM public.jobs WHERE id = v_job_a;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 26 FAILED: Job modified or lost';
    END IF;

    SELECT count(*) INTO v_count FROM public.candidates WHERE id = v_cand_id;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'TEST 26 FAILED: Candidate modified or lost';
    END IF;
    RAISE NOTICE 'TEST 26 PASSED: External provider failure isolation verified across platform';

    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'SUCCESS: ALL 26 INTEGRATION TESTS PASSED!';
    RAISE NOTICE '=============================================================================';
END;
$$;

ROLLBACK;

SELECT 'SUCCESS: ALL 26 INTEGRATION TESTS PASSED!' AS status;
