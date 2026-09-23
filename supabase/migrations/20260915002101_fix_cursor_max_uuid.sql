-- ============================================================================
-- Hiren Beyond Backend — Migration 20260915002101
-- Fix get_applications_cursor: cast uuid to text inside max() aggregate
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_applications_cursor(
    p_organization_id UUID,
    p_job_id UUID DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_cursor TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_limit INT := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_cursor_ts TIMESTAMPTZ := NULL;
    v_cursor_id UUID := NULL;
    v_items JSONB := '[]'::jsonb;
    v_next_cursor TEXT := NULL;
    v_has_more BOOLEAN := false;
    v_last_ts TIMESTAMPTZ;
    v_last_id UUID;
BEGIN
    IF p_cursor IS NOT NULL AND btrim(p_cursor) <> '' THEN
        SELECT cursor_created_at, cursor_id 
        INTO v_cursor_ts, v_cursor_id
        FROM public.decode_pagination_cursor(p_cursor);
    END IF;

    WITH app_rows AS (
        SELECT 
            a.id,
            a.job_id,
            a.candidate_id,
            a.organization_id,
            a.status,
            a.current_stage_id,
            a.match_score,
            a.created_at
        FROM public.applications a
        WHERE a.organization_id = p_organization_id
          AND (p_job_id IS NULL OR a.job_id = p_job_id)
          AND (p_status IS NULL OR a.status = p_status)
          AND (
              v_cursor_ts IS NULL 
              OR (a.created_at, a.id) < (v_cursor_ts, v_cursor_id)
          )
        ORDER BY a.created_at DESC, a.id DESC
        LIMIT (v_limit + 1)
    )
    SELECT 
        COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', r.id,
                'job_id', r.job_id,
                'candidate_id', r.candidate_id,
                'organization_id', r.organization_id,
                'status', r.status,
                'current_stage_id', r.current_stage_id,
                'match_score', r.match_score,
                'created_at', r.created_at
            )
        ) FILTER (WHERE rn <= v_limit), '[]'::jsonb),
        bool_or(rn > v_limit),
        max(r.created_at) FILTER (WHERE rn = v_limit),
        (max(r.id::text) FILTER (WHERE rn = v_limit))::uuid
    INTO v_items, v_has_more, v_last_ts, v_last_id
    FROM (
        SELECT *, row_number() OVER () AS rn 
        FROM app_rows
    ) r;

    IF v_has_more AND v_last_ts IS NOT NULL AND v_last_id IS NOT NULL THEN
        v_next_cursor := public.encode_pagination_cursor(v_last_ts, v_last_id);
    END IF;

    RETURN jsonb_build_object(
        'items', COALESCE(v_items, '[]'::jsonb),
        'has_more', COALESCE(v_has_more, false),
        'next_cursor', v_next_cursor,
        'limit', v_limit
    );
END;
$$;
