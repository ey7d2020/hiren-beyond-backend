# Hiren Beyond — Candidate Domain Security & Access Control

## 1. Security Architecture & Threat Model

The Candidate Domain houses sensitive personal identifiable information (PII), career histories, compensation expectations, and uploaded documents. To uphold GDPR, CCPA, and global recruitment data protection standards, data access is strictly governed at the PostgreSQL database level.

```mermaid
flowchart TD
    Req[Incoming Candidate Request] --> AuthCheck{Authenticated Session?}
    AuthCheck -- No --> Deny[403 Denied: Anonymous Blocked]
    AuthCheck -- Yes --> EvaluateCaller{Caller Role}

    EvaluateCaller -->|Candidate| OwnCheck{candidate.user_id == auth.uid()?}
    OwnCheck -- Yes --> GrantPersonal[Full Candidate Access]
    OwnCheck -- No --> Deny

    EvaluateCaller -->|Recruiter| RecruiterCheck{Active Member in Agency/Platform Org AND has 'candidates.read'?}
    RecruiterCheck -- Yes --> GrantRecruiter[Authorized Recruiter Read]
    RecruiterCheck -- No --> Deny

    EvaluateCaller -->|Client / Anonymous| DenyClient[Denied: Direct Access Prohibited]

    EvaluateCaller -->|Platform Admin| GrantAdmin[Global Platform Authority]
```

---

## 2. Access Boundaries

### A. Candidate Privileges
- Candidates possess complete autonomy over their own record.
- A candidate can insert, view, edit, and delete their own skills, languages, experience, education, certifications, preferences, and documents.
- Candidates cannot inspect or tamper with another candidate's profile or uploaded assets.

### B. Recruiter Privileges
- Recruiters cannot browse candidate data arbitrarily.
- Access requires:
  1. Active membership in an organization of type `platform` or `recruitment_agency`.
  2. Possession of the `candidates.read` or `candidates.manage` permission grant.
- Recruiters can evaluate candidate profiles, verified credentials, and CV assets to facilitate matching and screening workflows.

### C. Client Privileges
- Client users (e.g. `client_admin`, `client_reviewer`) have **zero direct access** to the candidate table catalog.
- Candidate access for clients will be introduced in subsequent tasks via explicit application submissions and shortlisted candidate reviews.

### D. Anonymous Callers
- All unauthenticated requests are unconditionally blocked.

---

## 3. Database Security Definer Helpers

To ensure atomic and high-performance RLS policy evaluation, authorization queries rely on dedicated `SECURITY DEFINER` functions:

### `public.has_candidate_read_access(target_candidate_id UUID, check_user_id UUID)`
```sql
-- Returns true if caller is candidate owner, platform admin, or authorized recruiter
```

### `public.has_candidate_manage_access(target_candidate_id UUID, check_user_id UUID)`
```sql
-- Returns true if caller is candidate owner, platform admin, or recruiter with 'candidates.manage'
```

---

## 4. Anti-Tampering & Data Integrity Rules

1. **AI Suggestion Integrity**:
   - `CHECK (NOT (source = 'ai_suggestion' AND is_verified = true))`
   - Prohibits AI-extracted skills or languages from being marked as verified without human recruiter or assessment confirmation.
2. **Date Range Validation**:
   - Work experience and education end dates must be greater than or equal to start dates.
   - Current positions (`is_current = true`) strictly require `end_date IS NULL`.
3. **Salary Consistency**:
   - `CHECK (salary_max IS NULL OR salary_min IS NULL OR salary_max >= salary_min)`
4. **Unique Competency Deduping**:
   - A candidate cannot register duplicate normalized skill names or duplicate ISO language codes.
