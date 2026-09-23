# 02 Candidates

Owns canonical candidate records and structured profile data.

External dependencies: `profiles`, `organizations`, Globalization reference tables.

```mermaid
erDiagram
    candidates {
        uuid id PK
        uuid organization_id FK
        uuid profile_id FK
        text status
    }
    candidate_profiles {
        uuid id PK
        uuid candidate_id FK
        text headline
    }
    candidate_skills {
        uuid id PK
        uuid candidate_id FK
        text skill_name
    }
    candidate_languages {
        uuid id PK
        uuid candidate_id FK
        text language_code
    }
    candidate_experience {
        uuid id PK
        uuid candidate_id FK
        text company
    }
    candidate_education {
        uuid id PK
        uuid candidate_id FK
        text institution
    }
    candidate_certifications {
        uuid id PK
        uuid candidate_id FK
        text name
    }
    candidate_preferences {
        uuid id PK
        uuid candidate_id FK
    }
    candidate_documents {
        uuid id PK
        uuid candidate_id FK
        text storage_path
    }

    candidates ||--|| candidate_profiles : profile
    candidates ||--o{ candidate_skills : skills
    candidates ||--o{ candidate_languages : languages
    candidates ||--o{ candidate_experience : experience
    candidates ||--o{ candidate_education : education
    candidates ||--o{ candidate_certifications : certifications
    candidates ||--o{ candidate_preferences : preferences
    candidates ||--o{ candidate_documents : documents
```

Related but owned elsewhere: `candidate_availability` is shown in Interviews; `candidate_readiness` is shown in Assessments; CV extraction tables are shown in CV Intelligence.

