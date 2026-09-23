-- Migration: 20260915001600_globalization_localization.sql
-- Description: Task 16 - Globalization, Localization, Countries, Languages, Currencies, Timezones & International Recruitment Support

-- ============================================================================
-- 1. REFERENCE DATA: COUNTRIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.countries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iso2 VARCHAR(2) NOT NULL UNIQUE,
    iso3 VARCHAR(3) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    native_name VARCHAR(255),
    phone_code VARCHAR(20),
    region VARCHAR(100),
    subregion VARCHAR(100),
    currency_code VARCHAR(3),
    default_timezone VARCHAR(100),
    data_region VARCHAR(20) DEFAULT 'MENA', -- EU, MENA, US, APAC
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_countries_iso2 ON public.countries(iso2);
CREATE INDEX IF NOT EXISTS idx_countries_iso3 ON public.countries(iso3);
CREATE INDEX IF NOT EXISTS idx_countries_is_active ON public.countries(is_active);

-- ============================================================================
-- 2. REFERENCE DATA: REGIONS / STATES / PROVINCES / GOVERNORATES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.regions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_id UUID NOT NULL REFERENCES public.countries(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'state', -- state, province, governorate, emirate, region, territory
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(country_id, code)
);

CREATE INDEX IF NOT EXISTS idx_regions_country_id ON public.regions(country_id);
CREATE INDEX IF NOT EXISTS idx_regions_code ON public.regions(code);

-- ============================================================================
-- 3. REFERENCE DATA: CITIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.cities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_id UUID NOT NULL REFERENCES public.countries(id) ON DELETE CASCADE,
    region_id UUID REFERENCES public.regions(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    latitude NUMERIC(10,7),
    longitude NUMERIC(10,7),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cities_country_id ON public.cities(country_id);
CREATE INDEX IF NOT EXISTS idx_cities_region_id ON public.cities(region_id);
CREATE INDEX IF NOT EXISTS idx_cities_name ON public.cities(name);

-- ============================================================================
-- 4. REFERENCE DATA: LANGUAGES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    native_name VARCHAR(100),
    iso639_1 VARCHAR(2),
    iso639_3 VARCHAR(3),
    direction VARCHAR(3) NOT NULL CHECK (direction IN ('ltr', 'rtl')) DEFAULT 'ltr',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_languages_code ON public.languages(code);
CREATE INDEX IF NOT EXISTS idx_languages_direction ON public.languages(direction);

-- ============================================================================
-- 5. REFERENCE DATA: LANGUAGE PROFICIENCY LEVELS (CENTRALIZED CEFR)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.language_proficiency_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    numeric_level INT NOT NULL,
    framework VARCHAR(50) NOT NULL DEFAULT 'CEFR',
    sort_order INT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_language_proficiency_code ON public.language_proficiency_levels(code);

-- ============================================================================
-- 6. REFERENCE DATA: CURRENCIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.currencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(3) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    minor_unit INT NOT NULL DEFAULT 2,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_currencies_code ON public.currencies(code);

-- ============================================================================
-- 7. REFERENCE DATA: EXCHANGE RATES FOUNDATION
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.exchange_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_currency VARCHAR(3) NOT NULL REFERENCES public.currencies(code) ON DELETE RESTRICT,
    quote_currency VARCHAR(3) NOT NULL REFERENCES public.currencies(code) ON DELETE RESTRICT,
    rate NUMERIC(18,6) NOT NULL CHECK (rate > 0),
    source VARCHAR(100) NOT NULL DEFAULT 'REFERENCE_MANUAL',
    effective_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_pair ON public.exchange_rates(base_currency, quote_currency, effective_at DESC);

-- ============================================================================
-- 8. REFERENCE DATA: TIMEZONES (IANA STANDARDS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.timezones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iana_name VARCHAR(100) NOT NULL UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    utc_offset VARCHAR(10) NOT NULL,
    country_code VARCHAR(2) REFERENCES public.countries(iso2) ON DELETE SET NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_timezones_iana_name ON public.timezones(iana_name);
CREATE INDEX IF NOT EXISTS idx_timezones_country_code ON public.timezones(country_code);

-- ============================================================================
-- 9. TENANT CONFIGURATION: ORGANIZATION LOCALES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.organization_locales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL UNIQUE REFERENCES public.organizations(id) ON DELETE CASCADE,
    default_language_code VARCHAR(10) NOT NULL REFERENCES public.languages(code) DEFAULT 'en',
    default_currency_code VARCHAR(3) NOT NULL REFERENCES public.currencies(code) DEFAULT 'USD',
    default_timezone VARCHAR(100) NOT NULL REFERENCES public.timezones(iana_name) DEFAULT 'UTC',
    default_country_code VARCHAR(2) REFERENCES public.countries(iso2) ON DELETE SET NULL,
    date_format VARCHAR(50) NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format VARCHAR(50) NOT NULL DEFAULT '24h',
    number_format JSONB NOT NULL DEFAULT '{"decimal_separator": ".", "thousands_separator": ","}'::jsonb,
    first_day_of_week VARCHAR(10) NOT NULL CHECK (first_day_of_week IN ('Saturday', 'Sunday', 'Monday')) DEFAULT 'Monday',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_org_locales_org_id ON public.organization_locales(organization_id);

-- ============================================================================
-- 10. USER CONFIGURATION: USER LOCALES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_locales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    language_code VARCHAR(10) REFERENCES public.languages(code) ON DELETE SET NULL,
    currency_code VARCHAR(3) REFERENCES public.currencies(code) ON DELETE SET NULL,
    timezone VARCHAR(100) REFERENCES public.timezones(iana_name) ON DELETE SET NULL,
    date_format VARCHAR(50),
    time_format VARCHAR(50),
    first_day_of_week VARCHAR(10) CHECK (first_day_of_week IN ('Saturday', 'Sunday', 'Monday')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_locales_user_id ON public.user_locales(user_id);

-- ============================================================================
-- 11. ORGANIZATION SUPPORTED MARKETS (COUNTRIES, LANGUAGES, CURRENCIES)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.organization_supported_countries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    country_code VARCHAR(2) NOT NULL REFERENCES public.countries(iso2) ON DELETE CASCADE,
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(organization_id, country_code)
);

CREATE TABLE IF NOT EXISTS public.organization_supported_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    language_code VARCHAR(10) NOT NULL REFERENCES public.languages(code) ON DELETE CASCADE,
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(organization_id, language_code)
);

CREATE TABLE IF NOT EXISTS public.organization_supported_currencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    currency_code VARCHAR(3) NOT NULL REFERENCES public.currencies(code) ON DELETE CASCADE,
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(organization_id, currency_code)
);

