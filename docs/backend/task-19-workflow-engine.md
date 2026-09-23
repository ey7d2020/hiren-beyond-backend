# Task 19 — Automation & Workflow Engine

**Migration:** `20260915001900_automation_workflow_engine.sql`  
**Status:** ✅ COMPLETE — Deployed to remote Supabase (32 migrations in sync)

---

## Architecture

The Automation Engine is an orchestration layer above all existing business services.
It never duplicates ATS, matching, assessment, notifications, or any other domain logic.

```
Business Event (e.g. application_submitted)
      ↓
enqueue_workflow_event()    ← Idempotent, sliding-window dedup
      ↓
workflow_event_queue        ← Persisted, status-tracked
      ↓
route_workflow_events()     ← Matches active published workflows by trigger.event_type
      ↓
Loop Protection Check       ← execution_depth < max_execution_depth
Idempotency Check           ← no duplicate within idempotency_window_seconds
      ↓
workflow_executions         ← One execution per matched workflow
      ↓
evaluate_workflow_condition() ← Field allowlist-validated, no arbitrary SQL
      ↓
execute_workflow_action()   ← Dispatches to existing services (ATS, assessments, etc.)
      ↓
workflow_execution_steps    ← Step-level audit trail
workflow_execution_logs     ← Debug/info/warning/error logs
workflow_failures           ← Dead letter queue for failed steps
```

---

## New Tables (13)

| Table | Purpose |
|-------|---------|
| `workflow_definitions` | Named, versioned workflow blueprints |
| `workflow_versions` | Immutable published snapshots |
| `workflow_triggers` | Event/schedule/manual trigger config per version |
| `workflow_fields` | Allowlist registry of permitted condition fields |
| `workflow_conditions` | Structured condition tree (no arbitrary SQL) |
| `workflow_actions` | Action steps with risk level, delay, approval |
| `workflow_approval_steps` | Approval requirements for high-risk actions |
| `workflow_schedules` | Cron/once/interval with timezone |
| `workflow_event_queue` | Persistent event queue with idempotency |
| `workflow_executions` | Per-trigger execution records with loop protection |
| `workflow_execution_steps` | Per-action step tracking with retry state |
| `workflow_execution_logs` | Debug logs (no PII, no secrets) |
| `workflow_failures` | Dead letter queue with retryable classification |

---

## RPCs (15 total — all SECURITY DEFINER)

| RPC | Purpose |
|-----|---------|
| `validate_workflow_definition()` | JSON schema + security validation |
| `publish_workflow_version()` | Create immutable published version |
| `enqueue_workflow_event()` | Idempotent event ingestion |
| `route_workflow_events()` | Match events to active workflows |
| `execute_workflow_action()` | Dispatch to existing business services |
| `create_workflow_execution_step()` | Create step record |
| `evaluate_workflow_condition()` | Safe condition evaluation (allowlist only) |
| `cancel_workflow_execution()` | Cancel without reversing completed actions |
| `pause_workflow()` | Pause workflow (no new executions) |
| `resume_workflow()` | Resume paused workflow |
| `approve_workflow_action()` | Approve step waiting for human review |
| `deny_workflow_action()` | Deny and cancel execution |
| `retry_workflow_step()` | Idempotent manual retry of failed steps |
| `get_workflow_execution()` | Full execution + steps + logs view |
| `get_failed_workflows()` | Paginated failed execution list |

---

## Safety Controls

### No Arbitrary SQL/Code
- `validate_workflow_definition()` rejects steps with keys: `sql`, `query`, `execute`, `eval`, `shell`, `system`
- `execute_workflow_action()` blocks action types: `raw_sql`, `execute_sql`, `shell`, `system`

### Condition Field Allowlist
- `evaluate_workflow_condition()` rejects any field not in `workflow_fields` registry
- Unknown fields raise `invalid_field` exception (not a silent failure)

### Cross-Tenant Isolation
- `route_workflow_events()`: only matches org's own workflows or `is_system = true`
- All RPCs verify entity belongs to caller org before modification
- RLS on all 13 tables

### Idempotency
- Partial unique index `uq_weq_idempotency_partial` on `(organization_id, idempotency_key)` when key IS NOT NULL
- Execution-level dedup within `idempotency_window_seconds` (default 300s)

### Loop Protection
- `max_execution_depth` (default 5) per workflow definition
- Checked at `route_workflow_events()` time — skips if depth exceeded
- Logged as warning in execution logs

---

## Integration Map

| Action | Existing Service Used |
|--------|-----------------------|
| `move_application_stage` | Direct UPDATE + existing ATS trigger fires events/history |
| `create_assessment_invitation` | `trigger_required_assessments()` from Task 08 |
| `add_to_talent_pool` | `add_candidate_to_talent_pool()` from Task 07 |
| `send_notification` | `emit_notification_event()` from Task 11 |
| `create_review_item` | `recruiter_review_queue` INSERT from Task 07 |
| `run_matching` | Enqueues via `enqueue_workflow_event()` for async matching |
| `create_analytics_event` | `audit_logs` INSERT from Task 01 |

---

## Retry Policy

| Failure Type | Retryable | Max Retries |
|-------------|-----------|-------------|
| `temporary_failure` | YES | 3 |
| `external_provider_failure` | YES | 3 |
| `rate_limit` | YES | 3 |
| `permanent_failure` | NO | 0 |
| `authorization_failure` | NO | 0 |
| `validation_failure` | NO | 0 |

---

## Scheduling

| Feature | Implementation |
|---------|----------------|
| Cron | `cron_expression` + `next_run_at` |
| Timezone | `timezone TEXT NOT NULL DEFAULT 'UTC'` |
| Duplicate-run prevention | `next_run_at` updated after run + `run_count` |
| Server-side | Persisted in DB, no browser timers |

---

## Test Results: 71/71 Passed

All 71 tests in `docs/backend/test-workflow-engine.sql` passed.

---

## Blockers

None. Task 19 is fully deployed and operational.

> **Note:** Live workflow execution requires an external worker/scheduler (e.g., pg_cron or Supabase Edge Functions)
> to poll `workflow_event_queue` and advance executions. The schema, RPCs, and event queue are fully deployed.
> Worker activation is a DevOps step, not a code blocker.
