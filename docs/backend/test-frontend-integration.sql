-- ============================================================================
-- Hiren Beyond Backend -- Task 23 Test Suite
-- Frontend Integration Contract Helper RPCs
-- ============================================================================

WITH rpc_checks AS (
    SELECT 'Test 01: get_user_organizations exists SECURITY DEFINER' AS test_name,
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_user_organizations' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END AS result
    UNION ALL
    SELECT 'Test 02: get_user_permissions exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_user_permissions' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 03: get_my_profile exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_my_profile' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 04: update_my_profile exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='update_my_profile' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 05: get_notification_badge_count exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_notification_badge_count' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 06: get_frontend_config exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_frontend_config' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 07: mark_notification_read returns TABLE (proretset=true)',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_notification_read'
              AND p.prosecdef=true AND p.proretset=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 08: mark_all_notifications_read returns TABLE (proretset=true)',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_all_notifications_read'
              AND p.prosecdef=true AND p.proretset=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 09: list_notifications returns TABLE (proretset=true)',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='list_notifications'
              AND p.prosecdef=true AND p.proretset=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 10: get_organization_summary exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_organization_summary' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 11: get_dashboard_metrics exists SECURITY DEFINER',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_dashboard_metrics' AND p.prosecdef=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 12: get_user_organizations return type includes organization_id',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_user_organizations'
              AND pg_get_function_result(p.oid) LIKE '%organization_id%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 13: list_notifications return type includes has_more and next_cursor',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='list_notifications'
              AND pg_get_function_result(p.oid) LIKE '%has_more%'
              AND pg_get_function_result(p.oid) LIKE '%next_cursor%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 14: mark_notification_read return type includes success and notification_id',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_notification_read'
              AND pg_get_function_result(p.oid) LIKE '%success%'
              AND pg_get_function_result(p.oid) LIKE '%notification_id%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 15: mark_all_notifications_read return type includes success and updated_count',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_all_notifications_read'
              AND pg_get_function_result(p.oid) LIKE '%success%'
              AND pg_get_function_result(p.oid) LIKE '%updated_count%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 16: get_organization_summary return type includes active_jobs_count',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_organization_summary'
              AND pg_get_function_result(p.oid) LIKE '%active_jobs_count%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 17: get_dashboard_metrics return type includes metric_name and trend_direction',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_dashboard_metrics'
              AND pg_get_function_result(p.oid) LIKE '%metric_name%'
              AND pg_get_function_result(p.oid) LIKE '%trend_direction%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 18: get_frontend_config callable (no auth required)',
        CASE WHEN (SELECT COUNT(*) >= 0 FROM public.get_frontend_config())
        THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 19: All 11 Task 23 RPCs are SECURITY DEFINER',
        CASE WHEN (
            SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public'
              AND p.proname IN (
                'get_user_organizations','get_user_permissions','get_my_profile',
                'update_my_profile','get_notification_badge_count','get_frontend_config',
                'mark_notification_read','mark_all_notifications_read','list_notifications',
                'get_organization_summary','get_dashboard_metrics'
              ) AND p.prosecdef=true
        ) = 11 THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 20: mark_notification_read no longer returns VOID',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_notification_read'
              AND p.prorettype != 'void'::regtype::oid
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 21: mark_all_notifications_read no longer returns INT',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_all_notifications_read'
              AND p.proretset=true
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 22: get_notification_badge_count return includes unread_count',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_notification_badge_count'
              AND pg_get_function_result(p.oid) LIKE '%unread_count%'
              AND pg_get_function_result(p.oid) LIKE '%has_urgent%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 23: list_notifications body uses recipient_user_id (correct column)',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='list_notifications'
              AND pg_get_functiondef(p.oid) LIKE '%recipient_user_id%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 24: mark_notification_read body uses recipient_user_id (correct column)',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='mark_notification_read'
              AND pg_get_functiondef(p.oid) LIKE '%recipient_user_id%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 25: get_my_profile return type includes email column',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_my_profile'
              AND pg_get_function_result(p.oid) LIKE '%email%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 26: update_my_profile return type includes success and updated_at',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='update_my_profile'
              AND pg_get_function_result(p.oid) LIKE '%success%'
              AND pg_get_function_result(p.oid) LIKE '%updated_at%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 27: get_user_organizations return includes role_name and role_display_name',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_user_organizations'
              AND pg_get_function_result(p.oid) LIKE '%role_name%'
              AND pg_get_function_result(p.oid) LIKE '%role_display_name%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 28: get_organization_summary return includes pending_applications',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_organization_summary'
              AND pg_get_function_result(p.oid) LIKE '%pending_applications%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 29: get_dashboard_metrics return includes metric_value and trend_delta',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_dashboard_metrics'
              AND pg_get_function_result(p.oid) LIKE '%metric_value%'
              AND pg_get_function_result(p.oid) LIKE '%trend_delta%'
        ) THEN 'PASS' ELSE 'FAIL' END
    UNION ALL
    SELECT 'Test 30: get_user_permissions return includes permission_key and category',
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
            WHERE n.nspname='public' AND p.proname='get_user_permissions'
              AND pg_get_function_result(p.oid) LIKE '%permission_key%'
              AND pg_get_function_result(p.oid) LIKE '%category%'
        ) THEN 'PASS' ELSE 'FAIL' END
),
summary AS (
    SELECT test_name, result, ROW_NUMBER() OVER (ORDER BY test_name) AS n
    FROM rpc_checks
)
SELECT
    n,
    test_name,
    result,
    CASE result WHEN 'PASS' THEN 'ok' ELSE '*** FAILED ***' END AS status
FROM summary
ORDER BY n;