CREATE INDEX IF NOT EXISTS idx_org_supp_countries ON public.organization_supported_countries(organization_id, country_code);
CREATE INDEX IF NOT EXISTS idx_org_supp_languages ON public.organization_supported_languages(organization_id, language_code);
CREATE INDEX IF NOT EXISTS idx_org_supp_currencies ON public.organization_supported_currencies(organization_id, currency_code);

-- ============================================================================
-- 12. COMPLIANCE & REGIONAL POLICY FOUNDATION
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.regional_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_code VARCHAR(2) NOT NULL REFERENCES public.countries(iso2) ON DELETE CASCADE,
    policy_key VARCHAR(100) NOT NULL,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(country_code, policy_key, version)
);

CREATE INDEX IF NOT EXISTS idx_regional_policies_lookup ON public.regional_policies(country_code, policy_key, status);

-- ============================================================================
-- 13. LOCALIZATION DICTIONARY & CONTENT TRANSLATION
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.localization_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(255) NOT NULL UNIQUE,
    namespace VARCHAR(100) NOT NULL DEFAULT 'common',
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.localization_translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    localization_key_id UUID NOT NULL REFERENCES public.localization_keys(id) ON DELETE CASCADE,
    language_code VARCHAR(10) NOT NULL REFERENCES public.languages(code) ON DELETE CASCADE,
    value TEXT NOT NULL,
    version INT NOT NULL DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'published',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(localization_key_id, language_code, version)
);

CREATE INDEX IF NOT EXISTS idx_loc_translations_lookup ON public.localization_translations(localization_key_id, language_code, status);

-- ============================================================================
-- 14. SEED INITIAL CANONICAL REFERENCE DATA
-- ============================================================================

-- Currencies
INSERT INTO public.currencies (code, name, symbol, minor_unit, is_active)
VALUES
    ('USD', 'US Dollar', '$', 2, true),
    ('EUR', 'Euro', '€', 2, true),
    ('GBP', 'British Pound', '£', 2, true),
    ('EGP', 'Egyptian Pound', 'E£', 2, true),
    ('SAR', 'Saudi Riyal', '﷼', 2, true),
    ('AED', 'United Arab Emirates Dirham', 'د.إ', 2, true),
    ('QAR', 'Qatari Riyal', '﷼', 2, true),
    ('KWD', 'Kuwaiti Dinar', 'د.ك', 3, true),
    ('CAD', 'Canadian Dollar', 'CA$', 2, true),
    ('AUD', 'Australian Dollar', 'A$', 2, true),
    ('INR', 'Indian Rupee', '₹', 2, true),
    ('SGD', 'Singapore Dollar', 'S$', 2, true)
ON CONFLICT (code) DO UPDATE 
SET name = EXCLUDED.name, symbol = EXCLUDED.symbol, minor_unit = EXCLUDED.minor_unit;

-- Timezones (Representative global and MENA set)
INSERT INTO public.timezones (iana_name, display_name, utc_offset, is_active)
VALUES
    ('UTC', 'Coordinated Universal Time', '+00:00', true),
    ('Africa/Cairo', 'Cairo (Egypt Standard Time)', '+02:00', true),
    ('Asia/Riyadh', 'Riyadh (Arabia Standard Time)', '+03:00', true),
    ('Asia/Dubai', 'Dubai (Gulf Standard Time)', '+04:00', true),
    ('Asia/Kuwait', 'Kuwait City (Arabia Standard Time)', '+03:00', true),
    ('Asia/Qatar', 'Doha (Arabia Standard Time)', '+03:00', true),
    ('Europe/London', 'London (GMT / BST)', '+00:00', true),
    ('Europe/Berlin', 'Berlin (Central European Time)', '+01:00', true),
    ('Europe/Paris', 'Paris (Central European Time)', '+01:00', true),
    ('America/New_York', 'New York (Eastern Time)', '-05:00', true),
    ('America/Chicago', 'Chicago (Central Time)', '-06:00', true),
    ('America/Los_Angeles', 'Los Angeles (Pacific Time)', '-08:00', true),
    ('Asia/Kolkata', 'India Standard Time', '+05:30', true),
    ('Asia/Singapore', 'Singapore Standard Time', '+08:00', true)
