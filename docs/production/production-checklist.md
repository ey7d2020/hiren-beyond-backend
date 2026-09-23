# Production Checklist

Status: checklist prepared; live production execution not completed in this environment.

## Repository

| Check | Status | Notes |
|---|---|---|
| Migrations present | PASS | 40 migration files found |
| Supabase config present | PASS | `supabase/config.toml` exists |
| Edge Functions present | FAIL | No `supabase/functions` directory found |
| Package build/lint scripts | NOT APPLICABLE | No `package.json` or `tsconfig.json` found |
| Frontend contract docs | PASS | `docs/frontend/backend-integration-contract.md` and screen mapping exist |
| Database docs | PASS | README, master ERD, module ERDs, table inventory, naming audit exist |

## Supabase Remote

| Check | Status | Required action |
|---|---|---|
| CLI availability | FAIL | Install Supabase CLI on delivery machine |
| Remote migration state | NOT VERIFIED | Run `supabase migration list --linked` |
| Remote DB schema inventory | NOT VERIFIED | Run `docs/database/verification-report.sql` |
| RLS policies | NOT VERIFIED | Run RLS/security SQL tests against remote |
| Storage buckets/policies | NOT VERIFIED | Check dashboard and storage policy catalog |
| Auth redirect URLs | READY TO CONFIGURE | Set production app URLs in Supabase Auth settings |
| OAuth providers | READY TO CONFIGURE | Add provider secrets only in Supabase dashboard/secrets |

## Environment

| Variable class | Status | Notes |
|---|---|---|
| Browser variables | READY TO CONFIGURE | `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, optional API/app URLs |
| Server secrets | READY TO CONFIGURE | Service role, DB password, provider secrets must stay server-side |
| Example env file | PASS | `.env.example` contains public values and warns against secret exposure |

## Security

| Check | Status | Notes |
|---|---|---|
| Secret scan | PASS WITH NOTES | No obvious live secrets found; placeholders/test invalid keys retained |
| RLS enabled in migrations | PASS LOCAL | RLS statements present across module migrations |
| Tenant isolation live test | NOT VERIFIED | Requires remote test users/orgs |
| Private storage live test | NOT VERIFIED | Requires remote authenticated users and bucket policies |
| SECURITY DEFINER audit | PARTIAL | Functions exist; live grants/search_path audit still required |

## Delivery Gate

Current recommendation: NO-GO for production handover as a verified live system until remote Supabase verification and smoke tests are executed. Repository handover documentation is ready for client review.

