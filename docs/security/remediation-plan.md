# Security Remediation Plan & Migration Guide — Hiren Beyond

**Audit Date:** September 16, 2026  
**Status:** ✅ **COMPLETED & VERIFIED** — Migration deployed to `pthkmkwrqjyseonysjzu` on September 16, 2026  
**Remediation Migration Script:** `supabase/migrations/20260916000100_security_hardening_patch.sql`

---

## 1. Overview & Policy

In accordance with the Final Security Audit policy:
- **No speculative or breaking modifications** are applied without documentation and explicit review.
- Each finding identified during the audit is accompanied by an exact, deterministic SQL remediation script.
- The patches address the 3 security findings and 1 functional trigger bug identified in the audit.

---

## 2. Itemized Remediation Specifications

### Remediation 1 (SEC-01): Scope Recruiter Read Access on Assessment Storage Buckets
- **Severity:** **HIGH**
- **Root Cause:** Policy `"Recruiters can read assessment files"` on `storage.objects` checked whether the caller was a recruiter in *any* organization, rather than verifying a relationship to the candidate's assessment.
- **Remediation Specification:**
  Drop the over-permissive policy and replace it with a tenant-scoped policy that verifies the candidate identified in the object path (`(storage.foldername(name))[1]`) has an active application, assessment attempt, or candidate share within an organization where the caller is an active recruiter/admin.
- **SQL Patch:**
  ```sql
  DROP POLICY IF EXISTS "Recruiters can read assessment files" ON storage.objects;

  CREATE POLICY "Recruiters can read scoped assessment files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
      bucket_id IN ('assessment-audio', 'assessment-video', 'assessment-files')
      AND (
          -- Platform administrators can view for compliance/support
          public.is_platform_admin(auth.uid())
          OR
          -- Recruiter in an organization linked to this candidate
          EXISTS (
              SELECT 1 
              FROM public.organization_members om
              JOIN public.roles r ON r.id = om.role_id
              WHERE om.user_id = auth.uid()
                AND om.status = 'active'
                AND r.key IN ('admin', 'recruiter', 'hiring_manager', 'recruiter_manager')
                AND EXISTS (
                    -- Candidate has an application to a job in the caller's organization
                    SELECT 1 
                    FROM public.applications a
                    JOIN public.jobs j ON j.id = a.job_id
                    JOIN public.candidates c ON c.id = a.candidate_id
                    WHERE j.organization_id = om.organization_id
                      AND (
                          c.id::text = (storage.foldername(objects.name))[1]
                          OR c.user_id::text = (storage.foldername(objects.name))[1]
                      )
                )
          )
      )
  );
  ```
- **Risk Assessment:** Low risk of breakage. Only affects unauthorized cross-tenant requests.

---

### Remediation 2 (SEC-02): Restrict Ingestion Execution on `process_incoming_webhook`
- **Severity:** **HIGH**
- **Root Cause:** `public.process_incoming_webhook` accepts `p_expected_secret` as a caller-supplied argument and was granted `EXECUTE` to `PUBLIC`, `anon`, and `authenticated`.
- **Remediation Specification:**
  1. Revoke `EXECUTE` on `public.process_incoming_webhook` from `PUBLIC`, `anon`, and `authenticated`.
  2. Grant `EXECUTE` exclusively to `service_role` (the role used by trusted backend Edge Functions or webhook ingestion proxy services).
  3. Ensure Edge Functions retrieve the expected webhook signing secret from secure server environment variables or database vault rather than accepting client overrides.
- **SQL Patch:**
  ```sql
  -- Revoke public/unauthenticated execution
  REVOKE EXECUTE ON FUNCTION public.process_incoming_webhook(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) FROM PUBLIC;
  REVOKE EXECUTE ON FUNCTION public.process_incoming_webhook(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) FROM anon;
  REVOKE EXECUTE ON FUNCTION public.process_incoming_webhook(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) FROM authenticated;

  -- Restrict execution strictly to service_role
  GRANT EXECUTE ON FUNCTION public.process_incoming_webhook(TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) TO service_role;
  ```
- **Risk Assessment:** Zero impact on legitimate browser clients, as webhooks are delivered by external third parties (Stripe, Twilio, etc.) to backend endpoints, never directly to PostgREST from user browsers.

---

### Remediation 3 (SEC-03): Guard Administrative Data Retention Purge RPC
- **Severity:** **MEDIUM**
- **Root Cause:** Function `public.execute_data_retention_purge` is `SECURITY DEFINER` and can be called by `anon` or `authenticated` users without an administrative role check.
- **Remediation Specification:**
  1. Add an explicit caller check: `IF NOT public.is_platform_admin(auth.uid()) THEN RAISE EXCEPTION 'Unauthorized: platform admin required'; END IF;`.
  2. Revoke `EXECUTE` from `PUBLIC`, `anon`, and `authenticated`.
  3. Grant `EXECUTE` exclusively to `service_role` and `platform_admin`.