ON CONFLICT (iana_name) DO UPDATE 
SET display_name = EXCLUDED.display_name, utc_offset = EXCLUDED.utc_offset;

-- Countries
INSERT INTO public.countries (iso2, iso3, name, native_name, phone_code, region, subregion, currency_code, default_timezone, data_region, is_active, sort_order)
VALUES
    ('EG', 'EGY', 'Egypt', 'مصر', '+20', 'Africa', 'Northern Africa', 'EGP', 'Africa/Cairo', 'MENA', true, 10),
    ('SA', 'SAU', 'Saudi Arabia', 'المملكة العربية السعودية', '+966', 'Asia', 'Western Asia', 'SAR', 'Asia/Riyadh', 'MENA', true, 20),
    ('AE', 'ARE', 'United Arab Emirates', 'الإمارات العربية المتحدة', '+971', 'Asia', 'Western Asia', 'AED', 'Asia/Dubai', 'MENA', true, 30),
    ('QA', 'QAT', 'Qatar', 'قطر', '+974', 'Asia', 'Western Asia', 'QAR', 'Asia/Qatar', 'MENA', true, 40),
    ('KW', 'KWT', 'Kuwait', 'الكويت', '+965', 'Asia', 'Western Asia', 'KWD', 'Asia/Kuwait', 'MENA', true, 50),
    ('US', 'USA', 'United States', 'United States', '+1', 'Americas', 'Northern America', 'USD', 'America/New_York', 'US', true, 60),
    ('GB', 'GBR', 'United Kingdom', 'United Kingdom', '+44', 'Europe', 'Northern Europe', 'GBP', 'Europe/London', 'EU', true, 70),
    ('DE', 'DEU', 'Germany', 'Deutschland', '+49', 'Europe', 'Western Europe', 'EUR', 'Europe/Berlin', 'EU', true, 80),
    ('FR', 'FRA', 'France', 'France', '+33', 'Europe', 'Western Europe', 'EUR', 'Europe/Paris', 'EU', true, 90),
    ('IN', 'IND', 'India', 'भारत', '+91', 'Asia', 'Southern Asia', 'INR', 'Asia/Kolkata', 'APAC', true, 100),
    ('SG', 'SGP', 'Singapore', 'Singapore', '+65', 'Asia', 'South-Eastern Asia', 'SGD', 'Asia/Singapore', 'APAC', true, 110),
    ('CA', 'CAN', 'Canada', 'Canada', '+1', 'Americas', 'Northern America', 'CAD', 'America/New_York', 'US', true, 120)
ON CONFLICT (iso2) DO UPDATE 
SET iso3 = EXCLUDED.iso3, name = EXCLUDED.name, currency_code = EXCLUDED.currency_code, default_timezone = EXCLUDED.default_timezone, data_region = EXCLUDED.data_region;

-- Link timezones to country_code
UPDATE public.timezones SET country_code = 'EG' WHERE iana_name = 'Africa/Cairo';
UPDATE public.timezones SET country_code = 'SA' WHERE iana_name = 'Asia/Riyadh';
UPDATE public.timezones SET country_code = 'AE' WHERE iana_name = 'Asia/Dubai';
UPDATE public.timezones SET country_code = 'QA' WHERE iana_name = 'Asia/Qatar';
UPDATE public.timezones SET country_code = 'KW' WHERE iana_name = 'Asia/Kuwait';
UPDATE public.timezones SET country_code = 'GB' WHERE iana_name = 'Europe/London';
UPDATE public.timezones SET country_code = 'DE' WHERE iana_name = 'Europe/Berlin';
UPDATE public.timezones SET country_code = 'FR' WHERE iana_name = 'Europe/Paris';
UPDATE public.timezones SET country_code = 'US' WHERE iana_name IN ('America/New_York', 'America/Chicago', 'America/Los_Angeles');
UPDATE public.timezones SET country_code = 'IN' WHERE iana_name = 'Asia/Kolkata';
UPDATE public.timezones SET country_code = 'SG' WHERE iana_name = 'Asia/Singapore';

-- Languages
INSERT INTO public.languages (code, name, native_name, iso639_1, iso639_3, direction, is_active)
VALUES
    ('en', 'English', 'English', 'en', 'eng', 'ltr', true),
    ('ar', 'Arabic', 'العربية', 'ar', 'ara', 'rtl', true),
    ('fr', 'French', 'Français', 'fr', 'fra', 'ltr', true),
    ('de', 'German', 'Deutsch', 'de', 'deu', 'ltr', true),
    ('es', 'Spanish', 'Español', 'es', 'spa', 'ltr', true),
    ('hi', 'Hindi', 'हिन्दी', 'hi', 'hin', 'ltr', true),
    ('zh', 'Chinese', '中文', 'zh', 'zho', 'ltr', true)
