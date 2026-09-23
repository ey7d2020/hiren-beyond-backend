# Naming Audit

No production tables were renamed for this task. Naming issues are documented only.

## Consistent Patterns

| Pattern | Examples | Status |
|---|---|---|
| snake_case plural table names | `candidate_skills`, `workflow_executions` | Good |
| UUID primary key named `id` | Most module tables | Good |
| Domain prefixes | `ai_*`, `api_*`, `workflow_*`, `client_*` | Good |
| History/event suffixes | `*_history`, `*_events`, `*_logs` | Mostly good |
| Junction/member tables | `role_permissions`, `talent_pool_members` | Good |

## Inconsistencies To Watch

| Observation | Examples | Recommendation |
|---|---|---|
| Mixed event/log naming | `application_events`, `audit_logs`, `workflow_execution_logs`, `integration_events` | Keep existing names; document whether rows are domain events, audit logs, or execution logs. |
| Mixed public API acronym casing | `api_*` tables, `/api/v1` docs | Keep lowercase table prefix. |
| Candidate availability lives with interviews migration | `candidate_availability` | Treat as Interviews & Hiring dependency; avoid moving table physically. |
| Assessment media bucket documentation is broader than local bucket inserts | `assessment-audio` present; video/files need remote check | Verify storage buckets before documenting as deployed. |
| Public API database RPCs exist but Edge Function runtime not present | `api_v1_*` functions | Keep API docs explicit about runtime deployment status. |
| Billing is represented through org subscription fields and feature flags, not a full billing schema | `subscription_plan`, `subscription_status`, `feature_flags` | Document as entitlements/billing primitives until checkout tables/provider runtime exist. |

## Do Not Rename

Do not rename production tables, columns, RPCs, or buckets to improve visual layout. Use Mermaid/DBML/Graphviz documentation as the clean view instead.

