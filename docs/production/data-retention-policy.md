# Hiren Beyond — Data Retention & Archival Policy

## 1. Purpose & Scope
This policy defines the legal, operational, and architectural requirements for retaining, archiving, and purging data stored within the Hiren Beyond recruitment platform. It satisfies GDPR Art. 5(1)(e) (Storage Limitation) and SOC 2 CC6.5 requirements while preventing unbounded storage growth.

---

## 2. Retention Classifications

### 2.1 Immutable & Protected Data (NEVER Automatically Purged)
The following tables are **explicitly excluded** from automated deletion scripts:
- **Candidate Master Data**: `candidates`, `candidate_profiles`, `candidate_work_history`, `candidate_education`
- **Job Orders & Requisitions**: `jobs`, `job_requirements`
- **Job Applications & Pipeline Records**: `applications`, `application_stage_history`
- **Hiring Decisions & Contracts**: `hiring_decisions`, `client_hiring_decisions`
- **Client Organizations & Tenancy**: `organizations`, `organization_members`
- **Core RBAC & Security Grants**: `roles`, `permissions`, `role_permissions`

### 2.2 Time-Bound Retention Schedules (Managed by Data Retention Engine)
Enforced via `public.data_retention_policies` table:

| Category | Target Table | Timestamp Column | Retention Window | Justification |
|----------|--------------|------------------|------------------|---------------|
| **Audit Logs** | `audit_logs` | `created_at` | **365 Days** | Regulatory compliance & security audits |
| **User Analytics Events** | `analytics_events` | `created_at` | **90 Days** | Behavioral trends & dashboard reporting |
| **Search Query History** | `search_history` | `created_at` | **60 Days** | Popular suggestion & recruiter telemetry |
| **Notification Deliveries**| `notification_deliveries` | `created_at` | **30 Days** | Delivery diagnostic logs & webhook confirmation |
| **Workflow Execution Logs**| `workflow_execution_logs` | `created_at` | **30 Days** | Step-level debugging & execution traces |
| **Integration Job Attempts**| `integration_job_attempts`| `created_at` | **30 Days** | API payload replay & transient sync error logs |
| **Webhook Deliveries** | `webhook_deliveries` | `created_at` | **30 Days** | Third-party outbound webhook delivery receipts |

---

## 3. Automated Purge Engine (`public.execute_data_retention_purge`)

### 3.1 Safety Mechanisms
- **Dry-Run Mode**: Defaults to `p_dry_run = true` to report eligible records without deletion.
- **Audit Logging**: Successful purges record entry in `public.data_retention_audit_logs`.
- **RBAC Gating**: Execution strictly restricted to `platform_admin` and `super_admin` roles via RLS and `is_platform_admin()`.

### 3.2 Scheduled Execution
The retention purge is configured to execute weekly during low-traffic maintenance windows (Sundays 02:00 UTC) via pg_cron or Supabase Scheduled Edge Function:

```sql
SELECT public.execute_data_retention_purge(p_dry_run => false);
```
