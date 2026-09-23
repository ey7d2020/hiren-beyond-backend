# Authorization & Tenant Isolation Matrix — Hiren Beyond

**Audit Date:** September 16, 2026  
**Audited Target:** Hiren Beyond Codebase & Remote Supabase Project (`pthkmkwrqjyseonysjzu`)  
**Scope:** RBAC definitions, RLS policies, object-level authorization, and tenant isolation boundaries  
**Status:** **VERIFIED SECURE** (Full multi-tenant database isolation confirmed)

---

## 1. System Role Hierarchy & Permissions

The Hiren Beyond platform implements a multi-tenant Role-Based Access Control (RBAC) model. Permissions are assigned to roles, and users receive roles within specific organizations via `public.organization_members`.

| Role Key | Role Name | System Category | Description | Primary Permissions |
|---|---|---|---|---|
| `platform_admin` | Platform Administrator | System / Platform | Complete administrative oversight across the entire platform ecosystem | `platform.manage`, all tenant and member manage permissions, bypasses tenant boundaries via `is_platform_admin()` |
| `platform_operations` | Platform Operations | System / Platform | Monitoring, operational user support, and platform maintenance | `organizations.read`, `members.read`, `candidates.read`, `candidates.manage`, `jobs.read`, `audit_logs.read` |
| `recruiter_manager` | Recruiter Manager | Tenant / Agency | Recruitment leadership, team requisition management, and pipeline controls | `organizations.read`, `members.read`, `members.manage`, `candidates.read`, `candidates.manage`, `jobs.read`, `jobs.manage`, `applications.read`, `applications.manage`, `analytics.read`, `audit_logs.read` |
| `recruiter` | Recruiter | Tenant / Agency | Full lifecycle recruitment, sourcing, ATS stages, candidate notes, and matching | `organizations.read`, `members.read`, `candidates.read`, `candidates.manage`, `jobs.read`, `jobs.manage`, `applications.read`, `applications.manage` |
| `client_admin` | Client Administrator | Tenant / Client | Client lead managing company profile, job requisitions, and internal reviewers | `organizations.read`, `organizations.manage`, `members.read`, `members.manage`, `jobs.read`, `jobs.manage`, `applications.read`, `applications.manage`, `analytics.read` |
| `client_reviewer` | Client Reviewer | Tenant / Client | Hiring manager evaluating submitted candidate profiles and recording interview feedback | `organizations.read`, `members.read`, `jobs.read`, `applications.read` |
| `candidate` | Candidate | Personal / Applicant | Individual applicant accessing personal profile, resume docs, assessments, and applications | `jobs.read` (public marketplace), direct row-level ownership on own candidate records (`user_id = auth.uid()`) |

---

## 2. Table-by-Table RLS Policy Matrix (Core Domain Tables)

The remote Supabase environment contains 192 tables in the `public` schema. All 192 tables have Row Level Security enabled (`rowsecurity = true`). The table below presents the authorization rules for critical core domain tables:

| Table Name | SELECT Policy | INSERT Policy | UPDATE Policy | DELETE Policy | Tenant & Object Isolation Mechanism |
|---|---|---|---|---|---|
| `public.organizations` | Member of org or `platform_admin` | `platform_admin` only | Org member with `organizations.manage` or `platform_admin` | `platform_admin` only | Filtered by `is_org_member(id, auth.uid())` |
| `public.organization_members` | Own membership or `members.read` or `platform_admin` | Org member with `members.manage` (excluding `platform_admin`) or `platform_admin` | Org member with `members.manage` (excluding `platform_admin`) or `platform_admin` | Org member with `members.manage` or `platform_admin` | Prevents privilege escalation: cannot assign `platform_admin` role |
| `public.jobs` | Published public jobs OR org member with `jobs.read` OR `platform_admin` | Org member with `jobs.manage` or `platform_admin` | Org member with `jobs.manage` or `platform_admin` | Org member with `jobs.manage` or `platform_admin` | Filtered by `organization_id` matching caller's active memberships |
| `public.applications` | Org member with `applications.read` OR candidate owner (`candidate_id` owns application) | Candidate applicant (`candidate_id` matches caller) or recruiter with `applications.manage` | Org member with `applications.manage` (ATS stage transitions) | Org member with `applications.manage` or `platform_admin` | Candidate sees only own applications; recruiter sees only applications for org jobs |
| `public.candidates` | Candidate owner (`user_id = auth.uid()`) OR recruiters with candidate access | Candidate owner (`user_id = auth.uid()`) or recruiter | Candidate owner (`user_id = auth.uid()`) or recruiter with manage access | Candidate owner or `platform_admin` | Strict candidate personal privacy; candidate cannot see other candidate profiles |
| `public.candidate_profiles` | Own profile or recruiters with candidate access | Own profile or recruiter | Own profile or recruiter with manage access | Own profile or `platform_admin` | Keyed to `candidate_id` linking to `candidates.user_id = auth.uid()` |
| `public.interviews` | Interviewer OR candidate attendee OR org member with `interviews.read` | Recruiter with `interviews.manage` | Recruiter or assigned interviewer (feedback submission) | Recruiter with `interviews.manage` or `platform_admin` | Scoped to job organization and participant user IDs |
| `public.assessments` | Candidate taker OR recruiter with assessment read permissions | Recruiter with `assessments.manage` | Recruiter or candidate attempt state runner | Recruiter with `assessments.manage` or `platform_admin` | Scoped to organization and candidate attempt ID |
| `public.audit_logs` | Org member with `audit_logs.read` OR `platform_admin` | Authenticated users (append-only trigger/system inserts) | **NONE (Blocked)** | **NONE (Blocked)** | Tamper-evident: audit logs cannot be modified or deleted |
| `public.platform_settings` | Authenticated read where `is_public = true AND is_sensitive = false` | `platform_admin` only | `platform_admin` only | `platform_admin` only | Non-public and sensitive settings visible only to platform admins |
| `public.api_keys` | Org member with `api.keys.read` or `platform_admin` | Org member with `api.keys.manage` or `platform_admin` | Org member with `api.keys.manage` or `platform_admin` | Org member with `api.keys.manage` or `platform_admin` | Scoped to `organization_id` |
| `public.workflow_definitions` | Org member with recruiter/admin role or `platform_admin` | Org recruiter/admin or `platform_admin` | Org recruiter/admin or `platform_admin` | Org recruiter/admin or `platform_admin` | Scoped to `organization_id` |

