-- =============================================================================
-- Migration: 20260915001200_notifications_communications.sql
-- Description: Notifications, Email, WhatsApp, Messaging Events & Communication Preferences
-- Author: Hiren Beyond Engineering
-- Schema: notification_types, notification_templates, notification_preferences,
--         user_contact_channels, notifications, notification_events,
--         notification_deliveries, notification_delivery_attempts
-- =============================================================================

-- =============================================================================
-- 1. EXTEND PERMISSIONS CATALOG
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('notifications.read', 'Read Notifications', 'View in-app notifications and alert messages', 'notifications'),
    ('notifications.manage', 'Manage Notifications', 'Configure organization notification templates and channels', 'notifications'),
    ('notifications.system_manage', 'Manage System Notifications', 'Global administrative control over platform notification types', 'notifications')
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;

-- Map permissions to roles
WITH new_mappings (role_key, perm_key) AS (
    VALUES
        ('platform_admin', 'notifications.read'),
        ('platform_admin', 'notifications.manage'),
        ('platform_admin', 'notifications.system_manage'),
        ('recruiter_manager', 'notifications.read'),
        ('recruiter_manager', 'notifications.manage'),
        ('recruiter', 'notifications.read'),
        ('client_admin', 'notifications.read'),
        ('client_reviewer', 'notifications.read'),
        ('candidate', 'notifications.read')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings nm
JOIN public.roles r ON r.key = nm.role_key
JOIN public.permissions p ON p.key = nm.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. SCHEMA DEFINITION: 8 TABLES
-- =============================================================================

-- 2.1 Notification Types
CREATE TABLE IF NOT EXISTS public.notification_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('application', 'assessment', 'interview', 'client', 'hiring', 'matching', 'system', 'marketing', 'security')),
    default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('low', 'normal', 'high', 'urgent')),
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_system BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.2 Notification Templates (Versioned & Multi-Channel)
CREATE TABLE IF NOT EXISTS public.notification_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    notification_type_id UUID NOT NULL REFERENCES public.notification_types(id) ON DELETE CASCADE,
    channel TEXT NOT NULL CHECK (channel IN ('in_app', 'email', 'whatsapp', 'sms')),
    name TEXT NOT NULL,
    subject_template TEXT,
    body_template TEXT NOT NULL,
    language_code VARCHAR(10) NOT NULL DEFAULT 'en',
    version INT NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('draft', 'published', 'archived')),
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_notification_templates UNIQUE (organization_id, notification_type_id, channel, language_code, version)
);

-- 2.3 User Communication Preferences
CREATE TABLE IF NOT EXISTS public.notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    notification_type_id UUID NOT NULL REFERENCES public.notification_types(id) ON DELETE CASCADE,
    channel TEXT NOT NULL CHECK (channel IN ('in_app', 'email', 'whatsapp', 'sms')),
    enabled BOOLEAN NOT NULL DEFAULT true,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    timezone VARCHAR(100) NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_notification_preferences UNIQUE (user_id, notification_type_id, channel)
);

-- 2.4 User Contact Channels (Email, Phone, WhatsApp)
CREATE TABLE IF NOT EXISTS public.user_contact_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    channel TEXT NOT NULL CHECK (channel IN ('email', 'phone', 'whatsapp', 'sms')),
    address TEXT NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'unverified', 'bounced', 'opted_out')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_contact_channels UNIQUE (user_id, channel, address)
);

-- 2.5 In-App Notification Center
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    notification_type_id UUID REFERENCES public.notification_types(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    read_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.6 Centralized Notification Events Queue
CREATE TABLE IF NOT EXISTS public.notification_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL,
    source_module TEXT NOT NULL,
    source_record_id UUID,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
    actor_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'processed', 'failed', 'ignored')),
    idempotency_key TEXT UNIQUE
);

