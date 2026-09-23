# Hiren Beyond Frontend Backend Integration Contract

Status: partial frontend readiness. Source of truth: repository snapshot at `E:\New Downloads\Backend Project`, Supabase migrations through `20260915002300_frontend_integration_contract.sql`, `supabase/config.toml`, existing backend task docs, and `docs/api/openapi-v1.yaml`.

Remote verification status: not completed in this environment because the Supabase CLI is not installed. Do not treat unverified capabilities as production-ready until `supabase migration list`, catalog queries, RLS checks, and storage policy checks are run against project `pthkmkwrqjyseonysjzu`.

## 1. Architecture Overview

The implemented backend is Supabase-first:

| Surface | Status | Frontend use |
|---|---:|---|
| Supabase Auth | Implemented in config | Browser login/session management with anon key only |
| Postgres tables/views/RLS | Implemented in migrations | Direct reads only where RLS allows and no RPC exists |
| Postgres RPCs | Implemented in migrations | Primary internal frontend integration surface |
| Supabase Storage | Implemented for candidate docs, assessment media, analytics exports | Direct browser upload/download only through RLS/signed URL rules |
| `/api/v1` public API | Specified as OpenAPI and database RPC layer | External developer/server integrations, not normal logged-in frontend |
| Edge Functions | Not present in repo | Requires future implementation if REST/HTTP runtime is required |
| Realtime | Supabase realtime enabled locally | Contract-level only unless publication membership is verified remotely |

Implementation labels used below:

| Label | Meaning |
|---|---|
| IMPLEMENTED + MIGRATED | Present in repository migrations or config |
| DOCUMENTATION ONLY | Contract exists but no concrete deployable runtime/object found |
| REQUIRES FUTURE IMPLEMENTATION | Needed by likely frontend screens but missing or incomplete |
| REQUIRES REMOTE VERIFICATION | Present locally but not verified against remote database |

## 2. Authentication

Frontend must initialize Supabase with only publishable values:

```ts
import { createClient } from '@supabase/supabase-js';
import type { Database } from '../types/database.types';

export const supabase = createClient<Database>(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);
```

Implemented auth configuration from `supabase/config.toml`:

| Method | Status | Notes |
|---|---:|---|
| Email/password | IMPLEMENTED + CONFIGURED | `auth.email.enable_signup = true`, minimum password length 6 |
| Email OTP / magic link | IMPLEMENTED + CONFIGURED | email OTP length 6, expiry 3600 seconds |
| Session restoration | IMPLEMENTED BY SUPABASE CLIENT | Use `getSession`, `onAuthStateChange` |
| Token refresh | IMPLEMENTED BY SUPABASE CLIENT | refresh token rotation enabled, JWT expiry 3600 seconds |
| Logout | IMPLEMENTED BY SUPABASE CLIENT | Call `supabase.auth.signOut()` and clear app-local org state |
| Password recovery | SUPABASE CAPABILITY, CONFIG DEPENDENT | Frontend may call `resetPasswordForEmail`; redirect allow-list must be set per env |
| Email verification | DISABLED LOCALLY | `enable_confirmations = false` |
| Anonymous auth | NOT IMPLEMENTED | `enable_anonymous_sign_ins = false` |
| Google OAuth | NOT IMPLEMENTED IN CONFIG | No `[auth.external.google]` enabled block found |
| Apple OAuth | NOT IMPLEMENTED IN CONFIG | `[auth.external.apple].enabled = false` |
| MFA/passkeys | NOT IMPLEMENTED IN CONFIG | TOTP/phone MFA disabled |

Post-login flow:

1. Restore or create Supabase session.
2. Call `get_my_profile()`.
3. Call `get_user_organizations()`.
4. If no active organization exists, route to an account/setup blocked state.
5. Let the user select an organization if multiple exist.
6. Store selected organization id only as UI state, for example `hb_active_org`; backend authorization must derive authority from `auth.uid()`, organization membership, RLS, or RPC checks.
7. Call `get_user_permissions(p_organization_id)` for UX gating.

Route behavior:

| Route type | Frontend behavior |
|---|---|
| Public | Does not require session; may call `get_frontend_config()` and public active jobs |
| Protected | Requires active Supabase session; redirect to login on missing/expired session |
| Organization protected | Requires active session and selected active organization |
| Role protected | Uses `get_user_permissions` for UI gating; backend remains authoritative |
| Forbidden | Show permission denied; do not retry unless role/org changed |
| Unauthorized | Clear stale session and route to login |

Account disabled/suspended behavior: profiles, organization memberships, and organizations have active/status fields. The frontend must treat empty `get_user_organizations()` or authorization errors as blocked access and show support/contact messaging. Auth itself does not enforce a suspended state in config.

## 3. Authorization And Tenant Model

