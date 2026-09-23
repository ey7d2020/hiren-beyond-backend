-- ============================================================================
-- Hiren Beyond Backend -- Migration 20260915002301
-- Task 23 Fix: get_frontend_config
-- Use correct table: platform_settings (columns: key, value, value_type, is_public)
-- ============================================================================

-- Drop and recreate with correct table reference
DROP FUNCTION IF EXISTS public.get_frontend_config();

CREATE OR REPLACE FUNCTION public.get_frontend_config()
RETURNS TABLE (
    config_key   TEXT,
    config_value TEXT,
    value_type   TEXT,
    description  TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ps.key::TEXT         AS config_key,
        ps.value::TEXT       AS config_value,
        ps.value_type::TEXT  AS value_type,
        ps.description::TEXT AS description
    FROM public.platform_settings ps
    WHERE ps.is_public    = TRUE
      AND ps.is_sensitive = FALSE
    ORDER BY ps.key;
END;
$$;

COMMENT ON FUNCTION public.get_frontend_config IS
    'Returns safe public platform configuration from platform_settings. Accessible without authentication.';

GRANT EXECUTE ON FUNCTION public.get_frontend_config() TO anon, authenticated;