-- 2.7 Notification Delivery Jobs
CREATE TABLE IF NOT EXISTS public.notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID REFERENCES public.notifications(id) ON DELETE SET NULL,
    recipient_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    channel TEXT NOT NULL CHECK (channel IN ('in_app', 'email', 'whatsapp', 'sms')),
    destination TEXT NOT NULL,
    template_id UUID REFERENCES public.notification_templates(id) ON DELETE SET NULL,
    template_version INT DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'scheduled', 'processing', 'sent', 'delivered', 'failed', 'cancelled')),
    provider TEXT NOT NULL DEFAULT 'in_app' CHECK (provider IN ('in_app', 'mock_email', 'resend', 'sendgrid', 'mock_whatsapp', 'meta_whatsapp', 'mock_sms', 'twilio')),
    provider_message_id TEXT,
    attempt_count INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3,
    scheduled_for TIMESTAMPTZ,
    queued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    failure_code TEXT,
    failure_message TEXT,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.8 Notification Delivery Attempts Log
CREATE TABLE IF NOT EXISTS public.notification_delivery_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id UUID NOT NULL REFERENCES public.notification_deliveries(id) ON DELETE CASCADE,
    attempt_number INT NOT NULL,
    provider TEXT NOT NULL,
    request_metadata JSONB DEFAULT '{}'::jsonb,
    response_metadata JSONB DEFAULT '{}'::jsonb,
    status TEXT NOT NULL CHECK (status IN ('success', 'temporary_failure', 'permanent_failure')),
    error_code TEXT,
    error_message TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 3. SEED CORE NOTIFICATION TYPES & GLOBAL TEMPLATES
-- =============================================================================

