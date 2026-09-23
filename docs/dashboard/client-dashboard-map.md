# Client Dashboard Backend Map

This map describes the implemented dashboard pages and the backend operations they depend on. Status values reflect the current repository implementation.

| Page | Purpose | Backend reads | Backend writes/actions | Status |
|---|---|---|---|---|
| Login | Authenticate the user | Supabase Auth, `get_my_profile`, `get_user_organizations` | Supabase `signInWithPassword`, `signOut` | Implemented |
| Organization Selector | Choose active tenant for UX state | `get_user_organizations`, `get_user_permissions` | local `hb_active_org` only | Implemented |
| Overview | Business metrics and tenant summary | `get_organization_summary`, `get_dashboard_metrics`, `get_notification_badge_count`, `list_notifications` | none | Implemented |
| Organizations | Platform organization management | `search_platform_organizations`, `get_organization_summary`, `organizations` | `archive_organization`, `reactivate_organization` | Mapped shell |
| Users & Roles | Team and permission management | `search_platform_users`, `organization_members`, `get_user_permissions` | invite/membership updates through backend authorization | Mapped shell |
| Candidates | Candidate discovery and profile insight | `search_candidates`, `search_recruiter_candidates`, `candidate_intelligence_summary` | `shortlist_candidate`, allowed RLS updates | Mapped shell |
| Jobs | Job management | `search_jobs`, `get_active_jobs`, `jobs`, `job_requirements` | authorized job table/RPC lifecycle operations | Mapped shell |
| Applications | ATS list and pipeline | `get_applications_cursor`, `get_pipeline_board`, `search_applications` | `advance_application_stage`, `submit_application` | Mapped shell |
| Matching | Match inspection and overrides | `matching_runs`, `match_dimension_results`, `match_explanations`, `rank_candidates_for_job` | `calculate_candidate_job_match`, `override_match_score` | Mapped shell |
| Assessments | Assessment templates and results | `get_recruiter_assessment_dashboard`, `get_candidate_assessment_progress` | `trigger_required_assessments`, `score_assessment_attempt` | Mapped shell |
| Interviews | Scheduling and interview feedback | `get_recruiter_interview_dashboard`, `get_candidate_interview_view` | `schedule_interview`, `reschedule_interview`, `cancel_interview`, `submit_interview_feedback` | Mapped shell |
| Clients | Client relationships and shared candidates | `get_client_jobs`, `get_client_job_candidates`, `get_client_candidate` | `share_candidate_with_client`, `submit_client_feedback`, `request_client_interview` | Mapped shell |
| AI Assistants | AI usage and approvals | `ai_conversations`, `ai_messages`, `ai_tool_calls`, `ai_recommendations` | `start_ai_conversation`, `send_ai_message`, `approve_ai_action_request` | Mapped shell |
| Workflows | Workflow configuration and execution | `workflow_definitions`, `get_workflow_execution`, `get_failed_workflows` | `validate_workflow_definition`, `publish_workflow_version`, `retry_workflow_step` | Mapped shell |
| Notifications | Notification list and unread state | `list_notifications`, `get_notification_badge_count`, `notification_preferences` | `mark_notification_read`, `mark_all_notifications_read`, `update_notification_preference` | Implemented list |
| Analytics | Recruitment and platform analytics | `get_recruitment_funnel`, `get_organization_analytics`, `get_job_analytics` | `create_analytics_export_job` | Mapped shell |
| Billing | Plan and entitlement visibility | `get_organization_summary`, `check_feature_enabled`, organization subscription fields | checkout/customer portal not present | Backend gap |
| Integrations | Provider status and health | `get_available_integrations`, `get_organization_integrations` | `start_oauth_session`, `test_integration_connection`, `disconnect_integration` | Mapped shell |
| Search | Search control center | `search_candidates`, `search_jobs`, `search_applications`, `hybrid_search_candidates` | `validate_ai_search_filters` | Mapped shell |
| Public API | API apps, keys, scopes, logs | `api_applications`, `api_keys`, `get_api_usage_analytics` | `create_api_application`, `create_api_key`, `rotate_api_key`, `revoke_api_key` | Mapped shell |
| System Activity | Audit and activity review | `audit_logs`, `platform_security_events`, `search_platform_audit_logs` | none | Mapped shell |
| Platform Settings | Feature flags and platform controls | `get_platform_dashboard`, `feature_flags`, `platform_settings` | `update_platform_setting`, `create_support_access_session`, `update_feature_flag` | Mapped shell |

## Implementation Rule

Every page must continue to use server-side filtering and pagination. Do not load large production tables into browser memory. Do not add fake fallback rows to make an empty dashboard look populated.