ON CONFLICT (code) DO UPDATE 
SET name = EXCLUDED.name, native_name = EXCLUDED.native_name, direction = EXCLUDED.direction;

-- Language Proficiency Levels (Canonical CEFR Scale matching Task 06 & Task 08)
INSERT INTO public.language_proficiency_levels (code, name, numeric_level, framework, sort_order)
VALUES
    ('A1', 'A1 - Beginner', 1, 'CEFR', 10),
    ('A2', 'A2 - Elementary', 2, 'CEFR', 20),
    ('B1', 'B1 - Intermediate', 3, 'CEFR', 30),
    ('B2', 'B2 - Upper Intermediate', 4, 'CEFR', 40),
    ('C1', 'C1 - Advanced', 5, 'CEFR', 50),
    ('C2', 'C2 - Mastery / Proficient', 6, 'CEFR', 60),
    ('NATIVE', 'Native / Bilingual', 7, 'CEFR', 70)
ON CONFLICT (code) DO UPDATE
SET numeric_level = EXCLUDED.numeric_level, name = EXCLUDED.name, sort_order = EXCLUDED.sort_order;

-- Sample Reference Regions
DO $$
DECLARE
    v_eg_id UUID;
    v_sa_id UUID;
    v_ae_id UUID;
    v_us_id UUID;
    v_cairo_reg_id UUID;
    v_alex_reg_id UUID;
    v_riyadh_reg_id UUID;
    v_dubai_reg_id UUID;
BEGIN
    SELECT id INTO v_eg_id FROM public.countries WHERE iso2 = 'EG';
    SELECT id INTO v_sa_id FROM public.countries WHERE iso2 = 'SA';
    SELECT id INTO v_ae_id FROM public.countries WHERE iso2 = 'AE';
    SELECT id INTO v_us_id FROM public.countries WHERE iso2 = 'US';

    IF v_eg_id IS NOT NULL THEN
        INSERT INTO public.regions (country_id, code, name, type)
        VALUES 
            (v_eg_id, 'CAI', 'Cairo Governorate', 'governorate'),
            (v_eg_id, 'ALX', 'Alexandria Governorate', 'governorate'),
            (v_eg_id, 'GZA', 'Giza Governorate', 'governorate')
        ON CONFLICT (country_id, code) DO UPDATE SET name = EXCLUDED.name;

        SELECT id INTO v_cairo_reg_id FROM public.regions WHERE country_id = v_eg_id AND code = 'CAI';
        SELECT id INTO v_alex_reg_id FROM public.regions WHERE country_id = v_eg_id AND code = 'ALX';

        IF v_cairo_reg_id IS NOT NULL THEN
            INSERT INTO public.cities (country_id, region_id, name, latitude, longitude)
            VALUES (v_eg_id, v_cairo_reg_id, 'Cairo', 30.0444, 31.2357),
                   (v_eg_id, v_cairo_reg_id, 'New Cairo', 30.0300, 31.4700)
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    IF v_sa_id IS NOT NULL THEN
        INSERT INTO public.regions (country_id, code, name, type)
        VALUES 
            (v_sa_id, 'RIY', 'Riyadh Province', 'province'),
            (v_sa_id, 'MKH', 'Makkah Province', 'province'),
            (v_sa_id, 'EAS', 'Eastern Province', 'province')
        ON CONFLICT (country_id, code) DO UPDATE SET name = EXCLUDED.name;

        SELECT id INTO v_riyadh_reg_id FROM public.regions WHERE country_id = v_sa_id AND code = 'RIY';
        IF v_riyadh_reg_id IS NOT NULL THEN
            INSERT INTO public.cities (country_id, region_id, name, latitude, longitude)
            VALUES (v_sa_id, v_riyadh_reg_id, 'Riyadh', 24.7136, 46.6753)
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    IF v_ae_id IS NOT NULL THEN
        INSERT INTO public.regions (country_id, code, name, type)
        VALUES 
            (v_ae_id, 'DXB', 'Emirate of Dubai', 'emirate'),
            (v_ae_id, 'AUH', 'Emirate of Abu Dhabi', 'emirate')
        ON CONFLICT (country_id, code) DO UPDATE SET name = EXCLUDED.name;

        SELECT id INTO v_dubai_reg_id FROM public.regions WHERE country_id = v_ae_id AND code = 'DXB';
        IF v_dubai_reg_id IS NOT NULL THEN
            INSERT INTO public.cities (country_id, region_id, name, latitude, longitude)
            VALUES (v_ae_id, v_dubai_reg_id, 'Dubai', 25.2048, 55.2708)
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;
END $$;

