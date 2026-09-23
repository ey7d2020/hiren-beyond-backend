# Hiren Beyond — Supabase Setup & Operations Guide

## 1. Project Reference & Connection

The backend is connected to the real Supabase project:
- **Project Name**: `Recruitment Backend`
- **Project Reference**: `pthkmkwrqjyseonysjzu`
- **Region**: `eu-west-1`
- **Database Engine**: PostgreSQL 17

---

## 2. Linking the Project Locally

To link this repository to the remote Supabase project:

```bash
# Verify Supabase CLI is available
npx -y supabase --version

# Log in to Supabase CLI (if not already logged in)
npx -y supabase login

# Link the local workspace to the remote project
npx -y supabase link --project-ref pthkmkwrqjyseonysjzu
```

---

## 3. Environment Variables Configuration

Copy `.env.example` to `.env` in your application root:

```bash
cp .env.example .env
```

### Environment Variable Roles & Sensitivity

| Variable | Scope | Exposure | Purpose |
|---|---|---|---|
| `VITE_SUPABASE_URL` | Client / Web | Public | Supabase API Gateway endpoint (`https://pthkmkwrqjyseonysjzu.supabase.co`) |
| `VITE_SUPABASE_ANON_KEY` | Client / Web | Public | Safe public key for browser requests governed by RLS |
| `SUPABASE_SERVICE_ROLE_KEY` | Server / CI | **SECRET** | Bypasses RLS. NEVER place in frontend code or client bundles |
| `SUPABASE_DB_PASSWORD` | CI / Terminal | **SECRET** | Direct database password for CLI migrations |

> [!CAUTION]
> **Never commit `.env` containing real keys into version control.** Ensure `.env` is listed in your `.gitignore`.

---

## 4. Applying Database Migrations

All schema changes are tracked inside `supabase/migrations/`. To apply pending migrations to the linked remote database:

```bash
# Check diff or perform a dry-run
npx -y supabase db push --linked --dry-run

# Push migrations to the remote database
npx -y supabase db push --linked
```

To view the migration history between local and remote:

```bash
npx -y supabase migration list
```

---

## 5. Verification inside Supabase Dashboard

After applying migrations, verify the database objects directly inside the [Supabase Dashboard](https://supabase.com/dashboard):

1. **Table Editor**:
   - Check that all 7 tables appear under the `public` schema:
     - `profiles`
     - `organizations`
     - `roles`
     - `permissions`
     - `role_permissions`
     - `organization_members`
     - `audit_logs`
   - Confirm that `roles` contains 7 rows and `permissions` contains 13 rows.
   - Confirm that `organizations` has the default record `hiren-beyond`.

2. **Authentication -> Policies (RLS)**:
   - Verify that all 7 tables have **Row Level Security (RLS) enabled**.
   - Verify that policies are listed for `profiles`, `organizations`, `organization_members`, `roles`, `permissions`, `role_permissions`, and `audit_logs`.

3. **Database -> Functions**:
   - Verify that the following helper functions exist:
     - `set_updated_at()`
     - `handle_new_user()`
     - `is_platform_admin()`
     - `is_org_member()`
     - `has_org_permission()`

4. **Database -> Triggers**:
   - Verify `trg_profiles_updated_at` on `public.profiles`.
   - Verify `trg_organizations_updated_at` on `public.organizations`.
   - Verify `trg_org_members_updated_at` on `public.organization_members`.
   - Verify `on_auth_user_created` on `auth.users`.

---

## 6. Configuring OAuth Providers (Google & Apple)

When ready to enable social sign-in:

### Google OAuth Configuration
1. Open the [Google Cloud Console](https://console.cloud.google.com/).
2. Create an OAuth 2.0 Client ID (Web Application).
3. Set the **Authorized redirect URI** to:
   ```text
   https://pthkmkwrqjyseonysjzu.supabase.co/auth/v1/callback
   ```
4. In the **Supabase Dashboard**, navigate to **Authentication -> Providers -> Google**.
5. Toggle **Enable Google provider**, paste your **Client ID** and **Client Secret**, and save.

### Apple OAuth Configuration
1. Open the [Apple Developer Portal](https://developer.apple.com/).
2. Register an **App ID**, **Services ID**, and configure **Sign in with Apple**.
3. Set the **Return URL** to:
   ```text
   https://pthkmkwrqjyseonysjzu.supabase.co/auth/v1/callback
   ```
4. Generate an Apple private key (`.p8`) and retrieve your Key ID and Team ID.
5. In the **Supabase Dashboard**, navigate to **Authentication -> Providers -> Apple**.
6. Toggle **Enable Apple provider**, enter your credentials, and save.

---

## 7. Assigning the Initial Platform Administrator

When the first developer or founder registers through Supabase Auth:

1. Identify the user's UUID in the Supabase Dashboard under **Authentication -> Users** or query `SELECT id, email FROM public.profiles;`.
2. Retrieve the `Hiren Beyond Platform` organization ID:
   ```sql
   SELECT id FROM public.organizations WHERE slug = 'hiren-beyond';
   ```
3. Retrieve the `platform_admin` role ID:
   ```sql
   SELECT id FROM public.roles WHERE key = 'platform_admin';
   ```
4. Execute the membership assignment in the Supabase SQL Editor:
   ```sql
   INSERT INTO public.organization_members (organization_id, user_id, role_id, status)
   VALUES (
       (SELECT id FROM public.organizations WHERE slug = 'hiren-beyond'),
       '<FIRST_USER_UUID>',
       (SELECT id FROM public.roles WHERE key = 'platform_admin'),
       'active'
   );
   ```
5. The user now holds `platform_admin` privileges across the entire platform.
