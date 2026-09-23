# 08 Assessments

Owns assessment templates, invitations, attempts, answers, scoring outputs, reviews, voice results, and candidate readiness.

External dependencies: `applications`, `jobs`, `candidates`, storage bucket `assessment-audio`.

```mermaid
erDiagram
    assessment_templates {
        uuid id PK
        uuid organization_id FK
        text title
    }
    assessment_sections {
        uuid id PK
        uuid assessment_template_id FK
        text title
    }
    assessment_questions {
        uuid id PK
        uuid assessment_section_id FK
        text question_text
    }
    assessment_question_options {
        uuid id PK
        uuid assessment_question_id FK
        text option_text
    }
    job_assessments {
        uuid id PK
        uuid job_id FK
        uuid assessment_template_id FK
    }
    assessment_invitations {
        uuid id PK
        uuid application_id FK
        uuid assessment_template_id FK
        text status
    }
    assessment_attempts {
        uuid id PK
        uuid assessment_invitation_id FK
        text status
    }
    assessment_answers {
        uuid id PK
        uuid assessment_attempt_id FK
        uuid assessment_question_id FK
    }
    assessment_results {
        uuid id PK
        uuid assessment_attempt_id FK
        numeric total_score
    }
    assessment_section_results {
        uuid id PK
        uuid assessment_result_id FK
        uuid assessment_section_id FK
    }
    assessment_question_results {
        uuid id PK
        uuid assessment_result_id FK
        uuid assessment_question_id FK
    }
    voice_assessment_results {
        uuid id PK
        uuid assessment_answer_id FK
        numeric fluency_score
    }
    assessment_reviews {
        uuid id PK
        uuid assessment_result_id FK
        uuid reviewer_id FK
    }
    candidate_readiness {
        uuid id PK
        uuid candidate_id FK
        uuid job_id FK
        numeric readiness_score
    }

    assessment_templates ||--o{ assessment_sections : sections
    assessment_sections ||--o{ assessment_questions : questions
    assessment_questions ||--o{ assessment_question_options : options
    assessment_templates ||--o{ job_assessments : required_for
    assessment_templates ||--o{ assessment_invitations : invitations
    assessment_invitations ||--o{ assessment_attempts : attempts
    assessment_attempts ||--o{ assessment_answers : answers
    assessment_attempts ||--o{ assessment_results : result
    assessment_results ||--o{ assessment_section_results : section_scores
    assessment_results ||--o{ assessment_question_results : question_scores
    assessment_answers ||--o{ voice_assessment_results : voice
    assessment_results ||--o{ assessment_reviews : reviews
```

