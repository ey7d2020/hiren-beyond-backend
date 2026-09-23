# Acceptance Test Results

Status: static/repository acceptance only. Live remote tests were not executed because the Supabase CLI is not installed in this environment.

## Critical End-To-End Scenarios

| Scenario | Status | Evidence | Blocker / follow-up |
|---|---|---|---|
| 1. New User | PARTIAL | Supabase Auth config, `handle_new_user`, `profiles`, `organization_members`, roles/permissions, `get_my_profile`, `get_user_organizations` exist in migrations | Live signup/session/profile/member flow not executed |
| 2. Multi-Tenant Isolation | PARTIAL | RLS policies and org-scoped helper functions present in migrations | Must execute cross-org direct query/RPC/API/storage/search tests remotely |
| 3. Candidate Lifecycle | PARTIAL | Candidate tables, candidate document table, CV processing RPCs, matching/application RPCs exist | Live create/upload/process/match/apply flow not executed; CV worker/runtime not verified |
| 4. Recruiter Lifecycle | PARTIAL | Jobs, requirements, search, matching, shortlists, assessment, interview, hiring RPCs/tables present | Live recruiter role/permission flow not executed |
| 5. Client Lifecycle | PARTIAL | Client relationship, access, share, feedback, interview request, hiring decision tables/RPCs present | Live strict visibility test not executed |
| 6. Billing | FAIL | Subscription fields and feature flags/overrides exist | No checkout/customer portal/provider subscription flow found in repo |
| 7. Files | PARTIAL | Private storage bucket inserts and storage policies exist in migrations | Live authorized/unauthorized storage retrieval test not executed |
| 8. AI Safety | PARTIAL | AI conversations/tool calls/action approvals and workflow action validation exist | Live AI provider/tool execution and unauthorized context tests not executed |

## Client Acceptance Capabilities

| Capability | Status | Notes |
|---|---|---|
| Connect a frontend | PASS | Frontend contract and Supabase client config documented |
| Configure env vars | PASS | `.env.example`, frontend contract, and handover docs describe variables |
| Authenticate users | PARTIAL | Config/RPCs exist; live auth not tested |
| Create organizations | PARTIAL | Tables/RLS exist; no live scenario executed |
| Assign roles | PARTIAL | Roles/permissions/memberships exist; live scenario not executed |
| Manage candidates | PARTIAL | Tables/RPCs exist; live authorization tests not executed |
| Upload candidate files | PARTIAL | Storage/table primitives exist; helper upload-session RPC missing |
| Create jobs | PARTIAL | Tables/API RPCs exist; live creation not tested |
| Publish jobs | PARTIAL | Job lifecycle structures exist; live publish not tested |
| Receive applications | PARTIAL | `submit_application` and ATS tables exist; live flow not tested |
| Manage ATS stages | PARTIAL | `ats_stages`, history, advance RPC exist; live transition not tested |
| Run matching | PARTIAL | Matching RPCs/tables exist; live ranking not tested |
| Run assessments | PARTIAL | Assessment tables/RPCs exist; live attempt/scoring not tested |
| Schedule interviews | PARTIAL | Interview RPCs/tables exist; live conflict checks not tested |
| Share candidates with clients | PARTIAL | Client share RPCs/tables exist; live visibility not tested |
| Manage notifications | PARTIAL | Notification tables/RPCs exist; worker/provider delivery not verified |
| Use AI assistant features | PARTIAL | AI tables/RPCs exist; provider runtime not verified |
| View analytics | PARTIAL | Analytics RPCs/tables exist; live data not tested |
| Manage subscriptions | FAIL | Entitlement primitives only; no full billing flow |
| Connect integrations | PARTIAL | Integration foundation exists; credentials/provider setup required |
| Use advanced search | PARTIAL | Search RPCs/tables exist; embedding runtime not verified |
| Configure workflows | PARTIAL | Workflow engine exists; live execution worker not verified |
| Use public API | PARTIAL | Database RPCs/OpenAPI exist; HTTP runtime not proven |
| Manage platform admin | PARTIAL | Admin RPCs/tables exist; live platform admin not tested |

## Security Gate

| Check | Status | Notes |
|---|---|---|
| RLS on protected tables | PARTIAL | Present in migrations; remote catalog not verified |
| Tenant isolation | NOT VERIFIED | Requires remote test actors |
| Insecure SECURITY DEFINER functions | PARTIAL | Functions use explicit `search_path = public` in many cases; complete remote grant audit not run |
| Exposed service role key | PASS STATIC | No obvious live value found |
| DB password in frontend | PASS STATIC | No obvious live value found |
| Provider secrets in frontend | PASS STATIC | Placeholders/docs only |
| Private storage exposure | NOT VERIFIED | Requires remote bucket policy test |
| IDOR / privilege escalation | NOT VERIFIED | Requires scenario testing |
| Unsafe API access | PARTIAL | API scopes/rate/idempotency in migrations; HTTP runtime not verified |
| Sensitive error leakage | PARTIAL | Error contracts documented; live API/RPC behavior not tested |

Final security gate: PARTIAL, with NO-GO for verified production acceptance until live remote checks pass.
