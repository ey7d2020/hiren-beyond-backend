# Task 17 - Platform Administration, Super Admin and Operational Controls

**Migration**: 20260915001700_platform_administration.sql
**Fix Migration**: 20260915001701_fix_admin_status_constraints.sql
**Test Suite**: docs/backend/test-platform-admin.sql (28 tests - all passing)
**Status**: Deployed to remote Supabase project pthkmkwrqjyseonysjzu

## Overview

Task 17 delivers the centralized platform administration control plane for authorized platform administrators. Provides safe, auditable, multi-tenant-aware tooling for managing organizations, users, feature rollouts, platform configuration, system health monitoring, and support access - all enforced server-side.

## New Tables (7)

- **feature_flags** - Feature toggle registry (status: draft/active/disabled/deprecated)
- **feature_flag_targets** - Granular per-org/user/plan targeting (unique per flag+type+target)
- **organization_feature_overrides** - Per-org overrides with expiry, limit_value, reason
- **platform_settings** - Typed KV config (string/number/boolean/json) with is_public/is_sensitive flags
- **platform_announcements** - Broadcast messages with severity and target scoping
- **support_access_sessions** - Time-bounded support access (max 24h, reason >= 10 chars required)
- **platform_security_events** - Immutable security event log

## Extended Constraints (fix migration 001701)

- organizations.status: added archived value
- profiles.status: added pending value

## New Permissions (15)

All in platform.* namespace, seeded and mapped to platform_admin role:
platform.organizations.read/manage, platform.users.read/manage,
platform.roles.manage, platform.permissions.manage, platform.settings.manage,
platform.features.manage, platform.plans.manage, platform.reference_data.manage,
platform.integrations.manage, platform.ai.manage, platform.audit.read,
platform.operations.read, platform.support.manage

## New Roles (2)

- **platform_operator** - Monitoring + support + integrations oversight
- **platform_support** - Read-only: orgs, users, audit logs

## RPCs (22)

### Public (no auth)
- get_public_platform_settings() - returns is_public=true, is_sensitive=false settings only
- check_feature_enabled(key, org_id, user_id) - resolves with override priority chain

### Admin Only (is_platform_admin required)

Dashboard & Monitoring:
- get_platform_dashboard() - aggregate platform metrics
- get_platform_health() - CV queue, AI latency, webhook failures
- get_platform_audit_summary() - recent security events and critical audits

Organization Management:
- search_platform_organizations(query, status, limit, offset)
- get_platform_organization_details(org_id)
- suspend_organization(org_id, reason) - with audit + security event
- reactivate_organization(org_id, reason) - with audit
- archive_organization(org_id, reason) - soft archive, data preserved
- create_platform_announcement(title, message, severity, target_type, ...)

User Management:
- search_platform_users(query, status, limit, offset)
- get_platform_user_details(user_id)
- suspend_platform_user(user_id, reason) - with security event
- reactivate_platform_user(user_id, reason) - with audit
- disable_platform_user(user_id, reason) - deactivates all memberships

Feature Flags & Settings:
- grant_organization_feature_override(org_id, key, enabled, limit, reason, expires_at)
- update_platform_setting(key, value, reason) - with type validation + audit

Support Access:
- create_support_access_session(target_user_id, org_id, reason, scope, duration_minutes)
- revoke_support_access_session(session_id, reason)

Audit & Operations:
- search_audit_logs(org_id, actor_id, action, from, to, limit, offset)
- retry_failed_cv_job(job_id, reason)

## Feature Flag Resolution Priority

check_feature_enabled resolves in this order:
1. organization_feature_overrides (highest, respects expires_at)
2. feature_flag_targets for organization
3. feature_flag_targets for user
4. feature_flags.default_enabled (lowest)

## RLS Summary

| Table | Read | Write |
|-------|------|-------|
| feature_flags | Active flags public | platform_admin only |
| feature_flag_targets | Own org/user targets | platform_admin only |
| organization_feature_overrides | Own org members | platform_admin only |
| platform_settings | is_public=true non-sensitive | platform_admin only |
| platform_announcements | Active announcements | platform_admin only |
| support_access_sessions | platform_admin only | platform_admin only |
| platform_security_events | platform_admin read | SECURITY DEFINER insert |

## Security Guarantees

1. Server-side authorization: is_platform_admin() checked first in every admin RPC
2. Privilege escalation prevention: denied attempts logged to platform_security_events
3. Self-protection: cannot suspend/disable own account
4. Reason requirements: archive org, disable user, create support session require >= 10 char reason
5. Support session limits: max 24 hours, never exposes credentials/tokens/payment data
6. Sensitive settings: is_sensitive=true never returned by any public RPC
7. Zero physical deletion: all lifecycle ops are status transitions only
8. Audit completeness: every admin action recorded in audit_logs and/or platform_security_events

## Test Suite (28 tests - all passing)

1.  platform_admin role is system role with >= 15 platform.* perms
2.  get_public_platform_settings returns expected keys
3.  Sensitive settings excluded from public RPC
4.  value_type validity and is_public+is_sensitive constraint
5.  feature_flags columns and >= 2 RLS policies
6.  Disabled/non-existent flag returns false
7.  default_enabled=true flag returns true
8.  Org targeting enables/disables correctly
9.  Org override takes priority over flag target
10. Expired override falls back to default_enabled
11. support_access_sessions check constraints (structural)
12. Org lifecycle status transitions (active to suspended to archived)
13. FK schema confirms status update does not cascade-delete
14. profiles.status column exists for lifecycle transitions
15. platform_security_events columns and >= 3 indexes
16. Invalid event_type rejected by check constraint
17. platform_announcements columns and >= 2 RLS policies
18. feature_flag_targets unique constraint enforced
19. platform_settings key uniqueness enforced
20. is_public+is_sensitive conflict constraint enforced
21. Support session check constraints verified (structural)
22. All 22 admin RPCs registered
23. All 15 platform.* permissions mapped to platform_admin
24. platform_operator and platform_support roles with correct perms
25. is_platform_admin returns false for random UUID and NULL
26. All 11 critical admin RPCs are SECURITY DEFINER
27. support_access_sessions status check constraint exists
28. All 7 admin tables have >= 2 indexes each
