-- ============================================================================
-- Hiren Beyond Backend -- Migration 20260915002300
-- Task 23: Frontend Integration Contract
--   - Frontend helper RPCs (organization context, permissions, config)
--   - Dashboard metrics, org summary, notification badge count
--   - mark_notification_read / mark_all_notifications_read (updated signatures)
--   - list_notifications (frontend-optimized paginated RPC)
--   - get_my_profile / update_my_profile
--   - get_frontend_config (public, anon-accessible)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. DROP FUNCTIONS WITH INCOMPATIBLE RETURN TYPES
-- PostgreSQL cannot change return type via CREATE OR REPLACE.
-- We must drop and recreate.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.mark_notification_read(UUID);
DROP FUNCTION IF EXISTS public.mark_all_notifications_read();

-- ----------------------------------------------------------------------------
-- 1. get_user_organizations
-- Returns all organizations the caller belongs to, with their role.
-- Used by the frontend post-login to resolve organization context.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_user_organizations()
RETURNS TABLE (
    organization_id     UUID,
    organization_name   TEXT,
    organization_slug   TEXT,
    logo_url            TEXT,
    subscription_plan   TEXT,
    subscription_status TEXT,
    role_name           TEXT,
    role_display_name   TEXT,
    is_active           BOOLEAN,
    joined_at           TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    RETURN QUERY
    SELECT
        o.id            AS organization_id,
        o.name::TEXT    AS organization_name,
        o.slug::TEXT    AS organization_slug,
        o.logo_url::TEXT,
        o.subscription_plan::TEXT,
        o.subscription_status::TEXT,
        r.name::TEXT    AS role_name,
        r.display_name::TEXT AS role_display_name,
        om.is_active    AS is_active,
        om.joined_at    AS joined_at
    FROM public.organization_members om
    JOIN public.organizations o ON o.id = om.organization_id
    JOIN public.roles r ON r.id = om.role_id
    WHERE om.user_id = auth.uid()
      AND om.is_active = TRUE
      AND o.is_active  = TRUE
    ORDER BY om.joined_at ASC;
END;
$$;

COMMENT ON FUNCTION public.get_user_organizations IS
    'Returns all active organizations for the authenticated user. Frontend post-login.';

GRANT EXECUTE ON FUNCTION public.get_user_organizations() TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. get_user_permissions
-- Returns all permission keys for the caller in a specific organization.
-- Used by the frontend to gate UI elements without fetching full role objects.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_user_permissions(
    p_organization_id UUID
)
RETURNS TABLE (
    permission_key  TEXT,
    permission_name TEXT,
    category        TEXT,
    role_name       TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE user_id       = auth.uid()
          AND organization_id = p_organization_id
          AND is_active     = TRUE
    ) AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Not a member of this organization';
    END IF;

    RETURN QUERY
    SELECT
        p.key::TEXT     AS permission_key,
        p.name::TEXT    AS permission_name,
        p.category::TEXT AS category,
        r.name::TEXT    AS role_name
    FROM public.organization_members om
    JOIN public.roles r           ON r.id  = om.role_id
    JOIN public.role_permissions rp ON rp.role_id = r.id
    JOIN public.permissions p     ON p.id  = rp.permission_id
    WHERE om.user_id        = auth.uid()
      AND om.organization_id  = p_organization_id
      AND om.is_active      = TRUE
    ORDER BY p.category, p.key;
END;
$$;

COMMENT ON FUNCTION public.get_user_permissions IS
    'Returns all permission keys for the caller in an organization. For frontend UI gating.';

GRANT EXECUTE ON FUNCTION public.get_user_permissions(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. get_my_profile
-- Returns the caller's own profile record.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS TABLE (
    id           UUID,
    email        TEXT,
    full_name    TEXT,
    avatar_url   TEXT,
    phone        TEXT,
    timezone     TEXT,
    locale       TEXT,
    is_active    BOOLEAN,
    last_seen_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    RETURN QUERY
    SELECT
        p.id,
        p.email::TEXT,
        p.full_name::TEXT,
        p.avatar_url::TEXT,
        p.phone::TEXT,
        p.timezone::TEXT,
        p.locale::TEXT,
        p.is_active,
        p.last_seen_at,
        p.created_at,
        p.updated_at
    FROM public.profiles p
    WHERE p.id = auth.uid();
END;
$$;

COMMENT ON FUNCTION public.get_my_profile IS
    'Returns the authenticated user profile. Frontend /me equivalent.';

GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated;

-- ----------------------------------------------------------------------------
-- 4. update_my_profile
-- Allows users to update their own profile fields.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_my_profile(
    p_full_name  TEXT DEFAULT NULL,
    p_phone      TEXT DEFAULT NULL,
    p_timezone   TEXT DEFAULT NULL,
    p_locale     TEXT DEFAULT NULL,
    p_avatar_url TEXT DEFAULT NULL
)
RETURNS TABLE (
    success    BOOLEAN,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    UPDATE public.profiles
    SET
        full_name  = COALESCE(p_full_name,  full_name),
        phone      = COALESCE(p_phone,      phone),
        timezone   = COALESCE(p_timezone,   timezone),
        locale     = COALESCE(p_locale,     locale),
        avatar_url = COALESCE(p_avatar_url, avatar_url),
        updated_at = now()
    WHERE id = auth.uid();

    RETURN QUERY SELECT TRUE, now()::TIMESTAMPTZ;
END;
$$;

COMMENT ON FUNCTION public.update_my_profile IS
    'Allows the authenticated user to update their own profile fields.';

GRANT EXECUTE ON FUNCTION public.update_my_profile(TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. get_notification_badge_count
-- Lightweight RPC for unread count badge in the navbar.
-- Uses the notifications table (recipient_user_id, read_at).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_notification_badge_count()
RETURNS TABLE (
    unread_count BIGINT,
    has_urgent   BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT AS unread_count,
        BOOL_OR(
            n.priority IN ('high', 'urgent')
        ) AS has_urgent
    FROM public.notifications n
    WHERE n.recipient_user_id = auth.uid()
      AND n.read_at IS NULL;
END;
$$;

COMMENT ON FUNCTION public.get_notification_badge_count IS
    'Returns unread notification count and urgent flag for navbar badge.';

GRANT EXECUTE ON FUNCTION public.get_notification_badge_count() TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. get_frontend_config
-- Returns safe public platform config for frontend feature flags.
-- Accessible by anon + authenticated (no secrets returned).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_frontend_config()
RETURNS TABLE (
    config_key   TEXT,
    config_value TEXT,
    category     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        sc.config_key::TEXT,
        sc.config_value::TEXT,
        sc.category::TEXT
    FROM public.system_configs sc
    WHERE sc.is_public = TRUE
      AND sc.is_active  = TRUE
    ORDER BY sc.category, sc.config_key;
END;
$$;

COMMENT ON FUNCTION public.get_frontend_config IS
    'Returns safe public platform configuration. Accessible without authentication.';

GRANT EXECUTE ON FUNCTION public.get_frontend_config() TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 7. mark_notification_read
-- Marks a single notification as read. Validates ownership.
-- NOTE: Dropped above because old signature returned VOID.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mark_notification_read(
    p_notification_id UUID
)
RETURNS TABLE (
    success         BOOLEAN,
    notification_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_owner UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    SELECT recipient_user_id INTO v_owner
    FROM public.notifications
    WHERE id = p_notification_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Notification % not found', p_notification_id;
    END IF;

    IF v_owner != auth.uid() THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Cannot modify another user''s notification';
    END IF;

    UPDATE public.notifications
    SET read_at = now()
    WHERE id                = p_notification_id
      AND recipient_user_id = auth.uid()
      AND read_at IS NULL;

    RETURN QUERY SELECT TRUE, p_notification_id;
END;
$$;

COMMENT ON FUNCTION public.mark_notification_read IS
    'Marks a single notification as read. Validates ownership.';

GRANT EXECUTE ON FUNCTION public.mark_notification_read(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 8. mark_all_notifications_read
-- Bulk marks all unread notifications as read for the caller.
-- NOTE: Old version had no args and returned INT. Dropped above.
-- New version returns TABLE for frontend consistency.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS TABLE (
    success       BOOLEAN,
    updated_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count BIGINT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    UPDATE public.notifications
    SET read_at = now()
    WHERE recipient_user_id = auth.uid()
      AND read_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN QUERY SELECT TRUE, v_count;
END;
$$;

COMMENT ON FUNCTION public.mark_all_notifications_read IS
    'Bulk marks all unread notifications as read for the authenticated user.';

GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

-- ----------------------------------------------------------------------------
-- 9. list_notifications (frontend-optimized, paginated)
-- Returns paginated in-app notifications for the notification panel.
-- Uses cursor pagination on (created_at DESC, id DESC).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.list_notifications(
    p_limit       INT     DEFAULT 20,
    p_cursor      UUID    DEFAULT NULL,
    p_unread_only BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id                   UUID,
    notification_type_id UUID,
    title                TEXT,
    body                 TEXT,
    data                 JSONB,
    priority             TEXT,
    read_at              TIMESTAMPTZ,
    created_at           TIMESTAMPTZ,
    has_more             BOOLEAN,
    next_cursor          UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INT := LEAST(COALESCE(p_limit, 20), 100);
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    RETURN QUERY
    WITH paginated AS (
        SELECT n.*
        FROM public.notifications n
        WHERE n.recipient_user_id = auth.uid()
          AND (NOT p_unread_only OR n.read_at IS NULL)
          AND (p_cursor IS NULL OR n.id < p_cursor)
        ORDER BY n.created_at DESC, n.id DESC
        LIMIT v_limit + 1
    ),
    result AS (
        SELECT * FROM paginated LIMIT v_limit
    )
    SELECT
        r.id,
        r.notification_type_id,
        r.title::TEXT,
        r.body::TEXT,
        r.data,
        r.priority::TEXT,
        r.read_at,
        r.created_at,
        (SELECT COUNT(*) FROM paginated) > v_limit,
        (
            SELECT p.id FROM paginated p
            ORDER BY p.created_at DESC, p.id DESC
            LIMIT 1 OFFSET v_limit - 1
        )
    FROM result r
    ORDER BY r.created_at DESC, r.id DESC;
END;
$$;

COMMENT ON FUNCTION public.list_notifications IS
    'Paginated notification list for the frontend notification panel.';

GRANT EXECUTE ON FUNCTION public.list_notifications(INT, UUID, BOOLEAN) TO authenticated;

-- ----------------------------------------------------------------------------
-- 10. get_organization_summary
-- Lightweight org summary for dashboard header / org switcher.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_organization_summary(
    p_organization_id UUID
)
RETURNS TABLE (
    organization_id         UUID,
    name                    TEXT,
    slug                    TEXT,
    logo_url                TEXT,
    subscription_plan       TEXT,
    subscription_status     TEXT,
    trial_ends_at           TIMESTAMPTZ,
    active_jobs_count       BIGINT,
    active_candidates_count BIGINT,
    pending_applications    BIGINT,
    team_member_count       BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE user_id        = auth.uid()
          AND organization_id = p_organization_id
          AND is_active      = TRUE
    ) AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Not a member of this organization';
    END IF;

    RETURN QUERY
    SELECT
        o.id,
        o.name::TEXT,
        o.slug::TEXT,
        o.logo_url::TEXT,
        o.subscription_plan::TEXT,
        o.subscription_status::TEXT,
        o.trial_ends_at,
        (SELECT COUNT(*)::BIGINT FROM public.jobs j
            WHERE j.organization_id = o.id AND j.status = 'published'),
        (SELECT COUNT(*)::BIGINT FROM public.candidates c
            WHERE c.organization_id = o.id AND c.status = 'active'),
        (SELECT COUNT(*)::BIGINT FROM public.applications a
            WHERE a.organization_id = o.id AND a.status IN ('new', 'in_review')),
        (SELECT COUNT(*)::BIGINT FROM public.organization_members om2
            WHERE om2.organization_id = o.id AND om2.is_active = TRUE)
    FROM public.organizations o
    WHERE o.id = p_organization_id;
END;
$$;

COMMENT ON FUNCTION public.get_organization_summary IS
    'Returns org summary metrics for the dashboard header and context switcher.';

GRANT EXECUTE ON FUNCTION public.get_organization_summary(UUID) TO authenticated;

-- ----------------------------------------------------------------------------
-- 11. get_dashboard_metrics
-- Returns key KPI cards for the main recruiter dashboard.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(
    p_organization_id UUID,
    p_days            INT DEFAULT 30
)
RETURNS TABLE (
    metric_name     TEXT,
    metric_value    NUMERIC,
    metric_unit     TEXT,
    trend_delta     NUMERIC,
    trend_direction TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_period_start TIMESTAMPTZ := now() - (p_days || ' days')::INTERVAL;
    v_prev_start   TIMESTAMPTZ := now() - (p_days * 2 || ' days')::INTERVAL;
    v_curr_apps    BIGINT;
    v_prev_apps    BIGINT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE user_id        = auth.uid()
          AND organization_id = p_organization_id
          AND is_active      = TRUE
    ) AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Not a member of this organization';
    END IF;

    SELECT COUNT(*) INTO v_curr_apps FROM public.applications
    WHERE organization_id = p_organization_id AND applied_at >= v_period_start;

    SELECT COUNT(*) INTO v_prev_apps FROM public.applications
    WHERE organization_id = p_organization_id
      AND applied_at BETWEEN v_prev_start AND v_period_start;

    RETURN QUERY

    -- 1. New applications in period
    SELECT
        'new_applications'::TEXT,
        v_curr_apps::NUMERIC,
        'applications'::TEXT,
        (v_curr_apps - v_prev_apps)::NUMERIC,
        CASE WHEN v_curr_apps >= v_prev_apps THEN 'up' ELSE 'down' END::TEXT

    UNION ALL

    -- 2. Interviews scheduled in period
    SELECT
        'interviews_scheduled'::TEXT,
        COUNT(*)::NUMERIC,
        'interviews'::TEXT,
        0::NUMERIC,
        'neutral'::TEXT
    FROM public.interviews
    WHERE organization_id = p_organization_id
      AND scheduled_at >= v_period_start
      AND status NOT IN ('cancelled')

    UNION ALL

    -- 3. Open positions right now
    SELECT
        'open_positions'::TEXT,
        COUNT(*)::NUMERIC,
        'jobs'::TEXT,
        0::NUMERIC,
        'neutral'::TEXT
    FROM public.jobs
    WHERE organization_id = p_organization_id
      AND status = 'published'

    UNION ALL

    -- 4. Hires made in period
    SELECT
        'hires_made'::TEXT,
        COUNT(*)::NUMERIC,
        'candidates'::TEXT,
        0::NUMERIC,
        'neutral'::TEXT
    FROM public.hiring_decisions
    WHERE organization_id = p_organization_id
      AND decision          = 'offer_extended'
      AND candidate_response = 'accepted'
      AND decided_at        >= v_period_start;
END;
$$;

COMMENT ON FUNCTION public.get_dashboard_metrics IS
    'Returns key KPI metrics for the recruiter dashboard with trend direction.';

GRANT EXECUTE ON FUNCTION public.get_dashboard_metrics(UUID, INT) TO authenticated;
