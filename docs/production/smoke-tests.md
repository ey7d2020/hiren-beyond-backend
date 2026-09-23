# Hiren Beyond — Production Smoke Test Checklist

Execute this checklist following any production migration, database maintenance, or deployment.

---

## Smoke Test Matrix

| # | Domain | Action | Verification Query / RPC | Target Result |
|---|--------|--------|--------------------------|---------------|
| 1 | **Foundation** | System Readiness | `SELECT public.get_readiness();` | `ready: true, rls_enforced: true` |
| 2 | **Observability** | System Health | `SELECT public.get_system_health();` | `status: "healthy"` |
| 3 | **Observability** | Queue Health | `SELECT public.get_queue_health();` | Queue stats returned without error |
| 4 | **Identity & RBAC** | Admin Authorization | `SELECT public.is_platform_admin(auth.uid());` | Deterministic boolean returned |
| 5 | **Candidate** | Profile Access | `SELECT id FROM candidate_profiles LIMIT 1;` | Read successful under RLS |
| 6 | **Jobs** | Marketplace Filter | `SELECT id FROM jobs WHERE status = 'published' LIMIT 1;` | Fast index scan (< 1 ms) |
| 7 | **Applications** | Keyset Cursor Pagination | `SELECT public.get_applications_cursor('00000000-0000-0000-0000-000000000000'::uuid);` | Returns structured JSON items |
| 8 | **Matching** | Match Engine Exists | `SELECT proname FROM pg_proc WHERE proname = 'calculate_candidate_job_match';` | Exists and valid |
| 9 | **Assessments** | Assessment Trigger | `SELECT proname FROM pg_proc WHERE proname = 'trigger_required_assessments';` | Exists and valid |
| 10 | **Interviews** | Calendar Schedule | `SELECT id FROM interviews WHERE status = 'scheduled' LIMIT 1;` | Index scan utilized |
| 11 | **Client Portal** | Feedback Review | `SELECT id FROM client_candidate_shares LIMIT 1;` | Read successful under RLS |
| 12 | **Notifications** | Unread Index Lookup | `SELECT id FROM notifications WHERE read_at IS NULL LIMIT 1;` | Partial index utilized |
| 13 | **AI Assistants** | Circuit Breaker Check | `SELECT public.check_circuit_breaker('openai');` | `allowed: true, state: "healthy"` |
| 14 | **Integrations** | Provider Check | `SELECT public.check_circuit_breaker('stripe');` | `allowed: true, state: "healthy"` |
| 15 | **Search** | Global Candidate Search | `SELECT proname FROM pg_proc WHERE proname = 'search_candidates';` | Exists and valid |
| 16 | **Workflows** | Queue Worker Claim | `SELECT public.claim_queue_jobs('workflow_events', 'smoke_tester', 1);` | Returns claimed count JSON |
| 17 | **Workflows** | Failure Dead Letter | `SELECT count(*) FROM workflow_failures WHERE resolved_at IS NULL;` | Numeric count returned |
| 18 | **Compliance** | Retention Policies | `SELECT count(*) FROM data_retention_policies WHERE is_active = true;` | At least 6 policies active |
| 19 | **Compliance** | Dry-Run Purge | `SELECT public.execute_data_retention_purge(true);` | `dry_run: true` |
| 20 | **Security** | RLS Table Count | `SELECT count(*) FROM pg_tables WHERE schemaname='public' AND rowsecurity=true;` | 100% of public tables secured |
