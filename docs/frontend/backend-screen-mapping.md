# Backend Screen Mapping

This document maps future frontend screens to the implemented backend surface. Status values: GREEN = implemented in migrations and documented, YELLOW = backend primitives exist but frontend contract or runtime verification is incomplete, RED = missing backend/runtime support in this repo.

Remote verification is still required because the Supabase CLI is unavailable in this environment.

| Screen/module | Purpose | Roles | Required data | Reads | Writes/actions | Storage | Realtime/polling | UI states | Status |
|---|---|---|---|---|---|---|---|---|---|
| Login/register | Supabase Auth entry | public | auth config | Supabase Auth | sign in/up, OTP, reset | none | auth listener | loading, auth error | GREEN |
| Org selector | choose active tenant | authenticated | memberships, roles | `get_user_organizations` | local active org only | none | refetch on login | empty no-org, forbidden | GREEN |
| App shell/nav | permissions and badges | org users | profile, permissions, unread count | `get_my_profile`, `get_user_permissions`, `get_notification_badge_count` | logout | avatar path if used | poll badge or realtime if verified | loading, denied | GREEN |
| Onboarding | create candidate/org setup | candidate/admin | profile/candidate/org | profile/candidate tables/RLS | direct table writes where RLS allows | optional avatar/docs | refetch after save | validation, incomplete | YELLOW |
| Organization management | org settings/team | owner/admin | org, members, roles | `organizations`, `organization_members`, permissions | direct/RPC per permissions | logo not fully defined | poll/refetch | empty team, denied | YELLOW |
| Recruiter dashboard | KPI landing | recruiters/admins | org summary, dashboard metrics | `get_organization_summary`, `get_dashboard_metrics`, analytics RPCs | none | none | refresh on focus | loading, empty metrics | GREEN |
| Jobs list | manage jobs | recruiters/admins | jobs, filters | `search_jobs`, direct `jobs`, `get_active_jobs` | status changes where authorized | none | refetch after mutation | empty jobs, denied | GREEN |
| Job create/edit | job requisition authoring | recruiters/admins | job, requirements, skills, questions | job tables | direct/RLS or API/RPC paths; verify before UI | none | no realtime | validation, conflict | YELLOW |
| Marketplace | public active jobs | public/candidate | active jobs | `public_active_jobs`, `get_active_jobs`, `search_jobs` | `submit_application` for candidates | resume doc id optional | no realtime | empty search, auth required to apply | GREEN |
| Candidates list | recruiter candidate discovery | recruiters/admins | candidate summaries | `search_candidates`, `search_recruiter_candidates` | shortlist/pool add | none | no realtime | empty filters, denied | GREEN |
| Candidate profile | candidate detail | candidate/recruiter/client scoped | profile, skills, docs, CV analysis | candidate tables, `candidate_intelligence_summary`, client RPCs | edit own/profile notes where authorized | candidate docs | poll CV while processing | private field hidden, denied | YELLOW |
| CV/document management | upload and process docs | candidates/recruiters scoped | docs, processing status | `candidate_documents`, `get_cv_processing_status` | storage upload, metadata insert, `queue_cv_processing` | `candidate-documents` | poll 3-5s; realtime if verified | upload progress, failed, review | YELLOW |
| Applications | candidate/recruiter applications | candidate/recruiter | applications | `get_my_applications`, `get_applications_cursor`, `search_applications` | `submit_application`, status/stage RPCs | resume docs | poll/refetch | duplicate/conflict/empty | GREEN |
| ATS pipeline board | move candidates through stages | recruiters/managers | stages, applications | `get_pipeline_board` | `advance_application_stage`, bulk move/reject | none | realtime if verified; refetch on move | optimistic rollback, denied | GREEN |
| Recruiter command center | review queue and bulk work | recruiters/managers | review queue, bulk runs, shortlists | dashboard/search/pool RPCs | shortlist, bulk screen/move/reject | none | poll bulk run | empty queue, processing | GREEN |
| Talent pools | curated candidate pools | recruiters | pools/members/rules | `get_talent_pool_candidates`, search pool RPC | add/evaluate pool RPCs | none | refetch | empty pool, validation | GREEN |
| Assessments | templates/invitations/attempts/results | candidates/recruiters | assessment templates, attempts, readiness | `get_candidate_assessment_progress`, `get_recruiter_assessment_dashboard` | start/submit/score/review RPCs | assessment audio/video/files | poll attempt/results | in progress, expired, submitted | GREEN |
| Interviews | scheduling and feedback | candidate/recruiter/client scoped | interviews, availability, feedback | `get_recruiter_interview_dashboard`, `get_candidate_interview_view`, feedback RPC | schedule/reschedule/cancel/feedback | attachments not fully defined | poll/refetch | conflict, cancelled, denied | GREEN |
| Client portal | client review of shared jobs/candidates | client | client jobs, shares, sanitized profiles | `get_client_jobs`, `get_client_job_candidates`, `get_client_candidate` | feedback, interview/info/hiring requests | client doc access | refetch | expired share, no access | GREEN |
| Notifications center | in-app notifications/preferences | authenticated | notifications, prefs | `list_notifications`, badge RPCs | mark read/all, update prefs | none | poll or realtime if verified | empty, unread-only empty | GREEN |
| AI assistants | copilot conversations/actions | authorized users | assistants, conversations, messages | AI tables/RLS, conversation records | start/send/approve/reject RPCs | none | poll/realtime; no streaming found | pending tool, approval required | YELLOW |
| Analytics | funnel/time/source dashboards | recruiters/admins | analytics metrics/reports | analytics RPCs | create export job | `analytics-exports` | poll export job | empty range, export processing | GREEN |
| Billing/subscription | plan and entitlements | owner/admin | org subscription fields, feature flags | `get_organization_summary`, `check_feature_enabled` | no checkout runtime found | none | refresh after external change | upgrade required | RED |
| Integrations | provider connections | admins | providers/connections/health | `get_available_integrations`, `get_organization_integrations` | OAuth/test/disconnect RPCs | none | poll job/health | disconnected, provider error | GREEN |
| Globalization/settings | locale, currency, regional settings | all/admin | locales/currencies/translations | `translate_key`, `get_effective_locale`, reference tables | locale preference writes | none | no realtime | fallback locale | GREEN |
| Platform admin | system management | platform admin | org/user/audit/health | platform search/dashboard/health RPCs | suspend/reactivate/archive/support/session/settings RPCs | none | refetch | denied, audit empty | GREEN |
| Advanced search | unified discovery | recruiters/admins | search docs, filters | search/autocomplete/semantic/hybrid RPCs | save search/alerts direct tables | none | no realtime | no results, rate limited | GREEN |
| Workflow engine | workflow authoring/execution | admins/managers | definitions, versions, execution history | workflow tables, `get_workflow_execution`, `get_failed_workflows` | validate/publish/pause/resume/approve/retry/cancel RPCs | none | poll executions | invalid config, failed step | GREEN |
| Public API developer portal | API apps/keys/docs/webhooks | org admins/developers | apps, keys, scopes, usage, docs | API tables/RLS, usage analytics RPC | create app/key, rotate/revoke, webhook subscribe | none | no realtime | key shown once, scope denied | YELLOW |

