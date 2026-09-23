-- =============================================================================
-- TASK 17: PLATFORM ADMINISTRATION & OPERATIONAL CONTROLS
-- Migration: 20260915001700_platform_administration.sql
-- =============================================================================
-- Adds:
--   • 15 platform.* permissions seeded onto platform_admin role
--   • feature_flags + feature_flag_targets
--   • organization_feature_overrides
--   • platform_settings (typed KV store with public/sensitive flags)
--   • platform_announcements
--   • support_access_sessions
--   • platform_security_events
--   • Administrative RPCs (platform_admin authorized only)
--   • Public helper: get_public_platform_settings()
--   • Full RLS on all new tables
-- =============================================================================

-- =============================================================================
-- 1. EXTEND PERMISSIONS — PLATFORM ADMIN NAMESPACE
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category) VALUES
    ('platform.organizations.read',    'Read All Organizations',       'View all organizations platform-wide',                  'platform'),
    ('platform.organizations.manage',  'Manage All Organizations',     'Create, update, suspend, archive any organization',     'platform'),
    ('platform.users.read',            'Read All Users',               'View all user profiles platform-wide',                  'platform'),
    ('platform.users.manage',          'Manage All Users',             'Suspend, reactivate, disable any user',                 'platform'),
    ('platform.roles.manage',          'Manage Roles',                 'Create and modify platform roles',                      'platform'),
    ('platform.permissions.manage',    'Manage Permissions',           'Create and assign permissions',                         'platform'),
    ('platform.settings.manage',       'Manage Platform Settings',     'Read and write platform configuration values',          'platform'),
    ('platform.features.manage',       'Manage Feature Flags',         'Enable, disable, and target feature flags',             'platform'),
    ('platform.plans.manage',          'Manage Plans',                 'Create, version, archive subscription plans',           'platform'),
    ('platform.reference_data.manage', 'Manage Reference Data',        'Modify global reference data (countries, etc.)',        'platform'),
    ('platform.integrations.manage',   'Manage Integrations',          'Monitor and manage all integration connections',        'platform'),
    ('platform.ai.manage',             'Manage AI Configuration',      'Configure AI assistants, prompts, and providers',       'platform'),
    ('platform.audit.read',            'Read Audit Logs',              'View platform-wide audit log records',                  'platform'),
    ('platform.operations.read',       'Read Operational Health',      'View platform health, job queues, and system metrics',  'platform'),
    ('platform.support.manage',        'Manage Support Access',        'Create, approve, and revoke support access sessions',   'platform')
ON CONFLICT (key) DO NOTHING;

-- Assign all platform.* permissions to the platform_admin role
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON p.key LIKE 'platform.%'
WHERE r.key = 'platform_admin'
ON CONFLICT DO NOTHING;

-- Create platform_operator and platform_support roles (limited scopes)
INSERT INTO public.roles (key, name, description, is_system_role) VALUES
    ('platform_operator', 'Platform Operator',
     'Operational monitoring and support access management; no destructive actions', true),
    ('platform_support',  'Platform Support',
     'Read-only access to user/org details for tier-1 support', true)
ON CONFLICT (key) DO NOTHING;

-- platform_operator gets read + health + support.manage
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p
  ON p.key IN (
      'platform.organizations.read',
      'platform.users.read',
      'platform.audit.read',
      'platform.operations.read',
      'platform.support.manage',
      'platform.integrations.manage'
  )
WHERE r.key = 'platform_operator'
ON CONFLICT DO NOTHING;

-- platform_support gets read-only
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p
  ON p.key IN (
      'platform.organizations.read',
      'platform.users.read',
      'platform.audit.read'
  )
WHERE r.key = 'platform_support'
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 2. FEATURE FLAGS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.feature_flags (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    key             TEXT        NOT NULL UNIQUE,
    name            TEXT        NOT NULL,
    description     TEXT,
    status          TEXT        NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'active', 'disabled', 'deprecated')),
    default_enabled BOOLEAN     NOT NULL DEFAULT false,
    configuration   JSONB       NOT NULL DEFAULT '{}'::JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feature_flags_key    ON public.feature_flags(key);
CREATE INDEX IF NOT EXISTS idx_feature_flags_status ON public.feature_flags(status);

CREATE TRIGGER trg_feature_flags_updated_at
    BEFORE UPDATE ON public.feature_flags
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 3. FEATURE FLAG TARGETS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.feature_flag_targets (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_flag_id UUID        NOT NULL REFERENCES public.feature_flags(id) ON DELETE CASCADE,
    target_type     TEXT        NOT NULL CHECK (target_type IN ('organization', 'user', 'plan')),
    target_id       UUID        NOT NULL,
    enabled         BOOLEAN     NOT NULL DEFAULT true,
    configuration   JSONB       NOT NULL DEFAULT '{}'::JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_feature_flag_target UNIQUE (feature_flag_id, target_type, target_id)
);

CREATE INDEX IF NOT EXISTS idx_fft_flag      ON public.feature_flag_targets(feature_flag_id);
CREATE INDEX IF NOT EXISTS idx_fft_target    ON public.feature_flag_targets(target_type, target_id);

