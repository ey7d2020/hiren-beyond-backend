# 15 Integrations

Owns integration providers, connections, OAuth sessions, jobs, attempts, events, health checks, webhooks, and spreadsheet mappings.

External dependencies: organizations, profiles, notifications, interviews/calendar, public API.

```mermaid
erDiagram
    integration_providers {
        uuid id PK
        text provider_key
    }
    integration_connections {
        uuid id PK
        uuid organization_id FK
        uuid provider_id FK
        text status
    }
    integration_oauth_sessions {
        uuid id PK
        uuid organization_id FK
        uuid provider_id FK
        text state
    }
    integration_jobs {
        uuid id PK
        uuid connection_id FK
        text job_type
        text status
    }
    integration_job_attempts {
        uuid id PK
        uuid integration_job_id FK
        text status
    }
    integration_events {
        uuid id PK
        uuid connection_id FK
        text event_type
    }
    integration_health_checks {
        uuid id PK
        uuid connection_id FK
        text status
    }
    external_api_connections {
        uuid id PK
        uuid organization_id FK
    }
    incoming_webhook_events {
        uuid id PK
        uuid organization_id FK
        text provider
    }
    outbound_webhooks {
        uuid id PK
        uuid organization_id FK
        text event_type
    }
    webhook_deliveries {
        uuid id PK
        uuid outbound_webhook_id FK
        text status
    }
    whatsapp_templates {
        uuid id PK
        uuid organization_id FK
        text template_name
    }
    spreadsheet_mappings {
        uuid id PK
        uuid connection_id FK
    }

    integration_providers ||--o{ integration_connections : connections
    integration_providers ||--o{ integration_oauth_sessions : oauth
    integration_connections ||--o{ integration_jobs : jobs
    integration_jobs ||--o{ integration_job_attempts : attempts
    integration_connections ||--o{ integration_events : events
    integration_connections ||--o{ integration_health_checks : health
    integration_connections ||--o{ spreadsheet_mappings : mappings
    outbound_webhooks ||--o{ webhook_deliveries : deliveries
```

