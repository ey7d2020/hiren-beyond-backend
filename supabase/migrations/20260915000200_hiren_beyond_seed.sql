-- =============================================================================
-- Migration: 20260915000200_hiren_beyond_seed.sql
-- Description: Seed data for roles, permissions, role_permissions, and platform organization
-- Author: Hiren Beyond Engineering
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SEED ROLES
-- -----------------------------------------------------------------------------
INSERT INTO public.roles (key, name, description, is_system_role)
VALUES
    ('platform_admin', 'Platform Administrator', 'Full system administration across the entire Hiren Beyond ecosystem', true),
    ('platform_operations', 'Platform Operations', 'Operational monitoring, user support, and platform maintenance', true),
    ('recruiter_manager', 'Recruiter Manager', 'Recruitment team leadership, requisition approvals, and team management', true),
    ('recruiter', 'Recruiter', 'End-to-end recruitment lifecycle, candidate sourcing, screening, and placement', true),
    ('client_admin', 'Client Administrator', 'Client company lead managing organization settings, jobs, and reviewers', true),
    ('client_reviewer', 'Client Reviewer', 'Hiring manager evaluating candidate submissions and interview feedback', true),
    ('candidate', 'Candidate', 'Applicant accessing personal profile, submissions, assessments, and status', true)
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_system_role = EXCLUDED.is_system_role;

-- -----------------------------------------------------------------------------
-- 2. SEED PERMISSIONS
-- -----------------------------------------------------------------------------
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('platform.manage', 'Manage Platform', 'Full administrative authority over platform configurations and tenants', 'platform'),
    ('organizations.read', 'Read Organization', 'View organization profile, branding, and metadata', 'organizations'),
    ('organizations.manage', 'Manage Organization', 'Update organization profile, settings, and billing contact', 'organizations'),
    ('members.read', 'Read Members', 'View member roster and membership roles within the organization', 'members'),
    ('members.manage', 'Manage Members', 'Invite, modify roles, and remove organization members', 'members'),
    ('candidates.read', 'Read Candidates', 'Access candidate profiles, resumes, and qualifications', 'candidates'),
    ('candidates.manage', 'Manage Candidates', 'Create, update candidate profiles, workflows, and notes', 'candidates'),
    ('jobs.read', 'Read Jobs', 'View job postings, descriptions, and requisition status', 'jobs'),
    ('jobs.manage', 'Manage Jobs', 'Create, edit, publish, archive, and close job postings', 'jobs'),
    ('applications.read', 'Read Applications', 'View candidate job applications and progress stages', 'applications'),
    ('applications.manage', 'Manage Applications', 'Update application stages, evaluation scores, and status', 'applications'),
    ('analytics.read', 'Read Analytics', 'Access recruitment reports, pipeline metrics, and time-to-hire data', 'analytics'),
    ('audit_logs.read', 'Read Audit Logs', 'Inspect tenant-scoped security and compliance audit event logs', 'compliance')
ON CONFLICT (key) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;

-- -----------------------------------------------------------------------------
-- 3. SEED ROLE_PERMISSIONS
-- -----------------------------------------------------------------------------
-- Helper CTE to safely insert role-permission mappings by key
WITH mappings (role_key, perm_key) AS (
    VALUES
        -- Platform Admin: All Permissions
        ('platform_admin', 'platform.manage'),
        ('platform_admin', 'organizations.read'),
        ('platform_admin', 'organizations.manage'),
        ('platform_admin', 'members.read'),
        ('platform_admin', 'members.manage'),
        ('platform_admin', 'candidates.read'),
        ('platform_admin', 'candidates.manage'),
        ('platform_admin', 'jobs.read'),
        ('platform_admin', 'jobs.manage'),
        ('platform_admin', 'applications.read'),
        ('platform_admin', 'applications.manage'),
        ('platform_admin', 'analytics.read'),
        ('platform_admin', 'audit_logs.read'),

        -- Platform Operations
        ('platform_operations', 'organizations.read'),
        ('platform_operations', 'members.read'),
        ('platform_operations', 'candidates.read'),
        ('platform_operations', 'candidates.manage'),
        ('platform_operations', 'jobs.read'),
        ('platform_operations', 'applications.read'),
        ('platform_operations', 'analytics.read'),
        ('platform_operations', 'audit_logs.read'),

        -- Recruiter Manager
        ('recruiter_manager', 'organizations.read'),
        ('recruiter_manager', 'members.read'),
        ('recruiter_manager', 'members.manage'),
        ('recruiter_manager', 'candidates.read'),
        ('recruiter_manager', 'candidates.manage'),
        ('recruiter_manager', 'jobs.read'),
        ('recruiter_manager', 'jobs.manage'),
        ('recruiter_manager', 'applications.read'),
        ('recruiter_manager', 'applications.manage'),
        ('recruiter_manager', 'analytics.read'),
        ('recruiter_manager', 'audit_logs.read'),

        -- Recruiter
        ('recruiter', 'organizations.read'),
        ('recruiter', 'members.read'),
        ('recruiter', 'candidates.read'),
        ('recruiter', 'candidates.manage'),
        ('recruiter', 'jobs.read'),
        ('recruiter', 'jobs.manage'),
        ('recruiter', 'applications.read'),
        ('recruiter', 'applications.manage'),

        -- Client Admin
        ('client_admin', 'organizations.read'),
        ('client_admin', 'organizations.manage'),
        ('client_admin', 'members.read'),
        ('client_admin', 'members.manage'),
        ('client_admin', 'jobs.read'),
        ('client_admin', 'jobs.manage'),
        ('client_admin', 'applications.read'),
        ('client_admin', 'applications.manage'),
        ('client_admin', 'analytics.read'),

        -- Client Reviewer
        ('client_reviewer', 'organizations.read'),
        ('client_reviewer', 'members.read'),
        ('client_reviewer', 'jobs.read'),
        ('client_reviewer', 'applications.read'),

        -- Candidate
        ('candidate', 'jobs.read')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM mappings m
JOIN public.roles r ON r.key = m.role_key
JOIN public.permissions p ON p.key = m.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. SEED DEFAULT PLATFORM ORGANIZATION
-- -----------------------------------------------------------------------------
-- Creates default Hiren Beyond Platform organization without unsafe ownership assumptions
INSERT INTO public.organizations (name, slug, organization_type, status, created_by)
VALUES ('Hiren Beyond Platform', 'hiren-beyond', 'platform', 'active', NULL)
ON CONFLICT (slug) DO UPDATE
SET name = EXCLUDED.name,
    organization_type = EXCLUDED.organization_type,
    status = EXCLUDED.status;
