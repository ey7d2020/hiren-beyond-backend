# 01 Identity & Organizations

Owns tenant identity, user profiles, roles, permissions, and membership.

External dependencies: Supabase Auth users.

```mermaid
erDiagram
    profiles {
        uuid id PK
        text email
        text full_name
        boolean is_active
    }
    organizations {
        uuid id PK
        text name
        text slug
        text subscription_plan
        text subscription_status
    }
    roles {
        uuid id PK
        uuid organization_id FK
        text name
    }
    permissions {
        uuid id PK
        text key
        text category
    }
    role_permissions {
        uuid role_id FK
        uuid permission_id FK
    }
    organization_members {
        uuid id PK
        uuid organization_id FK
        uuid user_id FK
        uuid role_id FK
    }
    audit_logs {
        uuid id PK
        uuid organization_id FK
        uuid actor_id FK
        text action
    }

    profiles ||--o{ organization_members : user
    organizations ||--o{ organization_members : members
    organizations ||--o{ roles : defines
    roles ||--o{ organization_members : assigned
    roles ||--o{ role_permissions : grants
    permissions ||--o{ role_permissions : included
    organizations ||--o{ audit_logs : scopes
    profiles ||--o{ audit_logs : actor
```

Layout note: keep `organizations` and `profiles` at the top, membership/roles in the middle, and audit logs below.