## Coverage Audit Matrix

| Screen/module | Contract exists | Read ops | Write ops | Authz | Storage | Errors | Loading/empty | Realtime/polling | Env |
|---|---|---|---|---|---|---|---|---|---|
| Authentication | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Onboarding | YELLOW | YELLOW | YELLOW | YELLOW | YELLOW | YELLOW | GREEN | GREEN | GREEN |
| Organization management | YELLOW | GREEN | YELLOW | GREEN | YELLOW | YELLOW | GREEN | GREEN | GREEN |
| Recruiter dashboard | GREEN | GREEN | N/A | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Jobs | GREEN | GREEN | YELLOW | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Marketplace | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Candidates | GREEN | GREEN | YELLOW | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Candidate profile | YELLOW | GREEN | YELLOW | GREEN | YELLOW | GREEN | GREEN | GREEN | GREEN |
| CV/documents | YELLOW | GREEN | YELLOW | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN |
| Applications/ATS | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Assessments | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN |
| Interviews | GREEN | GREEN | GREEN | GREEN | YELLOW | GREEN | GREEN | GREEN | GREEN |
| Client portal | GREEN | GREEN | GREEN | GREEN | YELLOW | GREEN | GREEN | GREEN | GREEN |
| Notifications | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| AI assistants | YELLOW | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | YELLOW | GREEN |
| Analytics | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN | GREEN |
| Billing/subscription | RED | YELLOW | RED | YELLOW | N/A | YELLOW | GREEN | GREEN | GREEN |
| Integrations | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Globalization/settings | GREEN | GREEN | YELLOW | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Platform admin | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Advanced search | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Workflow engine | GREEN | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |
| Public API/developer portal | YELLOW | GREEN | GREEN | GREEN | N/A | GREEN | GREEN | GREEN | GREEN |