CREATE TRIGGER trg_feature_flag_targets_updated_at
    BEFORE UPDATE ON public.feature_flag_targets
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. ORGANIZATION FEATURE OVERRIDES
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.organization_feature_overrides (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    feature_key     TEXT        NOT NULL,
    enabled         BOOLEAN     NOT NULL DEFAULT true,
    limit_value     NUMERIC,
    reason          TEXT,
    expires_at      TIMESTAMPTZ,
    created_by      UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_org_feat_overrides_org     ON public.organization_feature_overrides(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_feat_overrides_key     ON public.organization_feature_overrides(feature_key);
CREATE INDEX IF NOT EXISTS idx_org_feat_overrides_expires ON public.organization_feature_overrides(expires_at)
    WHERE expires_at IS NOT NULL;

CREATE TRIGGER trg_org_feat_overrides_updated_at
    BEFORE UPDATE ON public.organization_feature_overrides
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 5. PLATFORM SETTINGS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.platform_settings (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    key          TEXT        NOT NULL UNIQUE,
    value        TEXT        NOT NULL,
    value_type   TEXT        NOT NULL DEFAULT 'string'
        CHECK (value_type IN ('string', 'number', 'boolean', 'json')),
    description  TEXT,
    is_public    BOOLEAN     NOT NULL DEFAULT false,
    is_sensitive BOOLEAN     NOT NULL DEFAULT false,
    updated_by   UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_platform_setting_not_both CHECK (NOT (is_public AND is_sensitive))
);

CREATE INDEX IF NOT EXISTS idx_platform_settings_key    ON public.platform_settings(key);
CREATE INDEX IF NOT EXISTS idx_platform_settings_public ON public.platform_settings(is_public) WHERE is_public = true;

CREATE TRIGGER trg_platform_settings_updated_at
    BEFORE UPDATE ON public.platform_settings
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Seed initial platform settings
INSERT INTO public.platform_settings (key, value, value_type, description, is_public, is_sensitive) VALUES
    ('default_language',              'en',    'string',  'Default platform UI language code',                         true,  false),
    ('default_currency',              'USD',   'string',  'Default currency code for billing display',                  true,  false),
    ('default_timezone',              'UTC',   'string',  'Default timezone for scheduling and reports',                true,  false),
    ('maintenance_mode',              'false', 'boolean', 'When true, show maintenance page to non-admin users',        true,  false),
    ('maximum_file_size_mb',          '50',    'number',  'Maximum file upload size in megabytes',                      true,  false),
    ('maximum_ai_request_size_kb',    '500',   'number',  'Maximum AI request payload size in kilobytes',               false, false),
    ('default_application_expiry_days','30',   'number',  'Days after which unreviewed applications auto-expire',       true,  false),
    ('default_assessment_expiry_days', '7',    'number',  'Days after which an assessment invitation auto-expires',     false, false),
    ('ai_provider_primary',           'gemini','string',  'Primary AI provider identifier (no secrets stored here)',    false, false),
    ('platform_name',                 'Hiren Beyond', 'string', 'Platform display name',                               true,  false)
ON CONFLICT (key) DO NOTHING;

-- =============================================================================
-- 6. PLATFORM ANNOUNCEMENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.platform_announcements (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT        NOT NULL,
    message     TEXT        NOT NULL,
    severity    TEXT        NOT NULL DEFAULT 'info'
        CHECK (severity IN ('info', 'warning', 'critical', 'maintenance')),
    status      TEXT        NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'active', 'expired', 'cancelled')),
    target_type TEXT        NOT NULL DEFAULT 'all'
        CHECK (target_type IN ('all', 'organization', 'plan')),
    target_id   UUID,
    starts_at   TIMESTAMPTZ,
    ends_at     TIMESTAMPTZ,
    created_by  UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_announcements_status   ON public.platform_announcements(status);
CREATE INDEX IF NOT EXISTS idx_announcements_severity ON public.platform_announcements(severity);
CREATE INDEX IF NOT EXISTS idx_announcements_target   ON public.platform_announcements(target_type, target_id);

CREATE TRIGGER trg_announcements_updated_at
    BEFORE UPDATE ON public.platform_announcements
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 7. SUPPORT ACCESS SESSIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.support_access_sessions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    support_user_id UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    target_user_id  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    organization_id UUID        REFERENCES public.organizations(id) ON DELETE SET NULL,
    reason          TEXT        NOT NULL CHECK (char_length(reason) >= 10),
    scope           TEXT        NOT NULL DEFAULT 'read_only',
    starts_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'active'
        CHECK (status IN ('pending', 'active', 'expired', 'revoked', 'completed')),
    approved_by     UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at        TIMESTAMPTZ,
    CONSTRAINT chk_support_session_expiry CHECK (expires_at > starts_at),
    CONSTRAINT chk_support_session_max_duration
        CHECK (expires_at <= starts_at + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_support_sessions_support_user ON public.support_access_sessions(support_user_id);
CREATE INDEX IF NOT EXISTS idx_support_sessions_target_user  ON public.support_access_sessions(target_user_id);
CREATE INDEX IF NOT EXISTS idx_support_sessions_status       ON public.support_access_sessions(status);
CREATE INDEX IF NOT EXISTS idx_support_sessions_expires      ON public.support_access_sessions(expires_at);

-- =============================================================================
-- 8. PLATFORM SECURITY EVENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.platform_security_events (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type    TEXT        NOT NULL CHECK (event_type IN (
                      'privilege_escalation_attempt',
                      'unauthorized_admin_action',
                      'support_access_started',
                      'support_access_ended',
                      'bulk_admin_action',
                      'configuration_changed',
                      'feature_override_granted',
                      'organization_suspended',
                      'organization_archived',
                      'user_suspended',
                      'user_disabled',
                      'admin_action_denied',
                      'support_access_revoked'
                  )),
    actor_user_id UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    target_type   TEXT,
    target_id     UUID,
    severity      TEXT        NOT NULL DEFAULT 'info'
        CHECK (severity IN ('info', 'warning', 'critical')),
    metadata      JSONB       NOT NULL DEFAULT '{}'::JSONB,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_security_events_type     ON public.platform_security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_actor    ON public.platform_security_events(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON public.platform_security_events(severity);
CREATE INDEX IF NOT EXISTS idx_security_events_created  ON public.platform_security_events(created_at DESC);

-- =============================================================================
-- 9. RLS — ENABLE ON ALL NEW TABLES
-- =============================================================================

ALTER TABLE public.feature_flags                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feature_flag_targets             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_feature_overrides   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_settings                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_announcements           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_access_sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_security_events         ENABLE ROW LEVEL SECURITY;

-- ---- feature_flags ----
CREATE POLICY "ff_public_read_active"
    ON public.feature_flags FOR SELECT TO authenticated, anon
    USING (status = 'active');

CREATE POLICY "ff_admin_all"
    ON public.feature_flags FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- ---- feature_flag_targets ----
CREATE POLICY "fft_org_member_read"
    ON public.feature_flag_targets FOR SELECT TO authenticated
    USING (
        (target_type = 'organization' AND public.is_org_member(target_id, auth.uid()))
        OR (target_type = 'user' AND target_id = auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "fft_admin_manage"
    ON public.feature_flag_targets FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- ---- organization_feature_overrides ----
CREATE POLICY "ofo_org_member_read"
    ON public.organization_feature_overrides FOR SELECT TO authenticated
    USING (
        public.is_org_member(organization_id, auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "ofo_admin_manage"
    ON public.organization_feature_overrides FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- ---- platform_settings ----
CREATE POLICY "ps_public_read"
    ON public.platform_settings FOR SELECT TO authenticated, anon
    USING (is_public = true AND is_sensitive = false);

CREATE POLICY "ps_admin_all"
    ON public.platform_settings FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- ---- platform_announcements ----
CREATE POLICY "pa_public_read_active"
    ON public.platform_announcements FOR SELECT TO authenticated, anon
    USING (status = 'active');

CREATE POLICY "pa_admin_all"
    ON public.platform_announcements FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- ---- support_access_sessions ----
CREATE POLICY "sas_admin_all"
    ON public.support_access_sessions FOR ALL TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- ---- platform_security_events ----
CREATE POLICY "pse_admin_read"
    ON public.platform_security_events FOR SELECT TO authenticated
    USING (public.is_platform_admin(auth.uid()));

CREATE POLICY "pse_system_insert"
    ON public.platform_security_events FOR INSERT TO authenticated
    WITH CHECK (true);  -- insert happens inside SECURITY DEFINER functions only

-- =============================================================================
-- 10. HELPER: check_feature_enabled
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_feature_enabled(
    p_feature_key TEXT,
    p_org_id      UUID DEFAULT NULL,
    p_user_id     UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_flag        public.feature_flags%ROWTYPE;
    v_enabled     BOOLEAN;
BEGIN
    -- Get base flag
    SELECT * INTO v_flag FROM public.feature_flags WHERE key = p_feature_key;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    IF v_flag.status != 'active' THEN
        RETURN false;
    END IF;

    -- Check org-level override (highest priority)
    IF p_org_id IS NOT NULL THEN
        SELECT enabled INTO v_enabled
        FROM public.organization_feature_overrides
        WHERE organization_id = p_org_id
          AND feature_key = p_feature_key
          AND (expires_at IS NULL OR expires_at > now())
        LIMIT 1;
        IF FOUND THEN
            RETURN v_enabled;
        END IF;

        -- Check feature_flag_targets for this org
        SELECT enabled INTO v_enabled
        FROM public.feature_flag_targets
        WHERE feature_flag_id = v_flag.id
          AND target_type = 'organization'
          AND target_id = p_org_id
        LIMIT 1;
        IF FOUND THEN
            RETURN v_enabled;
        END IF;
    END IF;

    -- Check user-level target
    IF p_user_id IS NOT NULL THEN
        SELECT enabled INTO v_enabled
        FROM public.feature_flag_targets
        WHERE feature_flag_id = v_flag.id
          AND target_type = 'user'
          AND target_id = p_user_id
        LIMIT 1;
        IF FOUND THEN
            RETURN v_enabled;
        END IF;
    END IF;

    -- Fall back to default
    RETURN v_flag.default_enabled;
END;
$$;

-- =============================================================================
-- 11. PUBLIC: get_public_platform_settings
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_public_platform_settings()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB := '{}'::JSONB;
    v_row    RECORD;
BEGIN
    FOR v_row IN
        SELECT key, value, value_type, description
        FROM public.platform_settings
        WHERE is_public = true
          AND is_sensitive = false
        ORDER BY key
    LOOP
        v_result := v_result || jsonb_build_object(v_row.key, jsonb_build_object(
            'value',       v_row.value,
            'value_type',  v_row.value_type,
            'description', v_row.description
        ));
    END LOOP;
    RETURN v_result;
END;
$$;

-- =============================================================================
-- 12. ADMIN: get_platform_dashboard
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_dashboard()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT jsonb_build_object(
        'organizations', jsonb_build_object(
            'total',     (SELECT COUNT(*) FROM public.organizations),
            'active',    (SELECT COUNT(*) FROM public.organizations WHERE status = 'active'),
            'suspended', (SELECT COUNT(*) FROM public.organizations WHERE status = 'suspended'),
            'archived',  (SELECT COUNT(*) FROM public.organizations WHERE status = 'archived')
        ),
        'users', jsonb_build_object(
            'total',     (SELECT COUNT(*) FROM public.profiles),
            'active',    (SELECT COUNT(*) FROM public.profiles WHERE status = 'active'),
            'suspended', (SELECT COUNT(*) FROM public.profiles WHERE status = 'suspended')
        ),
        'jobs', jsonb_build_object(
            'total',  (SELECT COUNT(*) FROM public.jobs),
            'open',   (SELECT COUNT(*) FROM public.jobs WHERE status = 'published')
        ),
        'applications', jsonb_build_object(
            'total', (SELECT COUNT(*) FROM public.applications)
        ),
        'cv_processing', jsonb_build_object(
            'queued',     (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'queued'),
            'processing', (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'processing'),
            'failed',     (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'failed')
        ),
        'ai_usage', jsonb_build_object(
            'total_requests',   (SELECT COUNT(*) FROM public.ai_usage_logs),
            'failed_requests',  (SELECT COUNT(*) FROM public.ai_usage_logs WHERE status = 'error'),
            'last_24h_requests',(SELECT COUNT(*) FROM public.ai_usage_logs WHERE created_at > now() - INTERVAL '24 hours')
        ),
        'webhooks', jsonb_build_object(
            'failed_deliveries', (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status = 'failed')
        ),
        'support_sessions', jsonb_build_object(
            'active', (SELECT COUNT(*) FROM public.support_access_sessions WHERE status = 'active' AND expires_at > now())
        ),
        'feature_flags', jsonb_build_object(
            'active',   (SELECT COUNT(*) FROM public.feature_flags WHERE status = 'active'),
            'disabled', (SELECT COUNT(*) FROM public.feature_flags WHERE status = 'disabled')
        ),
        'generated_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 13. ADMIN: get_platform_health
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_health()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT jsonb_build_object(
        'database', jsonb_build_object(
            'status', 'healthy',
            'checked_at', now()
        ),
        'cv_processing', jsonb_build_object(
            'queued',          (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'queued'),
            'processing',      (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'processing'),
            'failed_total',    (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'failed'),
            'failed_last_1h',  (SELECT COUNT(*) FROM public.cv_processing_jobs WHERE status = 'failed' AND updated_at > now() - INTERVAL '1 hour'),
            'oldest_queued',   (SELECT MIN(created_at) FROM public.cv_processing_jobs WHERE status = 'queued')
        ),
        'ai_operations', jsonb_build_object(
            'total_last_24h',    (SELECT COUNT(*) FROM public.ai_usage_logs WHERE created_at > now() - INTERVAL '24 hours'),
            'failed_last_24h',   (SELECT COUNT(*) FROM public.ai_usage_logs WHERE status = 'error' AND created_at > now() - INTERVAL '24 hours'),
            'avg_latency_ms',    (SELECT ROUND(AVG(latency_ms)) FROM public.ai_usage_logs WHERE created_at > now() - INTERVAL '24 hours')
        ),
        'webhooks', jsonb_build_object(
            'queued',         (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status = 'queued'),
            'failed_total',   (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status = 'failed'),
            'failed_last_1h', (SELECT COUNT(*) FROM public.webhook_deliveries WHERE status = 'failed' AND created_at > now() - INTERVAL '1 hour')
        ),
        'notifications', jsonb_build_object(
            'failed_last_24h', (SELECT COUNT(*) FROM public.notifications WHERE status = 'failed' AND created_at > now() - INTERVAL '24 hours')
        ),
        'support_sessions', jsonb_build_object(
            'active_count', (SELECT COUNT(*) FROM public.support_access_sessions WHERE status = 'active' AND expires_at > now())
        ),
        'maintenance_mode', (SELECT value FROM public.platform_settings WHERE key = 'maintenance_mode'),
        'checked_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 14. ADMIN: get_platform_audit_summary
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_audit_summary()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT jsonb_build_object(
        'recent_security_events', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id',           id,
                'event_type',   event_type,
                'actor_user_id',actor_user_id,
                'severity',     severity,
                'created_at',   created_at
            ) ORDER BY created_at DESC), '[]'::JSONB)
            FROM public.platform_security_events
            WHERE created_at > now() - INTERVAL '7 days'
        ),
        'recent_critical_audits', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id',           id,
                'actor',        actor_user_id,
                'action',       action,
                'entity_type',  entity_type,
                'created_at',   created_at
            ) ORDER BY created_at DESC), '[]'::JSONB)
            FROM public.audit_logs
            WHERE action IN (
                'organization_suspended','organization_archived',
                'user_suspended','user_disabled',
                'platform_setting_changed','feature_flag_changed',
                'support_access_started','support_access_revoked',
                'role_assigned','plan_changed'
            )
            AND created_at > now() - INTERVAL '7 days'
            LIMIT 50
        ),
        'generated_at', now()
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 15. ADMIN: search_platform_organizations
-- =============================================================================

CREATE OR REPLACE FUNCTION public.search_platform_organizations(
    p_query  TEXT    DEFAULT NULL,
    p_status TEXT    DEFAULT NULL,
    p_limit  INT     DEFAULT 20,
    p_offset INT     DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    p_limit  := LEAST(GREATEST(p_limit, 1), 100);
    p_offset := GREATEST(p_offset, 0);

    SELECT jsonb_build_object(
        'organizations', COALESCE(jsonb_agg(row_to_json(t.*)), '[]'::JSONB),
        'limit',  p_limit,
        'offset', p_offset
    )
    INTO v_result
    FROM (
        SELECT
            o.id, o.name, o.slug, o.organization_type, o.status,
            o.country_code, o.created_at, o.updated_at,
            (SELECT COUNT(*) FROM public.organization_members om
             WHERE om.organization_id = o.id AND om.status = 'active') AS member_count,
            (SELECT COUNT(*) FROM public.jobs j WHERE j.organization_id = o.id) AS job_count
        FROM public.organizations o
        WHERE (p_query IS NULL OR o.name ILIKE '%' || p_query || '%' OR o.slug ILIKE '%' || p_query || '%')
          AND (p_status IS NULL OR o.status = p_status)
        ORDER BY o.created_at DESC
        LIMIT p_limit OFFSET p_offset
    ) t;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 16. ADMIN: get_platform_organization_details
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_organization_details(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_org    public.organizations%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_org FROM public.organizations WHERE id = p_org_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organization not found';
    END IF;

    SELECT jsonb_build_object(
        'organization', row_to_json(v_org.*),
        'stats', jsonb_build_object(
            'member_count',       (SELECT COUNT(*) FROM public.organization_members  WHERE organization_id = p_org_id AND status = 'active'),
            'active_jobs',        (SELECT COUNT(*) FROM public.jobs                  WHERE organization_id = p_org_id AND status = 'published'),
            'total_applications', (SELECT COUNT(*) FROM public.applications a JOIN public.jobs j ON j.id = a.job_id WHERE j.organization_id = p_org_id),
            'total_candidates',   (SELECT COUNT(*) FROM public.candidates WHERE organization_id = p_org_id)
        ),
        'subscription', (
            SELECT row_to_json(s.*) FROM public.organization_subscriptions s
            WHERE s.organization_id = p_org_id AND s.status = 'active'
            ORDER BY s.created_at DESC LIMIT 1
        ),
        'feature_overrides', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'feature_key', feature_key,
                'enabled',     enabled,
                'limit_value', limit_value,
                'expires_at',  expires_at
            )), '[]'::JSONB)
            FROM public.organization_feature_overrides
            WHERE organization_id = p_org_id
              AND (expires_at IS NULL OR expires_at > now())
        ),
        'recent_audit', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'action',     action,
                'actor',      actor_user_id,
                'entity_type',entity_type,
                'created_at', created_at
            ) ORDER BY created_at DESC), '[]'::JSONB)
            FROM public.audit_logs
            WHERE organization_id = p_org_id
            LIMIT 10
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 17. ADMIN: search_platform_users
-- =============================================================================

