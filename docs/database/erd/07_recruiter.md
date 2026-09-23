# 07 Recruiter Operations

Owns recruiter-facing queues, saved searches, shortlists, bulk screening, and talent pools.

External dependencies: `applications`, `jobs`, `candidates`, Matching.

```mermaid
erDiagram
    recruiter_review_queue {
        uuid id PK
        uuid organization_id FK
        uuid application_id FK
        text priority
    }
    recruiter_saved_searches {
        uuid id PK
        uuid organization_id FK
        uuid recruiter_id FK
        jsonb filters
    }
    candidate_screening_summaries {
        uuid id PK
        uuid application_id FK
        uuid candidate_id FK
        text summary
    }
    candidate_shortlists {
        uuid id PK
        uuid job_id FK
        uuid candidate_id FK
        uuid created_by FK
    }
    bulk_screening_runs {
        uuid id PK
        uuid job_id FK
        text status
    }
    bulk_screening_candidates {
        uuid id PK
        uuid bulk_screening_run_id FK
        uuid candidate_id FK
        numeric score
    }
    talent_pools {
        uuid id PK
        uuid organization_id FK
        text name
    }
    talent_pool_members {
        uuid id PK
        uuid talent_pool_id FK
        uuid candidate_id FK
    }
    talent_pool_rules {
        uuid id PK
        uuid talent_pool_id FK
        jsonb rule_config
    }
    talent_pool_membership_events {
        uuid id PK
        uuid talent_pool_id FK
        uuid candidate_id FK
        text event_type
    }

    bulk_screening_runs ||--o{ bulk_screening_candidates : candidates
    talent_pools ||--o{ talent_pool_members : members
    talent_pools ||--o{ talent_pool_rules : rules
    talent_pools ||--o{ talent_pool_membership_events : history
```

Keep review queues and saved searches separate from pool membership to reduce line crossings.