INSERT INTO public.notification_types (code, name, description, category, default_priority, is_required)
VALUES
    ('application_submitted', 'Application Submitted', 'Candidate submitted job application', 'application', 'normal', false),
    ('application_status_changed', 'Application Status Changed', 'Candidate stage moved or status updated', 'application', 'high', false),
    ('assessment_invited', 'Assessment Invitation', 'Candidate invited to complete skills or voice assessment', 'assessment', 'urgent', true),
    ('assessment_reminder', 'Assessment Reminder', 'Reminder for pending assessment completion', 'assessment', 'normal', false),
    ('assessment_completed', 'Assessment Completed', 'Candidate completed evaluation assessment', 'assessment', 'normal', false),
    ('interview_requested', 'Interview Requested', 'Client or recruiter requested candidate interview', 'interview', 'high', false),
    ('interview_scheduled', 'Interview Scheduled', 'Interview date, time, and link confirmed', 'interview', 'urgent', true),
    ('interview_rescheduled', 'Interview Rescheduled', 'Interview session timing updated', 'interview', 'urgent', true),
    ('interview_cancelled', 'Interview Cancelled', 'Interview cancelled by coordinator or candidate', 'interview', 'high', true),
    ('interview_reminder', 'Interview Reminder', 'Upcoming interview timing and meeting link reminder', 'interview', 'high', false),
    ('candidate_shared', 'Candidate Presented to Client', 'New candidate profile shared for client review', 'client', 'high', false),
    ('client_feedback_submitted', 'Client Feedback Received', 'Client reviewed candidate and submitted scorecard feedback', 'client', 'high', false),
    ('client_interview_requested', 'Client Interview Request', 'Client requested an interview with candidate', 'client', 'high', false),
    ('hiring_decision_made', 'Hiring Decision Made', 'Authoritative hiring decision recorded', 'hiring', 'urgent', true),
    ('strong_candidate_match', 'High Candidate Match Detected', 'Matching engine identified candidate scoring over 90%', 'matching', 'normal', false),
    ('security_alert', 'Security & Access Alert', 'Account login from new device or security credential update', 'security', 'urgent', true),
    ('system_alert', 'System Operational Alert', 'Background worker or integration pipeline warning', 'system', 'high', true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    default_priority = EXCLUDED.default_priority,
    is_required = EXCLUDED.is_required;

-- Seed Global Platform Default Templates (English)
WITH seeded_types AS (SELECT id, code, name FROM public.notification_types)
INSERT INTO public.notification_templates (
    organization_id, notification_type_id, channel, name, subject_template, body_template, language_code, version, status, is_default
)
SELECT
    NULL,
    t.id,
    'in_app',
    'Default In-App: ' || t.name,
    '{{title}}',
    '{{body}}',
    'en',
    1,
    'published',
    true
FROM seeded_types t
ON CONFLICT (organization_id, notification_type_id, channel, language_code, version) DO NOTHING;

-- Seed Default Email Templates for Critical Types
WITH seeded_types AS (SELECT id, code FROM public.notification_types)
INSERT INTO public.notification_templates (
    organization_id, notification_type_id, channel, name, subject_template, body_template, language_code, version, status, is_default
)
VALUES
    (
        NULL,
        (SELECT id FROM seeded_types WHERE code = 'interview_scheduled'),
        'email',
        'Interview Scheduled Confirmation',
        'Interview Confirmed: {{job_title}} with {{company_name}}',
        'Dear {{candidate_name}}, your interview for {{job_title}} has been scheduled on {{interview_date}} at {{interview_time}}. Meeting link: {{meeting_link}}.',
        'en', 1, 'published', true
    ),
    (
        NULL,
        (SELECT id FROM seeded_types WHERE code = 'assessment_invited'),
        'email',
        'Assessment Invitation Email',
        'Action Required: Skills Assessment for {{job_title}}',
        'Hello {{candidate_name}}, you have been invited to complete the {{assessment_name}} assessment for {{job_title}}. Please complete it before {{expires_at}}.',
        'en', 1, 'published', true
    ),
    (
        NULL,
        (SELECT id FROM seeded_types WHERE code = 'application_status_changed'),
        'email',
        'Application Update Email',
        'Update regarding your application for {{job_title}}',
        'Dear {{candidate_name}}, your application status has been updated to {{application_status}}.',
        'en', 1, 'published', true
    )
ON CONFLICT (organization_id, notification_type_id, channel, language_code, version) DO NOTHING;

-- =============================================================================
-- 4. PERFORMANCE INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON public.notifications(recipient_user_id, read_at);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_deliveries_recipient ON public.notification_deliveries(recipient_user_id, status);
CREATE INDEX IF NOT EXISTS idx_notif_deliveries_status ON public.notification_deliveries(status, scheduled_for);
CREATE INDEX IF NOT EXISTS idx_notif_deliveries_idemp ON public.notification_deliveries(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_notif_events_status ON public.notification_events(status, occurred_at);
CREATE INDEX IF NOT EXISTS idx_notif_events_idemp ON public.notification_events(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_notif_prefs_user ON public.notification_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_channels_user ON public.user_contact_channels(user_id, status);
CREATE INDEX IF NOT EXISTS idx_deliv_attempts_deliv ON public.notification_delivery_attempts(delivery_id, attempt_number);

-- =============================================================================
-- 5. ROW LEVEL SECURITY POLICIES
-- =============================================================================

ALTER TABLE public.notification_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_contact_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_delivery_attempts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.notification_types FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notification_templates FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_contact_channels FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notifications FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notification_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notification_delivery_attempts FORCE ROW LEVEL SECURITY;

-- 5.1 Notification Types: Public catalog for authenticated users
CREATE POLICY "Authenticated users read notification types"
ON public.notification_types FOR SELECT
TO authenticated
USING (is_active = true OR public.is_platform_admin(auth.uid()));

CREATE POLICY "Platform admins manage notification types"
ON public.notification_types FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()))
WITH CHECK (public.is_platform_admin(auth.uid()));

-- 5.2 Notification Templates
CREATE POLICY "Read notification templates"
ON public.notification_templates FOR SELECT
TO authenticated
USING (
    organization_id IS NULL
    OR public.check_user_is_recruiter(organization_id)
    OR public.is_platform_admin(auth.uid())
);

CREATE POLICY "Recruiters manage organization templates"
ON public.notification_templates FOR ALL
TO authenticated
USING (
    organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id)
)
WITH CHECK (
    organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id)
);

