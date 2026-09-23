-- =============================================================================
-- Migration: 20260916000100_security_hardening_patch.sql
-- Description: Task 27 Security Audit Remediation Patch
-- Fixes:
--   1. SEC-01 (HIGH): Tenant-scoping on assessment storage buckets for recruiters
--   2. SEC-02 (HIGH): Revoke public/anon execute on process_incoming_webhook
--   3. SEC-03 (MEDIUM): Add is_platform_admin guard and revoke public execute on execute_data_retention_purge
--   4. BUG-01 (LOW): Correct column reference in trg_refresh_job_search_doc (OLD.id / NEW.id)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SEC-01: SCOPE RECRUITER ASSESSMENT STORAGE ACCESS TO TENANT CANDIDATES
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Recruiters can read assessment files" ON storage.objects;
DROP POLICY IF EXISTS "Recruiters can read scoped assessment files" ON storage.objects;

CREATE POLICY "Recruiters can read scoped assessment files"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id IN ('assessment-audio', 'assessment-video', 'assessment-files')
    AND (
        -- Platform administrators can view for audit/support
        public.is_platform_admin(auth.uid())
        OR
        -- Recruiter in an organization where the candidate has an application or assessment
        EXISTS (
            SELECT 1 
            FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.user_id = auth.uid()
              AND om.status = 'active'
              AND r.key IN ('admin', 'recruiter', 'hiring_manager', 'recruiter_manager')
              AND EXISTS (
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

-- -----------------------------------------------------------------------------
-- 2. SEC-02: RESTRICT process_incoming_webhook EXECUTION TO service_role
-- -----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.process_incoming_webhook(VARCHAR, TEXT, VARCHAR, JSONB, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.process_incoming_webhook(VARCHAR, TEXT, VARCHAR, JSONB, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.process_incoming_webhook(VARCHAR, TEXT, VARCHAR, JSONB, TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_incoming_webhook(VARCHAR, TEXT, VARCHAR, JSONB, TEXT, TEXT) TO service_role;

-- -----------------------------------------------------------------------------
-- 3. SEC-03: HARDEN execute_data_retention_purge WITH CALLER VERIFICATION
-- -----------------------------------------------------------------------------
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
    -- Guard: Only service_role or platform administrators may execute data retention purges
    IF auth.role() <> 'service_role' AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Platform administrator privileges required to execute data retention purge';
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

-- -----------------------------------------------------------------------------
-- 4. BUG-01: FIX COLUMN REFERENCE IN trg_refresh_job_search_doc
-- -----------------------------------------------------------------------------
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