Tenant scope is organization based. Most business tables include `organization_id`; candidates are also linked to user-owned candidate records and organization access through applications, shares, pools, or recruiter permissions.

Implemented role/permission tables: `roles`, `permissions`, `role_permissions`, `organization_members`. Seeded role names must be verified remotely before UI labels are frozen. Implemented helper RPCs:

| RPC | Purpose | Auth |
|---|---|---|
| `is_platform_admin(check_user_id)` | Platform admin check | authenticated/security definer |
| `is_org_member(check_org_id, check_user_id)` | Membership check | authenticated/security definer |
| `has_org_permission(check_org_id, perm_key, check_user_id)` | Permission check | authenticated/security definer |
| `get_user_permissions(p_organization_id)` | Frontend-safe permission list | authenticated |

Frontend capability mapping:

| Role/persona | Implemented authority source | Visible modules | Restricted actions |
|---|---|---|---|
| Platform admin | `is_platform_admin`, platform admin RPCs | Platform admin, audit, org/user search, support access, feature flags | Normal tenant UI still must respect scoped access |
| Organization owner/admin | Role permissions in `organization_members` | Organization settings, jobs, recruiters, analytics, integrations, API keys, workflows | Cannot bypass RLS or access other orgs |
| Recruiter / recruiter manager | Permission keys and recruiter RPCs | Dashboard, jobs, candidates, applications, ATS, assessments, interviews, talent pools | Admin/billing/API key actions unless permission grants exist |
| Candidate | candidate ownership helpers and candidate RLS | Public marketplace, applications, own candidate profile, own assessments/interviews | Other candidates, recruiter notes, client shares |
| Client | client portal helper RPCs and client relationship tables | Client jobs, shared candidates, feedback, interview requests | Full candidate private data unless share config allows |
| Support/admin access | `support_access_sessions` plus platform admin functions | Limited support views | Must be time-boxed and audited |

Frontend checks are UX only. Do not rely on hidden buttons for security. Never trust browser-supplied `organization_id`, `user_id`, role names, permissions, or AI-generated decisions.

## 4. Implemented Backend Inventory

Major implemented modules by migrations:

| Module | Tables/views | Frontend-relevant RPCs | Status |
|---|---|---|---|
| Foundation/identity | `profiles`, `organizations`, `roles`, `permissions`, `organization_members`, `audit_logs` | `get_my_profile`, `update_my_profile`, `get_user_organizations`, `get_user_permissions` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Candidate domain | `candidates`, `candidate_profiles`, `candidate_skills`, `candidate_languages`, `candidate_experience`, `candidate_education`, `candidate_certifications`, `candidate_documents`, `candidate_preferences` | `get_candidate_id_for_user`, `calculate_candidate_profile_completion` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Jobs/marketplace | `jobs`, `job_requirements`, `job_skills`, `job_languages`, `job_questions`, `public_active_jobs` | `get_active_jobs`, `submit_application`, `get_my_applications` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Applications/ATS | `applications`, `ats_stages`, `application_stage_history`, `application_notes`, `application_events` | `advance_application_stage`, `get_applications_cursor`, `get_pipeline_board` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Matching | `matching_profiles`, `matching_runs`, `match_dimension_results`, `match_explanations`, `match_overrides` | `calculate_candidate_job_match`, `rank_candidates_for_job`, `override_match_score` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| CV intelligence | `cv_processing_jobs`, `cv_extracted_content`, `candidate_cv_profiles`, `candidate_cv_ai_analysis`, `candidate_cv_review_items`, `candidate_intelligence_summary` | `queue_cv_processing`, `advance_cv_pipeline_stage`, `save_cv_extracted_text`, `save_cv_ai_analysis`, `get_cv_processing_status` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Recruiter command center | `recruiter_review_queue`, `bulk_screening_runs`, `candidate_shortlists`, `talent_pools`, `talent_pool_members` | `get_recruiter_dashboard_metrics`, `search_recruiter_candidates`, `shortlist_candidate`, `create_bulk_screening_run`, `get_talent_pool_candidates` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Assessments | assessment tables, readiness tables, `voice_assessment_results` | `trigger_required_assessments`, `start_assessment_attempt`, `submit_assessment_attempt`, `score_assessment_attempt`, `get_candidate_assessment_progress` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Interviews/hiring | interview, availability, feedback, hiring decision tables | `schedule_interview`, `reschedule_interview`, `cancel_interview`, `submit_interview_feedback`, `record_hiring_decision`, `get_recruiter_interview_dashboard` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Client portal | client relationship/share/feedback tables | `share_job_with_client`, `share_candidate_with_client`, `get_client_jobs`, `get_client_candidate`, `submit_client_feedback`, `request_client_interview` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Notifications | notification tables | `list_notifications`, `get_notification_badge_count`, `mark_notification_read`, `mark_all_notifications_read`, `update_notification_preference` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| AI assistants | `ai_assistants`, `ai_conversations`, `ai_messages`, `ai_tool_calls`, `ai_action_requests`, `ai_recommendations` | `start_ai_conversation`, `send_ai_message`, `dispatch_ai_tool_call`, `approve_ai_action_request`, `reject_ai_action_request` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Analytics | analytics metrics/report/export tables | `get_recruitment_funnel`, `get_organization_analytics`, `get_job_analytics`, `create_analytics_export_job` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Integrations | integration providers/connections/jobs/webhooks | `get_available_integrations`, `get_organization_integrations`, `start_oauth_session`, `complete_oauth_session`, `test_integration_connection`, `disconnect_integration` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Globalization/settings | countries, currencies, languages, locales, regional policies | `translate_key`, `get_effective_locale`, `convert_currency_amount` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Platform admin | feature flags, platform settings, support sessions, security events | platform dashboard/search/suspend/reactivate/support RPCs | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Search | search documents/history/config/embeddings | `search_candidates`, `search_jobs`, `search_applications`, `semantic_search_candidates`, `hybrid_search_candidates`, autocomplete RPCs | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Workflow engine | workflow definition/version/trigger/action/execution/failure tables | `validate_workflow_definition`, `publish_workflow_version`, `enqueue_workflow_event`, `approve_workflow_action`, `retry_workflow_step` | IMPLEMENTED + REQUIRES REMOTE VERIFICATION |
| Public API | API app/key/scope/rate/idempotency/webhook tables | `api_v1_get_jobs`, `api_v1_create_job`, `api_v1_get_candidates`, `api_v1_get_applications`, `api_v1_update_application_stage` | DATABASE RPC IMPLEMENTED; HTTP EDGE RUNTIME NOT FOUND |