-- 5.3 Communication Preferences
CREATE POLICY "Users manage own preferences"
ON public.notification_preferences FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 5.4 User Contact Channels
CREATE POLICY "Users manage own contact channels"
ON public.user_contact_channels FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 5.5 In-App Notifications (Strict Recipient Isolation)
CREATE POLICY "Users read own in-app notifications"
ON public.notifications FOR SELECT
TO authenticated
USING (recipient_user_id = auth.uid());

CREATE POLICY "Users update own in-app notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (recipient_user_id = auth.uid())
WITH CHECK (recipient_user_id = auth.uid());

-- 5.6 Notification Events Queue
CREATE POLICY "Recruiters and admins read notification events"
ON public.notification_events FOR SELECT
TO authenticated
USING (
    actor_user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
    OR public.is_platform_admin(auth.uid())
);

-- 5.7 Notification Deliveries
CREATE POLICY "Users read own deliveries"
ON public.notification_deliveries FOR SELECT
TO authenticated
USING (
    recipient_user_id = auth.uid()
    OR public.is_platform_admin(auth.uid())
);

-- 5.8 Delivery Attempts Log
CREATE POLICY "Admins and recruiters read delivery attempts"
ON public.notification_delivery_attempts FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.notification_deliveries nd
        WHERE nd.id = delivery_id
          AND (nd.recipient_user_id = auth.uid() OR public.is_platform_admin(auth.uid()))
    )
);

-- =============================================================================
-- 6. STORED PROCEDURES & BUSINESS LOGIC (15 FUNCTIONS)
-- =============================================================================