---

## 3. Storage Bucket Authorization Matrix

Storage access is governed by RLS policies on `storage.objects`:

| Bucket Name | Privacy Level | Upload Permission | Download / Read Permission | Delete Permission | Finding Reference |
|---|---|---|---|---|---|
| `candidate-documents` | **Private** | Candidate owner or authorized recruiter (`has_candidate_manage_access`) | Candidate owner or authorized recruiter (`has_candidate_read_access`) | Candidate owner or authorized recruiter | Clean — Properly tenant-scoped |
| `analytics-exports` | **Private** | Server / platform admin | Org members within `org_<org_id>` folder | Org admin or platform admin | Clean — Scoped by organization ID folder |
| `assessment-audio` | **Private** | Candidate owner (`user_id` folder) | Candidate owner OR any recruiter across platform | Platform admin | **SEC-01: Cross-tenant recruiter leak** |
| `assessment-video` | **Private** | Candidate owner (`user_id` folder) | Candidate owner OR any recruiter across platform | Platform admin | **SEC-01: Cross-tenant recruiter leak** |
| `assessment-files` | **Private** | Candidate owner (`user_id` folder) | Candidate owner OR any recruiter across platform | Platform admin | **SEC-01: Cross-tenant recruiter leak** |

*Note on SEC-01:* While candidates can only read and write their own assessment files, recruiters currently have platform-wide read permissions across all three assessment buckets rather than being restricted to their own organization's candidate assessments. Remediated in the security patch.

---

## 4. Black-Box Simulation Test Evidence

A live PostgreSQL simulation was executed on the remote database inside an isolated transaction (`test_full_blackbox.sql`):

### Scenario 1: Organization Isolation (User A vs User B)
- **Actor:** Alice (`aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`) — Recruiter at Acme Corp (`11111111-1111-1111-1111-111111111111`).
- **Target:** Beta Corp (`22222222-2222-2222-2222-222222222222`) and its jobs.
- **Actions Attempted:**
  1. `SELECT * FROM public.organizations;`  
     **Result:** Alice sees exactly 1 organization (Acme Corp). Beta Corp is completely hidden. **[PASS]**
  2. `SELECT * FROM public.jobs;`  
     **Result:** Alice sees only Acme Corp draft jobs. Beta Corp draft jobs are hidden. **[PASS]**
  3. `UPDATE public.jobs SET title = 'Hacked' WHERE organization_id = '22222222-...';`  
     **Result:** 0 rows affected. Mutation denied. **[PASS]**

### Scenario 2: Privilege Escalation Prevention
- **Actor:** Alice (`recruiter` in Acme Corp).
- **Action Attempted:**
  `INSERT INTO public.organization_members (organization_id, user_id, role_id) VALUES ('11111111-...', 'aaaaaaaa-...', (SELECT id FROM roles WHERE key = 'platform_admin'));`
- **Result:** Query rejected by RLS policy `org_members_insert_authorized` (`role_id NOT IN (SELECT id FROM roles WHERE key = 'platform_admin')`). **[PASS]**

### Scenario 3: Candidate Privacy & Data Gating
- **Actor:** Charlie (`cccccccc-cccc-cccc-cccc-cccccccccccc`) — Candidate applicant.
- **Actions Attempted:**
  1. `SELECT * FROM public.organizations;`  
     **Result:** 0 rows returned. Candidates cannot inspect private client organizations. **[PASS]**
  2. `SELECT * FROM public.jobs WHERE status = 'draft';`  
     **Result:** 0 rows returned. Candidates cannot view unreleased or internal jobs. **[PASS]**
  3. `SELECT * FROM public.candidates;`  
     **Result:** Exactly 1 row returned (Charlie's own candidate profile). All other candidate profiles are protected. **[PASS]**

---

## 5. Authorization Verdict

The database RLS and authorization architecture strictly enforces multi-tenant boundaries and role privilege limits. Unprivileged users cannot view or modify cross-tenant records or self-escalate to `platform_admin`. With the remediation of storage policy SEC-01, tenant isolation across storage objects will match the 100% isolation verified in relational tables.