No Supabase Edge Function directory exists in this repository snapshot.

## 5. API Response Contract

Internal frontend calls using `supabase.from()` and `supabase.rpc()` return native Supabase responses:

```ts
type SupabaseResult<T> = {
  data: T | null;
  error: PostgrestError | null;
  count?: number | null;
  status: number;
  statusText: string;
};
```

Do not wrap native Supabase calls in a fake `{ success, data, meta }` envelope unless the frontend app creates its own client-side adapter.

Public API/database API RPC responses use JSONB shapes or rowsets depending on function. The OpenAPI file documents REST shapes as `{ data, pagination, request_id }` for list success and `{ code, message, request_id }` for errors. That is the external API contract, not the internal Supabase RPC contract.

Task 23 frontend helper RPCs return rowsets:

| RPC | Response shape |
|---|---|
| `get_user_organizations()` | rows with organization id/name/slug/logo/subscription/role/is_active/joined_at |
| `get_user_permissions(org)` | rows with permission key/name/category/role |
| `get_my_profile()` | one profile row |
| `update_my_profile(...)` | `{ success, updated_at }` |
| `get_notification_badge_count()` | `{ unread_count, has_urgent }` |
| `get_frontend_config()` | public config rows |
| `list_notifications(limit,cursor,unread)` | notification rows with repeated `has_more` and `next_cursor` columns |
| `mark_notification_read(id)` | `{ success, notification_id }` |
| `mark_all_notifications_read()` | `{ success, updated_count }` |
| `get_organization_summary(org)` | org summary counts |
| `get_dashboard_metrics(org,days)` | metric rows |

Nullable values mean the backend has no value or the viewer is not allowed to see the field. Empty lists must be represented as `[]`, not `null`, in frontend state.

## 6. Error Contract

Implemented RPC errors are primarily PL/pgSQL `RAISE EXCEPTION` messages surfaced as `PostgrestError.message`. Current code uses message prefixes such as `ACCESS_DENIED`, `NOT_FOUND`, `ALREADY_EXISTS`, `VALIDATION_ERROR`, `BUSINESS_RULE_VIOLATION`, `QUOTA_EXCEEDED`, and `WORKFLOW_INVALID_TRANSITION`.

Frontend-normalized errors:

