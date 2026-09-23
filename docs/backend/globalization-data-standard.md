# Hiren Beyond — Globalization Data Standard

**Version**: 1.0  
**Effective from**: Task 16 (Migration `20260915001600`)  
**Status**: Canonical — all new code must follow these standards

---

## 1. Country Codes

All country references across the platform **MUST** use **ISO 3166-1 alpha-2** (2-letter) codes stored in `public.countries.iso2`.

### Rules
- New columns referencing countries → `REFERENCES public.countries(iso2)` or `VARCHAR(2)` with documented mapping
- Free-text country names (e.g., user inputs) → pass through `public.normalize_country_code()` before storage
- Ambiguous, regional, or non-country values (`"MENA"`, `"Remote"`, `"Global"`) → store as `NULL`, never guess
- Legacy `country TEXT` fields → preserved for backward compatibility; do not remove; `country_code` is the canonical column

### Reference Data
```sql
SELECT iso2, iso3, name, default_timezone, currency_code 
FROM public.countries 
WHERE is_active = true 
ORDER BY sort_order;
```

---

## 2. Languages

Language codes follow **ISO 639-1** (2-letter) with extension support for regional codes (e.g., `zh-TW`), stored in `public.languages.code`.

### Rules
- All language selections → `REFERENCES public.languages(code)` or validated against `public.languages`
- Text direction (`ltr`/`rtl`) → read from `public.languages.direction`; never hardcode
- CEFR proficiency → always reference `public.language_proficiency_levels` by canonical `code` (e.g., `'B2'`) or FK to `id`

### CEFR Canonical Scale (must match matching engine)

| Code | Name | Numeric Level | Framework |
|---|---|---|---|
| A1 | Beginner | 1 | CEFR |
| A2 | Elementary | 2 | CEFR |
| B1 | Intermediate | 3 | CEFR |
| B2 | Upper Intermediate | 4 | CEFR |
| C1 | Advanced | 5 | CEFR |
| C2 | Mastery / Proficient | 6 | CEFR |
| NATIVE | Native / Bilingual | 7 | CEFR |

> ⚠️ The matching engine `get_cefr_level_numeric()` uses this same 1-6 scale. `NATIVE` maps to 7.

---

## 3. Currencies

All currency codes follow **ISO 4217** (3-letter), stored in `public.currencies.code`.

### Rules
- Salary columns → store the raw amount + currency code separately (e.g., `salary_min + salary_currency`)
- Display conversion → use `public.convert_currency_amount(amount, from, to)` for reference conversion only
- Never hardcode `'EGP'` or `'USD'` as defaults in new application code; always inherit from `get_effective_locale()`
- KWD has `minor_unit = 3` (fils); handle display rounding accordingly

---

## 4. Timezones

All timezone identifiers follow the **IANA Time Zone Database** (e.g., `Africa/Cairo`, `UTC`), stored in `public.timezones.iana_name`.

### Rules
- All `TIMESTAMPTZ` fields store **UTC** — never store local time
- Display-layer timezone conversion uses `get_effective_locale()` to resolve the user/org timezone
- Never use raw UTC offset strings (e.g., `"+03:00"`) as timezone identifiers
- The `utc_offset` column in `public.timezones` is for display purposes only; it does not account for DST

---

## 5. Locale Fallback Order

All locale-dependent presentation must use `get_effective_locale(user_id, org_id)`:

```
User Locale
    → Organization Locale
        → Platform Default (en / USD / UTC / YYYY-MM-DD / 24h / Monday)
```

### Example Usage
```sql
-- Get resolved locale for a user in an organization context
SELECT public.get_effective_locale(
    '00000000-0000-0000-0000-000000000001'::uuid, -- user_id
    '00000000-0000-0000-0000-000000000002'::uuid  -- organization_id
);
-- Returns: {"language_code":"ar","currency_code":"EGP","timezone":"Africa/Cairo",...}
```

---

## 6. Translation Keys

All user-facing strings in notifications, emails, UI copy, and system messages must be registered in `public.localization_keys` and translated via `public.translate_key()`.

### Namespaces

| Namespace | Usage |
|---|---|
| `common` | Shared UI strings (welcome, buttons, errors) |
| `recruitment` | Job, application, pipeline status labels |
| `interviews` | Interview scheduling, feedback, outcome labels |
| `assessments` | Assessment questions, instructions, results |
| `notifications` | Notification templates and push copy |
| `billing` | Subscription, invoice, currency display |
| `emails` | Email subject lines and greetings |

### Fallback Chain
```sql
public.translate_key('key.name', 'ar')
-- 1. Try Arabic translation
-- 2. Fallback to English translation
-- 3. Return raw key 'key.name' if no translations exist
```

---

## 7. Country Normalization Function

```sql
-- Safe normalization: returns NULL for unrecognized or ambiguous inputs
SELECT public.normalize_country_code('Egypt');           -- → 'EG'
SELECT public.normalize_country_code('مصر');             -- → 'EG'
SELECT public.normalize_country_code('Saudi Arabia');    -- → 'SA'
SELECT public.normalize_country_code('uae');             -- → 'AE'
SELECT public.normalize_country_code('Global');          -- → NULL
SELECT public.normalize_country_code('Remote');          -- → NULL
SELECT public.normalize_country_code('');                -- → NULL
```

---

## 8. Market Restrictions (Job Publishing)

Organizations can restrict which countries they recruit in via `organization_supported_countries`.

```sql
-- Check before posting a job to a specific country
SELECT public.can_publish_job_in_country(
    'org-uuid-here'::uuid,
    'DE'   -- ISO2 country code
);
-- Returns TRUE if allowed, FALSE if restricted
```

**Behavior**:
- No rows in `organization_supported_countries` → **all active countries allowed** (open market mode)
- Rows exist → only countries with `is_enabled = true` are allowed

---

## 9. Data Residency Regions

The `public.countries.data_region` field maps each country to a data residency zone for compliance:

| Region Code | Countries | Notes |
|---|---|---|
| `EU` | DE, FR, GB, etc. | GDPR applies; may require EU data hosting |
| `MENA` | EG, SA, AE, QA, KW | Egypt PDPL, Saudi PDPL, UAE data laws |
| `US` | US, CA | SOC2, CCPA considerations |
| `APAC` | IN, SG, etc. | PDPA (SG), IT Act (IN) |

Use `regional_policies` table to store country-specific compliance configuration:

```sql
SELECT configuration FROM public.regional_policies
WHERE country_code = 'EG' AND policy_key = 'data_retention_months' AND status = 'active';
```

---

## 10. Adding New Countries / Languages

To add new canonical reference data:

1. Create a migration file `20260915XXXXXX_add_country_<iso2>.sql`
2. `INSERT INTO public.countries (iso2, iso3, name, ...) ... ON CONFLICT (iso2) DO UPDATE`
3. Add corresponding timezone record if not already in `public.timezones`
4. Optionally add regions/cities for the new country

**Never** remove or rename existing `iso2`/`code` values — they are referenced by FK throughout the schema.
