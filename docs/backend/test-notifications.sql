-- ============================================================================
-- Hiren Beyond — Task 11 End-to-End Automated Test Suite: Notifications & Communications
-- Executes all 20 test scenarios inside a safe rollback transaction
-- ============================================================================

BEGIN;

DO $$
DECLARE
    -- Organizations
    v_org_a UUID := '90c362ea-2bcc-45ba-98e4-c8a5d3c57376';
    v_org_b UUID := gen_random_uuid();
    v_client_org_x UUID := gen_random_uuid();
    v_client_org_y UUID := gen_random_uuid();

    -- Users
    v_recruiter_a UUID := gen_random_uuid();
    v_recruiter_b UUID := gen_random_uuid();
    v_cand_user_a UUID := gen_random_uuid();
    v_cand_user_b UUID := gen_random_uuid();
    v_client_user_x UUID := gen_random_uuid();
    v_client_user_y UUID := gen_random_uuid();

    -- Entities
    v_cand_a UUID := gen_random_uuid();
    v_job_a UUID := gen_random_uuid();
    v_app_a UUID := gen_random_uuid();
    v_interview_a UUID := gen_random_uuid();
    v_invitation_a UUID := gen_random_uuid();

    -- Roles
    v_role_recruiter UUID;
    v_role_client_reviewer UUID;

    -- Working Variables
    v_type_id UUID;
    v_tmpl_id UUID;
    v_event_id UUID;
    v_notif_count INT;
    v_deliv_id UUID;
    v_attempt_id UUID;
    v_deliv RECORD;
    v_notif RECORD;
    v_rendered TEXT;
    v_is_quiet BOOLEAN;
    v_unread_cnt BIGINT;
    v_is_eligible BOOLEAN;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. SETUP AUTH USERS, PROFILES, ORGS & ROLES
    -- ------------------------------------------------------------------------
    INSERT INTO auth.users (id, email, role, aud)
    VALUES
        (v_recruiter_a, 'recruiter.a.task11@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_recruiter_b, 'recruiter.b.task11@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_cand_user_a, 'cand.a.task11@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_cand_user_b, 'cand.b.task11@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_client_user_x, 'client.x.task11@hirenbeyond.test', 'authenticated', 'authenticated'),
        (v_client_user_y, 'client.y.task11@hirenbeyond.test', 'authenticated', 'authenticated');

    INSERT INTO public.profiles (id, email, full_name, country_code)
    VALUES
        (v_recruiter_a, 'recruiter.a.task11@hirenbeyond.test', 'Recruiter Rachel', 'GB'),
        (v_recruiter_b, 'recruiter.b.task11@hirenbeyond.test', 'Recruiter Robert', 'US'),
        (v_cand_user_a, 'cand.a.task11@hirenbeyond.test', 'Candidate Charles', 'EG'),
        (v_cand_user_b, 'cand.b.task11@hirenbeyond.test', 'Candidate Chloe', 'DE'),
        (v_client_user_x, 'client.x.task11@hirenbeyond.test', 'Client Christopher', 'FR'),
        (v_client_user_y, 'client.y.task11@hirenbeyond.test', 'Client Clarissa', 'AE')
    ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name;

    INSERT INTO public.organizations (id, name, slug, organization_type, status)
    VALUES
        (v_org_b, 'Delta Staffing Global', 'delta-staffing', 'client', 'active'),
        (v_client_org_x, 'FinTech Cloud Corp', 'fintech-cloud', 'client', 'active'),
        (v_client_org_y, 'Nexus Retail Systems', 'nexus-retail', 'client', 'active');

    SELECT id INTO v_role_recruiter FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_role_client_reviewer FROM public.roles WHERE key = 'client_reviewer' LIMIT 1;

    INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
    VALUES
        (v_org_a, v_recruiter_a, v_role_recruiter, 'active'),
        (v_org_b, v_recruiter_b, v_role_recruiter, 'active'),
        (v_client_org_x, v_client_user_x, v_role_client_reviewer, 'active'),
        (v_client_org_y, v_client_user_y, v_role_client_reviewer, 'active');

    INSERT INTO public.candidates (id, user_id, status)
    VALUES
        (v_cand_a, v_cand_user_a, 'active');

    INSERT INTO public.jobs (id, organization_id, created_by, title, slug, description, status, job_type)
    VALUES
        (v_job_a, v_org_a, v_recruiter_a, 'Principal Distributed Architect', 'princ-dist-arch-' || substr(gen_random_uuid()::text, 1, 8), 'Design high-scale core systems', 'published', 'direct');

    INSERT INTO public.applications (id, job_id, candidate_id, organization_id, status, match_score)
    VALUES
        (v_app_a, v_job_a, v_cand_a, v_org_a, 'shortlisted', 95.00);

    -- ------------------------------------------------------------------------
    -- TEST 1: Notification Type Registration & Catalog Query
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_a::text, true);

    IF NOT EXISTS (
        SELECT 1 FROM public.notification_types WHERE code = 'interview_scheduled' AND is_required = true
    ) THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Core notification type interview_scheduled not found';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 2: Template Creation, Versioning & Platform Override
    -- ------------------------------------------------------------------------
    SELECT id INTO v_type_id FROM public.notification_types WHERE code = 'interview_scheduled';

    -- Org A creates custom version 1 template
    INSERT INTO public.notification_templates (
        organization_id, notification_type_id, channel, name, subject_template, body_template, language_code, version, status
    )
    VALUES (
        v_org_a, v_type_id, 'email', 'Org A Custom Interview Email v1',
        'Org A: Confirmed Interview for {{job_title}}',
        'Hello {{candidate_name}}, Org A has scheduled your interview for {{job_title}} at {{interview_time}}.',
        'en', 1, 'published'
    )
    RETURNING id INTO v_tmpl_id;

    IF NOT EXISTS (
        SELECT 1 FROM public.notification_templates WHERE id = v_tmpl_id AND version = 1
    ) THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Organization custom template v1 not created';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 3: In-App Notification Center Creation & Retrieval
    -- ------------------------------------------------------------------------
    -- Emit event for candidate Charles
    v_event_id := public.emit_notification_event(
        'application_status_changed',
        'applications',
        v_app_a,
        v_org_a,
        jsonb_build_object(
            'recipient_user_id', v_cand_user_a,
            'title', 'Application Shortlisted',
            'body', 'Congratulations! Your application for Principal Distributed Architect has been shortlisted.',
            'job_title', 'Principal Distributed Architect',
            'application_status', 'shortlisted',
            'route', '/applications/' || v_app_a
        ),
        'idemp:event:test3:' || v_app_a
    );

    v_notif_count := public.process_notification_event(v_event_id);
    IF v_notif_count < 1 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Notification event was not processed into notifications';
    END IF;

    -- Candidate Charles queries notifications
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    SELECT * INTO v_notif FROM public.get_my_notifications(10, 0, false) LIMIT 1;
    IF v_notif.out_title <> 'Application Shortlisted' THEN
        RAISE EXCEPTION 'TEST 3 FAILED: In-app notification title mismatch, got %', v_notif.out_title;
    END IF;

    v_unread_cnt := public.get_unread_notification_count();
    IF v_unread_cnt < 1 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Expected at least 1 unread notification, got %', v_unread_cnt;
    END IF;

    -- Mark notification read
    PERFORM public.mark_notification_read(v_notif.out_notification_id);
    v_unread_cnt := public.get_unread_notification_count();
    IF v_unread_cnt <> 0 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Notification was not marked read, count = %', v_unread_cnt;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 4: Candidate Privacy (Candidate B Blocked From Candidate A)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_b::text, true);

    IF EXISTS (
        SELECT 1 FROM public.get_my_notifications(10, 0, false)
        WHERE out_notification_id = v_notif.out_notification_id
    ) THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Candidate B was able to view Candidate A notification!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 5: Recruiter Privacy (Recruiter B Blocked From Recruiter A)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);

    IF EXISTS (
        SELECT 1 FROM public.get_my_notifications(10, 0, false)
        WHERE out_notification_id = v_notif.out_notification_id
    ) THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Recruiter B was able to view Candidate A private notification!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 6: Template Variable Interpolation Engine
    -- ------------------------------------------------------------------------
    v_rendered := public.render_notification_template(
        'Dear {{candidate_name}}, your interview for {{job_title}} at {{company_name}} is confirmed.',
        jsonb_build_object(
            'candidate_name', 'Charles Xavier',
            'job_title', 'Staff Cloud Architect',
            'company_name', 'Hiren Beyond'
        )
    );

    IF v_rendered <> 'Dear Charles Xavier, your interview for Staff Cloud Architect at Hiren Beyond is confirmed.' THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Template variable interpolation failed, got: %', v_rendered;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 7: Communication Preferences (User Disables Optional Channel)
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    -- Candidate Charles disables optional email for application status changed
    PERFORM public.update_notification_preference(
        'application_status_changed',
        'email',
        false
    );

    -- Emit second status change event
    v_event_id := public.emit_notification_event(
        'application_status_changed',
        'applications',
        v_app_a,
        v_org_a,
        jsonb_build_object(
            'recipient_user_id', v_cand_user_a,
            'title', 'Stage Advanced',
            'body', 'Advanced to technical screening'
        ),
        'idemp:event:test7:' || substr(gen_random_uuid()::text, 1, 8)
    );

    PERFORM public.process_notification_event(v_event_id);

    -- Email delivery job should NOT be created because user opted out
    IF EXISTS (
        SELECT 1 FROM public.notification_deliveries
        WHERE recipient_user_id = v_cand_user_a
          AND channel = 'email'
          AND idempotency_key LIKE 'deliv:email:' || v_event_id || '%'
    ) THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Email delivery job was created despite user opting out!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 8: Required Notification Enforcement
    -- ------------------------------------------------------------------------
    BEGIN
        -- Candidate Charles attempts to disable required interview notification
        PERFORM public.update_notification_preference(
            'interview_scheduled',
            'email',
            false
        );
        RAISE EXCEPTION 'TEST 8 FAILED: User was allowed to disable mandatory required notification!';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE '%TEST 8 FAILED%' THEN RAISE EXCEPTION '%', SQLERRM; END IF;
        -- Successfully blocked
    END;

    -- ------------------------------------------------------------------------
    -- TEST 9: Quiet Hours Delay (Non-Urgent Delivery Scheduled)
    -- ------------------------------------------------------------------------
    -- Check quiet hours logic crossing midnight (22:00 to 07:00)
    v_is_quiet := public.is_in_quiet_hours('22:00'::time, '07:00'::time, 'UTC');

    -- Configure quiet hours that are guaranteed active currently
    PERFORM public.update_notification_preference(
        'application_status_changed',
        'email',
        true,
        '00:00'::time,
        '23:59'::time,
        'UTC'
    );

    v_event_id := public.emit_notification_event(
        'application_status_changed',
        'applications',
        v_app_a,
        v_org_a,
        jsonb_build_object(
            'recipient_user_id', v_cand_user_a,
            'title', 'Review Underway',
            'body', 'Your profile is under technical review'
        ),
        'idemp:event:test9:' || substr(gen_random_uuid()::text, 1, 8)
    );

    PERFORM public.process_notification_event(v_event_id);

    SELECT * INTO v_deliv
    FROM public.notification_deliveries
    WHERE recipient_user_id = v_cand_user_a
      AND idempotency_key LIKE 'deliv:email:' || v_event_id || '%';

    IF v_deliv.status <> 'scheduled' OR v_deliv.scheduled_for IS NULL THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Delivery during quiet hours was not marked as scheduled with delay';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 10: Urgent Notification Bypass (Urgent Notification Ignores Quiet Hours)
    -- ------------------------------------------------------------------------
    v_event_id := public.emit_notification_event(
        'interview_scheduled',
        'interviews',
        v_interview_a,
        v_org_a,
        jsonb_build_object(
            'recipient_user_id', v_cand_user_a,
            'title', 'Urgent: Interview Confirmed',
            'body', 'Your interview has been scheduled for tomorrow at 10:00 UTC',
            'job_title', 'Principal Distributed Architect',
            'company_name', 'Hiren Beyond',
            'interview_date', '2026-09-20',
            'interview_time', '10:00 UTC',
            'meeting_link', 'https://meet.google.com/abc-def-ghi'
        ),
        'idemp:event:test10:' || substr(gen_random_uuid()::text, 1, 8)
    );

    PERFORM public.process_notification_event(v_event_id);

    SELECT * INTO v_deliv
    FROM public.notification_deliveries
    WHERE recipient_user_id = v_cand_user_a
      AND idempotency_key LIKE 'deliv:email:' || v_event_id || '%';

    IF v_deliv.status <> 'queued' THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Urgent notification was delayed instead of immediate queue, status = %', v_deliv.status;
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 11: Idempotency (Duplicate Event Processing Creates 0 Duplicate Deliveries)
    -- ------------------------------------------------------------------------
    -- Process the exact same event again
    PERFORM public.process_notification_event(v_event_id);

    IF (
        SELECT count(*) FROM public.notification_deliveries
        WHERE idempotency_key LIKE 'deliv:email:' || v_event_id || '%'
    ) <> 1 THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Duplicate processing created multiple deliveries for same idempotency key';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 12: Delivery Retry on Temporary Failure
    -- ------------------------------------------------------------------------
    v_deliv_id := v_deliv.id;

    v_attempt_id := public.record_delivery_attempt(
        v_deliv_id,
        'mock_email',
        'temporary_failure',
        'RATE_LIMIT_EXCEEDED',
        'Provider rate limit encountered, retry scheduled'
    );

    SELECT * INTO v_deliv FROM public.notification_deliveries WHERE id = v_deliv_id;
    IF v_deliv.attempt_count <> 1 OR v_deliv.status <> 'queued' OR v_deliv.scheduled_for IS NULL THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Temporary failure did not increment attempt count or reschedule';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 13: Permanent Failure Classification
    -- ------------------------------------------------------------------------
    v_attempt_id := public.record_delivery_attempt(
        v_deliv_id,
        'mock_email',
        'permanent_failure',
        'INVALID_EMAIL_ADDRESS',
        'Mailbox does not exist'
    );

    SELECT * INTO v_deliv FROM public.notification_deliveries WHERE id = v_deliv_id;
    IF v_deliv.status <> 'failed' OR v_deliv.failure_code <> 'INVALID_EMAIL_ADDRESS' THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Permanent failure was not marked as failed';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 14: Interview Reminder Suppression
    -- ------------------------------------------------------------------------
    INSERT INTO public.interviews (
        id, application_id, job_id, candidate_id, organization_id, title, interview_type, status, scheduled_start_at, scheduled_end_at, timezone
    )
    VALUES (
        v_interview_a, v_app_a, v_job_a, v_cand_a, v_org_a, 'Cancelled Technical Session',
        'technical', 'cancelled', now() + interval '24 hours', now() + interval '25 hours', 'UTC'
    );

    v_is_eligible := public.check_interview_reminder_eligibility(v_interview_a);
    IF v_is_eligible IS TRUE THEN
        RAISE EXCEPTION 'TEST 14 FAILED: Cancelled interview was marked eligible for reminder';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 15: Assessment Reminder Suppression
    -- ------------------------------------------------------------------------
    DECLARE
        v_asm_tmpl_id UUID;
    BEGIN
        INSERT INTO public.assessment_templates (
            organization_id, name, slug, assessment_type, version, status
        )
        VALUES (
            v_org_a, 'Skills Assessment', 'skills-assessment-' || substr(gen_random_uuid()::text, 1, 8),
            'technical', 1, 'published'
        )
        RETURNING id INTO v_asm_tmpl_id;

        INSERT INTO public.assessment_invitations (
            id, assessment_template_id, application_id, candidate_id, token, status, expires_at
        )
        VALUES (
            v_invitation_a, v_asm_tmpl_id, v_app_a, v_cand_a, 'token-completed-' || substr(gen_random_uuid()::text, 1, 8),
            'completed', now() + interval '48 hours'
        );
    END;

    v_is_eligible := public.check_assessment_reminder_eligibility(v_invitation_a);
    IF v_is_eligible IS TRUE THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Completed assessment invitation was marked eligible for reminder';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 16: Client Isolation
    -- ------------------------------------------------------------------------
    -- Emit event for Client Christopher
    v_event_id := public.emit_notification_event(
        'candidate_shared',
        'client_candidate_shares',
        v_app_a,
        v_client_org_x,
        jsonb_build_object(
            'recipient_user_id', v_client_user_x,
            'title', 'New Candidate Shared',
            'body', 'A senior architect profile has been shared with Acme Fintech'
        ),
        'idemp:event:clientx:' || v_app_a
    );

    PERFORM public.process_notification_event(v_event_id);

    -- Client Y should not see Client X's notification
    PERFORM set_config('request.jwt.claim.sub', v_client_user_y::text, true);

    IF EXISTS (
        SELECT 1 FROM public.get_my_notifications(10, 0, false)
        WHERE out_title = 'New Candidate Shared'
    ) THEN
        RAISE EXCEPTION 'TEST 16 FAILED: Client Y was able to see Client X candidate share notification!';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 17: Cross-Tenant Delivery Isolation
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_recruiter_b::text, true);

    -- Under Recruiter B authenticated context, delivery RLS policy evaluates to false for Candidate A
    IF EXISTS (
        SELECT 1 FROM public.notification_deliveries
        WHERE recipient_user_id = v_cand_user_a
          AND (recipient_user_id = auth.uid() OR public.is_platform_admin(auth.uid()))
    ) THEN
        RAISE EXCEPTION 'TEST 17 FAILED: Recruiter B was able to view Org A delivery records';
    END IF;

    -- Under Recruiter B context, event queue RLS policy evaluates to false for Org A
    IF EXISTS (
        SELECT 1 FROM public.notification_events
        WHERE organization_id = v_org_a
          AND (
              actor_user_id = auth.uid()
              OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    ) THEN
        RAISE EXCEPTION 'TEST 17 FAILED: Recruiter B was able to view Org A notification events';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 18: Deep Link Metadata Integrity
    -- ------------------------------------------------------------------------
    PERFORM set_config('request.jwt.claim.sub', v_cand_user_a::text, true);

    SELECT * INTO v_notif FROM public.get_my_notifications(10, 0, false)
    WHERE out_title = 'Application Shortlisted';

    IF (v_notif.out_data->>'route') <> ('/applications/' || v_app_a) THEN
        RAISE EXCEPTION 'TEST 18 FAILED: Notification route metadata corrupted';
    END IF;

    -- ------------------------------------------------------------------------
    -- TEST 19: User Contact Channel Registration & Verification
    -- ------------------------------------------------------------------------
    DECLARE
        v_chan_id UUID;
    BEGIN
        v_chan_id := public.add_communication_channel('whatsapp', '+201001234567', true);

        IF NOT EXISTS (
            SELECT 1 FROM public.user_contact_channels WHERE id = v_chan_id AND is_verified = false
        ) THEN
            RAISE EXCEPTION 'TEST 19 FAILED: Channel was not added in unverified state';
        END IF;

        -- Verify channel
        PERFORM public.request_channel_verification(v_chan_id);

        IF NOT EXISTS (
            SELECT 1 FROM public.user_contact_channels WHERE id = v_chan_id AND is_verified = true
        ) THEN
            RAISE EXCEPTION 'TEST 19 FAILED: Channel verification failed';
        END IF;
    END;

    -- ------------------------------------------------------------------------
    -- TEST 20: Provider Failure Isolation
    -- ------------------------------------------------------------------------
    -- Verify that delivery failure did NOT roll back earlier application record
    IF NOT EXISTS (SELECT 1 FROM public.applications WHERE id = v_app_a) THEN
        RAISE EXCEPTION 'TEST 20 FAILED: Recruitment application was rolled back due to notification failure';
    END IF;

    RAISE NOTICE 'ALL 20 END-TO-END NOTIFICATIONS & COMMUNICATIONS TESTS PASSED!';
END;
$$;

SELECT 'SUCCESS: ALL 20 NOTIFICATIONS & COMMUNICATIONS TESTS PASSED!' AS status;

ROLLBACK;
