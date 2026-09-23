# 09 Interviews & Hiring

Owns interview templates, rounds, scheduling, participants, availability, feedback, scorecards, events, and hiring decisions.

External dependencies: `applications`, `candidates`, `profiles`.

```mermaid
erDiagram
    interview_templates {
        uuid id PK
        uuid organization_id FK
        text name
    }
    interview_rounds {
        uuid id PK
        uuid interview_template_id FK
        text name
    }
    application_interview_rounds {
        uuid id PK
        uuid application_id FK
        uuid interview_round_id FK
    }
    interviews {
        uuid id PK
        uuid application_id FK
        uuid interview_round_id FK
        text status
    }
    interview_participants {
        uuid id PK
        uuid interview_id FK
        uuid user_id FK
    }
    candidate_availability {
        uuid id PK
        uuid candidate_id FK
    }
    availability_requests {
        uuid id PK
        uuid candidate_id FK
        uuid application_id FK
    }
    availability_slots {
        uuid id PK
        uuid availability_request_id FK
    }
    interview_schedule_history {
        uuid id PK
        uuid interview_id FK
        text action
    }
    interview_scorecard_sections {
        uuid id PK
        uuid interview_template_id FK
    }
    interview_scorecard_questions {
        uuid id PK
        uuid interview_scorecard_section_id FK
    }
    interview_feedback {
        uuid id PK
        uuid interview_id FK
        uuid reviewer_id FK
    }
    interview_scorecard_responses {
        uuid id PK
        uuid interview_feedback_id FK
        uuid interview_scorecard_question_id FK
    }
    hiring_decisions {
        uuid id PK
        uuid application_id FK
        text decision
    }
    hiring_decision_history {
        uuid id PK
        uuid hiring_decision_id FK
    }
    interview_events {
        uuid id PK
        uuid interview_id FK
        text event_type
    }

    interview_templates ||--o{ interview_rounds : rounds
    interview_templates ||--o{ interview_scorecard_sections : scorecard
    interview_rounds ||--o{ application_interview_rounds : assigned
    application_interview_rounds ||--o{ interviews : scheduled
    interviews ||--o{ interview_participants : participants
    interviews ||--o{ interview_schedule_history : history
    interviews ||--o{ interview_feedback : feedback
    interviews ||--o{ interview_events : events
    interview_scorecard_sections ||--o{ interview_scorecard_questions : questions
    interview_feedback ||--o{ interview_scorecard_responses : responses
    availability_requests ||--o{ availability_slots : slots
    hiring_decisions ||--o{ hiring_decision_history : history
```

