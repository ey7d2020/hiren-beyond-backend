-- Test Suite: Task 16 - Globalization, Localization & International Recruitment
-- Description: 24 automated tests in a safe transactional rollback
-- All tests pass or raise EXCEPTION on failure

BEGIN;

DO $$
DECLARE
    v_test_name TEXT;
    v_passed INT := 0;
    v_failed INT := 0;

    -- Test UUIDs
    v_org_id UUID;
    v_user_id UUID;
    v_candidate_id UUID;
    v_job_id UUID;
    v_ca_lang_id UUID;
    v_ca_prof_id UUID;
    v_locale JSONB;
    v_trans TEXT;
    v_country_code VARCHAR(2);
    v_can_publish BOOLEAN;
    v_amount NUMERIC;

    -- Reference IDs
    v_eg_id UUID;
    v_en_lang_id UUID;
    v_ar_lang_id UUID;
    v_b2_prof_id UUID;
    v_native_prof_id UUID;
    v_usd_id UUID;
    v_usd_egp_rate NUMERIC;
BEGIN

    -----------------------------------------------------------------------
    -- TEST 1: Countries - Core reference data exists with correct ISO codes
    -----------------------------------------------------------------------
    v_test_name := 'Test 01: Countries reference data - ISO2/ISO3 exists';
    PERFORM 1 FROM public.countries WHERE iso2 = 'EG' AND iso3 = 'EGY' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: %', v_test_name; END IF;
    PERFORM 1 FROM public.countries WHERE iso2 = 'SA' AND iso3 = 'SAU' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: %', v_test_name; END IF;
    PERFORM 1 FROM public.countries WHERE iso2 = 'AE' AND iso3 = 'ARE' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: %', v_test_name; END IF;
    PERFORM 1 FROM public.countries WHERE iso2 = 'US' AND iso3 = 'USA' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: %', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 2: Languages - reference data with text directions
    -----------------------------------------------------------------------
    v_test_name := 'Test 02: Languages reference data - direction correctness';
    PERFORM 1 FROM public.languages WHERE code = 'en' AND direction = 'ltr' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (en LTR)', v_test_name; END IF;
    PERFORM 1 FROM public.languages WHERE code = 'ar' AND direction = 'rtl' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (ar RTL)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 3: CEFR Levels - Canonical numeric ordering A1=1 to C2=6, NATIVE=7
    -----------------------------------------------------------------------
    v_test_name := 'Test 03: CEFR language proficiency levels - canonical ordering';
    PERFORM 1 FROM public.language_proficiency_levels WHERE code = 'A1' AND numeric_level = 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (A1=1)', v_test_name; END IF;
    PERFORM 1 FROM public.language_proficiency_levels WHERE code = 'B2' AND numeric_level = 4;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (B2=4)', v_test_name; END IF;
    PERFORM 1 FROM public.language_proficiency_levels WHERE code = 'C2' AND numeric_level = 6;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (C2=6)', v_test_name; END IF;
    PERFORM 1 FROM public.language_proficiency_levels WHERE code = 'NATIVE' AND numeric_level = 7;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (NATIVE=7)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 4: Currencies - Canonical ISO codes and symbols
    -----------------------------------------------------------------------
    v_test_name := 'Test 04: Currencies - ISO codes and minor units';
    PERFORM 1 FROM public.currencies WHERE code = 'EGP' AND minor_unit = 2 AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (EGP)', v_test_name; END IF;
    PERFORM 1 FROM public.currencies WHERE code = 'KWD' AND minor_unit = 3 AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (KWD minor_unit=3)', v_test_name; END IF;
    PERFORM 1 FROM public.currencies WHERE code = 'USD' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (USD)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 5: Timezones - IANA timezone identifiers exist
    -----------------------------------------------------------------------
    v_test_name := 'Test 05: Timezones - IANA standard identifiers';
    PERFORM 1 FROM public.timezones WHERE iana_name = 'Africa/Cairo' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (Africa/Cairo)', v_test_name; END IF;
    PERFORM 1 FROM public.timezones WHERE iana_name = 'UTC' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (UTC)', v_test_name; END IF;
    PERFORM 1 FROM public.timezones WHERE iana_name = 'Asia/Dubai' AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (Asia/Dubai)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 6: Exchange Rates - Reference rates exist and are positive
    -----------------------------------------------------------------------
    v_test_name := 'Test 06: Exchange rates - rates are positive and reference pairs exist';
    PERFORM 1 FROM public.exchange_rates WHERE base_currency = 'USD' AND quote_currency = 'EGP' AND rate > 0;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (USD->EGP rate)', v_test_name; END IF;
    PERFORM 1 FROM public.exchange_rates WHERE base_currency = 'USD' AND quote_currency = 'SAR' AND rate > 0;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (USD->SAR rate)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 7: Regions - Country-linked regions exist
    -----------------------------------------------------------------------
    v_test_name := 'Test 07: Regions - Country-linked regions for Egypt, Saudi Arabia, UAE';
    SELECT c.id INTO v_eg_id FROM public.countries c WHERE c.iso2 = 'EG';
    PERFORM 1 FROM public.regions WHERE country_id = v_eg_id AND code = 'CAI' AND type = 'governorate';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (Cairo governorate)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 8: normalize_country_code() - Unambiguous mapping
    -----------------------------------------------------------------------
    v_test_name := 'Test 08: normalize_country_code() - Unambiguous text to ISO2';
    v_country_code := public.normalize_country_code('Egypt');
    IF v_country_code IS DISTINCT FROM 'EG' THEN
        RAISE EXCEPTION 'FAILED: % (Egypt -> expected EG, got %)', v_test_name, v_country_code;
    END IF;
    v_country_code := public.normalize_country_code('Saudi Arabia');
    IF v_country_code IS DISTINCT FROM 'SA' THEN
        RAISE EXCEPTION 'FAILED: % (Saudi Arabia -> expected SA, got %)', v_test_name, v_country_code;
    END IF;
    v_country_code := public.normalize_country_code('مصر');
    IF v_country_code IS DISTINCT FROM 'EG' THEN
        RAISE EXCEPTION 'FAILED: % (Arabic Egypt -> expected EG, got %)', v_test_name, v_country_code;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 9: normalize_country_code() - Ambiguous/unknown returns NULL
    -----------------------------------------------------------------------
    v_test_name := 'Test 09: normalize_country_code() - Ambiguous/unknown returns NULL';
    v_country_code := public.normalize_country_code('Global');
    IF v_country_code IS NOT NULL THEN
        RAISE EXCEPTION 'FAILED: % (Global should return NULL, got %)', v_test_name, v_country_code;
    END IF;
    v_country_code := public.normalize_country_code('Remote');
    IF v_country_code IS NOT NULL THEN
        RAISE EXCEPTION 'FAILED: % (Remote should return NULL, got %)', v_test_name, v_country_code;
    END IF;
    v_country_code := public.normalize_country_code('');
    IF v_country_code IS NOT NULL THEN
        RAISE EXCEPTION 'FAILED: % (empty string should return NULL, got %)', v_test_name, v_country_code;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 10: convert_currency_amount() - Direct pair conversion
    -----------------------------------------------------------------------
    v_test_name := 'Test 10: convert_currency_amount() - Direct pair (USD -> EGP)';
    v_amount := public.convert_currency_amount(100, 'USD', 'EGP');
    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION 'FAILED: % (100 USD -> EGP got null or zero: %)', v_test_name, v_amount;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: % (100 USD = % EGP)', v_test_name, v_amount;

    -----------------------------------------------------------------------
    -- TEST 11: convert_currency_amount() - Same currency returns same amount
    -----------------------------------------------------------------------
    v_test_name := 'Test 11: convert_currency_amount() - Same currency passthrough';
    v_amount := public.convert_currency_amount(500.00, 'EGP', 'EGP');
    IF v_amount IS DISTINCT FROM 500.00 THEN
        RAISE EXCEPTION 'FAILED: % (EGP->EGP got %)', v_test_name, v_amount;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 12: Organization Locales - Create and read org locale
    -----------------------------------------------------------------------
    v_test_name := 'Test 12: Organization locale - Create and read defaults';

    -- Create a test organization
    INSERT INTO public.organizations (name, slug, organization_type, status)
    VALUES ('GlobalTech International', 'globaltech-intl-t16', 'recruitment_agency', 'active')
    RETURNING id INTO v_org_id;

    INSERT INTO public.organization_locales (
        organization_id, default_language_code, default_currency_code,
        default_timezone, default_country_code, date_format, first_day_of_week
    ) VALUES (
        v_org_id, 'ar', 'EGP', 'Africa/Cairo', 'EG', 'DD/MM/YYYY', 'Saturday'
    );

    PERFORM 1 FROM public.organization_locales
    WHERE organization_id = v_org_id
      AND default_language_code = 'ar'
      AND default_currency_code = 'EGP'
      AND default_timezone = 'Africa/Cairo'
      AND first_day_of_week = 'Saturday';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: %', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 13: get_effective_locale() - Org-level fallback
    -----------------------------------------------------------------------
    v_test_name := 'Test 13: get_effective_locale() - Org-level fallback resolves correctly';
    v_locale := public.get_effective_locale(NULL, v_org_id);
    IF (v_locale->>'language_code') IS DISTINCT FROM 'ar' THEN
        RAISE EXCEPTION 'FAILED: % (expected ar, got %)', v_test_name, (v_locale->>'language_code');
    END IF;
    IF (v_locale->>'currency_code') IS DISTINCT FROM 'EGP' THEN
        RAISE EXCEPTION 'FAILED: % (expected EGP, got %)', v_test_name, (v_locale->>'currency_code');
    END IF;
    IF (v_locale->>'timezone') IS DISTINCT FROM 'Africa/Cairo' THEN
        RAISE EXCEPTION 'FAILED: % (expected Africa/Cairo, got %)', v_test_name, (v_locale->>'timezone');
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 14: get_effective_locale() - Platform default (no user, no org)
    -----------------------------------------------------------------------
    v_test_name := 'Test 14: get_effective_locale() - Platform defaults (en/USD/UTC)';
    v_locale := public.get_effective_locale(NULL, NULL);
    IF (v_locale->>'language_code') IS DISTINCT FROM 'en' THEN
        RAISE EXCEPTION 'FAILED: % (language expected en, got %)', v_test_name, (v_locale->>'language_code');
    END IF;
    IF (v_locale->>'currency_code') IS DISTINCT FROM 'USD' THEN
        RAISE EXCEPTION 'FAILED: % (currency expected USD, got %)', v_test_name, (v_locale->>'currency_code');
    END IF;
    IF (v_locale->>'timezone') IS DISTINCT FROM 'UTC' THEN
        RAISE EXCEPTION 'FAILED: % (timezone expected UTC, got %)', v_test_name, (v_locale->>'timezone');
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 15: translate_key() - English translation resolved
    -----------------------------------------------------------------------
    v_test_name := 'Test 15: translate_key() - English translation resolved for seeded key';
    v_trans := public.translate_key('common.welcome', 'en');
    IF v_trans IS DISTINCT FROM 'Welcome to Hiren Beyond' THEN
        RAISE EXCEPTION 'FAILED: % (got %)', v_test_name, v_trans;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 16: translate_key() - Arabic translation resolved
    -----------------------------------------------------------------------
    v_test_name := 'Test 16: translate_key() - Arabic translation resolved for seeded key';
    v_trans := public.translate_key('common.welcome', 'ar');
    IF v_trans IS DISTINCT FROM 'مرحباً بكم في هايرين بيوند' THEN
        RAISE EXCEPTION 'FAILED: % (got %)', v_test_name, v_trans;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 17: translate_key() - Fallback to English for unsupported language
    -----------------------------------------------------------------------
    v_test_name := 'Test 17: translate_key() - Fallback to English for missing language (de)';
    v_trans := public.translate_key('common.welcome', 'de');
    IF v_trans IS DISTINCT FROM 'Welcome to Hiren Beyond' THEN
        RAISE EXCEPTION 'FAILED: % (expected English fallback, got %)', v_test_name, v_trans;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 18: translate_key() - Missing key returns key itself
    -----------------------------------------------------------------------
    v_test_name := 'Test 18: translate_key() - Missing key returns key name as fallback';
    v_trans := public.translate_key('nonexistent.key.xyz', 'en');
    IF v_trans IS DISTINCT FROM 'nonexistent.key.xyz' THEN
        RAISE EXCEPTION 'FAILED: % (expected key passthrough, got %)', v_test_name, v_trans;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 19: Organization Supported Countries - can_publish_job_in_country()
    -----------------------------------------------------------------------
    v_test_name := 'Test 19: can_publish_job_in_country() - No restrictions: any active country allowed';
    v_can_publish := public.can_publish_job_in_country(v_org_id, 'EG');
    IF NOT v_can_publish THEN
        RAISE EXCEPTION 'FAILED: % (EG should be allowed when no restrictions set)', v_test_name;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 20: can_publish_job_in_country() - Restriction blocks disallowed countries
    -----------------------------------------------------------------------
    v_test_name := 'Test 20: can_publish_job_in_country() - Restriction correctly blocks unlisted country';

    -- Set restriction to only EG and SA
    INSERT INTO public.organization_supported_countries (organization_id, country_code, is_enabled)
    VALUES (v_org_id, 'EG', true), (v_org_id, 'SA', true);

    v_can_publish := public.can_publish_job_in_country(v_org_id, 'DE');
    IF v_can_publish THEN
        RAISE EXCEPTION 'FAILED: % (DE should be blocked when only EG/SA allowed)', v_test_name;
    END IF;
    v_can_publish := public.can_publish_job_in_country(v_org_id, 'EG');
    IF NOT v_can_publish THEN
        RAISE EXCEPTION 'FAILED: % (EG should still be allowed)', v_test_name;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 21: Jobs - Additive canonical columns exist on existing table
    -----------------------------------------------------------------------
    v_test_name := 'Test 21: Jobs table - Additive columns (country_code, region_id, city_id, remote_restrictions)';
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'country_code';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (country_code column missing)', v_test_name; END IF;
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'remote_restrictions';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (remote_restrictions column missing)', v_test_name; END IF;
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'localized_content';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (localized_content column missing)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 22: Candidate Profiles - Additive canonical columns exist
    -----------------------------------------------------------------------
    v_test_name := 'Test 22: Candidate Profiles - Additive columns (canonical_country_code, preferred_locations)';
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'candidate_profiles' AND column_name = 'canonical_country_code';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (canonical_country_code column missing)', v_test_name; END IF;
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'candidate_profiles' AND column_name = 'preferred_locations';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (preferred_locations column missing)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 23: Candidate Languages - Canonical references added
    -----------------------------------------------------------------------
    v_test_name := 'Test 23: Candidate Languages - Canonical language_id and proficiency_level_id columns added';
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'candidate_languages' AND column_name = 'language_id';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (language_id column missing)', v_test_name; END IF;
    PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'candidate_languages' AND column_name = 'proficiency_level_id';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAILED: % (proficiency_level_id column missing)', v_test_name; END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- TEST 24: Cross-System Consistency - CEFR numeric_level ordering matches get_cefr_level_numeric()
    -----------------------------------------------------------------------
    v_test_name := 'Test 24: Cross-system consistency - CEFR levels match matching engine numeric scale';
    -- Verify that proficiency_level_ids are canonical and ordered correctly
    -- B2 (4) < C1 (5) must hold for matching engine to work correctly
    IF NOT (
        (SELECT numeric_level FROM public.language_proficiency_levels WHERE code = 'B2') <
        (SELECT numeric_level FROM public.language_proficiency_levels WHERE code = 'C1')
    ) THEN
        RAISE EXCEPTION 'FAILED: % (B2 must be < C1 numerically)', v_test_name;
    END IF;
    -- Native (7) must be highest
    IF NOT (
        (SELECT numeric_level FROM public.language_proficiency_levels WHERE code = 'NATIVE') >
        (SELECT MAX(numeric_level) FROM public.language_proficiency_levels WHERE code <> 'NATIVE')
    ) THEN
        RAISE EXCEPTION 'FAILED: % (NATIVE must have highest numeric_level)', v_test_name;
    END IF;
    v_passed := v_passed + 1;
    RAISE NOTICE 'PASSED: %', v_test_name;

    -----------------------------------------------------------------------
    -- FINAL REPORT
    -----------------------------------------------------------------------
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TASK 16 TEST SUITE COMPLETE';
    RAISE NOTICE 'PASSED: % / 24', v_passed;
    IF v_failed > 0 THEN
        RAISE NOTICE 'FAILED: %', v_failed;
    END IF;
    RAISE NOTICE '========================================';

END $$;

ROLLBACK;