-- 6.1 In-App Notification Query
CREATE OR REPLACE FUNCTION public.get_my_notifications(
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0,
    p_unread_only BOOLEAN DEFAULT false
)
RETURNS TABLE (
    out_notification_id UUID,
    out_type_code TEXT,
    out_type_category TEXT,
    out_title TEXT,
    out_body TEXT,
    out_data JSONB,
    out_priority TEXT,
    out_read_at TIMESTAMPTZ,
    out_created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT
        n.id AS out_notification_id,
        COALESCE(nt.code, 'general') AS out_type_code,
        COALESCE(nt.category, 'system') AS out_type_category,
        n.title AS out_title,
        n.body AS out_body,
        n.data AS out_data,
        n.priority AS out_priority,
        n.read_at AS out_read_at,
        n.created_at AS out_created_at
    FROM public.notifications n
    LEFT JOIN public.notification_types nt ON nt.id = n.notification_type_id
    WHERE n.recipient_user_id = auth.uid()
      AND (p_unread_only IS FALSE OR n.read_at IS NULL)
      AND (n.expires_at IS NULL OR n.expires_at > now())
    ORDER BY n.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 6.2 Get Unread Count
CREATE OR REPLACE FUNCTION public.get_unread_notification_count()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_count BIGINT;
BEGIN
    SELECT count(*)::BIGINT INTO v_count
    FROM public.notifications n
    WHERE n.recipient_user_id = auth.uid()
      AND n.read_at IS NULL
      AND (n.expires_at IS NULL OR n.expires_at > now());
    RETURN v_count;
END;
$$;

-- 6.3 Mark Notification Read
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.notifications
    SET read_at = now()
    WHERE id = p_notification_id AND recipient_user_id = auth.uid();
END;
$$;

-- 6.4 Mark All Notifications Read
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_updated INT;
BEGIN
    WITH updated AS (
        UPDATE public.notifications
        SET read_at = now()
        WHERE recipient_user_id = auth.uid() AND read_at IS NULL
        RETURNING id
    )
    SELECT count(*)::INT INTO v_updated FROM updated;
    RETURN v_updated;
END;
$$;

-- 6.5 Update Communication Preferences
CREATE OR REPLACE FUNCTION public.update_notification_preference(
    p_type_code TEXT,
    p_channel TEXT,
    p_enabled BOOLEAN,
    p_quiet_start TIME DEFAULT NULL,
    p_quiet_end TIME DEFAULT NULL,
    p_tz TEXT DEFAULT 'UTC'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_type RECORD;
    v_pref_id UUID;
BEGIN
    SELECT * INTO v_type FROM public.notification_types WHERE code = p_type_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification type % not found', p_type_code;
    END IF;

    -- Enforce required notification rule: cannot disable if required
    IF v_type.is_required IS TRUE AND p_enabled IS FALSE THEN
        RAISE EXCEPTION 'Cannot disable notification %: this notification is required by the platform', p_type_code;
    END IF;

    INSERT INTO public.notification_preferences (
        user_id, notification_type_id, channel, enabled, quiet_hours_start, quiet_hours_end, timezone
    )
    VALUES (
        auth.uid(), v_type.id, p_channel, p_enabled, p_quiet_start, p_quiet_end, p_tz
    )
    ON CONFLICT (user_id, notification_type_id, channel) DO UPDATE
    SET enabled = EXCLUDED.enabled,
        quiet_hours_start = EXCLUDED.quiet_hours_start,
        quiet_hours_end = EXCLUDED.quiet_hours_end,
        timezone = EXCLUDED.timezone,
        updated_at = now()
    RETURNING id INTO v_pref_id;

    RETURN v_pref_id;
END;
$$;

-- 6.6 Manage User Contact Channels
CREATE OR REPLACE FUNCTION public.add_communication_channel(
    p_channel TEXT,
    p_address TEXT,
    p_is_primary BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_channel_id UUID;
BEGIN
    IF p_is_primary IS TRUE THEN
        UPDATE public.user_contact_channels
        SET is_primary = false, updated_at = now()
        WHERE user_id = auth.uid() AND channel = p_channel;
    END IF;

    INSERT INTO public.user_contact_channels (
        user_id, channel, address, is_verified, is_primary, status
    )
    VALUES (
        auth.uid(), p_channel, p_address, false, p_is_primary, 'unverified'
    )
    ON CONFLICT (user_id, channel, address) DO UPDATE
    SET is_primary = EXCLUDED.is_primary,
        status = 'active',
        updated_at = now()
    RETURNING id INTO v_channel_id;

    RETURN v_channel_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_communication_channel(p_channel_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    DELETE FROM public.user_contact_channels
    WHERE id = p_channel_id AND user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.request_channel_verification(p_channel_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.user_contact_channels
    SET is_verified = true, status = 'active', updated_at = now()
    WHERE id = p_channel_id AND user_id = auth.uid();
    RETURN FOUND;
END;
$$;

-- 6.7 Safe Template Variable Interpolation
CREATE OR REPLACE FUNCTION public.render_notification_template(
    p_template_body TEXT,
    p_variables JSONB
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_res TEXT := p_template_body;
    v_key TEXT;
    v_val TEXT;
BEGIN
    IF p_variables IS NULL THEN
        RETURN v_res;
    END IF;

    FOR v_key, v_val IN SELECT key, value#>>'{}' FROM jsonb_each(p_variables)
    LOOP
        v_res := replace(v_res, '{{' || v_key || '}}', COALESCE(v_val, ''));
    END LOOP;

    RETURN v_res;
END;
$$;

-- 6.8 Quiet Hours Verification (Handles midnight crossing)
CREATE OR REPLACE FUNCTION public.is_in_quiet_hours(
    p_start_time TIME,
    p_end_time TIME,
    p_tz TEXT DEFAULT 'UTC'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_now TIME;
BEGIN
    IF p_start_time IS NULL OR p_end_time IS NULL THEN
        RETURN false;
    END IF;

    -- Current time in recipient timezone
    BEGIN
        v_now := (now() AT TIME ZONE COALESCE(p_tz, 'UTC'))::time;
    EXCEPTION WHEN OTHERS THEN
        v_now := (now() AT TIME ZONE 'UTC')::time;
    END;

    -- Case 1: Start < End (e.g. 13:00 to 15:00)
    IF p_start_time < p_end_time THEN
        RETURN v_now >= p_start_time AND v_now < p_end_time;
    -- Case 2: Start >= End (e.g. 22:00 to 07:00 crossing midnight)
    ELSE
        RETURN v_now >= p_start_time OR v_now < p_end_time;
    END IF;
END;
$$;

-- 6.9 Central Event Emission Bridge
CREATE OR REPLACE FUNCTION public.emit_notification_event(
    p_event_type TEXT,
    p_source_module TEXT,
    p_source_record_id UUID,
    p_organization_id UUID DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_event_id UUID;
    v_key TEXT;
BEGIN
    v_key := COALESCE(p_idempotency_key, p_event_type || ':' || COALESCE(p_source_record_id::text, gen_random_uuid()::text));

    INSERT INTO public.notification_events (
        event_type, source_module, source_record_id, organization_id, actor_user_id, payload, status, idempotency_key
    )
    VALUES (
        p_event_type, p_source_module, p_source_record_id, p_organization_id, auth.uid(), p_payload, 'queued', v_key
    )
    ON CONFLICT (idempotency_key) DO UPDATE
    SET status = 'queued', occurred_at = now()
    RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$$;

-- 6.10 Process Notification Event (Dispatches to In-App & Channels)
CREATE OR REPLACE FUNCTION public.process_notification_event(p_event_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ev RECORD;
    v_type RECORD;
    v_recipient UUID;
    v_title TEXT;
    v_body TEXT;
    v_inapp_id UUID;
    v_deliveries_created INT := 0;
    v_tmpl RECORD;
    v_channel_pref RECORD;
    v_address TEXT;
    v_sched TIMESTAMPTZ := NULL;
    v_is_quiet BOOLEAN := false;
BEGIN
    SELECT * INTO v_ev FROM public.notification_events WHERE id = p_event_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event % not found', p_event_id;
    END IF;

    SELECT * INTO v_type FROM public.notification_types WHERE code = v_ev.event_type;
    IF NOT FOUND THEN
        -- Mark ignored if no matching notification type
        UPDATE public.notification_events SET status = 'ignored', processed_at = now() WHERE id = p_event_id;
        RETURN 0;
    END IF;

    -- Determine recipient from payload
    v_recipient := (v_ev.payload->>'recipient_user_id')::uuid;
    IF v_recipient IS NULL THEN
        UPDATE public.notification_events SET status = 'failed', processed_at = now() WHERE id = p_event_id;
        RETURN 0;
    END IF;

    -- Generate rendered title & body
    v_title := public.render_notification_template(COALESCE(v_ev.payload->>'title', v_type.name), v_ev.payload);
    v_body := public.render_notification_template(COALESCE(v_ev.payload->>'body', v_type.description), v_ev.payload);

    -- 1. Create In-App Notification
    INSERT INTO public.notifications (
        recipient_user_id, notification_type_id, title, body, data, priority
    )
    VALUES (
        v_recipient, v_type.id, v_title, v_body, v_ev.payload, v_type.default_priority
    )
    RETURNING id INTO v_inapp_id;
    v_deliveries_created := v_deliveries_created + 1;

    -- 2. Dispatch Email Delivery Job if enabled / required
    SELECT * INTO v_channel_pref
    FROM public.notification_preferences
    WHERE user_id = v_recipient AND notification_type_id = v_type.id AND channel = 'email';

    IF (v_channel_pref.enabled IS NOT FALSE OR v_type.is_required IS TRUE) THEN
        -- Check quiet hours
        IF v_channel_pref.quiet_hours_start IS NOT NULL AND v_type.default_priority <> 'urgent' THEN
            v_is_quiet := public.is_in_quiet_hours(v_channel_pref.quiet_hours_start, v_channel_pref.quiet_hours_end, v_channel_pref.timezone);
            IF v_is_quiet THEN
                v_sched := now() + interval '4 hours';
            END IF;
        END IF;

        -- Find destination email
        SELECT address INTO v_address
        FROM public.user_contact_channels
        WHERE user_id = v_recipient AND channel = 'email' AND status = 'active'
        ORDER BY is_primary DESC LIMIT 1;

        IF v_address IS NULL THEN
            SELECT email INTO v_address FROM public.profiles WHERE id = v_recipient;
        END IF;

        IF v_address IS NOT NULL THEN
            -- Select appropriate template
            SELECT * INTO v_tmpl
            FROM public.notification_templates
            WHERE notification_type_id = v_type.id AND channel = 'email' AND status = 'published'
            ORDER BY (organization_id = v_ev.organization_id) DESC, version DESC LIMIT 1;

            INSERT INTO public.notification_deliveries (
                notification_id, recipient_user_id, channel, destination, template_id, template_version,
                status, provider, scheduled_for, idempotency_key
            )
            VALUES (
                v_inapp_id, v_recipient, 'email', v_address, v_tmpl.id, COALESCE(v_tmpl.version, 1),
                CASE WHEN v_sched IS NOT NULL THEN 'scheduled' ELSE 'queued' END,
                'mock_email', v_sched,
                'deliv:email:' || v_ev.id || ':' || v_recipient
            )
            ON CONFLICT (idempotency_key) DO NOTHING;

            IF FOUND THEN
                v_deliveries_created := v_deliveries_created + 1;
            END IF;
        END IF;
    END IF;

    UPDATE public.notification_events SET status = 'processed', processed_at = now() WHERE id = p_event_id;
    RETURN v_deliveries_created;
END;
$$;

-- 6.11 Record Delivery Attempt & Handle Retries
CREATE OR REPLACE FUNCTION public.record_delivery_attempt(
    p_delivery_id UUID,
    p_provider TEXT,
    p_status TEXT,
    p_error_code TEXT DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_provider_msg_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_deliv RECORD;
    v_attempt_id UUID;
    v_new_count INT;
BEGIN
    SELECT * INTO v_deliv FROM public.notification_deliveries WHERE id = p_delivery_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Delivery % not found', p_delivery_id;
    END IF;

    v_new_count := v_deliv.attempt_count + 1;

    INSERT INTO public.notification_delivery_attempts (
        delivery_id, attempt_number, provider, status, error_code, error_message, completed_at
    )
    VALUES (
        p_delivery_id, v_new_count, p_provider, p_status, p_error_code, p_error_message, now()
    )
    RETURNING id INTO v_attempt_id;

    -- Status updates based on outcome
    IF p_status = 'success' THEN
        UPDATE public.notification_deliveries
        SET status = 'delivered',
            attempt_count = v_new_count,
            provider_message_id = p_provider_msg_id,
            delivered_at = now(),
            updated_at = now()
        WHERE id = p_delivery_id;
    ELSIF p_status = 'permanent_failure' OR v_new_count >= v_deliv.max_attempts THEN
        UPDATE public.notification_deliveries
        SET status = 'failed',
            attempt_count = v_new_count,
            failed_at = now(),
            failure_code = p_error_code,
            failure_message = p_error_message,
            updated_at = now()
        WHERE id = p_delivery_id;
    ELSE -- temporary_failure with remaining attempts
        UPDATE public.notification_deliveries
        SET status = 'queued',
            attempt_count = v_new_count,
            scheduled_for = now() + (v_new_count * interval '5 minutes'),
            failure_code = p_error_code,
            failure_message = p_error_message,
            updated_at = now()
        WHERE id = p_delivery_id;
    END IF;

    RETURN v_attempt_id;
END;
$$;

-- 6.12 Interview Reminder Suppression Check
CREATE OR REPLACE FUNCTION public.check_interview_reminder_eligibility(p_interview_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_int RECORD;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Suppress if cancelled or completed
    IF v_int.status IN ('cancelled', 'completed') THEN
        RETURN false;
    END IF;

    -- Only remind if scheduled start is still in the future
    RETURN v_int.scheduled_start_at > now();
END;
$$;

-- 6.13 Assessment Reminder Suppression Check
CREATE OR REPLACE FUNCTION public.check_assessment_reminder_eligibility(p_invitation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_inv RECORD;
BEGIN
    SELECT * INTO v_inv FROM public.assessment_invitations WHERE id = p_invitation_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Suppress if completed, expired, or cancelled
    IF v_inv.status IN ('completed', 'expired', 'cancelled') THEN
        RETURN false;
    END IF;

    RETURN v_inv.expires_at > now();
END;
$$;

-- =============================================================================
-- END OF MIGRATION 20260915001200_notifications_communications.sql
-- =============================================================================