| Code | Status | Source status | Retry | Frontend behavior |
|---|---:|---|---|---|
| `AUTH_REQUIRED` | 401 | Contract-level normalized from missing session/`ACCESS_DENIED: Authentication required` | No | Redirect to login |
| `AUTH_INVALID` | 401 | Supabase/Auth/API key invalid | No | Clear session/key context |
| `FORBIDDEN` | 403 | Contract-level normalized from `ACCESS_DENIED`/permission errors | No | Show permission denied |
| `TENANT_ACCESS_DENIED` | 403 | Contract-level; many RPCs currently return `ACCESS_DENIED` | No | Switch org or deny |
| `RESOURCE_NOT_FOUND` | 404 | Implemented as `NOT_FOUND` messages | No | Show not-found state |
| `VALIDATION_ERROR` | 400 | Implemented | No | Show field errors when details exist |
| `CONFLICT` | 409 | Partially implemented; idempotency conflict implemented in API layer | Maybe | Refetch and retry consciously |
| `DUPLICATE_RESOURCE` | 409 | Implemented as `ALREADY_EXISTS` in several RPCs | No | Show duplicate message |
| `RATE_LIMITED` | 429 | Implemented for API/search rate limits | Yes after reset | Back off; show retry later |
| `FILE_TOO_LARGE` | 413 | Storage bucket limits implemented, code contract-level | No | Client-side validate size |
| `UNSUPPORTED_FILE_TYPE` | 415 | Storage bucket MIME rules implemented, code contract-level | No | Client-side validate type |
| `STORAGE_ACCESS_DENIED` | 403 | Storage policy failure, contract-level | No | Show denied/private file state |
| `PROCESSING_FAILED` | 422/500 | CV/workflow job statuses implemented, exact code contract-level | Maybe | Show retry if retry RPC exists |
| `AI_PROVIDER_ERROR` | 502 | AI provider/circuit breaker tables implemented, exact code contract-level | Yes | Retry later or fallback |
| `INTEGRATION_ERROR` | 502 | Integration jobs/events implemented, exact code contract-level | Maybe | Show connection health |
| `BILLING_REQUIRED` | 402 | Entitlement tables/status fields exist, no complete billing provider runtime found | No | Show upgrade prompt |
| `FEATURE_NOT_ENTITLED` | 403 | `check_feature_enabled` implemented | No | Hide/paywall feature |
| `INTERNAL_ERROR` | 500 | Catch-all | Maybe | Log request context, generic message |

Never display raw database/provider secrets or stack traces. Log `request_id` where the API provides it; internal Supabase RPCs do not consistently emit request ids.

## 7. CRUD And Access Patterns

Use RPCs for mutations when available. Direct table writes are allowed only when RLS/policies explicitly support the persona and no RPC is designated.

| Object | Create | Read/list | Update | Delete/archive | Status |
|---|---|---|---|---|---|
| Organizations | Platform/admin table/RPC paths only | `get_user_organizations`, `get_organization_summary` | direct/RPC per permissions | `archive_organization` | Implemented |
| Profiles | Auth trigger creates profile | `get_my_profile` | `update_my_profile` | platform user disable/suspend RPCs | Implemented |
| Candidates/profile/details | direct table with RLS or candidate domain RPCs | direct/RLS plus search/recruiter summaries | direct/RLS; guarded verified fields | archive/status fields, no universal restore RPC found | Partial contract |
| Documents | direct storage/table with RLS; no upload-session RPC found | `candidate_documents`, `get_cv_processing_status` | metadata via table/RLS | storage/table policies; delete contract incomplete | Partial |
| Jobs/requirements | job table/RPC/API paths | `get_active_jobs`, `search_jobs`, direct RLS | direct/RLS or job lifecycle RPCs | archive/status | Implemented |
| Applications | `submit_application` | `get_my_applications`, `get_applications_cursor`, `search_applications` | `advance_application_stage` | status transitions | Implemented |
| ATS stages | seeded/default table access | `get_pipeline_board` | direct/RLS likely | no dedicated archive RPC found | Partial |
| Assessments | assessment template/invitation tables and `trigger_required_assessments` | assessment dashboard/progress RPCs | attempt/score/review RPCs | no frontend delete contract | Implemented for core flow |
| Interviews | table creation plus `schedule_interview` | dashboards/candidate view | reschedule/cancel/feedback RPCs | cancel, not hard delete | Implemented |
| Client relationships/shares | share RPCs | client portal RPCs | feedback/interview/info/hiring RPCs | revoke RPCs | Implemented |
| Notifications | `emit_notification_event` backend/system | `list_notifications`, badge RPCs | mark read/preferences RPCs | no delete RPC found | Implemented |
| AI conversations | `start_ai_conversation` | conversation/message tables via RLS | `send_ai_message`, approval/reject RPCs | no delete RPC found | Implemented |
| Analytics | events/reports/export tables | analytics RPCs | export process RPCs | retention policies | Implemented |
| Subscriptions/billing | org subscription fields and feature flags | org summary, `check_feature_enabled` | no checkout/provider RPC found | suspend/reactivate org platform admin | Partial |
| Integrations | OAuth/session RPCs | `get_available_integrations`, `get_organization_integrations` | test/disconnect/sync RPCs | disconnect RPC | Implemented |
| Workflows | direct workflow tables plus publish RPC | workflow execution/history RPCs | pause/resume/approval/retry/cancel RPCs | no hard delete contract | Implemented core |
| API apps/keys/scopes | `create_api_application`, `create_api_key` | tables/RLS, usage analytics | rotate/revoke key | revoke key | Implemented |

## 8. Pagination, Filtering, Sorting