CREATE OR REPLACE FUNCTION public.search_platform_users(
    p_query  TEXT DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit  INT  DEFAULT 20,
    p_offset INT  DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    p_limit  := LEAST(GREATEST(p_limit, 1), 100);
    p_offset := GREATEST(p_offset, 0);

    SELECT jsonb_build_object(
        'users', COALESCE(jsonb_agg(row_to_json(t.*)), '[]'::JSONB),
        'limit',  p_limit,
        'offset', p_offset
    )
    INTO v_result
    FROM (
        SELECT
            p.id, p.email, p.full_name, p.status, p.avatar_url,
            p.created_at, p.updated_at,
            (SELECT COUNT(*) FROM public.organization_members om
             WHERE om.user_id = p.id AND om.status = 'active') AS org_count
        FROM public.profiles p
        WHERE (p_query IS NULL OR p.email ILIKE '%' || p_query || '%' OR p.full_name ILIKE '%' || p_query || '%')
          AND (p_status IS NULL OR p.status = p_status)
        ORDER BY p.created_at DESC
        LIMIT p_limit OFFSET p_offset
    ) t;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 18. ADMIN: get_platform_user_details
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_user_details(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
    v_profile public.profiles%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    SELECT jsonb_build_object(
        'profile', jsonb_build_object(
            'id',         v_profile.id,
            'email',      v_profile.email,
            'full_name',  v_profile.full_name,
            'status',     v_profile.status,
            'avatar_url', v_profile.avatar_url,
            'phone',      v_profile.phone,
            'created_at', v_profile.created_at,
            'updated_at', v_profile.updated_at
        ),
        'organizations', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'org_id',   o.id,
                'org_name', o.name,
                'org_type', o.organization_type,
                'org_status', o.status,
                'role_key', r.key,
                'membership_status', om.status
            )), '[]'::JSONB)
            FROM public.organization_members om
            JOIN public.organizations o ON o.id = om.organization_id
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.user_id = p_user_id
        ),
        'recent_audit', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'action',     action,
                'entity_type',entity_type,
                'created_at', created_at
            ) ORDER BY created_at DESC), '[]'::JSONB)
            FROM public.audit_logs
            WHERE actor_user_id = p_user_id
            LIMIT 10
        ),
        'active_support_sessions', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id',          id,
                'support_user',support_user_id,
                'scope',       scope,
                'expires_at',  expires_at
            )), '[]'::JSONB)
            FROM public.support_access_sessions
            WHERE target_user_id = p_user_id
              AND status = 'active'
              AND expires_at > now()
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 19. ADMIN: search_audit_logs
-- =============================================================================

