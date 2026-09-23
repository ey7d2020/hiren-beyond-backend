# Task 22: Public API Layer, API Keys, Webhooks, Developer API & Integration Contracts

## 1. Executive Summary
Task 22 establishes the official, secure Public API & Developer Platform layer for Hiren Beyond. External ATSs, client applications, web portals, and mobile clients can now integrate programmatically with platform capabilities (Jobs, Candidates, Applications, Stage Transitions, Interviews, Assessments, and Webhooks) through a strictly controlled, versioned, authenticated, rate-limited, and audited API interface.

---

## 2. Architectural Security Principles
1. **Never Expose Raw Database Access**: Public developers interact strictly through versioned `/api/v1` RPC endpoints and secured application registries. Service-role credentials, database passwords, and internal RPCs are strictly inaccessible.
2. **Cryptographic Key Storage**: API keys follow the format `hb_live_<prefix>_<random>`. The database stores strictly `key_prefix` and the irreversible SHA-256 hash (`key_hash`). The raw plaintext key is returned strictly once upon generation.
3. **Derived Multi-Tenant Scoping**: All API operations derive `organization_id` strictly from the authenticated API key and application mapping. Tenant IDs supplied in request bodies or query parameters are ignored for authorization, preventing cross-tenant privilege escalation.
4. **Fine-Grained Scopes (Least Privilege)**: Every API key is bound to explicit scopes (`jobs.read`, `jobs.write`, `candidates.read`, `candidates.write`, `applications.read`, `applications.write`, `interviews.read`, `assessments.read`, `webhooks.manage`, `analytics.read`). Requests without the requisite scope are rejected with `403 FORBIDDEN`.
5. **Idempotency Protection**: Write operations (`POST /api/v1/jobs`, stage updates, webhook actions) support the `Idempotency-Key` header. Requests with identical keys and hashes return cached responses without re-executing business logic; mismatched hashes trigger `IDEMPOTENCY_CONFLICT`.
6. **Server-Side Rate Limiting**: Enforces configurable requests-per-minute, requests-per-hour, and burst limits per application and organization with sliding-window accounting. Exceeded limits return `429 RATE_LIMITED`.

---

## 3. Database Schema (11 New Tables)

| Table Name | Purpose | RLS Status |
|------------|---------|------------|
| `api_applications` | Client application registry (server, web, mobile, partner) | Enforced |
| `api_keys` | Hashed API credentials with prefix, expiration, and last used timestamps | Enforced |
| `api_scopes` | Master catalog of functional permission scopes | Enforced |
| `api_key_scopes` | Scopes bound to specific API keys | Enforced |
| `api_usage_records` | Metric accounting for latency, status codes, and rate groups | Enforced |
| `api_request_logs` | Operational error logs with request IDs and error codes | Enforced |
| `api_rate_limits` | Per-application and per-organization throttling thresholds | Enforced |
| `api_endpoints` | Public API catalog with risk levels and scope requirements | Enforced |
| `api_idempotency_records` | Request hashes and cached responses for safe retries | Enforced |
| `api_webhook_subscriptions` | Event subscriptions binding API apps to outbound webhooks | Enforced |
| `api_documentation` | Metadata and base URLs for public developer documentation | Enforced |

---

## 4. Deployed Migrations
- `supabase/migrations/20260915002200_public_api_layer.sql` (48.3 KB)
- `supabase/migrations/20260915002201_fix_gen_random_bytes.sql` (6.2 KB)
- `supabase/migrations/20260915002202_fix_webhook_subscribe_cols.sql` (2.1 KB)
- **Status**: Remote Supabase database synchronized (37/37 migrations).

---

## 5. Core API Endpoints (/api/v1)

### 5.1 Jobs API
- `GET /api/v1/jobs`: Query active and published jobs for the caller's organization with keyset cursor pagination.
  - Required Scope: `jobs.read`
- `POST /api/v1/jobs`: Create a new job requisition with idempotency support.
  - Required Scope: `jobs.write`

### 5.2 Candidates API
- `GET /api/v1/candidates`: Query candidates who have applied to the organization's jobs.
  - Required Scope: `candidates.read`
  - Privacy Guarantees: Private contact information, national IDs, and internal review notes are excluded.

### 5.3 Applications API
- `GET /api/v1/applications`: Query ATS applications filtered by job ID with cursor pagination.
  - Required Scope: `applications.read`
- `POST /api/v1/applications/{id}/stage`: Advance application stage respecting tenant ownership.
  - Required Scope: `applications.write`

### 5.4 Webhooks API
- `POST /api/v1/webhooks/subscriptions`: Programmatically register external HTTPS endpoints to receive signed platform events (`application.created`, `job.published`, `candidate.hired`).
  - Required Scope: `webhooks.manage`

---

## 6. Verification Results
- Test suite: `docs/backend/test-public-api.sql`
- Executed on remote Supabase instance: **39/39 tests passed (100%)**.
