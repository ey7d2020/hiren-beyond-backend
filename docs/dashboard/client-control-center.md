# Hiren Beyond Client Control Center

## Status

The dashboard is implemented as a typed browser application on top of the existing Supabase backend contract. It does not create a parallel database, does not expose service-role credentials, and does not execute arbitrary SQL from the browser.

Current status: partial implementation. The first authenticated control-center layer is present; several deeper CRUD/detail workflows require remote Supabase verification and dedicated record-list implementations before production use.

## Architecture

Flow:

```text
Browser UI
-> typed dashboard service layer
-> Supabase Auth / RPC / RLS-protected tables
-> existing Hiren Beyond database authorization
```

Implemented frontend files:

- `src/backend.ts`: Supabase client and typed RPC wrappers.
- `src/modules.ts`: dashboard module registry, permission gates, and backend operation map.
- `src/main.ts`: authenticated shell, organization selection, role-based navigation, overview, notifications, and module pages.
- `src/styles.css`: responsive SaaS dashboard styling.

The browser initializes Supabase with only:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

The dashboard never requires or references:

- `SUPABASE_SERVICE_ROLE_KEY`
- database passwords
- provider secrets
- webhook secrets
- OAuth client secrets
- AI provider keys

## Authentication

Authentication uses Supabase Auth through `@supabase/supabase-js`.

Implemented:

- email/password sign-in
- session restoration through Supabase client
- logout
- missing configuration state
- authenticated profile load through `get_my_profile`

The dashboard blocks application access when:

- there is no active session
- no active organization membership is returned
- required backend calls return an error

## Organization Scope

After login, the dashboard calls:

- `get_user_organizations()`
- `get_user_permissions(p_organization_id)`

The selected organization is stored only as UI state in `localStorage` under `hb_active_org`. The backend remains responsible for authorization and tenant isolation through RLS and RPC validation.

## Navigation

The sidebar is built from `src/modules.ts` and filtered by backend permission keys. Frontend filtering is for user experience only; it is not a security boundary.

Visible groups:

- Dashboard
- Recruitment
- Clients
- AI & Automation
- Platform
- Admin

Implemented top-level sections:

- Overview
- Organizations
- Users & Roles
- Candidates
- Jobs
- Applications
- Matching
- Assessments
- Interviews
- Clients
- AI Assistants
- Workflows
- Notifications
- Analytics
- Billing
- Integrations
- Search
- Public API
- System Activity
- Platform Settings

## Roles And Permissions

The dashboard supports role-based navigation through `get_user_permissions`.

Current UX behavior:

- sections with no explicit permission are visible to authenticated organization members
- sections with required permissions are visible only when a matching permission key is returned
- platform administrators are detected through the `platform.admin` permission or a platform role name

Backend authority remains with:

- Supabase Auth identity
- RLS policies
- security definer RPCs
- role and permission tables

## Pages

### Login

Purpose: authenticate into the client control center.

Backend:

- Supabase Auth
- `get_my_profile`
- `get_user_organizations`

### Overview

Purpose: show real organization metrics and operational status.

Backend:

- `get_organization_summary`
- `get_dashboard_metrics`
- `get_notification_badge_count`
- `list_notifications`

No fake metrics are rendered. If the backend returns no rows, the UI shows an empty state.

### Notifications

Purpose: show in-app notifications and unread status.

Backend:

- `list_notifications`
- `get_notification_badge_count`

### Module Pages

Purpose: expose role-gated business modules with backend operation mapping and UI states.

Each module page includes:

- search control
- filter controls
- date range control
- backend read operations
- authorized write operations
- empty state
- implementation status

The first implementation intentionally does not render fake record rows. Real record tables should be added one module at a time using the mapped RPC/table surfaces.

## Backend Dependencies

Required migrations/contracts:

- `20260915002300_frontend_integration_contract.sql`
- `20260915002301_fix_frontend_config.sql`
- generated or curated `types/database.types.ts`
- `types/frontend-contract.ts`

Key required RPCs:

- `get_my_profile`
- `get_user_organizations`
- `get_user_permissions`
- `get_notification_badge_count`
- `get_organization_summary`
- `get_dashboard_metrics`
- `list_notifications`

## Environment Variables

Safe browser variables:

```bash
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_API_BASE_URL=
```

Server-only variables must stay out of browser bundles and `.env` files committed to source control.

## Deployment

Build command:

```bash
npm run build
```

Preview command:

```bash
npm run preview
```

Production hosting must inject only public Vite variables. Configure Supabase Auth redirect URLs for the deployed dashboard origin.

## Security

Implemented security controls:

- no service-role key usage
- no arbitrary SQL UI
- no direct privileged credentials
- module visibility based on backend permission RPCs
- active organization loaded from backend membership
- all real data loaded through Supabase Auth context
- empty/error states instead of fake records

Security limitations:

- remote RLS verification was not completed in this local pass
- some module pages are mapped shells pending record-list implementation
- billing checkout/customer portal runtime is not present in this repository
- public API HTTP runtime is not present in this repository

## Limitations

This implementation is not yet the full Task 26 completion. It is the control-center foundation with real auth, role-gated navigation, overview data, notifications, and module mapping.

Before marking production ready:

- run Supabase remote verification
- confirm all Task 23 RPCs exist in the remote project
- implement live server-side record tables per module
- add detail pages and mutation flows one module at a time
- test role isolation with real users across organizations
- verify private storage access for candidate documents and analytics exports
