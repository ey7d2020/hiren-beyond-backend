-- =============================================================================
-- Migration: 20260915001701_fix_admin_status_constraints.sql
-- Extends organizations.status to include 'archived'
-- Extends profiles.status to include 'pending'
-- Required for platform_administration lifecycle operations (Task 17)
-- =============================================================================

-- Extend organizations.status to include 'archived'
ALTER TABLE public.organizations
    DROP CONSTRAINT IF EXISTS organizations_status_check;

ALTER TABLE public.organizations
    ADD CONSTRAINT organizations_status_check
        CHECK (status IN ('active', 'inactive', 'suspended', 'archived'));

-- Extend profiles.status to include 'pending'
ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_status_check;

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_status_check
        CHECK (status IN ('active', 'inactive', 'suspended', 'pending'));
