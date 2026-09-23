# Hiren Beyond — Roles & Permissions Matrix (RBAC)

## Overview

Hiren Beyond implements a decoupled Role-Based Access Control (RBAC) model. Permissions represent granular capabilities that are tied to roles, and roles are assigned to users on an organization-by-organization basis via `organization_members`.

Platform administrators hold global authority, while agency and client roles operate strictly within the bounds of their associated organization.

---

## System Roles Catalog

| Role Key | Role Name | System Role | Primary Scope |
|---|---|---|---|
| `platform_admin` | Platform Administrator | Yes | Full system management across all organizations, tenants, settings, and users. |
| `platform_operations` | Platform Operations | Yes | Platform support, user troubleshooting, operational monitoring, and metrics. |
| `recruiter_manager` | Recruiter Manager | Yes | Manages recruitment teams, job requisitions, candidate workflows, and reporting. |
| `recruiter` | Recruiter | Yes | Sourcing, managing candidates, viewing applications, and coordinating interviews. |
| `client_admin` | Client Administrator | Yes | Manages client company settings, job requests, team members, and reviewer access. |
| `client_reviewer` | Client Reviewer | Yes | Hiring manager evaluating candidates submitted to their assigned jobs. |
| `candidate` | Candidate | Yes | Job seeker managing personal profile, resume assets, applications, and offers. |

---

## Permissions Catalog

| Permission Key | Category | Name | Description |
|---|---|---|---|
| `platform.manage` | `platform` | Manage Platform | Administrative authority over global configs and multi-tenant structures. |
| `organizations.read` | `organizations` | Read Organization | View organization profile, settings, and branding. |
| `organizations.manage` | `organizations` | Manage Organization | Update organization settings, contact info, and branding. |
| `members.read` | `members` | Read Members | View the member roster and role assignments within the organization. |
| `members.manage` | `members` | Manage Members | Invite, modify membership roles, or remove members from the organization. |
| `candidates.read` | `candidates` | Read Candidates | Access candidate profiles, documents, and qualifications. |
| `candidates.manage` | `candidates` | Manage Candidates | Create, edit, and organize candidate profiles and screening workflows. |
| `jobs.read` | `jobs` | Read Jobs | View job requisitions and public/internal listings. |
| `jobs.manage` | `jobs` | Manage Jobs | Create, publish, update, and close job postings. |
| `applications.read` | `applications` | Read Applications | View candidate submissions and evaluation stages. |
| `applications.manage` | `applications` | Manage Applications | Advance applicants through pipeline stages and update decision notes. |
| `analytics.read` | `analytics` | Read Analytics | Access hiring velocity, funnel metrics, and performance analytics. |
| `audit_logs.read` | `compliance` | Read Audit Logs | View security and compliance audit logs for the organization. |

---

## Role-to-Permission Matrix

| Permission | `platform_admin` | `platform_operations` | `recruiter_manager` | `recruiter` | `client_admin` | `client_reviewer` | `candidate` |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| `platform.manage` | :white_check_mark: | :x: | :x: | :x: | :x: | :x: | :x: |
| `organizations.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: |
| `organizations.manage` | :white_check_mark: | :x: | :x: | :x: | :white_check_mark: | :x: | :x: |
| `members.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: |
| `members.manage` | :white_check_mark: | :x: | :white_check_mark: | :x: | :white_check_mark: | :x: | :x: |
| `candidates.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: | :x: | :x: |
| `candidates.manage` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: | :x: | :x: |
| `jobs.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| `jobs.manage` | :white_check_mark: | :x: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: | :x: |
| `applications.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: |
| `applications.manage` | :white_check_mark: | :x: | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: | :x: |
| `analytics.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: | :white_check_mark: | :x: | :x: |
| `audit_logs.read` | :white_check_mark: | :white_check_mark: | :white_check_mark: | :x: | :x: | :x: | :x: |
| **Total Grants** | **13** | **8** | **11** | **8** | **9** | **4** | **1** |

---

## Privilege Escalation Defense

1. **Platform Admin Protection**:
   - In `organization_members` RLS policies, users with `members.manage` cannot assign or escalate any user into the `platform_admin` role. Only an existing `platform_admin` can grant platform admin privileges.
2. **Strict Candidate Isolation**:
   - Candidates interact through user-centric policies on their own profiles and future application records (`user_id = auth.uid()`), preventing unauthorized exposure of internal recruiter notes or client deliberations.
3. **Database Authorization**:
   - Frontend role claims are never trusted for authorization. The database helper `public.has_org_permission(...)` validates active membership and role mappings on every request.
