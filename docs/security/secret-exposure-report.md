# Secret & Credential Exposure Report — Hiren Beyond

**Audit Date:** September 16, 2026  
**Audited Target:** Hiren Beyond Codebase & Remote Supabase Environment (`pthkmkwrqjyseonysjzu`)  
**Scope:** Repository filesystem, Git history, documentation, migrations, config files, remote database tables  
**Final Status:** **PASS — ZERO PRODUCTION SECRETS EXPOSED**

---

## 1. Executive Summary

An exhaustive audit was conducted across all files, source code, database migrations, configuration templates, environment files, and remote database tables to identify any accidentally exposed credentials, private keys, service-role tokens, database passwords, or third-party provider API keys.

**Summary of Findings:**
- **Zero Real Secrets Exposed:** No production API keys, service-role JWTs, database passwords, private certificates, or SSH keys were identified in any repository file or client bundle.
- **Documentation & Template Placeholders:** References to secrets in documentation and `.env.example` exclusively utilize masked placeholders or descriptive templates (e.g. `your-supabase-anon-key`, `sk-...`).
- **Remote Database Audit:** The live remote PostgreSQL database (`pthkmkwrqjyseonysjzu`) contains no secrets in public tables. The `platform_settings` table contains only non-sensitive configuration values.

---

## 2. Secrets Search Methodology & Regex Patterns

The repository was searched recursively (excluding standard library types in `node_modules`) using the following patterns:
1. **Supabase Service-Role & Anon JWTs:** `eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}`
2. **AI Provider API Keys:**
   - OpenAI: `sk-[a-zA-Z0-9]{20,}`
   - Anthropic: `sk-ant-[a-zA-Z0-9]{20,}`
   - Google AI / Gemini: `AIza[0-9A-Za-z-_]{35}`
3. **Database Connection Strings:** `postgres://.*:.*@.*` and `postgresql://.*:.*@.*`
4. **Stripe & Payment Keys:** `sk_live_[0-9a-zA-Z]{24}` and `sk_test_[0-9a-zA-Z]{24}`
5. **Private Keys & Certificates:** `-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----`
6. **Generic Keywords:** `password`, `secret`, `token`, `service_role`, `api_key`, `bearer`

---

## 3. Detailed Inventory of Credential Mentions

The table below documents every location where credential variables or secret references occur, along with an evaluation of their safety:

| File Location | Variable / Identifier | Credential Type | Exposure Classification | Masked Value | Severity | Analysis |
|---|---|---|---|---|---|---|
| `.env.example:8` | `VITE_SUPABASE_ANON_KEY` | Supabase Anon Key | Template Placeholder | `your-supabase-anon-key-here` | **INFO** | Safe placeholder in sample env file. |
| `.env.example:16` | `SUPABASE_SERVICE_ROLE_KEY` | Service Role Key | Commented Template | `your-supabase-service-role-key-here` | **INFO** | Explicitly documented as server-only variable with non-functional placeholder. |
| `.env.example:17` | `SUPABASE_DB_PASSWORD` | Database Password | Commented Template | `your-database-password-here` | **INFO** | Safe commented placeholder. |
| `supabase/config.toml:56` | `db.vault.secret_key` | Supabase Vault Key | Configuration Placeholder | `env(SECRET_VALUE)` | **INFO** | References system environment variable via `env()`. |
| `supabase/config.toml:100` | `studio.openai_api_key` | OpenAI Key | Configuration Placeholder | `env(OPENAI_API_KEY)` | **INFO** | References system environment variable via `env()`. |
| `docs/backend/task-05-cv-intelligence.md:222` | `OPENAI_API_KEY` | OpenAI API Key | Documentation Template | `sk-****...` | **INFO** | Standard documentation template format. |
| `docs/backend/task-05-cv-intelligence.md:223` | `ANTHROPIC_API_KEY` | Anthropic API Key | Documentation Template | `sk-ant-****...` | **INFO** | Standard documentation template format. |
| `src/backend.ts:16` | `supabaseAnonKey` fallback | Client Fallback String | Hardcoded Fallback | `missing-anon-key` | **INFO** | Intentional dummy string preventing silent runtime failures if env var missing. |
| `20260915000600_cv_intelligence.sql:1161` | `SUPABASE_SERVICE_ROLE_KEY` | Service Role Reference | SQL Migration Comment | `<secret — server-side only>` | **INFO** | Architectural design comment indicating server boundary. |

---

## 4. Remote Database Credential Verification

A live query was executed against the remote database (`pthkmkwrqjyseonysjzu`) to inspect tables that store configuration or authentication data:

### 4.1 Table `public.platform_settings`
- **Query:** `SELECT key, is_public, is_sensitive, value FROM public.platform_settings;`
- **Results:**
  - `default_language`: `'en'` (`is_public: true`, `is_sensitive: false`)
  - `default_currency`: `'USD'` (`is_public: true`, `is_sensitive: false`)
  - `default_timezone`: `'UTC'` (`is_public: true`, `is_sensitive: false`)
  - `maintenance_mode`: `'false'` (`is_public: true`, `is_sensitive: false`)
  - `maximum_file_size_mb`: `'50'` (`is_public: true`, `is_sensitive: false`)
  - `maximum_ai_request_size_kb`: `'500'` (`is_public: false`, `is_sensitive: false`)
  - `default_application_expiry_days`: `'30'` (`is_public: true`, `is_sensitive: false`)
  - `default_assessment_expiry_days`: `'7'` (`is_public: false`, `is_sensitive: false`)
  - `ai_provider_primary`: `'gemini'` (`is_public: false`, `is_sensitive: false`)
  - `platform_name`: `'Hiren Beyond'` (`is_public: true`, `is_sensitive: false`)
  - `workflow.max_steps_per_execution`: `'50'` (`is_public: false`, `is_sensitive: false`)
  - `workflow.max_execution_duration_sec`: `'3600'` (`is_public: false`, `is_sensitive: false`)
- **Conclusion:** No sensitive credentials, API keys, or passwords are stored in `public.platform_settings`.

### 4.2 Table `public.api_keys`
- **Architecture:** API keys created for public API consumers store `key_prefix` (e.g. `hb_live_a1b2`) and `key_hash` (SHA-256 hash). The raw plaintext secret is generated only once during issuance and is never stored in the database.
- **Status:** Verified compliant with zero plaintext storage.

---

## 5. Client Bundle & Browser Exposure Audit

The client-facing frontend build was evaluated:
- **Build Output Analysis:** The production build produced in `dist/` was checked for environment variable inclusion.
- **Results:**
  - Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` are read by Vite.
  - The Supabase anon key is a public, publishable client credential whose access is gated by RLS in PostgreSQL.
  - No server-side secrets (e.g. `service_role` key, database password) are imported or bundled into frontend JavaScript files.

---

## 6. Secret Exposure Verdict

- **REAL PRODUCTION SECRETS FOUND:** `0`
- **ACCIDENTALLY COMMITTED SECRETS:** `0`
- **LEAKED PRIVATE KEYS:** `0`
- **CLIENT-BUNDLE EXPOSURES:** `0`

**Verdict:** **PASS — ZERO EXPOSED CREDENTIALS**