Standards for new frontend work:

| Collection | Existing style | Default | Max | Sort |
|---|---|---:|---:|---|
| Public jobs | page/size | 20 | verify | `newest`, relevance filters |
| Search candidates/jobs/applications | page/page_size | 20 | function-specific | `relevance`, `newest`, score fields |
| Applications cursor | encoded cursor | 20 | function-specific | created/status dependent |
| Notifications Task 23 | UUID cursor | 20 | 100 | `created_at DESC, id DESC`; note cursor condition uses `id < cursor`, so remote correctness must be tested |
| Client candidates | offset | 20 | function-specific | `match_score` default |
| Audit/platform search | offset | 20/50 | function-specific | newest |
| Public API | cursor | 20 | 50 in OpenAPI | endpoint default |

Prefer server-side filtering, sorting, and pagination. The frontend must not load entire production collections into memory.

Common filter behavior:

| Operator | Usage |
|---|---|
| exact | ids, statuses, enum-like fields |
| range | dates, salaries, scores, years |
| array contains/overlap | skills, languages, scopes |
| full-text/relevance | search document RPCs |
| semantic/hybrid | vector RPCs with backend-validated filters |

Null ordering is not standardized across all RPCs. If a screen depends on null ordering, document it in that screen implementation and add a backend test.

## 9. Storage And File Uploads

Implemented buckets:

| Bucket | Visibility | Limit/MIME | Intended files | Status |
|---|---:|---|---|---|
| `candidate-documents` | private | 20 MB; PDF, DOC, DOCX, JPEG, PNG | CVs and candidate documents | IMPLEMENTED |
| `assessment-audio` | private | bucket created, MIME/size policy not fully visible in summary | assessment audio | IMPLEMENTED |
| `assessment-video` | private | inferred from storage policies; bucket insert must be verified | assessment video | REQUIRES VERIFICATION |
| `assessment-files` | private | inferred from storage policies; bucket insert must be verified | assessment attachments | REQUIRES VERIFICATION |
| `analytics-exports` | private | 50 MB; CSV, JSON | analytics exports | IMPLEMENTED |

No `create_document_upload_session` or `confirm_document_upload` RPC exists in the local migrations. Frontend upload flow must therefore use Supabase Storage client under storage policies, or a future upload-session RPC/Edge Function must be added before documenting signed upload URLs as implemented.

Candidate document flow:

1. Validate MIME and size client-side.
2. Upload to `candidate-documents` using a path owned by the authenticated candidate/org access policy. Exact path convention must be confirmed from storage policies before frontend build.
3. Insert/update `candidate_documents` metadata if RLS allows the persona.
4. Call `queue_cv_processing(p_candidate_document_id)`.
5. Poll `get_cv_processing_status(p_candidate_document_id)` until terminal state.

Private file access: use Supabase signed URLs or authenticated storage downloads. Do not expose service role keys, public bucket URLs for private files, or raw provider storage credentials.

## 10. CV Processing Lifecycle

Implemented tables/RPCs support this lifecycle:

`UPLOAD -> candidate_documents -> queue_cv_processing -> cv_processing_jobs -> cv_extracted_content -> candidate_cv_profiles -> candidate_cv_ai_analysis -> candidate_cv_review_items -> READY/HUMAN REVIEW`

Frontend statuses must come from `get_cv_processing_status` and related job rows; do not assume instant extraction. Show:

| Backend phase | UI state |
|---|---|
| queued/created | Waiting to process |
| extracting | Extracting text |
| analyzing | Building profile/AI analysis |
| review_required | Needs human review |
| completed | Ready |
| failed | Failed with retry option if authorized |

Exact enum values require remote/catalog verification. `retry_failed_cv_job` exists for platform/admin recovery.

## 11. RPC Contract Summary

Use actual PostgreSQL signatures from migrations. Important frontend RPCs include:

