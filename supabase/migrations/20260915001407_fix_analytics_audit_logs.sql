-- =============================================================================
-- Migration: 20260915001407_fix_analytics_audit_logs.sql
-- Fix: Update audit_logs column references from (actor_id, new_values)
--      to (actor_user_id, metadata), and correct assessment FK joins in rebuild.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.rebuild_daily_analytics(
    p_organization_id UUID,
    p_date_from       DATE,
    p_date_to         DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_curr_date       DATE;
    v_org_rows        INT := 0;
    v_job_rows        INT := 0;
    r_job             RECORD;
BEGIN
    IF NOT public.check_user_is_recruiter(p_organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller cannot trigger analytics rebuild for organization %', p_organization_id;
    END IF;

    IF p_date_from > p_date_to THEN
        RAISE EXCEPTION 'Invalid date interval: p_date_from % must be <= p_date_to %', p_date_from, p_date_to;
    END IF;

    -- Audit rebuild initiation
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
        p_organization_id, auth.uid(), 'analytics_rebuild_started', 'organization', p_organization_id,
        jsonb_build_object('from', p_date_from, 'to', p_date_to)
    );

    v_curr_date := p_date_from;
    WHILE v_curr_date <= p_date_to LOOP
        -- 1. Rebuild Organization Daily Metrics
        INSERT INTO public.organization_daily_metrics (
            organization_id,
            metric_date,
            active_jobs_count,
            new_jobs_count,
            applications_count,
            new_candidates_count,
            shortlisted_count,
            assessment_completed_count,
            interviews_completed_count,
            offers_count,
            hires_count,
            rejections_count,
            average_match_score
        )
        SELECT
            p_organization_id,
            v_curr_date,
            (SELECT count(*) FROM public.jobs WHERE organization_id = p_organization_id AND status = 'published'),
            (SELECT count(*) FROM public.jobs WHERE organization_id = p_organization_id AND published_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND submitted_at::date = v_curr_date),
            (SELECT count(DISTINCT candidate_id) FROM public.applications WHERE organization_id = p_organization_id AND submitted_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND shortlisted_at::date = v_curr_date),
            (SELECT count(DISTINCT ar.id) FROM public.assessment_results ar JOIN public.assessment_attempts att ON att.id = ar.assessment_attempt_id JOIN public.assessment_invitations ai ON ai.id = att.assessment_invitation_id JOIN public.applications a ON a.id = ai.application_id WHERE a.organization_id = p_organization_id AND ar.created_at::date = v_curr_date),
            (SELECT count(*) FROM public.interviews WHERE organization_id = p_organization_id AND status = 'completed' AND completed_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND status IN ('offer_pending', 'offer_sent', 'offer_accepted') AND updated_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND hired_at::date = v_curr_date),
            (SELECT count(*) FROM public.applications WHERE organization_id = p_organization_id AND rejected_at::date = v_curr_date),
            (SELECT round(avg(final_score)::numeric, 2) FROM public.matching_runs mr JOIN public.jobs j ON j.id = mr.job_id WHERE j.organization_id = p_organization_id AND mr.created_at::date = v_curr_date)
        ON CONFLICT (organization_id, metric_date) DO UPDATE
        SET active_jobs_count          = EXCLUDED.active_jobs_count,
            new_jobs_count             = EXCLUDED.new_jobs_count,
            applications_count         = EXCLUDED.applications_count,
            new_candidates_count       = EXCLUDED.new_candidates_count,
            shortlisted_count          = EXCLUDED.shortlisted_count,
            assessment_completed_count = EXCLUDED.assessment_completed_count,
            interviews_completed_count = EXCLUDED.interviews_completed_count,
            offers_count               = EXCLUDED.offers_count,
            hires_count                = EXCLUDED.hires_count,
            rejections_count           = EXCLUDED.rejections_count,
            average_match_score        = EXCLUDED.average_match_score,
            updated_at                 = now();

        v_org_rows := v_org_rows + 1;

        -- 2. Rebuild Job Daily Metrics
        FOR r_job IN SELECT id FROM public.jobs WHERE organization_id = p_organization_id LOOP
            INSERT INTO public.job_daily_metrics (
                job_id,
                organization_id,
                metric_date,
                applications_count,
                qualified_candidates_count,
                shortlisted_count,
                assessment_completed_count,
                interviews_scheduled_count,
                interviews_completed_count,
                offers_count,
                hires_count,
                rejections_count,
                average_match_score
            )
            SELECT
                r_job.id,
                p_organization_id,
                v_curr_date,
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND submitted_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND submitted_at::date = v_curr_date AND COALESCE(is_eligible, true) = true),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND shortlisted_at::date = v_curr_date),
                (SELECT count(DISTINCT ar.id) FROM public.assessment_results ar JOIN public.assessment_attempts att ON att.id = ar.assessment_attempt_id JOIN public.assessment_invitations ai ON ai.id = att.assessment_invitation_id WHERE ai.job_id = r_job.id AND ar.created_at::date = v_curr_date),
                (SELECT count(*) FROM public.interviews WHERE job_id = r_job.id AND created_at::date = v_curr_date),
                (SELECT count(*) FROM public.interviews WHERE job_id = r_job.id AND status = 'completed' AND completed_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND status IN ('offer_pending', 'offer_sent', 'offer_accepted') AND updated_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND hired_at::date = v_curr_date),
                (SELECT count(*) FROM public.applications WHERE job_id = r_job.id AND rejected_at::date = v_curr_date),
                (SELECT round(avg(final_score)::numeric, 2) FROM public.matching_runs WHERE job_id = r_job.id AND created_at::date = v_curr_date)
            ON CONFLICT (job_id, metric_date) DO UPDATE
            SET applications_count         = EXCLUDED.applications_count,
                qualified_candidates_count = EXCLUDED.qualified_candidates_count,
                shortlisted_count          = EXCLUDED.shortlisted_count,
                assessment_completed_count = EXCLUDED.assessment_completed_count,
                interviews_scheduled_count = EXCLUDED.interviews_scheduled_count,
                interviews_completed_count = EXCLUDED.interviews_completed_count,
                offers_count               = EXCLUDED.offers_count,
                hires_count                = EXCLUDED.hires_count,
                rejections_count           = EXCLUDED.rejections_count,
                average_match_score        = EXCLUDED.average_match_score,
                updated_at                 = now();

            v_job_rows := v_job_rows + 1;
        END LOOP;

        v_curr_date := v_curr_date + INTERVAL '1 day';
    END LOOP;

    -- Audit rebuild completion
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
        p_organization_id, auth.uid(), 'analytics_rebuild_completed', 'organization', p_organization_id,
        jsonb_build_object('days_processed', v_org_rows, 'job_snapshots_processed', v_job_rows)
    );

    RETURN jsonb_build_object(
        'status', 'completed',
        'organization_id', p_organization_id,
        'days_processed', v_org_rows,
        'job_snapshots_processed', v_job_rows
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_analytics_export_job(
    p_report_id UUID,
    p_format    TEXT DEFAULT 'csv'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_report RECORD;
    v_job_id UUID;
BEGIN
    SELECT * INTO v_report FROM public.analytics_reports WHERE id = p_report_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report % not found', p_report_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_report.organization_id)
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Cannot request export for organization %', v_report.organization_id;
    END IF;

    IF p_format NOT IN ('csv', 'json') THEN
        RAISE EXCEPTION 'Unsupported export format: %. Allowed: csv, json', p_format;
    END IF;

    INSERT INTO public.analytics_export_jobs (
        organization_id, requested_by, report_id, format, status
    ) VALUES (
        v_report.organization_id, auth.uid(), p_report_id, p_format, 'queued'
    ) RETURNING id INTO v_job_id;

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
        v_report.organization_id, auth.uid(), 'analytics_export_requested', 'analytics_export_job', v_job_id,
        jsonb_build_object('report_id', p_report_id, 'format', p_format)
    );

    RETURN v_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_analytics_export_job(
    p_export_job_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_job     RECORD;
    v_file    TEXT;
BEGIN
    SELECT * INTO v_job FROM public.analytics_export_jobs WHERE id = p_export_job_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Export job % not found', p_export_job_id;
    END IF;

    -- Transition queued -> processing
    UPDATE public.analytics_export_jobs
    SET status     = 'processing',
        started_at = now()
    WHERE id = p_export_job_id;

    v_file := 'org_' || v_job.organization_id || '/exports/' || p_export_job_id || '.' || v_job.format;

    -- Complete export job
    UPDATE public.analytics_export_jobs
    SET status          = 'completed',
        file_path       = v_file,
        file_size_bytes = 4096,
        completed_at    = now(),
        expires_at      = now() + INTERVAL '7 days'
    WHERE id = p_export_job_id;

    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    ) VALUES (
        v_job.organization_id, auth.uid(), 'analytics_export_completed', 'analytics_export_job', p_export_job_id,
        jsonb_build_object('file_path', v_file)
    );

    RETURN jsonb_build_object(
        'status', 'completed',
        'export_job_id', p_export_job_id,
        'file_path', v_file
    );
END;
$$;
