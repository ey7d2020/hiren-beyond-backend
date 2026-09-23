# Task 16: Globalization, Localization & International Recruitment Support

**Migration**: `20260915001600_globalization_localization.sql`  
**Fix Migration**: `20260915001601_fix_globalization_audit_trigger.sql`  
**Status**: ✅ Deployed & Verified  
**Test Suite**: `docs/backend/test-globalization.sql` — **24/24 tests passed**

---

## Overview

Task 16 establishes a robust, globally configurable foundation for the Hiren Beyond platform. It removes all hardcoded Egypt/EGP/English/Cairo defaults and introduces a canonical international layer that covers countries, languages, CEFR proficiency levels, currencies, exchange rates, timezones, localization dictionaries, and organization/user locale preferences.

All changes are **additive and backward-compatible** — no existing columns, constraints, or data were modified or deleted.

---

## New Tables (15 Tables)

### Reference Data Layer (Publicly Readable)

| Table | Description |
|---|---|
| `public.countries` | ISO 3166-1 country registry (iso2, iso3, region, subregion, data_region, currency, timezone) |
| `public.regions` | Sub-country divisions: states, provinces, governorates, emirates |
| `public.cities` | City-level reference linked to country + region with lat/lng |
| `public.languages` | ISO 639 language registry with text direction (ltr/rtl) |
| `public.language_proficiency_levels` | Centralized CEFR scale: A1=1, A2=2, B1=3, B2=4, C1=5, C2=6, NATIVE=7 |
| `public.currencies` | ISO 4217 currency registry with symbol and minor_unit |
| `public.exchange_rates` | Timestamped exchange rate pairs (manual reference + updatable) |
| `public.timezones` | IANA timezone registry linked to countries |
| `public.regional_policies` | Country-level compliance/policy configuration (GDPR, labor law, data residency) |
| `public.localization_keys` | Translation dictionary key catalog |
| `public.localization_translations` | Versioned translations per key+language with published/draft lifecycle |

### Tenant & User Configuration Layer (RLS-Isolated)

| Table | Description |
|---|---|
| `public.organization_locales` | Per-organization default language, currency, timezone, date/time format, first day of week |
| `public.user_locales` | Per-user locale overrides (strictly private to each user) |
| `public.organization_supported_countries` | Countries an organization is authorized to recruit in |
| `public.organization_supported_languages` | Languages an organization has enabled for content and communication |
| `public.organization_supported_currencies` | Currencies an organization accepts for billing and salary display |

---

## Additive Enhancements on Existing Tables

### `public.jobs`
- `country_code VARCHAR(2)` → Canonical ISO2 country reference (replaces free-text `country`)
- `region_id UUID` → FK to `public.regions`
- `city_id UUID` → FK to `public.cities`
- `remote_restrictions JSONB` → `{mode, allowed_countries[], excluded_countries[], timezones[]}`
- `localized_content JSONB` → Multilingual job content storage
- **Safe backfill**: Unambiguous legacy `country` text values migrated to `country_code`

### `public.candidate_profiles`
- `canonical_country_code VARCHAR(2)` → Canonical ISO2 (alongside legacy `country_code` text)
- `region_id UUID` → FK to `public.regions`
- `city_id UUID` → FK to `public.cities`
- `preferred_locations JSONB` → `{countries[], regions[], cities[], timezones[]}`
- **Safe backfill**: Unambiguous values from `country_code` mapped to canonical ISO2

### `public.candidate_languages`
- `language_id UUID` → FK to `public.languages`
- `proficiency_level_id UUID` → FK to `public.language_proficiency_levels`
- **Safe backfill**: Existing `language_code`/`language_name` and `proficiency_level` strings mapped to canonical IDs

---

## Helper Functions & RPCs

### `get_effective_locale(p_user_id, p_organization_id) → JSONB`
Follows the canonical 3-tier fallback:
1. **User locale** (`user_locales`) — highest priority
2. **Organization locale** (`organization_locales`) — mid priority
3. **Platform default** (`en` / `USD` / `UTC` / `YYYY-MM-DD` / `24h` / `Monday`) — lowest priority

Returns: `{language_code, currency_code, timezone, country_code, date_format, time_format, first_day_of_week, number_format}`

### `translate_key(p_key, p_language_code, p_namespace) → TEXT`
3-level translation fallback:
1. Translation in `p_language_code`
2. English (`en`) fallback
3. Raw `p_key` as passthrough

### `normalize_country_code(p_input TEXT) → VARCHAR(2)`
Converts free-text country names (Arabic and English) to ISO2 codes for unambiguous inputs. Returns `NULL` for ambiguous values (`Global`, `Remote`, `MENA`, etc.).

### `can_publish_job_in_country(p_organization_id, p_country_code) → BOOLEAN`
- If no supported countries configured → any active country is allowed
- If restrictions configured → country must be in the enabled list

### `convert_currency_amount(p_amount, p_from_currency, p_to_currency) → NUMERIC`
Converts amounts using the latest `exchange_rates` record. Supports direct and inverse pairs. Returns `NULL` if no rate found.

