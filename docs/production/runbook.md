# Hiren Beyond — Production Operational Runbook

## 1. Service Overview & Architecture
Hiren Beyond backend operates on Supabase PostgreSQL with multi-tenant Row Level Security (RLS), background worker queues, external API circuit breakers, and transactional outboxes.

---

## 2. Emergency Operational Procedures

### 2.1 Circuit Breaker Tripped (AI Provider / Third-Party API Outage)
**Symptom**: `public.check_circuit_breaker('openai')` returns `allowed: false, state: "failing"`.
**Diagnosis**: 5 consecutive failures recorded against OpenAI API within 5 minutes.
**Resolution**:
1. Check external provider status page (e.g., status.openai.com).
2. If temporary incident resolved, reset circuit breaker manually:
   ```sql
   SELECT public.record_circuit_breaker_result('openai', true);
   ```
3. If outage persists, route traffic to fallback provider (e.g. Anthropic Claude or Google Gemini) via application configuration or update provider timeout:
   ```sql
   UPDATE public.provider_circuit_breakers 
   SET timeout_seconds = 45, cooldown_seconds = 600 
   WHERE provider_name = 'openai';
   ```

### 2.2 Workflow Dead Letter Queue (DLQ) Backlog Spike
**Symptom**: `public.get_system_health()` returns status `degraded` due to unresolved workflow failures.
**Diagnosis**: Inspect failure reasons in `workflow_failures`:
```sql
SELECT failure_type, error_code, error_message, count(*)
FROM public.workflow_failures
WHERE resolved_at IS NULL
GROUP BY failure_type, error_code, error_message
ORDER BY count(*) DESC;
```
**Resolution**:
- If failures were caused by transient external API timeouts that have recovered, redrive failed jobs using `retry_dead_letter_execution()`:
```sql
SELECT public.retry_dead_letter_execution(id)
FROM public.workflow_failures
WHERE resolved_at IS NULL AND retryable = true;
```

### 2.3 Long-Running Query / Lock Contention Investigation
**Diagnosis**:
```sql
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle' AND (now() - pg_stat_activity.query_start) > interval '5 seconds'
ORDER BY duration DESC;
```
**Resolution**: Terminate rogue client connection:
```sql
SELECT pg_terminate_backend(pid);
```

### 2.4 Requeuing Stalled Integration Jobs
**Diagnosis**: Check jobs stuck in `processing` state without recent heartbeat:
```sql
SELECT id, job_type, started_at
FROM public.integration_jobs
WHERE status = 'processing' AND started_at < (now() - interval '15 minutes');
```
**Resolution**: Reset stuck jobs back to `queued`:
```sql
UPDATE public.integration_jobs
SET status = 'queued', started_at = NULL
WHERE status = 'processing' AND started_at < (now() - interval '15 minutes');
```
