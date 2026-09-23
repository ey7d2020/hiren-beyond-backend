# Cross-Module Relationships

This is an architectural dependency map, not a complete foreign-key inventory.

```mermaid
flowchart LR
    identity["Identity & Organizations"]
    candidates["Candidates"]
    jobs["Jobs"]
    applications["Applications / ATS"]
    cv["CV Intelligence"]
    matching["Matching"]
    recruiter["Recruiter Operations"]
    assessments["Assessments"]
    interviews["Interviews & Hiring"]
    clients["Clients"]
    notifications["Notifications"]
    ai["AI Assistants"]
    analytics["Analytics"]
    billing["Billing / Entitlements"]
    integrations["Integrations"]
    globalization["Globalization"]
    admin["Platform Admin"]
    search["Search"]
    workflows["Workflows"]
    api["Public API"]
    security["Security"]

    identity --> candidates
    identity --> jobs
    identity --> applications
    identity --> clients
    identity --> api

    globalization --> candidates
    globalization --> jobs
    globalization --> notifications

    candidates --> cv
    candidates --> applications
    candidates --> matching
    candidates --> search

    jobs --> applications
    jobs --> matching
    jobs --> search
    jobs --> analytics

    applications --> matching
    applications --> assessments
    applications --> interviews
    applications --> clients
    applications --> notifications
    applications --> analytics

    recruiter --> candidates
    recruiter --> applications
    recruiter --> matching

    assessments --> candidate_readiness["candidate_readiness"]
    interviews --> hiring_decisions["hiring_decisions"]
    clients --> client_shares["candidate/job shares"]

    ai --> candidates
    ai --> matching
    ai --> assessments

    integrations --> notifications
    integrations --> interviews
    integrations --> api

    workflows --> applications
    workflows --> notifications
    workflows --> integrations

    billing --> feature_flags["feature flags / entitlements"]
    admin --> billing
    admin --> security
    security --> audit_logs["audit logs / retention / circuit breakers"]
```

## Important Boundaries

| Boundary | Rule |
|---|---|
| Identity to everything | `profiles`, `organizations`, and memberships provide user and tenant context. |
| Candidates to clients | Clients see only explicit shares, not full candidate records by default. |
| Jobs to marketplace | Published jobs can be public; draft/admin job data remains org-scoped. |
| Applications to ATS | Applications are the central join between jobs and candidates. |
| AI to business domains | AI may recommend or prepare actions, but authorization is still backend-enforced. |
| Public API to internal data | API keys/scopes/rate limits mediate external access. |
| Workflows to actions | Workflow configuration must use approved action types only. |

