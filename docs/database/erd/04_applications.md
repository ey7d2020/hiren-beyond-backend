# 04 Applications / ATS

Owns the core candidate-to-job application and ATS pipeline.

External dependencies: `candidates`, `jobs`, `profiles`, `organizations`.

```mermaid
erDiagram
    ats_stages {
        uuid id PK
        uuid organization_id FK
        text name
        int order_index
    }
    applications {
        uuid id PK
        uuid organization_id FK
        uuid candidate_id FK
        uuid job_id FK
        uuid current_stage_id FK
        text status
    }
    application_stage_history {
        uuid id PK
        uuid application_id FK
        uuid from_stage_id FK
        uuid to_stage_id FK
    }
    application_events {
        uuid id PK
        uuid application_id FK
        text event_type
    }
    application_notes {
        uuid id PK
        uuid application_id FK
        uuid author_id FK
    }
    application_screening_answers {
        uuid id PK
        uuid application_id FK
        uuid job_question_id FK
    }
    recruiter_application_views {
        uuid id PK
        uuid application_id FK
        uuid recruiter_id FK
    }

    ats_stages ||--o{ applications : current
    applications ||--o{ application_stage_history : history
    applications ||--o{ application_events : events
    applications ||--o{ application_notes : notes
    applications ||--o{ application_screening_answers : answers
    applications ||--o{ recruiter_application_views : viewed_by
```

Related but owned elsewhere: assessments, interviews, matching, and client shares all depend on `applications`.

