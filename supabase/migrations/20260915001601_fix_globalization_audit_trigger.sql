-- Migration: 20260915001601_fix_globalization_audit_trigger.sql
-- Description: Fix audit trigger for organization_locales to use correct audit_logs column names
--              (actor_user_id not user_id, metadata not details)

CREATE OR REPLACE FUNCTION public.audit_organization_locale_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.audit_logs (
        organization_id,
        actor_user_id,
        action,
        entity_type,
        entity_id,
        metadata
    ) VALUES (
        NEW.organization_id,
        auth.uid(),
        'organization_locale_updated',
        'organization_locales',
        NEW.id,
        jsonb_build_object(
            'default_language_code', NEW.default_language_code,
            'default_currency_code', NEW.default_currency_code,
            'default_timezone', NEW.default_timezone,
            'default_country_code', NEW.default_country_code
        )
    );
    RETURN NEW;
END;
$$;
