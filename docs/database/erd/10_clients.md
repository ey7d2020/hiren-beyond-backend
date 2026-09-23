# 10 Clients

Owns client portal relationships, access grants, candidate shares, feedback, scorecards, information requests, interview requests, hiring decisions, and activity.

External dependencies: `organizations`, `jobs`, `applications`, `candidates`, `candidate_documents`.

```mermaid
erDiagram
    client_relationships {
        uuid id PK
        uuid organization_id FK
        uuid client_organization_id FK
        text status
    }
    client_contacts {
        uuid id PK
        uuid client_relationship_id FK
        uuid user_id FK
    }
    client_job_access {
        uuid id PK
        uuid client_relationship_id FK
        uuid job_id FK
    }
    client_candidate_shares {
        uuid id PK
        uuid application_id FK
        uuid client_relationship_id FK
        text status
    }
    client_candidate_profiles {
        uuid id PK
        uuid client_candidate_share_id FK
    }
    client_document_access {
        uuid id PK
        uuid client_candidate_share_id FK
        uuid candidate_document_id FK
    }
    client_candidate_feedback {
        uuid id PK
        uuid client_candidate_share_id FK
        text decision
    }
    client_feedback_history {
        uuid id PK
        uuid client_candidate_feedback_id FK
    }
    client_scorecard_templates {
        uuid id PK
        uuid client_relationship_id FK
    }
    client_scorecard_sections {
        uuid id PK
        uuid client_scorecard_template_id FK
    }
    client_scorecard_questions {
        uuid id PK
        uuid client_scorecard_section_id FK
    }
    client_scorecard_responses {
        uuid id PK
        uuid client_candidate_feedback_id FK
    }
    client_interview_requests {
        uuid id PK
        uuid client_candidate_share_id FK
    }
    client_information_requests {
        uuid id PK
        uuid client_candidate_share_id FK
    }
    client_hiring_decisions {
        uuid id PK
        uuid client_candidate_share_id FK
    }
    client_activity_events {
        uuid id PK
        uuid client_relationship_id FK
        text event_type
    }

    client_relationships ||--o{ client_contacts : contacts
    client_relationships ||--o{ client_job_access : jobs
    client_relationships ||--o{ client_candidate_shares : shares
    client_candidate_shares ||--o{ client_candidate_profiles : redacted_profile
    client_candidate_shares ||--o{ client_document_access : documents
    client_candidate_shares ||--o{ client_candidate_feedback : feedback
    client_candidate_shares ||--o{ client_interview_requests : interview_requests
    client_candidate_shares ||--o{ client_information_requests : info_requests
    client_candidate_shares ||--o{ client_hiring_decisions : decisions
    client_candidate_feedback ||--o{ client_feedback_history : history
    client_scorecard_templates ||--o{ client_scorecard_sections : sections
    client_scorecard_sections ||--o{ client_scorecard_questions : questions
    client_candidate_feedback ||--o{ client_scorecard_responses : scorecard
    client_relationships ||--o{ client_activity_events : activity
```

