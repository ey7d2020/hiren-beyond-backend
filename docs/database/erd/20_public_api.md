# 20 Public API

Owns external API applications, keys, scopes, usage, request logs, rate limits, endpoint catalog, idempotency, webhook subscriptions, and documentation metadata.

External dependencies: organizations, jobs, candidates, applications.

```mermaid
erDiagram
    api_applications {
        uuid id PK
        uuid organization_id FK
        text name
        text status
    }
    api_keys {
        uuid id PK
        uuid api_application_id FK
        text key_prefix
        text status
    }
    api_scopes {
        uuid id PK
        text scope_key
    }
    api_key_scopes {
        uuid api_key_id FK
        uuid api_scope_id FK
    }
    api_usage_records {
        uuid id PK
        uuid api_application_id FK
        text endpoint
    }
    api_request_logs {
        uuid id PK
        uuid api_application_id FK
        text request_id
    }
    api_rate_limits {
        uuid id PK
        uuid api_application_id FK
    }
    api_endpoints {
        uuid id PK
        text path
        text method
    }
    api_idempotency_records {
        uuid id PK
        uuid api_application_id FK
        text idempotency_key
    }
    api_webhook_subscriptions {
        uuid id PK
        uuid api_application_id FK
        text target_url
    }
    api_documentation {
        uuid id PK
        text doc_key
    }

    api_applications ||--o{ api_keys : keys
    api_keys ||--o{ api_key_scopes : scopes
    api_scopes ||--o{ api_key_scopes : granted
    api_applications ||--o{ api_usage_records : usage
    api_applications ||--o{ api_request_logs : logs
    api_applications ||--o{ api_rate_limits : limits
    api_applications ||--o{ api_idempotency_records : idempotency
    api_applications ||--o{ api_webhook_subscriptions : webhooks
```

Note: local migrations implement the database API layer and OpenAPI documentation. No `supabase/functions` directory is present in this repository snapshot.

