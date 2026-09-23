# Hiren Beyond — Security Architecture & Row Level Security (RLS)

## Security Architecture Principles

In Hiren Beyond, security is enforced **at the database tier** using PostgreSQL Row Level Security (RLS). Application servers and frontend clients interact with the database via authenticated Supabase sessions, where each query executes under the caller's JWT identity (`auth.uid()`).

```mermaid
flowchart TD
    Request[Incoming Data Request] --> AuthCheck{Is User Authenticated?}
    AuthCheck -- No --> BlockAnon[Anonymous Access Blocked]
    AuthCheck -- Yes --> Evaluator[Postgres RLS Policy Engine]
    
    Evaluator --> HelperPlatform{is_platform_admin?}
    HelperPlatform -- Yes --> AllowFull[Grant Access]
    HelperPlatform -- No --> HelperOrg{is_org_member?}
    
    HelperOrg -- No --> CheckSelf{Target = auth.uid()?}
    HelperOrg -- Yes --> CheckPerm{has_org_permission?}
    
    CheckPerm -- Yes --> AllowScoped[Grant Scoped Access]
    CheckPerm -- No --> Deny[403 Denied]
    
    CheckSelf -- Yes --> AllowPersonal[Grant Personal Access]
    CheckSelf -- No --> Deny
```

---

## Zero-Trust Guardrails

1. **Anonymous Access Blocked**: All private tables reject unauthenticated (`anon`) queries. Policies explicitly target `TO authenticated`.
2. **No Wildcard `TRUE` Policies**: No policy permits unrestricted global access (`USING (true)` or `WITH CHECK (true)` on mutable tables).
3. **Immutability of Audit Logs**: The `audit_logs` table has no `UPDATE` or `DELETE` policies, guaranteeing that once written, audit entries cannot be modified or deleted by non-superusers.
4. **Anti-Escalation Safeguards**: Organization administrators cannot assign the `platform_admin` role.
5. **No Secret Keys in Frontend**: Client applications connect using the public `ANON_KEY`. The privileged `SERVICE_ROLE_KEY` is reserved strictly for automated backend functions and secure administrative tasks.

---

## Detailed Policy Catalog

### 1. `profiles`
*RLS Enabled: YES*

- **`profiles_select_own_or_platform_admin` (SELECT)**:
  ```sql
  id = auth.uid() OR public.is_platform_admin(auth.uid())
  ```
  *Ensures users only view their own profile, while platform administrators retain operational visibility.*

- **`profiles_update_own_or_platform_admin` (UPDATE)**:
  ```sql
  (id = auth.uid() OR public.is_platform_admin(auth.uid()))
  ```
  *Restricts profile modifications strictly to the account owner or platform admin.*

- **`profiles_insert_own_or_platform_admin` (INSERT)**:
  ```sql
  (id = auth.uid() OR public.is_platform_admin(auth.uid()))
  ```
  *Guarantees a newly signed-up user can only insert a profile matching their auth user ID.*

---

### 2. `organizations`
*RLS Enabled: YES*

- **`organizations_select_member_or_platform_admin` (SELECT)**:
  ```sql
  public.is_org_member(id, auth.uid()) OR public.is_platform_admin(auth.uid())
  ```
  *Cross-tenant isolation: Only verified members of the organization can view its profile.*

- **`organizations_insert_platform_admin` (INSERT)**:
  ```sql
  public.is_platform_admin(auth.uid())
  ```
  *Only platform administrators can register new root organizations.*

- **`organizations_update_authorized_admin` (UPDATE)**:
  ```sql
  public.has_org_permission(id, 'organizations.manage', auth.uid()) OR public.is_platform_admin(auth.uid())
  ```
  *Only members possessing the `organizations.manage` capability can modify tenant details.*

- **`organizations_delete_platform_admin` (DELETE)**:
  ```sql
  public.is_platform_admin(auth.uid())
  ```
  *Organization removal is restricted to platform administrators.*

---

### 3. `organization_members`
*RLS Enabled: YES*

- **`org_members_select_own_or_permitted` (SELECT)**:
  ```sql
  user_id = auth.uid()
  OR public.has_org_permission(organization_id, 'members.read', auth.uid())
  OR public.is_platform_admin(auth.uid())
  ```
  *Users can view their own membership rows, and organization managers can inspect their member directory.*

- **`org_members_insert_authorized` (INSERT)**:
  ```sql
  (public.has_org_permission(organization_id, 'members.manage', auth.uid())
   AND role_id NOT IN (SELECT id FROM public.roles WHERE key = 'platform_admin'))
  OR public.is_platform_admin(auth.uid())
  ```
  *Allows managers with `members.manage` to add team members, with an anti-escalation filter blocking self-promotion to `platform_admin`.*

- **`org_members_update_authorized` (UPDATE)**:
  ```sql
  (public.has_org_permission(organization_id, 'members.manage', auth.uid())
   AND role_id NOT IN (SELECT id FROM public.roles WHERE key = 'platform_admin'))
  OR public.is_platform_admin(auth.uid())
  ```
  *Enforces the same anti-escalation constraint on role or status updates.*

- **`org_members_delete_authorized` (DELETE)**:
  ```sql
  public.has_org_permission(organization_id, 'members.manage', auth.uid())
  OR public.is_platform_admin(auth.uid())
  ```
  *Allows organization managers to revoke memberships.*

---

### 4. `roles`, `permissions`, `role_permissions`
*RLS Enabled: YES*

- **`roles_select_authenticated` / `permissions_select_authenticated` / `role_permissions_select_authenticated` (SELECT)**:
  ```sql
  true (for authenticated users)
  ```
  *Allows all authenticated sessions to inspect the permission catalogue for UI rendering and permission checking.*

- **`roles_write_platform_admin` / `permissions_write_platform_admin` / `role_permissions_write_platform_admin` (ALL)**:
  ```sql
  public.is_platform_admin(auth.uid())
  ```
  *Only platform administrators can add or adjust system roles and permission grants.*

---

### 5. `audit_logs`
*RLS Enabled: YES*

- **`audit_logs_insert_authenticated` (INSERT)**:
  ```sql
  actor_user_id IS NULL OR actor_user_id = auth.uid() OR public.is_platform_admin(auth.uid())
  ```
  *Allows authenticated users and backend triggers to record actions without spoofing another actor ID.*

- **`audit_logs_select_scoped` (SELECT)**:
  ```sql
  (organization_id IS NOT NULL AND public.has_org_permission(organization_id, 'audit_logs.read', auth.uid()))
  OR public.is_platform_admin(auth.uid())
  ```
  *Ensures organization managers only see their own organization's logs, while platform admins view all logs.*

- **UPDATE / DELETE**:
  *No policies exist. Attempts to modify or delete logs are rejected by default.*
