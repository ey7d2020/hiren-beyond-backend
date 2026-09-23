# 05 CV Intelligence

Owns CV processing, extraction, AI analysis, and human review records.

External dependencies: `candidate_documents`, `candidates`, storage bucket `candidate-documents`.

```mermaid
erDiagram
    cv_processing_jobs {
        uuid id PK
        uuid candidate_document_id FK
        text status
        text processing_type
    }
    cv_processing_metadata {
        uuid id PK
        uuid processing_job_id FK
        jsonb metadata
    }
    cv_extracted_content {
        uuid id PK
        uuid candidate_document_id FK
        uuid processing_job_id FK
        text extracted_text
    }
    candidate_cv_profiles {
        uuid id PK
        uuid candidate_id FK
        uuid candidate_document_id FK
        numeric confidence_score
    }
    candidate_cv_ai_analysis {
        uuid id PK
        uuid candidate_id FK
        uuid cv_profile_id FK
        jsonb analysis_payload
    }
    candidate_cv_review_items {
        uuid id PK
        uuid candidate_id FK
        uuid cv_profile_id FK
        text status
    }

    cv_processing_jobs ||--o{ cv_processing_metadata : metadata
    cv_processing_jobs ||--o{ cv_extracted_content : extracts
    cv_extracted_content ||--o| candidate_cv_profiles : structures
    candidate_cv_profiles ||--o{ candidate_cv_ai_analysis : analyzed
    candidate_cv_profiles ||--o{ candidate_cv_review_items : review_items
```

Layout note: show the pipeline left-to-right as processing job, extracted content, structured profile, AI analysis, review.