| Area | RPCs |
|---|---|
| Identity | `get_user_organizations()`, `get_user_permissions(uuid)`, `get_my_profile()`, `update_my_profile(text,text,text,text,text)` |
| Jobs | `get_active_jobs(...)`, `submit_application(uuid,uuid,text,text,text,jsonb)`, `search_jobs(...)` |
| Applications | `get_applications_cursor(uuid,uuid,text,int,text)`, `advance_application_stage(uuid,uuid,text,text)`, `get_pipeline_board(uuid,uuid)` |
| Matching | `calculate_candidate_job_match(uuid,uuid,uuid,uuid,text)`, `rank_candidates_for_job(uuid,int,int,boolean,numeric,uuid)` |
| CV | `queue_cv_processing(uuid,text,text,text)`, `get_cv_processing_status(uuid)`, `advance_cv_pipeline_stage(...)` |
| Recruiter | `get_recruiter_dashboard_metrics(...)`, `search_recruiter_candidates(...)`, `shortlist_candidate(...)`, `bulk_*` RPCs |
| Assessments | `start_assessment_attempt(text)`, `submit_assessment_attempt(uuid,jsonb,int)`, `score_assessment_attempt(uuid)`, `get_recruiter_assessment_dashboard(...)` |
| Interviews | `schedule_interview(...)`, `reschedule_interview(...)`, `cancel_interview(uuid,text)`, `submit_interview_feedback(...)` |
| Client portal | `get_client_jobs(uuid)`, `get_client_job_candidates(...)`, `get_client_candidate(uuid)`, `submit_client_feedback(...)` |
| Notifications | `list_notifications(int,uuid,boolean)`, `mark_notification_read(uuid)`, `mark_all_notifications_read()`, `update_notification_preference(...)` |
| AI | `start_ai_conversation(...)`, `send_ai_message(...)`, `approve_ai_action_request(uuid,text)`, `reject_ai_action_request(uuid,text)` |
| Analytics | `get_recruitment_funnel(...)`, `get_organization_analytics(...)`, `get_job_analytics(...)`, `create_analytics_export_job(uuid,text)` |
| Integrations | `get_available_integrations()`, `get_organization_integrations(uuid)`, `start_oauth_session(...)`, `test_integration_connection(uuid)`, `disconnect_integration(uuid)` |
| Platform admin | `get_platform_dashboard()`, `search_platform_organizations(...)`, `search_platform_users(...)`, suspend/reactivate/archive RPCs |
| Search | `search_candidates(...)`, `hybrid_search_candidates(...)`, `semantic_search_candidates(...)`, autocomplete RPCs, `validate_ai_search_filters(jsonb)` |
| Workflow | `validate_workflow_definition(jsonb)`, `publish_workflow_version(uuid,jsonb)`, `pause_workflow(uuid)`, `resume_workflow(uuid)`, `get_workflow_execution(uuid)` |
| Public API admin | `create_api_application(...)`, `create_api_key(...)`, `rotate_api_key(...)`, `revoke_api_key(uuid)`, `get_api_usage_analytics(...)` |

Example invocation:

```ts
const { data, error } = await supabase.rpc('get_user_permissions', {
  p_organization_id: activeOrgId,
});
if (error) throw normalizeBackendError(error);
```

For full signatures, inspect the migration list or generated database types. Do not invent parameters in frontend code.

## 12. Public API Contract

Public API is for external integrations, not the logged-in SPA.

Implemented database RPC layer:

| Endpoint | Backing RPC | Scope |
|---|---|---|
| `GET /api/v1/jobs` | `api_v1_get_jobs` | `jobs.read` |
| `POST /api/v1/jobs` | `api_v1_create_job` | `jobs.write` |
| `GET /api/v1/candidates` | `api_v1_get_candidates` | `candidates.read` |
| `GET /api/v1/applications` | `api_v1_get_applications` | `applications.read` |
| `POST /api/v1/applications/{id}/stage` | `api_v1_update_application_stage` | `applications.write` |
| `POST /api/v1/webhooks/subscriptions` | `api_v1_subscribe_webhook` | `webhooks.manage` |

API keys use the format `hb_live_<prefix>_<secret>`. Raw keys are returned once and stored only as hashes/prefixes. Scopes and rate limits are enforced by database functions. Idempotency support exists for write paths.

No HTTP Edge Function implementation is present in this repo. If the production API is not implemented outside this repository, the REST API is DOCUMENTATION ONLY until an HTTP runtime maps requests to the RPCs.

## 13. Realtime And Events

Realtime is enabled in local config, but migrations in this snapshot do not prove publication membership for specific tables. Treat realtime subscriptions as contract-level until remote publication checks confirm them.

Recommended behavior:

| Module | Realtime if verified | Fallback |
|---|---|---|
| Notifications | `notifications` inserts/updates scoped to recipient/org | Poll `list_notifications` and badge every 30-60s or on focus |
| Applications/ATS | `applications`, `application_stage_history` | Refetch board after mutations; poll active pipeline |
| CV processing | `cv_processing_jobs` updates | Poll `get_cv_processing_status` every 3-5s while active |
| Interviews | `interviews`, `interview_participants` | Refetch schedule after mutation/focus |
| AI messages | `ai_messages`, `ai_tool_calls` | Poll conversation while pending |
| Workflow | `workflow_executions`, `workflow_execution_steps` | Poll execution detail |
| Billing/entitlement | none verified | Refresh org summary/feature flags after checkout/admin changes |

Subscriptions must include tenant/recipient filters and rely on RLS.

## 14. Concurrency And Optimistic UI

Use optimistic UI only for reversible, low-risk mutations:

