# 17 Platform Admin

Owns platform settings, feature flags, announcements, support sessions, and platform security event views.

External dependencies: Identity, Security, Billing entitlements.

```mermaid
erDiagram
    feature_flags {
        uuid id PK
        text feature_key
    }
    feature_flag_targets {
        uuid id PK
        uuid feature_flag_id FK
    }
    organization_feature_overrides {
        uuid id PK
        uuid organization_id FK
        uuid feature_flag_id FK
    }
    platform_settings {
        uuid id PK
        text setting_key
    }
    platform_announcements {
        uuid id PK
        text title
        text severity
    }
    support_access_sessions {
        uuid id PK
        uuid target_user_id FK
        uuid granted_by FK
        text scope
    }
    platform_security_events {
        uuid id PK
        text event_type
        text severity
    }

    feature_flags ||--o{ feature_flag_targets : targets
    feature_flags ||--o{ organization_feature_overrides : overrides
```

Support access must remain time-boxed and audited.

