# Table Inventory

Source: local migration audit through `20260915002400_database_domain_comments.sql`.

Remote status: not verified in this environment because the Supabase CLI is not installed.

## Summary

| Item | Count |
|---|---:|
| Migrations | 40 |
| Public tables | 192 |
| Public views | 2 |
| Unique public function names | 236 |
| RLS policies found in migrations | 381 |
| Index statements found in migrations | 548 |
| Trigger names found in migrations | 74 |
| Constraint names found in migrations | 84 |
| Storage bucket inserts found in migrations | 3 |

## Tables By Domain

### 01 Identity & Organizations

`profiles`, `organizations`, `roles`, `permissions`, `role_permissions`, `organization_members`, `audit_logs`

### 02 Candidates

`candidates`, `candidate_profiles`, `candidate_skills`, `candidate_languages`, `candidate_experience`, `candidate_education`, `candidate_certifications`, `candidate_preferences`, `candidate_documents`

### 03 Jobs

`jobs`, `job_categories`, `job_requirements`, `job_skills`, `job_languages`, `job_questions`

### 04 Applications / ATS

`applications`, `ats_stages`, `application_stage_history`, `application_events`, `application_notes`, `application_screening_answers`, `recruiter_application_views`

### 05 CV Intelligence

`cv_processing_jobs`, `cv_processing_metadata`, `cv_extracted_content`, `candidate_cv_profiles`, `candidate_cv_ai_analysis`, `candidate_cv_review_items`

### 06 Matching

`matching_profiles`, `match_criteria`, `matching_runs`, `match_dimension_results`, `match_explanations`, `match_overrides`, `skill_aliases`

### 07 Recruiter Operations

`recruiter_review_queue`, `recruiter_saved_searches`, `candidate_screening_summaries`, `candidate_shortlists`, `bulk_screening_runs`, `bulk_screening_candidates`, `talent_pools`, `talent_pool_members`, `talent_pool_rules`, `talent_pool_membership_events`

### 08 Assessments

`assessment_templates`, `assessment_sections`, `assessment_questions`, `assessment_question_options`, `job_assessments`, `assessment_invitations`, `assessment_attempts`, `assessment_answers`, `assessment_results`, `assessment_section_results`, `assessment_question_results`, `voice_assessment_results`, `assessment_reviews`, `candidate_readiness`

### 09 Interviews & Hiring

`interview_templates`, `interview_rounds`, `application_interview_rounds`, `interviews`, `interview_participants`, `candidate_availability`, `availability_requests`, `availability_slots`, `interview_schedule_history`, `interview_scorecard_sections`, `interview_scorecard_questions`, `interview_feedback`, `interview_scorecard_responses`, `hiring_decisions`, `hiring_decision_history`, `interview_events`

### 10 Clients

`client_relationships`, `client_contacts`, `client_job_access`, `client_candidate_shares`, `client_candidate_profiles`, `client_document_access`, `client_candidate_feedback`, `client_feedback_history`, `client_scorecard_templates`, `client_scorecard_sections`, `client_scorecard_questions`, `client_scorecard_responses`, `client_interview_requests`, `client_information_requests`, `client_hiring_decisions`, `client_activity_events`

### 11 Notifications

`notification_types`, `notification_templates`, `notification_preferences`, `user_contact_channels`, `notifications`, `notification_events`, `notification_deliveries`, `notification_delivery_attempts`

### 12 AI Assistants

`ai_assistants`, `ai_conversations`, `ai_messages`, `ai_tools`, `ai_tool_calls`, `ai_action_requests`, `ai_context_snapshots`, `ai_prompts`, `ai_usage_records`, `ai_recommendations`

### 13 Analytics

`analytics_events`, `organization_daily_metrics`, `job_daily_metrics`, `analytics_reports`, `analytics_export_jobs`

### 14 Billing / Entitlements

`feature_flags`, `feature_flag_targets`, `organization_feature_overrides`, plus subscription fields on `organizations`

### 15 Integrations

`integration_providers`, `integration_connections`, `integration_oauth_sessions`, `integration_jobs`, `integration_job_attempts`, `integration_events`, `integration_health_checks`, `external_api_connections`, `incoming_webhook_events`, `outbound_webhooks`, `webhook_deliveries`, `whatsapp_templates`, `spreadsheet_mappings`

### 16 Globalization

`regions`, `countries`, `cities`, `currencies`, `exchange_rates`, `languages`, `language_proficiency_levels`, `timezones`, `localization_keys`, `localization_translations`, `regional_policies`, `organization_locales`, `organization_supported_countries`, `organization_supported_currencies`, `organization_supported_languages`, `user_locales`

### 17 Platform Admin

`platform_settings`, `platform_announcements`, `support_access_sessions`, `platform_security_events`

### 18 Search

`search_configurations`, `candidate_search_documents`, `job_search_documents`, `search_embeddings`, `search_history`, `search_analytics`, `search_rate_limits`, `search_alerts`

### 19 Workflows

`workflow_definitions`, `workflow_versions`, `workflow_triggers`, `workflow_fields`, `workflow_conditions`, `workflow_actions`, `workflow_approval_steps`, `workflow_schedules`, `workflow_event_queue`, `workflow_executions`, `workflow_execution_steps`, `workflow_execution_logs`, `workflow_failures`

### 20 Public API

`api_applications`, `api_keys`, `api_scopes`, `api_key_scopes`, `api_usage_records`, `api_request_logs`, `api_rate_limits`, `api_endpoints`, `api_idempotency_records`, `api_webhook_subscriptions`, `api_documentation`

### 21 Security / Production Hardening

`provider_circuit_breakers`, `data_retention_policies`, `data_retention_audit_logs`

## Views

`public_active_jobs`, `candidate_intelligence_summary`

## Storage Buckets Found In Migrations

`candidate-documents`, `assessment-audio`, `analytics-exports`

Any additional buckets in the remote Supabase project must be verified manually and then added here.