| Operation | Optimistic? | Conflict behavior |
|---|---:|---|
| Mark notification read | Yes | Roll back on error |
| Candidate shortlist | Yes | Refetch candidate/job shortlist on conflict |
| ATS stage movement | Cautious | Refetch application and stage history before final toast |
| Interview scheduling | No | Use backend conflict check; show conflict from RPC |
| Job edits/publish | No for publish, cautious for draft fields | Compare `updated_at` before saving when editing forms |
| Client shares | No | Backend visibility/privacy is authoritative |
| Billing/subscription | No | Always refresh entitlement state |
| Workflow publish/run controls | No | Validate, publish, then refetch version/execution |

Where tables include `updated_at`, frontend edit forms should send or compare the original timestamp before saving. A standardized `CONFLICT` response is not consistently implemented across all RPCs, so screens that allow concurrent edits should refetch before overwrite.

## 15. Search

Implemented search RPCs:

| Search | RPC | Notes |
|---|---|---|
| Candidate keyword/filter | `search_candidates` | supports skills, languages, location, experience, completion, match score, job/pool filters |
| Job keyword/filter | `search_jobs` | supports category/location/workplace/employment/salary/status filters |
| Application search | `search_applications` | two overloads exist; verify generated types before use |
| Talent pool search | `search_talent_pool_candidates` | scoped by pool |
| Semantic candidate/job | `semantic_search_candidates`, `semantic_search_jobs` | requires vector embedding generated by backend/client service |
| Hybrid candidate | `hybrid_search_candidates` | combines FTS, semantic, matching, completion weights |
| Autocomplete | `autocomplete_skills`, `autocomplete_locations`, `autocomplete_jobs`, `autocomplete_candidates` | prefix based |
| AI filter validation | `validate_ai_search_filters` | AI output must be validated before use |

AI-generated filters are untrusted. Validate through `validate_ai_search_filters` and then pass only allowed fields/operators to search RPCs.

## 16. Workflow Engine

Frontend may configure workflows only through tables/RPCs that validate definitions. Do not permit arbitrary SQL, arbitrary code, arbitrary HTTP targets, or AI-generated executable actions.

Implemented functions include validation, publish, enqueue, route, execute action, approve/deny action, pause/resume, retry step, cancel execution, and failure listing. The action registry is documented separately in `docs/backend/workflow-action-registry.md`.

Frontend screens should show workflow version, status, trigger, conditions, actions, approval steps, schedules, execution history, failed steps, and retry controls only for authorized users.

## 17. Billing And Entitlements

Implemented primitives:

| Object/RPC | Use |
|---|---|
| `organizations.subscription_plan`, `subscription_status`, `trial_ends_at` | Plan/status display |
| `feature_flags`, `organization_feature_overrides` | Feature gates |
| `check_feature_enabled(feature, org, user)` | Authoritative entitlement check |
| `get_organization_summary` | Lightweight subscription fields |
| platform suspend/reactivate RPCs | Administrative state changes |

No Stripe/checkout/customer portal runtime or Edge Function is present in this repo. Subscription upgrade/downgrade UI is therefore REQUIRES FUTURE IMPLEMENTATION unless handled by an external service not included here.

## 18. Notifications

Use:

| Need | Contract |
|---|---|
| List | `list_notifications(p_limit, p_cursor, p_unread_only)` |
| Badge | `get_notification_badge_count()` |
| Mark one read | `mark_notification_read(p_notification_id)` |
| Mark all read | `mark_all_notifications_read()` |
| Preferences | `update_notification_preference(...)` |
| Quiet hours | `notification_preferences`, `is_in_quiet_hours(...)` |
| Delivery events | `notification_events`, `notification_deliveries`, `notification_delivery_attempts` |

Delivery is asynchronous/event-driven through notification event and delivery tables. Provider sending is represented by RPCs such as `process_notification_event` and `record_delivery_attempt`; a running worker is not present in this repo snapshot.

## 19. AI Integration

AI assistant frontend contract:

| Capability | Status | Contract |
|---|---|---|
| Start conversation | Implemented | `start_ai_conversation` |
| Send message | Implemented | `send_ai_message` inserts message records |
| Streaming | Not found | Use polling/realtime if publication verified |
| Tool calls | Implemented | `dispatch_ai_tool_call`, `ai_tool_calls` |
| Approval requests | Implemented | `ai_action_requests`, approve/reject RPCs |
| Recommendations | Implemented | `create_ai_recommendation`, `ai_recommendations` |
| Usage/rate/cost | Implemented tables/RPC | `record_ai_usage`, circuit breaker primitives |

AI output is advisory. The frontend must never treat AI output as authorization, final hiring decision, or permission grant. High-risk actions require explicit human confirmation and backend authorization.

## 20. Environment Variables

Safe browser variables:

```bash
VITE_SUPABASE_URL=https://pthkmkwrqjyseonysjzu.supabase.co
VITE_SUPABASE_ANON_KEY=...
VITE_API_BASE_URL=https://api.example.com/api/v1
VITE_APP_URL=https://app.example.com
```

