# Hiren Beyond Database Architecture

This directory is the canonical, human-readable architecture view for the Hiren Beyond Supabase/PostgreSQL database.

The production schema remains in the `public` schema. This documentation deliberately avoids physical schema moves because Supabase Studio's native schema visualizer should not drive production database structure. Use these diagrams as the organized ERD and module map.

## Audit Source

Local repository audit, based on migrations through `20260915002301_fix_frontend_config.sql`:

| Item | Local migration inventory |
|---|---:|
| Public tables | 192 |
| Public views | 2 |
| Unique public function names | 236 |
| Storage bucket inserts found | 3 |
| Supabase Edge Function directory | Not present |
| Remote verification | Not completed here; Supabase CLI is not installed |

Remote verification still needs to be run against the real Supabase project before this is used as an operational certification.

## Domain Map

| # | Domain | ERD |
|---|---|---|
| 01 | Identity & Organizations | [01_identity.md](./erd/01_identity.md) |
| 02 | Candidates | [02_candidates.md](./erd/02_candidates.md) |
| 03 | Jobs | [03_jobs.md](./erd/03_jobs.md) |
| 04 | Applications / ATS | [04_applications.md](./erd/04_applications.md) |
| 05 | CV Intelligence | [05_cv_ai.md](./erd/05_cv_ai.md) |
| 06 | Matching | [06_matching.md](./erd/06_matching.md) |
| 07 | Recruiter Operations | [07_recruiter.md](./erd/07_recruiter.md) |
| 08 | Assessments | [08_assessments.md](./erd/08_assessments.md) |
| 09 | Interviews & Hiring | [09_interviews.md](./erd/09_interviews.md) |
| 10 | Clients | [10_clients.md](./erd/10_clients.md) |
| 11 | Notifications | [11_notifications.md](./erd/11_notifications.md) |
| 12 | AI Assistants | [12_ai.md](./erd/12_ai.md) |
| 13 | Analytics | [13_analytics.md](./erd/13_analytics.md) |
| 14 | Billing | [14_billing.md](./erd/14_billing.md) |
| 15 | Integrations | [15_integrations.md](./erd/15_integrations.md) |
| 16 | Globalization | [16_globalization.md](./erd/16_globalization.md) |
| 17 | Platform Admin | [17_admin.md](./erd/17_admin.md) |
| 18 | Search | [18_search.md](./erd/18_search.md) |
| 19 | Workflows | [19_workflows.md](./erd/19_workflows.md) |
| 20 | Public API | [20_public_api.md](./erd/20_public_api.md) |
| 21 | Security | [21_security.md](./erd/21_security.md) |

## Primary Diagrams

- [Master ERD](./master-erd.md): high-level domain and entity relationships only.
- [Cross-module relationships](./cross-module-relationships.md): important architectural dependencies, not every foreign key.
- [Naming audit](./naming-audit.md): naming consistency observations without production renames.

## Shared / Core Tables

These tables are shared dependencies and are defined once in Identity, Globalization, Platform Admin, or Security diagrams:

| Table family | Owner domain | Referenced by |
|---|---|---|
| `profiles`, `organizations`, `organization_members` | Identity | Nearly all org-scoped modules |
| `roles`, `permissions`, `role_permissions` | Identity/Security | Admin, API, workflow, org access |
| `audit_logs` | Security | Platform-wide auditing |
| `countries`, `currencies`, `languages`, `timezones` | Globalization | Jobs, candidates, notifications, analytics |
| `feature_flags`, `organization_feature_overrides` | Billing/Admin | Entitlements and gated features |
| `provider_circuit_breakers`, retention tables | Security | Operations and production hardening |

## Security / RLS Overview

The migrations enable RLS on public tables and define policies per module. The organizing principle is:

- Organization scope is authoritative for tenant isolation.
- Candidate data is visible only to the candidate, authorized recruiters, or explicitly shared clients.
- Client portal access is mediated by client relationship and share tables.
- Platform admin access goes through explicit platform admin checks and audited support sessions.
- Frontend role checks are UX only; RLS and RPC authorization remain authoritative.

## Storage Overview

Storage bucket inserts found in migrations:

| Bucket | Purpose | Visibility |
|---|---|---|
| `candidate-documents` | CVs and candidate documents | Private |
| `assessment-audio` | Assessment audio uploads | Private |
| `analytics-exports` | CSV/JSON analytics exports | Private |

Some existing docs mention assessment video/files buckets; those must be verified remotely before being treated as deployed.

## RPC / Function Overview

The database exposes many SECURITY DEFINER RPCs for frontend and backend operations. Important groups:

- Identity helpers: `get_user_organizations`, `get_user_permissions`, `get_my_profile`.
- Jobs/applications: `get_active_jobs`, `submit_application`, `advance_application_stage`, `get_pipeline_board`.
- CV intelligence: `queue_cv_processing`, `get_cv_processing_status`, `save_cv_extracted_text`, `save_cv_ai_analysis`.
- Matching/search: `calculate_candidate_job_match`, `rank_candidates_for_job`, `search_candidates`, `hybrid_search_candidates`.
- Assessments/interviews: `start_assessment_attempt`, `submit_assessment_attempt`, `schedule_interview`, `submit_interview_feedback`.
- Notifications/AI/workflows/API: documented in their module ERDs.

## Supabase Visualizer Constraint

Supabase Studio's built-in schema visualizer should be treated as an inspection tool, not the canonical architecture presentation. If Studio cannot persist manual layout/grouping, do not alter production schemas or table names just to improve the Studio ERD.