-- Sample Exchange Rates
INSERT INTO public.exchange_rates (base_currency, quote_currency, rate, source)
VALUES
    ('USD', 'EGP', 48.500000, 'CENTRAL_BANK_OF_EGYPT'),
    ('USD', 'SAR', 3.750000, 'SAMA_FIXED_PEG'),
    ('USD', 'AED', 3.672500, 'CBUAE_FIXED_PEG'),
    ('USD', 'EUR', 0.920000, 'ECB_REFERENCE'),
    ('USD', 'GBP', 0.780000, 'BOE_REFERENCE'),
    ('EGP', 'USD', 0.020619, 'DERIVED'),
    ('SAR', 'USD', 0.266667, 'DERIVED'),
    ('AED', 'USD', 0.272294, 'DERIVED')
ON CONFLICT DO NOTHING;

-- Initial Localization Keys & Translations
DO $$
DECLARE
    v_k1 UUID;
    v_k2 UUID;
    v_k3 UUID;
BEGIN
    INSERT INTO public.localization_keys (key, namespace, description)
    VALUES ('common.welcome', 'common', 'Standard greeting')
    ON CONFLICT (key) DO UPDATE SET namespace = EXCLUDED.namespace
    RETURNING id INTO v_k1;

    INSERT INTO public.localization_keys (key, namespace, description)
    VALUES ('job.status.active', 'recruitment', 'Active job posting status label')
    ON CONFLICT (key) DO UPDATE SET namespace = EXCLUDED.namespace
    RETURNING id INTO v_k2;

    INSERT INTO public.localization_keys (key, namespace, description)
    VALUES ('interview.scheduled', 'interviews', 'Notification for interview scheduled')
    ON CONFLICT (key) DO UPDATE SET namespace = EXCLUDED.namespace
    RETURNING id INTO v_k3;

    IF v_k1 IS NOT NULL THEN
        INSERT INTO public.localization_translations (localization_key_id, language_code, value)
        VALUES 
            (v_k1, 'en', 'Welcome to Hiren Beyond'),
            (v_k1, 'ar', 'مرحباً بكم في هايرين بيوند')
        ON CONFLICT (localization_key_id, language_code, version) DO UPDATE SET value = EXCLUDED.value;
    END IF;

    IF v_k2 IS NOT NULL THEN
        INSERT INTO public.localization_translations (localization_key_id, language_code, value)
        VALUES 
            (v_k2, 'en', 'Active'),
            (v_k2, 'ar', 'نشط')
        ON CONFLICT (localization_key_id, language_code, version) DO UPDATE SET value = EXCLUDED.value;
    END IF;
END $$;

-- ============================================================================
-- 15. ADDITIVE FIELDS & NORMALIZATION ON EXISTING TABLES
-- ============================================================================

