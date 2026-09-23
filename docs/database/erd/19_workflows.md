# 19 Workflows

Owns workflow definitions, versions, triggers, fields, conditions, actions, approvals, schedules, queueing, executions, steps, logs, and failures.

External dependencies: organizations, profiles, applications, notifications, integrations.

```mermaid
erDiagram
    workflow_definitions {
        uuid id PK
        uuid organization_id FK
        text name
        text status
    }
    workflow_versions {
        uuid id PK
        uuid workflow_definition_id FK
        int version_number
    }
    workflow_triggers {
        uuid id PK
        uuid workflow_version_id FK
        text trigger_type
    }
    workflow_fields {
        uuid id PK
        uuid workflow_version_id FK
        text field_key
    }
    workflow_conditions {
        uuid id PK
        uuid workflow_version_id FK
        text condition_type
    }
    workflow_actions {
        uuid id PK
        uuid workflow_version_id FK
        text action_type
    }
    workflow_approval_steps {
        uuid id PK
        uuid workflow_action_id FK
    }
    workflow_schedules {
        uuid id PK
        uuid workflow_definition_id FK
    }
    workflow_event_queue {
        uuid id PK
        uuid organization_id FK
        text event_type
    }
    workflow_executions {
        uuid id PK
        uuid workflow_version_id FK
        text status
    }
    workflow_execution_steps {
        uuid id PK
        uuid workflow_execution_id FK
        uuid workflow_action_id FK
    }
    workflow_execution_logs {
        uuid id PK
        uuid workflow_execution_id FK
    }
    workflow_failures {
        uuid id PK
        uuid workflow_execution_id FK
        uuid workflow_execution_step_id FK
    }

    workflow_definitions ||--o{ workflow_versions : versions
    workflow_versions ||--o{ workflow_triggers : triggers
    workflow_versions ||--o{ workflow_fields : fields
    workflow_versions ||--o{ workflow_conditions : conditions
    workflow_versions ||--o{ workflow_actions : actions
    workflow_actions ||--o{ workflow_approval_steps : approvals
    workflow_definitions ||--o{ workflow_schedules : schedules
    workflow_versions ||--o{ workflow_executions : executions
    workflow_executions ||--o{ workflow_execution_steps : steps
    workflow_executions ||--o{ workflow_execution_logs : logs
    workflow_executions ||--o{ workflow_failures : failures
```

Workflow configuration must never expose arbitrary SQL, arbitrary code execution, or arbitrary unapproved HTTP actions to the frontend.

