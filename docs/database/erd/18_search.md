# 18 Search

Owns search configurations, search documents, embeddings, history, analytics, rate limits, and alerts.

External dependencies: candidates, jobs, applications, talent pools.

```mermaid
erDiagram
    search_configurations {
        uuid id PK
        uuid organization_id FK
        text search_type
    }
    candidate_search_documents {
        uuid candidate_id PK
        uuid organization_id FK
        tsvector search_vector
    }
    job_search_documents {
        uuid job_id PK
        uuid organization_id FK
        tsvector search_vector
    }
    search_embeddings {
        uuid id PK
        text entity_type
        uuid entity_id
    }
    search_history {
        uuid id PK
        uuid user_id FK
        text search_type
    }
    search_analytics {
        uuid id PK
        uuid organization_id FK
        text search_type
    }
    search_rate_limits {
        uuid id PK
        uuid user_id FK
    }
    search_alerts {
        uuid id PK
        uuid user_id FK
        jsonb filters
    }

    search_configurations ||--o{ search_alerts : defaults
    candidate_search_documents ||--o{ search_embeddings : vector
    job_search_documents ||--o{ search_embeddings : vector
    search_history ||--o{ search_analytics : aggregates
```

AI-generated filters must be validated before search RPCs execute.