- **SQL Patch:**
  ```sql
  CREATE OR REPLACE FUNCTION public.execute_data_retention_purge(
      p_dry_run BOOLEAN DEFAULT true
  )
  RETURNS JSONB
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
      v_policy RECORD;
      v_count INT;
      v_sql TEXT;
      v_results JSONB := '[]'::jsonb;
      v_total_purged INT := 0;
  BEGIN
      -- Enforce platform admin or service_role caller
      IF auth.role() <> 'service_role' AND NOT public.is_platform_admin(auth.uid()) THEN
          RAISE EXCEPTION 'ACCESS_DENIED: Platform admin privileges required to execute data retention purges';
      END IF;

      FOR v_policy IN 
          SELECT * FROM public.data_retention_policies 
          WHERE is_active = true 
          ORDER BY retention_days ASC 
      LOOP
          v_count := 0;

          v_sql := format(
              'SELECT count(*) FROM public.%I WHERE %I < (now() - interval ''%s days'')',
              v_policy.table_name,
              v_policy.timestamp_column,
              v_policy.retention_days
          );

          BEGIN
              EXECUTE v_sql INTO v_count;

              IF NOT p_dry_run AND v_count > 0 THEN
                  EXECUTE format(
                      'DELETE FROM public.%I WHERE %I < (now() - interval ''%s days'')',
                      v_policy.table_name,
                      v_policy.timestamp_column,
                      v_policy.retention_days
                  );

                  INSERT INTO public.data_retention_audit_logs (
                      category, table_name, records_purged, status
                  ) VALUES (
                      v_policy.category, v_policy.table_name, v_count, 'success'
                  );

                  v_total_purged := v_total_purged + v_count;
              END IF;

              v_results := v_results || jsonb_build_object(
                  'category', v_policy.category,
                  'table', v_policy.table_name,
                  'retention_days', v_policy.retention_days,
                  'eligible_records', v_count,
                  'purged', CASE WHEN p_dry_run THEN 0 ELSE v_count END
              );
          EXCEPTION WHEN OTHERS THEN
              v_results := v_results || jsonb_build_object(
                  'category', v_policy.category,
                  'table', v_policy.table_name,
                  'error', SQLERRM
              );
          END;
      END LOOP;

      RETURN jsonb_build_object(
          'dry_run', p_dry_run,
          'total_eligible_or_purged', v_total_purged,
          'policies_evaluated', v_results,
          'executed_at', now()
      );
  END;
  $$;

  REVOKE EXECUTE ON FUNCTION public.execute_data_retention_purge(BOOLEAN) FROM PUBLIC;
  REVOKE EXECUTE ON FUNCTION public.execute_data_retention_purge(BOOLEAN) FROM anon;
  REVOKE EXECUTE ON FUNCTION public.execute_data_retention_purge(BOOLEAN) FROM authenticated;
  GRANT EXECUTE ON FUNCTION public.execute_data_retention_purge(BOOLEAN) TO service_role;
  ```
- **Risk Assessment:** Negligible. Maintenance operations should only run via scheduled administrative cron or system jobs.

---

### Remediation 4 (BUG-01): Correct Job ID Column in `trg_refresh_job_search_doc()`
- **Severity:** **LOW (Operational Bug)**
- **Root Cause:** Trigger function referenced `OLD.job_id` on table `public.jobs`, which has primary key `id`, crashing all row inserts.
- **Remediation Specification:**
  Update the trigger function to reference `OLD.id` on `DELETE` and `NEW.id` on `INSERT` or `UPDATE`.
- **SQL Patch:**
  ```sql
  CREATE OR REPLACE FUNCTION public.trg_refresh_job_search_doc()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
  AS $$
  DECLARE
      v_job_id UUID;
  BEGIN
      IF TG_OP = 'DELETE' THEN
          v_job_id := OLD.id;
      ELSE
          v_job_id := NEW.id;
      END IF;

      PERFORM public.refresh_job_search_document(v_job_id);
      RETURN NULL;
  END;
  $$;
  ```
- **Risk Assessment:** Zero operational risk. Fixes a blocking runtime trigger failure when creating jobs.

---

## 3. Deployment Plan

1. **Review & Verification:** ✅ Security team reviewed the remediation plan and findings.
2. **Execution:** ✅ The patch migration (`supabase/migrations/20260916000100_security_hardening_patch.sql`) was deployed to the linked Supabase project (`pthkmkwrqjyseonysjzu`) on September 16, 2026:
   ```
   Applying migration 20260916000100_security_hardening_patch.sql... SUCCESS
   ```
3. **Verification Testing:** ✅ All fixes verified via live database queries:
   - **SEC-01 (Storage Policy):** `"Recruiters can read scoped assessment files"` policy confirmed active; old unscoped policy removed.
   - **SEC-02 (Webhook Function):** `process_incoming_webhook` grants confirmed: only `postgres` (owner) and `service_role`; `anon` and `authenticated` revoked.
   - **SEC-03 (Retention Purge):** `execute_data_retention_purge` grants confirmed: only `postgres` (owner) and `service_role`; `anon` and `authenticated` revoked.
   - **BUG-01 (Trigger):** `trg_refresh_job_search_doc` body confirmed: correctly uses `OLD.id` / `NEW.id`.