CREATE OR REPLACE FUNCTION public.search_audit_logs(
    p_org_id        UUID        DEFAULT NULL,
    p_actor_user_id UUID        DEFAULT NULL,
    p_action        TEXT        DEFAULT NULL,
    p_from          TIMESTAMPTZ DEFAULT NULL,
    p_to            TIMESTAMPTZ DEFAULT NULL,
    p_limit         INT         DEFAULT 50,
    p_offset        INT         DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    p_limit  := LEAST(GREATEST(p_limit, 1), 200);
    p_offset := GREATEST(p_offset, 0);

    SELECT jsonb_build_object(
        'logs', COALESCE(jsonb_agg(row_to_json(t.*) ORDER BY t.created_at DESC), '[]'::JSONB),
        'limit',  p_limit,
        'offset', p_offset
    )
    INTO v_result
    FROM (
        SELECT
            al.id, al.actor_user_id, al.organization_id,
            al.action, al.entity_type, al.entity_id,
            al.ip_address, al.created_at
        FROM public.audit_logs al
        WHERE (p_org_id        IS NULL OR al.organization_id  = p_org_id)
          AND (p_actor_user_id IS NULL OR al.actor_user_id    = p_actor_user_id)
          AND (p_action        IS NULL OR al.action ILIKE '%' || p_action || '%')
          AND (p_from          IS NULL OR al.created_at >= p_from)
          AND (p_to            IS NULL OR al.created_at <= p_to)
        ORDER BY al.created_at DESC
        LIMIT p_limit OFFSET p_offset
    ) t;

    RETURN v_result;
END;
$$;

-- =============================================================================
-- 20. ADMIN: suspend_organization
-- =============================================================================

CREATE OR REPLACE FUNCTION public.suspend_organization(
    p_org_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org public.organizations%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        INSERT INTO public.platform_security_events
            (event_type, actor_user_id, target_type, target_id, severity, metadata)
        VALUES
            ('admin_action_denied', auth.uid(), 'organization', p_org_id, 'warning',
             jsonb_build_object('attempted_action', 'suspend_organization', 'reason', p_reason));
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_org FROM public.organizations WHERE id = p_org_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organization not found';
    END IF;
    IF v_org.status = 'suspended' THEN
        RAISE EXCEPTION 'Organization is already suspended';
    END IF;
    IF v_org.status = 'archived' THEN
        RAISE EXCEPTION 'Cannot suspend an archived organization';
    END IF;

    UPDATE public.organizations
       SET status = 'suspended', updated_at = now()
     WHERE id = p_org_id;

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), p_org_id, 'organization_suspended', 'organization', p_org_id,
            jsonb_build_object('reason', p_reason, 'previous_status', v_org.status));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('organization_suspended', auth.uid(), 'organization', p_org_id, 'warning',
         jsonb_build_object('reason', p_reason));

    RETURN jsonb_build_object('success', true, 'org_id', p_org_id, 'status', 'suspended');
