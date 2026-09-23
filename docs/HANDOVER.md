# Hiren Beyond Backend Handover

## Project Overview

Hiren Beyond is a Supabase/PostgreSQL backend for a recruitment platform. The repository contains database migrations, RLS policies, RPCs, storage definitions, API contracts, frontend integration documentation, database architecture docs, and production operations notes.

Current delivery status: repository handover ready for review; production acceptance is NO-GO until remote Supabase verification and smoke tests are completed.

## Architecture

Primary stack:

- Supabase Auth for authentication.
- PostgreSQL in Supabase for data, RLS, functions/RPCs, triggers, constraints, and indexes.
- Supabase Storage for private candidate documents, assessment audio, and analytics exports.
- PostgREST/Supabase RPC for internal frontend/backend operations.
- Public API database layer plus OpenAPI contract.

No `supabase/functions` directory is present in this repository snapshot.

## Modules

Implemented in local migrations:

- Identity & Organizations
- Candidates
- Jobs
- Applications / ATS
- CV Intelligence
- Matching
- Recruiter Operations
- Assessments
- Interviews & Hiring
- Clients
- Notifications
- AI Assistants
- Analytics
- Billing / Entitlements
- Integrations
- Globalization
- Platform Admin
- Search
- Workflows
- Public API
- Security / Production Hardening

## How To Deploy

1. Install Supabase CLI.
2. Authenticate to Supabase.
3. Link the repository to the client Supabase project.
4. Review `.env.example` and configure local/CI environment variables.
5. Run remote migration status checks.
6. Apply pending migrations.
7. Run verification SQL and module tests.
8. Configure Auth redirect URLs and external provider secrets.
9. Verify storage policies and private file access.
10. Run production smoke tests.

Do not deploy to production until verification passes.

## Environment Variables

### Public Variables

Safe for frontend builds:

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_API_BASE_URL=
VITE_APP_URL=
```

### Server Secrets

Server/CI only:

```bash
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_DB_PASSWORD=
DATABASE_URL=
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
STRIPE_SECRET_KEY=
WEBHOOK_SECRET=
```

Never expose server secrets in browser bundles, public repos, logs, or client-side environment variables.

## Authentication

The frontend should use Supabase Auth with the anon/publishable key. Email/password and email OTP are configured locally. OAuth providers require external dashboard configuration before use.

Post-login flow:

1. Restore Supabase session.
2. Call `get_my_profile()`.
3. Call `get_user_organizations()`.
4. Select active organization.
5. Call `get_user_permissions(activeOrgId)`.

## Database

Important docs:

- `docs/database/README.md`
- `docs/database/table-inventory.md`
- `docs/database/master-erd.md`
- `docs/database/cross-module-relationships.md`
- `docs/database/erd/`
- `docs/database/verification-report.sql`

Local migration inventory:

- 40 migrations.
- 192 public tables.
- 2 public views.
- 236 unique public function names.

## Storage

Buckets found in migrations:

- `candidate-documents`
- `assessment-audio`
- `analytics-exports`

Private storage must be accessed through authenticated Supabase Storage operations or signed URLs. Do not make private buckets public for convenience.

## API

Public API contract:

- `docs/api/openapi-v1.yaml`
- `docs/backend/task-22-public-api.md`

Database RPCs exist for API key authentication, scopes, idempotency, rate limits, jobs, candidates, applications, stage updates, and webhook subscriptions.

HTTP `/api/v1` runtime is not proven by this repository because no Edge Functions directory exists.

## Integrations

Foundation present:

- Integration providers.
- Integration connections.
- OAuth sessions.
- Incoming/outbound webhook records.
- Integration jobs and health checks.

Ready to configure:

- Provider credentials.
- OAuth app settings.
- Webhook secrets.
- Calendar/email/WhatsApp/SMS provider settings.

Not already configured by this repository:

- Third-party live credentials.
- External provider dashboard settings.

## Testing

SQL test documents exist under `docs/backend` and `docs/production`.

Not executed here:

- Remote DB tests.
- RLS/tenant isolation live tests.
- Storage access live tests.
- Production smoke tests.

Reason: Supabase CLI is not installed in this environment.

## Security

Security model:

- RLS protects tenant and privacy boundaries.
- SECURITY DEFINER RPCs implement controlled cross-table operations.
- Candidate/client privacy is mediated by ownership, org membership, and share records.
- API keys are hashed and scoped.
- Service-role keys and provider secrets must stay server-side.

Static secret scan did not find obvious live credentials; placeholders and invalid test keys remain in docs/tests.

## Known Limitations

- Remote Supabase state is not verified.
- No Edge Functions are present in the repo.
- Billing checkout/customer portal flow is not implemented in repo.
- Realtime subscriptions require remote publication verification.
- AI provider runtime and streaming are not verified.
- Storage upload-session helper RPCs are not implemented locally.

## Ownership / Handover Notes

The client must own:

- Supabase organization/project access.
- Production Auth URL/redirect configuration.
- Secrets and provider credentials.
- Backup/restore policy execution.
- CI/CD migration deployment.
- External service dashboards for AI, email, messaging, calendar, billing, and webhooks.

Final delivery gate: NO-GO for verified production acceptance until the blockers in `docs/production/final-client-handover-report.md` are resolved.
