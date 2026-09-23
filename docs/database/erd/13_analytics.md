# 13 Analytics

Owns event capture, daily metrics, report definitions, and export jobs.

External dependencies: jobs, applications, candidates, clients, storage bucket `analytics-exports`.

```mermaid
erDiagram
    analytics_events {
        uuid id PK
        uuid organization_id FK
        text event_type
        text entity_type
    }
    organization_daily_metrics {
        uuid id PK
        uuid organization_id FK
        date metric_date
    }
    job_daily_metrics {
        uuid id PK
        uuid job_id FK
        date metric_date
    }
    analytics_reports {
        uuid id PK
        uuid organization_id FK
        text report_type
    }
    analytics_export_jobs {
        uuid id PK
        uuid analytics_report_id FK
        text status
    }

    analytics_events }o--|| organization_daily_metrics : aggregates_to
    analytics_events }o--|| job_daily_metrics : aggregates_to
    analytics_reports ||--o{ analytics_export_jobs : exports
```

Storage note: generated exports belong in the private `analytics-exports` bucket.

