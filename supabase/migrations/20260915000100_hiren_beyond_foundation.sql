-- =============================================================================
-- Migration: 20260915000100_hiren_beyond_foundation.sql
-- Description: Core backend foundation for Hiren Beyond
-- Author: Hiren Beyond Engineering
-- Schema: profiles, organizations, roles, permissions, role_permissions,
--         organization_members, audit_logs
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- 1. UTILITY & HELPER FUNCTIONS
-- =============================================================================

-- Automated timestamp updater function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 2. CORE TABLES
-- =============================================================================

-- A. PROFILES (extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT,
    avatar_url TEXT,
    phone TEXT,
    country_code VARCHAR(10),
    preferred_language VARCHAR(10) NOT NULL DEFAULT 'en',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- B. ORGANIZATIONS (multi-tenant boundaries)
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    organization_type TEXT NOT NULL CHECK (organization_type IN ('platform', 'recruitment_agency', 'client', 'partner', 'team')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    logo_url TEXT,
    country_code VARCHAR(10),
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_organizations_slug UNIQUE (slug)
);

-- C. ROLES (RBAC role catalog)
CREATE TABLE IF NOT EXISTS public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    is_system_role BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_roles_key UNIQUE (key)
);

-- D. PERMISSIONS (granular permissions catalog)
CREATE TABLE IF NOT EXISTS public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_permissions_key UNIQUE (key)
);

-- E. ROLE_PERMISSIONS (Role-to-Permission junction)
CREATE TABLE IF NOT EXISTS public.role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_role_permissions UNIQUE (role_id, permission_id)
);

-- F. ORGANIZATION_MEMBERS (Tenant user membership & role assignment)
CREATE TABLE IF NOT EXISTS public.organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invited', 'suspended', 'left')),
    joined_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_organization_members UNIQUE (organization_id, user_id)
);

-- G. AUDIT_LOGS (Immutable event logging foundation)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- 3. INDEXES
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON public.profiles(status);

CREATE INDEX IF NOT EXISTS idx_organizations_slug ON public.organizations(slug);
CREATE INDEX IF NOT EXISTS idx_organizations_type ON public.organizations(organization_type);
CREATE INDEX IF NOT EXISTS idx_organizations_status ON public.organizations(status);

CREATE INDEX IF NOT EXISTS idx_roles_key ON public.roles(key);
CREATE INDEX IF NOT EXISTS idx_permissions_key ON public.permissions(key);
CREATE INDEX IF NOT EXISTS idx_permissions_category ON public.permissions(category);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role ON public.role_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_perm ON public.role_permissions(permission_id);