---

## Seed Data

| Dataset | Records |
|---|---|
| Countries | 12 (EG, SA, AE, QA, KW, US, GB, DE, FR, IN, SG, CA) |
| Regions | 8 (Cairo/Alex/Giza governorates, Riyadh/Makkah/Eastern provinces, Dubai/Abu Dhabi emirates) |
| Cities | 4 (Cairo, New Cairo, Riyadh, Dubai) |
| Languages | 7 (en, ar, fr, de, es, hi, zh) |
| CEFR Levels | 7 (A1-C2 + NATIVE) |
| Currencies | 12 (USD, EUR, GBP, EGP, SAR, AED, QAR, KWD, CAD, AUD, INR, SGD) |
| Exchange Rates | 8 reference pairs (USD base + inverses) |
| Timezones | 14 IANA zones covering MENA, EU, Americas, APAC |
| Localization Keys | 3 sample keys (`common.welcome`, `job.status.active`, `interview.scheduled`) |
| Translations | 4 translations (en + ar for 2 keys) |

---

## Security & RLS Policies

### Reference Tables (Countries, Languages, Currencies, Timezones, etc.)
- **Allowed**: Unauthenticated (`anon`) and authenticated users — read only active/published records
- **Write**: Service role only

### Organization Locales & Supported Markets
- **Read**: `public.is_org_member(organization_id, auth.uid())` — any active org member
- **Write**: `public.has_org_permission(organization_id, 'organization_locale.manage', auth.uid())` OR `public.is_platform_admin(auth.uid())`

### User Locales
- **All operations**: Strictly `auth.uid() = user_id` — no cross-user access possible

---

## Audit Integration

- `trg_audit_organization_locale` → fires `AFTER INSERT OR UPDATE` on `organization_locales`
- Records: `actor_user_id`, `organization_id`, `action='organization_locale_updated'`, `entity_type`, `entity_id`, `metadata` (with the changed locale fields)

---

## Test Coverage (`docs/backend/test-globalization.sql`)

| # | Test | Result |
|---|---|---|
| 01 | Countries — ISO2/ISO3 reference data exists | ✅ |
| 02 | Languages — direction (ltr/rtl) correctness | ✅ |
| 03 | CEFR levels — canonical A1=1 to NATIVE=7 ordering | ✅ |
| 04 | Currencies — ISO codes and minor units (KWD=3 digits) | ✅ |
| 05 | Timezones — IANA identifiers (UTC, Africa/Cairo, Asia/Dubai) | ✅ |
| 06 | Exchange rates — positive rates exist for key pairs | ✅ |
| 07 | Regions — country-linked governorates (Cairo) exist | ✅ |
| 08 | `normalize_country_code()` — unambiguous text → ISO2 | ✅ |
| 09 | `normalize_country_code()` — ambiguous/unknown → NULL | ✅ |
| 10 | `convert_currency_amount()` — USD → EGP direct pair | ✅ |
| 11 | `convert_currency_amount()` — same currency passthrough | ✅ |
| 12 | Organization locale — create and read org defaults | ✅ |
| 13 | `get_effective_locale()` — org-level fallback resolves (ar/EGP/Cairo) | ✅ |
| 14 | `get_effective_locale()` — platform defaults (en/USD/UTC) | ✅ |
| 15 | `translate_key()` — English translation resolved | ✅ |
| 16 | `translate_key()` — Arabic translation resolved | ✅ |
| 17 | `translate_key()` — fallback to English for unsupported language | ✅ |
| 18 | `translate_key()` — missing key returns key name | ✅ |
| 19 | `can_publish_job_in_country()` — no restrictions: all active allowed | ✅ |
| 20 | `can_publish_job_in_country()` — restriction blocks unlisted countries | ✅ |
| 21 | Jobs table — additive columns exist (country_code, remote_restrictions, localized_content) | ✅ |
| 22 | Candidate profiles — additive columns exist (canonical_country_code, preferred_locations) | ✅ |
| 23 | Candidate languages — canonical FK columns added (language_id, proficiency_level_id) | ✅ |
| 24 | Cross-system CEFR consistency — B2 < C1 < NATIVE numerically | ✅ |

**Result: 24/24 tests passed ✅**

---

## Integration Notes

- **Matching Engine (Task 06/07)**: `language_proficiency_levels.numeric_level` uses identical 1-6 scale as `get_cefr_level_numeric()`. Backward-compatible.
- **Assessments (Task 09)**: Language requirements in assessments can now reference canonical `language_id` and `proficiency_level_id`.
- **Analytics (Task 14)**: Timezone-aware reporting uses UTC storage + `timezone` field from `get_effective_locale()` for display-layer conversion.
- **Integrations (Task 15)**: Google Calendar event invitations, WhatsApp notifications, and webhook payloads can include locale-resolved content via `translate_key()`.
- **Client Portal (Task 11)**: Client organizations have their own `organization_locales` rows with independent language/currency/timezone preferences.
