# Hiren Beyond — Candidate Domain Architecture

## 1. Domain Overview

The Candidate Domain is the foundational core of the **Hiren Beyond** AI-powered career and recruitment platform. It captures candidate identities, professional achievements, verified competencies, linguistic fluencies, preferences, career milestones, and portfolio assets.

The candidate model is designed with strict normalization to empower:
- High-performance multi-criteria search (e.g. *French speakers in Egypt open to relocation*).
- Algorithmic and AI candidate-job matching.
- Objective CV parsing and qualification extraction.
- Continuous profile completion telemetry.

---

## 2. Entity Relationship Diagram

```mermaid
erDiagram
    profiles ||--|| candidates : "1-to-1 (user_id)"
    candidates ||--|| candidate_profiles : "1-to-1"
    candidates ||--o{ candidate_skills : "1-to-many"
    candidates ||--o{ candidate_languages : "1-to-many"
    candidates ||--o{ candidate_experience : "1-to-many"
    candidates ||--o{ candidate_education : "1-to-many"
    candidates ||--o{ candidate_certifications : "1-to-many"
    candidates ||--|| candidate_preferences : "1-to-1"
    candidates ||--o{ candidate_documents : "1-to-many"

    candidates {
        uuid id PK
        uuid user_id FK,UK
        text status
        integer profile_completion_percentage
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_profiles {
        uuid id PK
        uuid candidate_id FK,UK
        text headline
        text professional_summary
        text current_title
        numeric years_of_experience
        varchar country_code
        text city
        text location_text
        text remote_preference
        text_array job_type_preference
        text availability_status
        date available_from
        numeric salary_min
        numeric salary_max
        varchar salary_currency
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_skills {
        uuid id PK
        uuid candidate_id FK
        text skill_name
        text normalized_skill_name
        text skill_type
        text proficiency_level
        numeric years_of_experience
        boolean is_verified
        text source
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_languages {
        uuid id PK
        uuid candidate_id FK
        text language_name
        text normalized_language_name
        varchar language_code
        text proficiency_level
        boolean is_native
        boolean is_verified
        text source
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_experience {
        uuid id PK
        uuid candidate_id FK
        text company_name
        text job_title
        text employment_type
        date start_date
        date end_date
        boolean is_current
        text description
        text achievements
        text location
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_education {
        uuid id PK
        uuid candidate_id FK
        text institution_name
        text degree
        text field_of_study
        date start_date
        date end_date
        boolean is_current
        text description
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_certifications {
        uuid id PK
        uuid candidate_id FK
        text name
        text issuing_organization
        date issue_date
        date expiry_date
        text credential_id
        text credential_url
        boolean is_verified
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_preferences {
        uuid id PK
        uuid candidate_id FK,UK
        text_array preferred_countries
        text_array preferred_cities
        text_array preferred_categories
        text_array preferred_shifts
        boolean remote_only
        boolean willing_to_relocate
        numeric minimum_salary
        varchar salary_currency
        integer notice_period_days
        timestamptz created_at
        timestamptz updated_at
    }

    candidate_documents {
        uuid id PK
        uuid candidate_id FK
        text document_type
        text file_path
        text original_file_name
        text mime_type
        bigint file_size
        text storage_bucket
        text status
        boolean is_primary
        timestamptz uploaded_at
        timestamptz created_at
        timestamptz updated_at
    }
```

---

## 3. Data Dictionary

### A. `candidates`
Root anchor linking an authenticated user to recruitment operations.
- `id` (`UUID`): Primary key.
- `user_id` (`UUID`): Foreign key referencing `profiles.id` (`ON DELETE CASCADE`), with a `UNIQUE` constraint ensuring one primary candidate identity per account.
- `status`: `active`, `inactive`, `suspended`, `archived`.
- `profile_completion_percentage`: Dynamically computed integer (`0`–`100`).

### B. `candidate_profiles`
Biographical and work orientation summary.
- `remote_preference`: `remote`, `hybrid`, `on_site`, `flexible`.
- `job_type_preference`: Array supporting `full_time`, `part_time`, `contract`, `freelance`, `temporary`, `internship`.
- `availability_status`: `immediately`, `within_two_weeks`, `within_one_month`, `not_available`, `open_to_discussion`.
- `salary_min` & `salary_max`: Numeric bounds with constraint `salary_max >= salary_min`.

### C. `candidate_skills`
Normalized competencies.
- `normalized_skill_name`: Lowercased, whitespace-stripped canonical name.
- `skill_type`: `technical`, `soft`, `industry`, `tool`, `domain`, `other`.
- `proficiency_level`: `beginner`, `intermediate`, `advanced`, `expert`, `unknown`.
- `source`: `candidate`, `cv_extraction`, `recruiter`, `assessment`, `ai_suggestion`.
- `is_verified`: Boolean. **Constraint Rule**: AI suggestions cannot be verified automatically (`CHECK (NOT (source = 'ai_suggestion' AND is_verified = true))`).

### D. `candidate_languages`
Multilingual qualifications.
- `language_code`: ISO language code (e.g. `en`, `ar`, `fr`, `de`).
- `proficiency_level`: Standardized to CEFR framework (`a1`, `a2`, `b1`, `b2`, `c1`, `c2`, `native`, `unknown`).
- **Constraint Rule**: Unique per candidate and language code; AI suggestions cannot be automatically marked as verified.

### E. `candidate_experience`
Chronological employment records.
- Enforces `end_date >= start_date`.
- Enforces consistency between `is_current = true` and `end_date IS NULL`.

### F. `candidate_education`
Academic history with start/end date validation.

### G. `candidate_certifications`
Credentials and licenses with expiry date verification.

### H. `candidate_preferences`
Relocation readiness, shift flexibility, target compensation, and notice periods.

---

## 4. Profile Completion Engine

Profile completeness is calculated dynamically by the database function:
`public.calculate_candidate_profile_completion(candidate_uuid UUID) RETURNS INTEGER`

### Scoring Weights:
1. **Candidate Profile (25%)**: Complete headline, professional summary, and current title.
2. **Primary CV Upload (20%)**: At least one active CV/resume document registered.
3. **Skills Inventory (15%)**: At least 3 skills entered (5% per skill up to 15%).
4. **Language Fluency (10%)**: At least 1 registered language.
5. **Employment History (15%)**: At least 1 valid work experience entry.
6. **Academic Background (10%)**: At least 1 educational qualification.
7. **Career Preferences (5%)**: Relocation and compensation preferences configured.

**Automated Synchronization**:
The `sync_candidate_profile_completion()` trigger fires automatically on `AFTER INSERT OR UPDATE OR DELETE` across all candidate sub-entities, continuously updating `candidates.profile_completion_percentage` and `candidates.updated_at`.