CREATE INDEX IF NOT EXISTS idx_org_members_org ON public.organization_members(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_members_user ON public.organization_members(user_id);
CREATE INDEX IF NOT EXISTS idx_org_members_role ON public.organization_members(role_id);
CREATE INDEX IF NOT EXISTS idx_org_members_status ON public.organization_members(status);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_org ON public.audit_logs(organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs(created_at DESC);

-- =============================================================================
-- 4. TRIGGERS
-- =============================================================================

-- Automatic updated_at triggers
DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_organizations_updated_at ON public.organizations;
CREATE TRIGGER trg_organizations_updated_at
    BEFORE UPDATE ON public.organizations
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_org_members_updated_at ON public.organization_members;
CREATE TRIGGER trg_org_members_updated_at
    BEFORE UPDATE ON public.organization_members
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Automatic profile creation on auth.users sign-up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture', '')
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =============================================================================
-- 5. MULTI-TENANCY & RBAC HELPER FUNCTIONS (SECURITY DEFINER)
-- =============================================================================

-- Check if a user has platform_admin privileges
CREATE OR REPLACE FUNCTION public.is_platform_admin(check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    IF check_user_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.organization_members om
        JOIN public.organizations o ON o.id = om.organization_id
        JOIN public.roles r ON r.id = om.role_id
        WHERE om.user_id = check_user_id
          AND om.status = 'active'
          AND o.organization_type = 'platform'
          AND o.status = 'active'
          AND r.key = 'platform_admin'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Check if user is an active member of an organization
CREATE OR REPLACE FUNCTION public.is_org_member(check_org_id UUID, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    IF check_user_id IS NULL OR check_org_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.organization_members
        WHERE organization_id = check_org_id
          AND user_id = check_user_id
          AND status = 'active'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Check if user has a specific permission in an organization
CREATE OR REPLACE FUNCTION public.has_org_permission(check_org_id UUID, perm_key TEXT, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
    IF check_user_id IS NULL THEN
        RETURN false;
    END IF;

    -- Platform admins implicitly hold all permissions
    IF public.is_platform_admin(check_user_id) THEN
        RETURN true;
    END IF;

    IF check_org_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.organization_members om
        JOIN public.role_permissions rp ON rp.role_id = om.role_id
        JOIN public.permissions p ON p.id = rp.permission_id
        WHERE om.organization_id = check_org_id
          AND om.user_id = check_user_id
          AND om.status = 'active'
          AND p.key = perm_key
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- =============================================================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- PROFILES POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "profiles_select_own_or_platform_admin"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (
        id = auth.uid()
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "profiles_update_own_or_platform_admin"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (
        id = auth.uid()
        OR public.is_platform_admin(auth.uid())
    )
    WITH CHECK (
        id = auth.uid()
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "profiles_insert_own_or_platform_admin"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (
        id = auth.uid()
        OR public.is_platform_admin(auth.uid())
    );

-- -----------------------------------------------------------------------------
-- ORGANIZATIONS POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "organizations_select_member_or_platform_admin"
    ON public.organizations FOR SELECT
    TO authenticated
    USING (
        public.is_org_member(id, auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "organizations_insert_platform_admin"
    ON public.organizations FOR INSERT
    TO authenticated
    WITH CHECK (
        public.is_platform_admin(auth.uid())
    );

CREATE POLICY "organizations_update_authorized_admin"
    ON public.organizations FOR UPDATE
    TO authenticated
    USING (
        public.has_org_permission(id, 'organizations.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    )
    WITH CHECK (
        public.has_org_permission(id, 'organizations.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "organizations_delete_platform_admin"
    ON public.organizations FOR DELETE
    TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
    );

-- -----------------------------------------------------------------------------
-- ROLES POLICIES (Read-only catalog for authenticated users, platform admin edit)
-- -----------------------------------------------------------------------------
CREATE POLICY "roles_select_authenticated"
    ON public.roles FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "roles_write_platform_admin"
    ON public.roles FOR ALL
    TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- -----------------------------------------------------------------------------
-- PERMISSIONS POLICIES (Read-only catalog for authenticated users, platform admin edit)
-- -----------------------------------------------------------------------------
CREATE POLICY "permissions_select_authenticated"
    ON public.permissions FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "permissions_write_platform_admin"
    ON public.permissions FOR ALL
    TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- -----------------------------------------------------------------------------
-- ROLE_PERMISSIONS POLICIES (Read-only catalog for authenticated users)
-- -----------------------------------------------------------------------------
CREATE POLICY "role_permissions_select_authenticated"
    ON public.role_permissions FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "role_permissions_write_platform_admin"
    ON public.role_permissions FOR ALL
    TO authenticated
    USING (public.is_platform_admin(auth.uid()))
    WITH CHECK (public.is_platform_admin(auth.uid()));

-- -----------------------------------------------------------------------------
-- ORGANIZATION_MEMBERS POLICIES
-- -----------------------------------------------------------------------------
CREATE POLICY "org_members_select_own_or_permitted"
    ON public.organization_members FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid()
        OR public.has_org_permission(organization_id, 'members.read', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "org_members_insert_authorized"
    ON public.organization_members FOR INSERT
    TO authenticated
    WITH CHECK (
        (public.has_org_permission(organization_id, 'members.manage', auth.uid())
         AND role_id NOT IN (SELECT id FROM public.roles WHERE key = 'platform_admin'))
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "org_members_update_authorized"
    ON public.organization_members FOR UPDATE
    TO authenticated
    USING (
        (public.has_org_permission(organization_id, 'members.manage', auth.uid())
         AND role_id NOT IN (SELECT id FROM public.roles WHERE key = 'platform_admin'))
        OR public.is_platform_admin(auth.uid())
    )
    WITH CHECK (
        (public.has_org_permission(organization_id, 'members.manage', auth.uid())
         AND role_id NOT IN (SELECT id FROM public.roles WHERE key = 'platform_admin'))
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "org_members_delete_authorized"
    ON public.organization_members FOR DELETE
    TO authenticated
    USING (
        public.has_org_permission(organization_id, 'members.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

-- -----------------------------------------------------------------------------
-- AUDIT_LOGS POLICIES (Append-only, scoped viewing)
-- -----------------------------------------------------------------------------
CREATE POLICY "audit_logs_insert_authenticated"
    ON public.audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (
        actor_user_id IS NULL
        OR actor_user_id = auth.uid()
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY "audit_logs_select_scoped"
    ON public.audit_logs FOR SELECT
    TO authenticated
    USING (
        (organization_id IS NOT NULL AND public.has_org_permission(organization_id, 'audit_logs.read', auth.uid()))
        OR public.is_platform_admin(auth.uid())
    );

-- NOTE: No UPDATE or DELETE policies are created for audit_logs,
-- guaranteeing that audit log records are immutable and append-only.

