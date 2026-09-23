-- =============================================================================
-- Migration: 20260915001405_drop_obsolete_get_org_analytics.sql
-- Fix: Drop old 4-argument get_organization_analytics overload to prevent 42725 ambiguity
-- =============================================================================

DROP FUNCTION IF EXISTS public.get_organization_analytics(uuid, uuid, timestamp with time zone, timestamp with time zone);