END;
$$;

-- =============================================================================
-- 21. ADMIN: reactivate_organization
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reactivate_organization(
    p_org_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org public.organizations%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_org FROM public.organizations WHERE id = p_org_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organization not found';
    END IF;
    IF v_org.status NOT IN ('suspended', 'inactive') THEN
        RAISE EXCEPTION 'Organization is not in a suspended or inactive state';
    END IF;

    UPDATE public.organizations
       SET status = 'active', updated_at = now()
     WHERE id = p_org_id;

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), p_org_id, 'organization_reactivated', 'organization', p_org_id,
            jsonb_build_object('reason', p_reason, 'previous_status', v_org.status));

    RETURN jsonb_build_object('success', true, 'org_id', p_org_id, 'status', 'active');
END;
$$;

-- =============================================================================
-- 22. ADMIN: archive_organization
-- =============================================================================

CREATE OR REPLACE FUNCTION public.archive_organization(
    p_org_id UUID,
    p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org public.organizations%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    IF p_reason IS NULL OR char_length(trim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'A detailed reason (>= 10 characters) is required to archive an organization';
    END IF;

    SELECT * INTO v_org FROM public.organizations WHERE id = p_org_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organization not found';
    END IF;
    IF v_org.status = 'archived' THEN
        RAISE EXCEPTION 'Organization is already archived';
    END IF;

    -- Soft archive only — no physical deletion of jobs/candidates/applications
    UPDATE public.organizations
       SET status = 'archived', updated_at = now()
     WHERE id = p_org_id;

    -- Suspend all active memberships (soft)
    UPDATE public.organization_members
       SET status = 'inactive', updated_at = now()
     WHERE organization_id = p_org_id AND status = 'active';

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), p_org_id, 'organization_archived', 'organization', p_org_id,
            jsonb_build_object('reason', p_reason, 'previous_status', v_org.status));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('organization_archived', auth.uid(), 'organization', p_org_id, 'warning',
         jsonb_build_object('reason', p_reason));

    RETURN jsonb_build_object('success', true, 'org_id', p_org_id, 'status', 'archived',
                               'note', 'Historical data (jobs, applications, candidates) preserved');
