# 11 Notifications

Owns notification templates, preferences, events, in-app notifications, delivery records, and attempts.

External dependencies: `profiles`, `organizations`, application/interview/assessment event sources.

```mermaid
erDiagram
    notification_types {
        uuid id PK
        text code
    }
    notification_templates {
        uuid id PK
        uuid notification_type_id FK
        text channel
    }
    notification_preferences {
        uuid id PK
        uuid user_id FK
        uuid notification_type_id FK
    }
    user_contact_channels {
        uuid id PK
        uuid user_id FK
        text channel
    }
    notification_events {
        uuid id PK
        uuid organization_id FK
        text event_type
    }
    notifications {
        uuid id PK
        uuid recipient_user_id FK
        uuid notification_type_id FK
        timestamptz read_at
    }
    notification_deliveries {
        uuid id PK
        uuid notification_id FK
        text channel
        text status
    }
    notification_delivery_attempts {
        uuid id PK
        uuid notification_delivery_id FK
        text status
    }

    notification_types ||--o{ notification_templates : templates
    notification_types ||--o{ notification_preferences : preferences
    notification_types ||--o{ notifications : type
    notification_events ||--o{ notifications : emits
    notifications ||--o{ notification_deliveries : deliveries
    notification_deliveries ||--o{ notification_delivery_attempts : attempts
```

