-- ============================================================================
-- Hiren Beyond Backend -- Migration 20260915002500
-- Fix missing RLS policies on integration event/attempt tables.
-- Non-destructive: adds read-only authenticated policies. No data changes.
-- ============================================================================

CREATE POLICY "Org members can view integration events"
ON public.integration_events FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1
        FROM public.organization_members om
        WHERE om.organization_id = integration_events.organization_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);

CREATE POLICY "Org members can view integration job attempts"
ON public.integration_job_attempts FOR SELECT
TO authenticated
USING (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
        SELECT 1
        FROM public.integration_jobs j
        JOIN public.organization_members om ON om.organization_id = j.organization_id
        WHERE j.id = integration_job_attempts.integration_job_id
          AND om.user_id = auth.uid()
          AND om.status = 'active'
    )
);
