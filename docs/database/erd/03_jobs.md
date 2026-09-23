# 03 Jobs

Owns job postings, requirements, marketplace metadata, and job search inputs.

External dependencies: `organizations`, Globalization reference tables.

```mermaid
erDiagram
    job_categories {
        uuid id PK
        text name
        text slug
    }
    jobs {
        uuid id PK
        uuid organization_id FK
        uuid category_id FK
        text title
        text status
    }
    job_requirements {
        uuid id PK
        uuid job_id FK
        text requirement_type
    }
    job_skills {
        uuid id PK
        uuid job_id FK
        text skill_name
    }
    job_languages {
        uuid id PK
        uuid job_id FK
        text language_code
    }
    job_questions {
        uuid id PK
        uuid job_id FK
        text question_text
    }

    job_categories ||--o{ jobs : categorizes
    jobs ||--o{ job_requirements : requirements
    jobs ||--o{ job_skills : skills
    jobs ||--o{ job_languages : languages
    jobs ||--o{ job_questions : screening
```

Related but owned elsewhere: `job_assessments` is in Assessments, `job_daily_metrics` in Analytics, and `job_search_documents` in Search.

