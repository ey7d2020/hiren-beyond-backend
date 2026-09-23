# Master ERD

High-level, intentionally simplified ERD. Detailed table-level diagrams live in `docs/database/erd`.

```mermaid
flowchart TB
    identity["01 Identity & Organizations"]
    candidates["02 Candidates"]
    jobs["03 Jobs"]
    applications["04 Applications / ATS"]
    cv["05 CV Intelligence"]
    matching["06 Matching"]
    recruiter["07 Recruiter Operations"]
    assessments["08 Assessments"]
    interviews["09 Interviews & Hiring"]
    clients["10 Clients"]

    notifications["11 Notifications"]
    ai["12 AI Assistants"]
    analytics["13 Analytics"]
    billing["14 Billing / Entitlements"]
    integrations["15 Integrations"]
    globalization["16 Globalization"]
    admin["17 Platform Admin"]
    search["18 Search"]
    workflows["19 Workflows"]
    api["20 Public API"]
    security["21 Security"]

    identity --> candidates
    identity --> jobs
    identity --> clients
    identity --> admin

    globalization -. reference data .-> candidates
    globalization -. reference data .-> jobs

    candidates --> cv
    candidates --> applications
    jobs --> applications
    applications --> matching
    applications --> assessments
    applications --> interviews
    interviews --> clients

    recruiter --> applications
    recruiter --> candidates
    recruiter --> matching

    clients --> applications
    clients --> candidates

    search -. indexes .-> candidates
    search -. indexes .-> jobs
    search -. indexes .-> applications

    ai -. assists .-> candidates
    ai -. assists .-> matching
    ai -. assists .-> assessments

    workflows -. automates .-> applications
    workflows -. automates .-> notifications
    workflows -. automates .-> integrations

    notifications -. informs .-> applications
    notifications -. informs .-> assessments
    notifications -. informs .-> interviews

    analytics -. reads .-> jobs
    analytics -. reads .-> applications
    analytics -. reads .-> clients

    billing -. gates .-> identity
    billing -. gates .-> api
    billing -. gates .-> workflows

    integrations -. syncs .-> jobs
    integrations -. syncs .-> interviews
    integrations -. webhooks .-> notifications

    api -. external access .-> jobs
    api -. external access .-> applications
    api -. external access .-> candidates

    security -. audits/protects .-> identity
    security -. audits/protects .-> api
    security -. audits/protects .-> integrations
```

## Design Notes

- The production database remains in `public`; these are logical boundaries.
- Shared tables are not duplicated in every detailed ERD.
- Cross-cutting modules are connected only where they are architecturally meaningful.