-- Additive canonical columns to jobs table
ALTER TABLE public.jobs
    ADD COLUMN IF NOT EXISTS country_code VARCHAR(2) REFERENCES public.countries(iso2) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES public.regions(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS city_id UUID REFERENCES public.cities(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS remote_restrictions JSONB NOT NULL DEFAULT '{"mode": "any", "allowed_countries": [], "allowed_regions": [], "excluded_countries": [], "timezones": []}'::jsonb,
    ADD COLUMN IF NOT EXISTS localized_content JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_jobs_country_code ON public.jobs(country_code);
CREATE INDEX IF NOT EXISTS idx_jobs_city_id ON public.jobs(city_id);

-- Additive canonical columns to candidate_profiles table
ALTER TABLE public.candidate_profiles
    ADD COLUMN IF NOT EXISTS canonical_country_code VARCHAR(2) REFERENCES public.countries(iso2) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES public.regions(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS city_id UUID REFERENCES public.cities(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS preferred_locations JSONB NOT NULL DEFAULT '{"countries": [], "regions": [], "cities": [], "timezones": []}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_candidate_profiles_canonical_country ON public.candidate_profiles(canonical_country_code);

-- Additive canonical references to candidate_languages table
ALTER TABLE public.candidate_languages
    ADD COLUMN IF NOT EXISTS language_id UUID REFERENCES public.languages(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS proficiency_level_id UUID REFERENCES public.language_proficiency_levels(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_cand_lang_language_id ON public.candidate_languages(language_id);
CREATE INDEX IF NOT EXISTS idx_cand_lang_prof_id ON public.candidate_languages(proficiency_level_id);

-- ============================================================================
-- 16. UNAMBIGUOUS DATA MIGRATION & BACKFILL HELPER
-- ============================================================================
CREATE OR REPLACE FUNCTION public.normalize_country_code(p_input TEXT)
RETURNS VARCHAR(2)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_clean TEXT;
BEGIN
    IF p_input IS NULL OR trim(p_input) = '' THEN
        RETURN NULL;
    END IF;

    v_clean := upper(trim(p_input));

    -- If 2-character ISO code already matches
    IF EXISTS (SELECT 1 FROM public.countries WHERE iso2 = v_clean) THEN
        RETURN v_clean;
    END IF;

    -- If 3-character ISO code matches
    IF EXISTS (SELECT 1 FROM public.countries WHERE iso3 = v_clean) THEN
        SELECT iso2 INTO v_clean FROM public.countries WHERE iso3 = v_clean LIMIT 1;
        RETURN v_clean;
    END IF;

    -- Unambiguous common names
    CASE lower(trim(p_input))
        WHEN 'egypt', 'arab republic of egypt', 'مصر' THEN RETURN 'EG';
        WHEN 'saudi arabia', 'kingdom of saudi arabia', 'ksa', 'السعودية', 'المملكة العربية السعودية' THEN RETURN 'SA';
        WHEN 'united arab emirates', 'uae', 'الإمارات', 'الإمارات العربية المتحدة' THEN RETURN 'AE';
        WHEN 'united states', 'usa', 'united states of america' THEN RETURN 'US';
        WHEN 'united kingdom', 'uk', 'great britain' THEN RETURN 'GB';
        WHEN 'germany', 'deutschland' THEN RETURN 'DE';
        WHEN 'france' THEN RETURN 'FR';
        WHEN 'qatar' THEN RETURN 'QA';
        WHEN 'kuwait' THEN RETURN 'KW';
        WHEN 'india' THEN RETURN 'IN';
        WHEN 'singapore' THEN RETURN 'SG';
        WHEN 'canada' THEN RETURN 'CA';
        ELSE
            -- Do not guess ambiguous or non-standard values (e.g., 'Global', 'MENA', 'Remote')
            RETURN NULL;
    END CASE;
END;
$$;

-- Perform safe, non-destructive backfill for existing jobs
UPDATE public.jobs
SET country_code = public.normalize_country_code(country)
WHERE country_code IS NULL AND country IS NOT NULL;

-- Perform safe backfill for candidate_profiles
UPDATE public.candidate_profiles
SET canonical_country_code = public.normalize_country_code(country_code)
WHERE canonical_country_code IS NULL AND country_code IS NOT NULL;

-- Perform safe backfill for candidate_languages
DO $$
BEGIN
    -- Map language names/codes to language_id
    UPDATE public.candidate_languages cl
    SET language_id = l.id
    FROM public.languages l
    WHERE cl.language_id IS NULL
      AND (
          lower(cl.language_code) = lower(l.code)
          OR lower(cl.language_name) = lower(l.name)
      );

    -- Map proficiency level strings to canonical proficiency_level_id
    UPDATE public.candidate_languages cl
    SET proficiency_level_id = pl.id
    FROM public.language_proficiency_levels pl
    WHERE cl.proficiency_level_id IS NULL
      AND (
          upper(cl.proficiency_level) = pl.code
          OR lower(cl.proficiency_level) = lower(pl.name)
          OR (cl.proficiency_level ILIKE 'native%' AND pl.code = 'NATIVE')
      );
END $$;

-- ============================================================================
-- 17. LOCALIZATION RESOLUTION & HELPER FUNCTIONS
-- ============================================================================

-- Effective locale resolver following the canonical fallback:
-- User locale -> Organization locale -> Platform default ('en', 'USD', 'UTC')
CREATE OR REPLACE FUNCTION public.get_effective_locale(
    p_user_id UUID DEFAULT NULL,
    p_organization_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_lang VARCHAR(10);
    v_user_curr VARCHAR(3);
    v_user_tz VARCHAR(100);
    v_user_df VARCHAR(50);
    v_user_tf VARCHAR(50);
    v_user_fdw VARCHAR(10);

    v_org_lang VARCHAR(10);
    v_org_curr VARCHAR(3);
    v_org_tz VARCHAR(100);
    v_org_country VARCHAR(2);
    v_org_df VARCHAR(50);
    v_org_tf VARCHAR(50);
    v_org_num JSONB;
    v_org_fdw VARCHAR(10);

    v_final_lang VARCHAR(10);
    v_final_curr VARCHAR(3);
    v_final_tz VARCHAR(100);
    v_final_df VARCHAR(50);
    v_final_tf VARCHAR(50);
    v_final_fdw VARCHAR(10);
BEGIN
    -- 1. Fetch user locale if user_id provided
    IF p_user_id IS NOT NULL THEN
        SELECT language_code, currency_code, timezone, date_format, time_format, first_day_of_week
        INTO v_user_lang, v_user_curr, v_user_tz, v_user_df, v_user_tf, v_user_fdw
        FROM public.user_locales
        WHERE user_id = p_user_id;
    END IF;

    -- 2. Fetch organization locale if organization_id provided
    IF p_organization_id IS NOT NULL THEN
        SELECT default_language_code, default_currency_code, default_timezone, default_country_code,
               date_format, time_format, number_format, first_day_of_week
        INTO v_org_lang, v_org_curr, v_org_tz, v_org_country,
             v_org_df, v_org_tf, v_org_num, v_org_fdw
        FROM public.organization_locales
        WHERE organization_id = p_organization_id;
    END IF;

    -- 3. Resolve with fallback
    v_final_lang := COALESCE(v_user_lang, v_org_lang, 'en');
    v_final_curr := COALESCE(v_user_curr, v_org_curr, 'USD');
    v_final_tz   := COALESCE(v_user_tz, v_org_tz, 'UTC');
    v_final_df   := COALESCE(v_user_df, v_org_df, 'YYYY-MM-DD');
    v_final_tf   := COALESCE(v_user_tf, v_org_tf, '24h');
    v_final_fdw  := COALESCE(v_user_fdw, v_org_fdw, 'Monday');

    RETURN jsonb_build_object(
        'language_code', v_final_lang,
        'currency_code', v_final_curr,
        'timezone', v_final_tz,
        'country_code', v_org_country,
        'date_format', v_final_df,
        'time_format', v_final_tf,
        'first_day_of_week', v_final_fdw,
        'number_format', COALESCE(v_org_num, '{"decimal_separator": ".", "thousands_separator": ","}'::jsonb)
    );
END;
$$;

-- Translation dictionary lookup with fallback
CREATE OR REPLACE FUNCTION public.translate_key(
    p_key TEXT,
    p_language_code TEXT DEFAULT 'en',
    p_namespace TEXT DEFAULT 'common'
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_key_id UUID;
    v_translation TEXT;
BEGIN
    SELECT id INTO v_key_id 
    FROM public.localization_keys 
    WHERE key = p_key;

    IF v_key_id IS NULL THEN
        RETURN p_key;
    END IF;

    -- 1. Try requested language
    SELECT value INTO v_translation
    FROM public.localization_translations
    WHERE localization_key_id = v_key_id
      AND language_code = p_language_code
      AND status = 'published'
    ORDER BY version DESC
    LIMIT 1;

    IF v_translation IS NOT NULL THEN
        RETURN v_translation;
    END IF;

    -- 2. Fallback to 'en'
    IF p_language_code <> 'en' THEN
        SELECT value INTO v_translation
        FROM public.localization_translations
        WHERE localization_key_id = v_key_id
          AND language_code = 'en'
          AND status = 'published'
        ORDER BY version DESC
        LIMIT 1;

        IF v_translation IS NOT NULL THEN
            RETURN v_translation;
        END IF;
    END IF;

    -- 3. Return original key if no translation found
    RETURN p_key;
END;
$$;

-- Market restriction check for job publishing
CREATE OR REPLACE FUNCTION public.can_publish_job_in_country(
    p_organization_id UUID,
    p_country_code VARCHAR(2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_has_restrictions BOOLEAN;
BEGIN
    IF p_country_code IS NULL THEN
        RETURN true;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.organization_supported_countries 
        WHERE organization_id = p_organization_id
    ) INTO v_has_restrictions;

    -- If no restriction set, any active country is allowed
    IF NOT v_has_restrictions THEN
        RETURN EXISTS (SELECT 1 FROM public.countries WHERE iso2 = p_country_code AND is_active = true);
    END IF;

    -- If restrictions exist, must be in supported list and enabled
    RETURN EXISTS (
        SELECT 1 FROM public.organization_supported_countries
        WHERE organization_id = p_organization_id
          AND country_code = p_country_code
          AND is_enabled = true
    );
END;
$$;

-- Convert salary amount using reference exchange rates (if base != quote)
CREATE OR REPLACE FUNCTION public.convert_currency_amount(
    p_amount NUMERIC,
    p_from_currency VARCHAR(3),
    p_to_currency VARCHAR(3)
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    IF p_amount IS NULL THEN
        RETURN NULL;
    END IF;

    IF p_from_currency = p_to_currency THEN
        RETURN p_amount;
    END IF;

    -- Direct pair
    SELECT rate INTO v_rate
    FROM public.exchange_rates
    WHERE base_currency = p_from_currency
      AND quote_currency = p_to_currency
    ORDER BY effective_at DESC
    LIMIT 1;

    IF v_rate IS NOT NULL THEN
        RETURN round(p_amount * v_rate, 2);
    END IF;

    -- Inverse pair
    SELECT rate INTO v_rate
    FROM public.exchange_rates
    WHERE base_currency = p_to_currency
      AND quote_currency = p_from_currency
    ORDER BY effective_at DESC
    LIMIT 1;

    IF v_rate IS NOT NULL AND v_rate > 0 THEN
        RETURN round(p_amount / v_rate, 2);
    END IF;

    -- No conversion rule found
    RETURN NULL;
END;
$$;

-- ============================================================================
-- 18. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on reference tables
ALTER TABLE public.countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.language_proficiency_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.timezones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regional_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.localization_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.localization_translations ENABLE ROW LEVEL SECURITY;

-- Enable RLS on organization & user configuration tables
ALTER TABLE public.organization_locales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_locales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_supported_countries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_supported_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_supported_currencies ENABLE ROW LEVEL SECURITY;

-- Reference Tables: Public / Authenticated read access
DROP POLICY IF EXISTS "Allow public read on countries" ON public.countries;
CREATE POLICY "Allow public read on countries" ON public.countries
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on regions" ON public.regions;
CREATE POLICY "Allow public read on regions" ON public.regions
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on cities" ON public.cities;
CREATE POLICY "Allow public read on cities" ON public.cities
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on languages" ON public.languages;
CREATE POLICY "Allow public read on languages" ON public.languages
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on language_proficiency_levels" ON public.language_proficiency_levels;
CREATE POLICY "Allow public read on language_proficiency_levels" ON public.language_proficiency_levels
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public read on currencies" ON public.currencies;
CREATE POLICY "Allow public read on currencies" ON public.currencies
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on exchange_rates" ON public.exchange_rates;
CREATE POLICY "Allow public read on exchange_rates" ON public.exchange_rates
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public read on timezones" ON public.timezones;
CREATE POLICY "Allow public read on timezones" ON public.timezones
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on regional_policies" ON public.regional_policies;
CREATE POLICY "Allow public read on regional_policies" ON public.regional_policies
    FOR SELECT USING (status = 'active');

DROP POLICY IF EXISTS "Allow public read on localization_keys" ON public.localization_keys;
CREATE POLICY "Allow public read on localization_keys" ON public.localization_keys
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Allow public read on localization_translations" ON public.localization_translations;
CREATE POLICY "Allow public read on localization_translations" ON public.localization_translations
    FOR SELECT USING (status = 'published');

-- Organization Locales: Tenant isolated
DROP POLICY IF EXISTS "Org members can view organization locale" ON public.organization_locales;
CREATE POLICY "Org members can view organization locale" ON public.organization_locales
    FOR SELECT USING (public.is_org_member(organization_id, auth.uid()));

DROP POLICY IF EXISTS "Org admins can manage organization locale" ON public.organization_locales;
CREATE POLICY "Org admins can manage organization locale" ON public.organization_locales
    FOR ALL USING (
        public.has_org_permission(organization_id, 'organization_locale.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

-- User Locales: User private
DROP POLICY IF EXISTS "Users can view own user_locales" ON public.user_locales;
CREATE POLICY "Users can view own user_locales" ON public.user_locales
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage own user_locales" ON public.user_locales;
CREATE POLICY "Users can manage own user_locales" ON public.user_locales
    FOR ALL USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Organization Supported Markets: Tenant isolated
DROP POLICY IF EXISTS "Org members can view supported countries" ON public.organization_supported_countries;
CREATE POLICY "Org members can view supported countries" ON public.organization_supported_countries
    FOR SELECT USING (public.is_org_member(organization_id, auth.uid()));

DROP POLICY IF EXISTS "Org admins can manage supported countries" ON public.organization_supported_countries;
CREATE POLICY "Org admins can manage supported countries" ON public.organization_supported_countries
    FOR ALL USING (
        public.has_org_permission(organization_id, 'supported_regions.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

DROP POLICY IF EXISTS "Org members can view supported languages" ON public.organization_supported_languages;
CREATE POLICY "Org members can view supported languages" ON public.organization_supported_languages
    FOR SELECT USING (public.is_org_member(organization_id, auth.uid()));

DROP POLICY IF EXISTS "Org admins can manage supported languages" ON public.organization_supported_languages;
CREATE POLICY "Org admins can manage supported languages" ON public.organization_supported_languages
    FOR ALL USING (
        public.has_org_permission(organization_id, 'supported_regions.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

DROP POLICY IF EXISTS "Org members can view supported currencies" ON public.organization_supported_currencies;
CREATE POLICY "Org members can view supported currencies" ON public.organization_supported_currencies
    FOR SELECT USING (public.is_org_member(organization_id, auth.uid()));

DROP POLICY IF EXISTS "Org admins can manage supported currencies" ON public.organization_supported_currencies;
CREATE POLICY "Org admins can manage supported currencies" ON public.organization_supported_currencies
    FOR ALL USING (
        public.has_org_permission(organization_id, 'supported_regions.manage', auth.uid())
        OR public.is_platform_admin(auth.uid())
    );

-- ============================================================================
-- 19. AUDIT TRIGGER REGISTRATION
-- ============================================================================
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

DROP TRIGGER IF EXISTS trg_audit_organization_locale ON public.organization_locales;
CREATE TRIGGER trg_audit_organization_locale
    AFTER INSERT OR UPDATE ON public.organization_locales
    FOR EACH ROW
    EXECUTE FUNCTION public.audit_organization_locale_change();

-- ============================================================================
-- 20. BACKWARD COMPATIBILITY & SYSTEM COMMENTS
-- ============================================================================
COMMENT ON TABLE public.countries IS 'Canonical ISO 3166-1 country reference data';
COMMENT ON TABLE public.languages IS 'Canonical ISO 639 language reference with text direction';
COMMENT ON TABLE public.language_proficiency_levels IS 'Canonical CEFR language proficiency levels shared across matching and assessments';
COMMENT ON TABLE public.currencies IS 'ISO 4217 standard currency reference table';
COMMENT ON TABLE public.timezones IS 'Canonical IANA timezone registry';
COMMENT ON TABLE public.organization_locales IS 'Organization-level default regional preferences and formats';
COMMENT ON TABLE public.user_locales IS 'User-level regional preferences that override organization defaults';
COMMENT ON COLUMN public.jobs.country IS 'Legacy country text field maintained for backward compatibility';
COMMENT ON COLUMN public.jobs.country_code IS 'Canonical ISO2 country reference';
COMMENT ON COLUMN public.candidate_profiles.country_code IS 'Legacy country string maintained for backward compatibility';
COMMENT ON COLUMN public.candidate_profiles.canonical_country_code IS 'Canonical ISO2 country reference';
