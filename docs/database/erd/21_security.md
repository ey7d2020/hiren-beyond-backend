# 21 Security

Security is cross-cutting. This diagram collects audit, retention, circuit breaker, RLS support, and support access structures.

External dependencies: all modules.

```mermaid
erDiagram
    audit_logs {
        uuid id PK
        uuid organization_id FK
        uuid actor_id FK
        text action
        text entity_type
    }
    platform_security_events {
        uuid id PK
        text event_type
        text severity
    }
    support_access_sessions {
        uuid id PK
        uuid target_user_id FK
        uuid granted_by FK
        timestamptz expires_at
    }
    provider_circuit_breakers {
        uuid id PK
        text provider_name
        text status
    }
    data_retention_policies {
        uuid id PK
        uuid organization_id FK
        text entity_type
    }
    data_retention_audit_logs {
        uuid id PK
        uuid data_retention_policy_id FK
        text action
    }
    roles {
        uuid id PK
        text name
    }
    permissions {
        uuid id PK
        text key
    }
    role_permissions {
        uuid role_id FK
        uuid permission_id FK
    }

    roles ||--o{ role_permissions : grants
    permissions ||--o{ role_permissions : included
    support_access_sessions ||--o{ audit_logs : audited_by
    data_retention_policies ||--o{ data_retention_audit_logs : purge_history
```

RLS policies are defined in the module migrations. This diagram intentionally does not duplicate every policy.