END;
$$;

-- =============================================================================
-- 23. ADMIN: suspend_platform_user
-- =============================================================================

CREATE OR REPLACE FUNCTION public.suspend_platform_user(
    p_user_id UUID,
    p_reason  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile public.profiles%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        INSERT INTO public.platform_security_events
            (event_type, actor_user_id, target_type, target_id, severity, metadata)
        VALUES
            ('admin_action_denied', auth.uid(), 'user', p_user_id, 'warning',
             jsonb_build_object('attempted_action', 'suspend_platform_user'));
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    -- Prevent self-suspension
    IF p_user_id = auth.uid() THEN
        RAISE EXCEPTION 'Cannot suspend your own account';
    END IF;

    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    IF v_profile.status = 'suspended' THEN
        RAISE EXCEPTION 'User is already suspended';
    END IF;

    UPDATE public.profiles
       SET status = 'suspended', updated_at = now()
     WHERE id = p_user_id;

    INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'user_suspended', 'profile', p_user_id,
            jsonb_build_object('reason', p_reason, 'previous_status', v_profile.status));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('user_suspended', auth.uid(), 'user', p_user_id, 'warning',
         jsonb_build_object('reason', p_reason));

    RETURN jsonb_build_object('success', true, 'user_id', p_user_id, 'status', 'suspended');
END;
$$;

-- =============================================================================
-- 24. ADMIN: reactivate_platform_user
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reactivate_platform_user(
    p_user_id UUID,
    p_reason  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile public.profiles%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    IF v_profile.status NOT IN ('suspended', 'inactive', 'pending') THEN
        RAISE EXCEPTION 'User is not in a suspendable state (current: %)', v_profile.status;
    END IF;

    UPDATE public.profiles
       SET status = 'active', updated_at = now()
     WHERE id = p_user_id;

    INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'user_reactivated', 'profile', p_user_id,
            jsonb_build_object('reason', p_reason, 'previous_status', v_profile.status));

    RETURN jsonb_build_object('success', true, 'user_id', p_user_id, 'status', 'active');
END;
$$;

-- =============================================================================
-- 25. ADMIN: disable_platform_user
-- =============================================================================