Never include these in frontend builds:

```bash
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_DB_PASSWORD
DATABASE_URL
JWT_SECRET
WEBHOOK_SECRET
STRIPE_SECRET_KEY
OPENAI_API_KEY
*_CLIENT_SECRET
*_PRIVATE_KEY
HIREN_BEYOND_API_KEY
```

Use separate `.env.local`, staging, and production values. Do not hardcode production URLs or secrets.

## 21. Security Rules For Frontend Developers

Never:

| Rule |
|---|
| Expose service-role keys or database credentials |
| Bypass RLS |
| Trust frontend role checks |
| Trust client-provided `organization_id` or `user_id` for authorization |
| Directly expose private storage as public URLs |
| Execute arbitrary SQL |
| Embed provider secrets or webhook signing secrets |
| Store long-lived privileged tokens in the browser |
| Trust AI-generated authorization or hiring decisions |
| Trust browser-generated permissions |

Always rely on Supabase Auth identity, RLS, SECURITY DEFINER RPC validation, scoped storage policies, and server-side/public API scope checks.

## 22. Example Integration Flows

### Candidate Registration

Status: partially implemented. Flow: Supabase sign-up/login -> `profiles` trigger -> candidate creates/updates `candidates` and `candidate_profiles` under RLS -> `calculate_candidate_profile_completion` -> onboarding complete. Exact candidate creation RPC is not present; use direct table access only after RLS verification.

### Candidate CV Upload

Status: implemented primitives, missing upload-session wrapper. Flow: authenticated candidate uploads to `candidate-documents` -> writes `candidate_documents` metadata -> `queue_cv_processing(document_id)` -> poll `get_cv_processing_status` -> extracted content/profile/AI analysis -> human review if review items exist -> ready.

### Recruiter Creates Job

Status: implemented primitives. Flow: authorized recruiter/admin creates job and requirements/skills/languages/questions -> publish via job status/lifecycle path -> public marketplace reads through `public_active_jobs`, `get_active_jobs`, or `search_jobs`.

### Recruiter Searches Candidates

Status: implemented. Flow: `search_candidates` or `hybrid_search_candidates` -> optional `rank_candidates_for_job` -> recruiter summary/detail tables/RPCs -> `shortlist_candidate` or application action.

### Application Pipeline

Status: implemented. Flow: candidate `submit_application` -> recruiter views `get_applications_cursor`/`get_pipeline_board` -> `advance_application_stage` -> assessments/interviews -> `record_hiring_decision`.

### Client Review

Status: implemented. Flow: recruiter `share_candidate_with_client` -> client `get_client_jobs`/`get_client_candidate` -> `submit_client_feedback` or `request_client_interview` -> `submit_client_hiring_decision`.

### Subscription Upgrade

Status: not implemented in this repo. Org subscription fields and entitlements exist, but checkout/provider flow requires future implementation.

## 23. Implemented Vs Specified Matrix

| Area | Implemented | Specified | Not implemented / gap |
|---|---:|---:|---|
| Auth email/password/OTP/session | Yes | Yes | OAuth disabled locally |
| Role/permission RPCs | Yes | Yes | Seeded role labels require remote verification |
| Core tables/RLS | Yes in migrations | Yes | Remote RLS verification pending |
| Frontend helper RPCs | Yes in Task 23 migration | Yes | Remote deployment pending |
| Storage buckets | Yes for main buckets | Yes | Signed upload-session RPC missing |
| CV processing records | Yes | Yes | Worker/runtime not present |
| Jobs/applications/ATS | Yes | Yes | Some CRUD paths rely on direct RLS |
| Search | Yes | Yes | Embedding generation runtime not present |
| Workflow engine | Yes | Yes | UI-safe authoring needs careful validation |
| Notifications | Yes | Yes | Worker/provider runtime not present |
| AI assistant | Yes | Yes | Streaming not implemented |
| Billing | Partial | Partial | Checkout/customer portal missing |
| Public API | DB RPC + OpenAPI | Yes | HTTP Edge/runtime not present |
| Realtime | Config enabled | Contract only | Publication verification missing |

## 24. Remote Verification Checklist

Before frontend implementation freeze, run against remote Supabase:

```sql
select * from supabase_migrations.schema_migrations order by version;
select table_schema, table_name from information_schema.tables where table_schema='public';
select n.nspname, p.proname, pg_get_function_arguments(p.oid), pg_get_function_result(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
order by p.proname;
select schemaname, tablename, rowsecurity from pg_tables where schemaname='public';
select * from storage.buckets;
select * from pg_publication_tables where pubname='supabase_realtime';
```

Also run SQL test files in `docs/backend`, especially `test-frontend-integration.sql`, `test-public-api.sql`, RLS/security tests, and module-specific tests.

