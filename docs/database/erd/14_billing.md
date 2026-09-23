# 14 Billing / Entitlements

Billing is currently represented by subscription fields and feature entitlement tables, not a full payment-provider schema.

External dependencies: `organizations`, Platform Admin.

```mermaid
erDiagram
    organizations {
        uuid id PK
        text subscription_plan
        text subscription_status
        timestamptz trial_ends_at
    }
    feature_flags {
        uuid id PK
        text feature_key
        boolean is_enabled
    }
    feature_flag_targets {
        uuid id PK
        uuid feature_flag_id FK
        text target_type
    }
    organization_feature_overrides {
        uuid id PK
        uuid organization_id FK
        uuid feature_flag_id FK
        boolean enabled
    }

    organizations ||--o{ organization_feature_overrides : overrides
    feature_flags ||--o{ feature_flag_targets : targets
    feature_flags ||--o{ organization_feature_overrides : org_override
```

Missing from local migrations: checkout sessions, invoices, payment customers, subscriptions table, and customer portal runtime. Treat billing as entitlement primitives until those are implemented or verified elsewhere.