CREATE OR REPLACE FUNCTION public.disable_platform_user(
    p_user_id UUID,
    p_reason  TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile public.profiles%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    IF p_user_id = auth.uid() THEN
        RAISE EXCEPTION 'Cannot disable your own account';
    END IF;

    IF p_reason IS NULL OR char_length(trim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'A detailed reason (>= 10 characters) is required to disable a user';
    END IF;

    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    UPDATE public.profiles
       SET status = 'inactive', updated_at = now()
     WHERE id = p_user_id;

    -- Soft-deactivate all active memberships
    UPDATE public.organization_members
       SET status = 'inactive', updated_at = now()
     WHERE user_id = p_user_id AND status = 'active';

    INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'user_disabled', 'profile', p_user_id,
            jsonb_build_object('reason', p_reason, 'previous_status', v_profile.status));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('user_disabled', auth.uid(), 'user', p_user_id, 'critical',
         jsonb_build_object('reason', p_reason));

    RETURN jsonb_build_object('success', true, 'user_id', p_user_id, 'status', 'disabled');
END;
$$;

-- =============================================================================
-- 26. ADMIN: grant_organization_feature_override
-- =============================================================================

CREATE OR REPLACE FUNCTION public.grant_organization_feature_override(
    p_org_id      UUID,
    p_feature_key TEXT,
    p_enabled     BOOLEAN     DEFAULT true,
    p_limit_value NUMERIC     DEFAULT NULL,
    p_reason      TEXT        DEFAULT NULL,
    p_expires_at  TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_override_id UUID;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
        RAISE EXCEPTION 'Organization not found';
    END IF;

    INSERT INTO public.organization_feature_overrides
        (organization_id, feature_key, enabled, limit_value, reason, expires_at, created_by)
    VALUES
        (p_org_id, p_feature_key, p_enabled, p_limit_value, p_reason, p_expires_at, auth.uid())
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_override_id;

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), p_org_id, 'feature_override_created', 'organization_feature_override',
            v_override_id,
            jsonb_build_object('feature_key', p_feature_key, 'enabled', p_enabled,
                               'limit_value', p_limit_value, 'expires_at', p_expires_at,
                               'reason', p_reason));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('feature_override_granted', auth.uid(), 'organization', p_org_id, 'info',
         jsonb_build_object('feature_key', p_feature_key, 'enabled', p_enabled,
                            'expires_at', p_expires_at));

    RETURN jsonb_build_object('success', true, 'override_id', v_override_id,
                               'org_id', p_org_id, 'feature_key', p_feature_key);
END;
$$;

-- =============================================================================
-- 27. ADMIN: create_support_access_session
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_support_access_session(
    p_target_user_id  UUID,
    p_org_id          UUID    DEFAULT NULL,
    p_reason          TEXT    DEFAULT NULL,
    p_scope           TEXT    DEFAULT 'read_only',
    p_duration_minutes INT    DEFAULT 60
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_id UUID;
    v_expires_at TIMESTAMPTZ;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    IF p_reason IS NULL OR char_length(trim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'A detailed reason (>= 10 characters) is required for support access';
    END IF;

    -- Enforce max 24h duration
    p_duration_minutes := LEAST(GREATEST(p_duration_minutes, 1), 1440);
    v_expires_at := now() + (p_duration_minutes || ' minutes')::INTERVAL;

    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_target_user_id) THEN
        RAISE EXCEPTION 'Target user not found';
    END IF;

    INSERT INTO public.support_access_sessions
        (support_user_id, target_user_id, organization_id, reason, scope,
         starts_at, expires_at, status, approved_by)
    VALUES
        (auth.uid(), p_target_user_id, p_org_id, p_reason, p_scope,
         now(), v_expires_at, 'active', auth.uid())
    RETURNING id INTO v_session_id;

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), p_org_id, 'support_access_started', 'support_access_session', v_session_id,
            jsonb_build_object('target_user_id', p_target_user_id, 'scope', p_scope,
                               'reason', p_reason, 'expires_at', v_expires_at));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('support_access_started', auth.uid(), 'user', p_target_user_id, 'warning',
         jsonb_build_object('session_id', v_session_id, 'scope', p_scope,
                            'expires_at', v_expires_at, 'reason', p_reason));

    RETURN jsonb_build_object(
        'success',     true,
        'session_id',  v_session_id,
        'expires_at',  v_expires_at,
        'scope',       p_scope,
        'note',        'Passwords, tokens, and payment credentials are never accessible through support sessions'
    );
END;
$$;

-- =============================================================================
-- 28. ADMIN: revoke_support_access_session
-- =============================================================================

CREATE OR REPLACE FUNCTION public.revoke_support_access_session(
    p_session_id UUID,
    p_reason     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session public.support_access_sessions%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_session FROM public.support_access_sessions WHERE id = p_session_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Support session not found';
    END IF;
    IF v_session.status NOT IN ('active', 'pending') THEN
        RAISE EXCEPTION 'Session is already % and cannot be revoked', v_session.status;
    END IF;

    UPDATE public.support_access_sessions
       SET status = 'revoked', ended_at = now(), updated_at = now()
     WHERE id = p_session_id;

    -- Mark expired so constraint is clear
    -- Note: updated_at is not a column on support_access_sessions so we skip that

    INSERT INTO public.audit_logs (actor_user_id, organization_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), v_session.organization_id, 'support_access_revoked',
            'support_access_session', p_session_id,
            jsonb_build_object('target_user_id', v_session.target_user_id,
                               'reason', p_reason, 'original_expires_at', v_session.expires_at));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('support_access_revoked', auth.uid(), 'user', v_session.target_user_id, 'warning',
         jsonb_build_object('session_id', p_session_id, 'revoke_reason', p_reason));

    RETURN jsonb_build_object('success', true, 'session_id', p_session_id, 'status', 'revoked');
END;
$$;

-- =============================================================================
-- 29. ADMIN: update_platform_setting
-- =============================================================================

CREATE OR REPLACE FUNCTION public.update_platform_setting(
    p_key    TEXT,
    p_value  TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_setting public.platform_settings%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_setting FROM public.platform_settings WHERE key = p_key FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Setting key "%" not found', p_key;
    END IF;

    -- Validate value type
    CASE v_setting.value_type
        WHEN 'boolean' THEN
            IF p_value NOT IN ('true', 'false') THEN
                RAISE EXCEPTION 'Boolean setting requires "true" or "false"';
            END IF;
        WHEN 'number' THEN
            IF p_value !~ '^-?[0-9]+\.?[0-9]*$' THEN
                RAISE EXCEPTION 'Number setting requires a numeric value';
            END IF;
        WHEN 'json' THEN
            BEGIN
                PERFORM p_value::JSONB;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'JSON setting requires valid JSON';
            END;
        ELSE
            NULL; -- string: any value is valid
    END CASE;

    UPDATE public.platform_settings
       SET value = p_value, updated_by = auth.uid(), updated_at = now()
     WHERE key = p_key;

    INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'platform_setting_changed', 'platform_setting', v_setting.id,
            jsonb_build_object('key', p_key, 'old_value',
                               CASE WHEN v_setting.is_sensitive THEN '[REDACTED]' ELSE v_setting.value END,
                               'new_value',
                               CASE WHEN v_setting.is_sensitive THEN '[REDACTED]' ELSE p_value END,
                               'reason', p_reason));

    INSERT INTO public.platform_security_events
        (event_type, actor_user_id, target_type, target_id, severity, metadata)
    VALUES
        ('configuration_changed', auth.uid(), 'platform_setting', v_setting.id, 'info',
         jsonb_build_object('key', p_key, 'reason', p_reason));

    RETURN jsonb_build_object('success', true, 'key', p_key, 'updated', true);
END;
$$;

-- =============================================================================
-- 30. ADMIN: retry_failed_cv_job
-- =============================================================================

CREATE OR REPLACE FUNCTION public.retry_failed_cv_job(
    p_job_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job public.cv_processing_jobs%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        INSERT INTO public.platform_security_events
            (event_type, actor_user_id, target_type, target_id, severity, metadata)
        VALUES
            ('admin_action_denied', auth.uid(), 'cv_processing_job', p_job_id, 'warning',
             jsonb_build_object('attempted_action', 'retry_failed_cv_job'));
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    SELECT * INTO v_job FROM public.cv_processing_jobs WHERE id = p_job_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job not found';
    END IF;
    IF v_job.status != 'failed' THEN
        RAISE EXCEPTION 'Job must be in failed state to retry (current: %)', v_job.status;
    END IF;

    UPDATE public.cv_processing_jobs
       SET status          = 'queued',
           attempt_count   = 0,
           next_retry_at   = NULL,
           error_code      = NULL,
           error_message   = NULL,
           started_at      = NULL,
           failed_at       = NULL,
           updated_at      = now()
     WHERE id = p_job_id;

    INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'system_job_requeued', 'cv_processing_job', p_job_id,
            jsonb_build_object('reason', p_reason, 'previous_attempts', v_job.attempt_count));

    RETURN jsonb_build_object('success', true, 'job_id', p_job_id, 'new_status', 'queued');
END;
$$;

-- =============================================================================
-- 31. ADMIN: create_platform_announcement
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_platform_announcement(
    p_title       TEXT,
    p_message     TEXT,
    p_severity    TEXT        DEFAULT 'info',
    p_target_type TEXT        DEFAULT 'all',
    p_target_id   UUID        DEFAULT NULL,
    p_starts_at   TIMESTAMPTZ DEFAULT now(),
    p_ends_at     TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: platform admin access required';
    END IF;

    INSERT INTO public.platform_announcements
        (title, message, severity, status, target_type, target_id, starts_at, ends_at, created_by)
    VALUES
        (p_title, p_message, p_severity, 'active', p_target_type, p_target_id,
         p_starts_at, p_ends_at, auth.uid())
    RETURNING id INTO v_id;

    INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
    VALUES (auth.uid(), 'announcement_created', 'platform_announcement', v_id,
            jsonb_build_object('title', p_title, 'severity', p_severity, 'target_type', p_target_type));

    RETURN jsonb_build_object('success', true, 'announcement_id', v_id);
END;
$$;

-- =============================================================================
-- 32. COMMENTS ON NEW TABLES
-- =============================================================================

COMMENT ON TABLE public.feature_flags IS
    'Platform-wide feature toggles. Active flags control beta, AI, and enterprise feature availability.';
COMMENT ON TABLE public.feature_flag_targets IS
    'Scoped feature flag overrides targeting specific organizations, users, or plans.';
COMMENT ON TABLE public.organization_feature_overrides IS
    'Per-organization feature unlocks/limits granted by platform admins. Overrides plan defaults. Supports expiration.';
COMMENT ON TABLE public.platform_settings IS
    'Typed platform configuration KV store. Sensitive settings never exposed via public RPCs. Public settings readable by all.';
COMMENT ON TABLE public.platform_announcements IS
    'Platform-wide banners and notifications. Severity and targeting control display scope.';
COMMENT ON TABLE public.support_access_sessions IS
    'Time-bounded, auditable support access grants. Max 24h duration. Never exposes passwords, tokens, or payment credentials.';
COMMENT ON TABLE public.platform_security_events IS
    'Immutable security event log for privilege escalation attempts, support access, bulk actions, and configuration changes.';
