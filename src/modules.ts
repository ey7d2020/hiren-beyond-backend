import type { ModuleDefinition } from './types';

export const modules: ModuleDefinition[] = [
  {
    key: 'overview',
    label: 'Overview',
    group: 'Dashboard',
    description: 'Operational health, recruitment throughput, unread work, and tenant summary from dashboard RPCs.',
    permissions: [],
    backendReads: ['get_organization_summary', 'get_dashboard_metrics', 'get_notification_badge_count'],
    backendWrites: [],
    status: 'available'
  },
  {
    key: 'organizations',
    label: 'Organizations',
    group: 'Dashboard',
    description: 'Platform organization list, status, subscription posture, usage, members, and activity.',
    permissions: ['organizations.read', 'platform.organizations.read', 'platform.admin'],
    backendReads: ['search_platform_organizations', 'get_organization_summary', 'organizations'],
    backendWrites: ['archive_organization', 'reactivate_organization'],
    status: 'partial'
  },
  {
    key: 'users',
    label: 'Users & Roles',
    group: 'Dashboard',
    description: 'Team members, roles, permission inspection, invites, and account status through RBAC controls.',
    permissions: ['users.read', 'members.read', 'platform.users.read'],
    backendReads: ['search_platform_users', 'organization_members', 'get_user_permissions'],
    backendWrites: ['invite user flow: backend support required', 'membership role updates: backend authorization required'],
    status: 'partial'
  },
  {
    key: 'candidates',
    label: 'Candidates',
    group: 'Recruitment',
    description: 'Candidate discovery, profile completeness, skills, documents, matching activity, and application count.',
    permissions: ['candidates.read', 'recruiter.candidates.read'],
    backendReads: ['search_candidates', 'search_recruiter_candidates', 'candidate_intelligence_summary'],
    backendWrites: ['shortlist_candidate', 'candidate profile direct RLS updates where allowed'],
    status: 'available'
  },
  {
    key: 'jobs',
    label: 'Jobs',
    group: 'Recruitment',
    description: 'Draft, published, and closed roles with requirements, skills, questions, and application statistics.',
    permissions: ['jobs.read'],
    backendReads: ['search_jobs', 'get_active_jobs', 'jobs', 'job_requirements'],
    backendWrites: ['job table writes under RLS', 'publish/archive status updates where authorized'],
    status: 'available'
  },
  {
    key: 'applications',
    label: 'Applications',
    group: 'Recruitment',
    description: 'ATS table and pipeline board with stage movement, history, notes, assessment, and interview context.',
    permissions: ['applications.read'],
    backendReads: ['get_applications_cursor', 'get_pipeline_board', 'search_applications'],
    backendWrites: ['advance_application_stage', 'submit_application'],
    status: 'available'
  },
  {
    key: 'matching',
    label: 'Matching',
    group: 'Recruitment',
    description: 'Matching runs, dimensions, explanations, mandatory failures, and authorized score overrides.',
    permissions: ['matching.read'],
    backendReads: ['matching_runs', 'match_dimension_results', 'match_explanations', 'rank_candidates_for_job'],
    backendWrites: ['calculate_candidate_job_match', 'override_match_score'],
    status: 'available'
  },
  {
    key: 'assessments',
    label: 'Assessments',
    group: 'Recruitment',
    description: 'Templates, invitations, attempts, scorecards, AI evaluations, and human review states.',
    permissions: ['assessments.read'],
    backendReads: ['get_recruiter_assessment_dashboard', 'get_candidate_assessment_progress'],
    backendWrites: ['trigger_required_assessments', 'score_assessment_attempt'],
    status: 'available'
  },
  {
    key: 'interviews',
    label: 'Interviews',
    group: 'Recruitment',
    description: 'Upcoming, completed, cancelled, and rescheduled interviews with timezone-aware scheduling.',
    permissions: ['interviews.read'],
    backendReads: ['get_recruiter_interview_dashboard', 'get_candidate_interview_view'],
    backendWrites: ['schedule_interview', 'reschedule_interview', 'cancel_interview', 'submit_interview_feedback'],
    status: 'available'
  },
  {
    key: 'clients',
    label: 'Clients',
    group: 'Clients',
    description: 'Client relationships, shared candidates, feedback, interview requests, and hiring activity.',
    permissions: ['clients.read'],
    backendReads: ['get_client_jobs', 'get_client_job_candidates', 'get_client_candidate'],
    backendWrites: ['share_candidate_with_client', 'submit_client_feedback', 'request_client_interview'],
    status: 'available'
  },
  {
    key: 'ai',
    label: 'AI Assistants',
    group: 'AI & Automation',
    description: 'AI conversations, usage, tool calls, approval-required actions, failures, and recommendations.',
    permissions: ['ai.read'],
    backendReads: ['ai_conversations', 'ai_messages', 'ai_tool_calls', 'ai_recommendations'],
    backendWrites: ['start_ai_conversation', 'send_ai_message', 'approve_ai_action_request'],
    status: 'partial'
  },
  {
    key: 'workflows',
    label: 'Workflows',
    group: 'AI & Automation',
    description: 'Workflow definitions, active versions, triggers, executions, failures, retries, and approvals.',
    permissions: ['workflows.read'],
    backendReads: ['workflow_definitions', 'get_workflow_execution', 'get_failed_workflows'],
    backendWrites: ['validate_workflow_definition', 'publish_workflow_version', 'retry_workflow_step'],
    status: 'available'
  },
  {
    key: 'notifications',
    label: 'Notifications',
    group: 'Platform',
    description: 'Unread work, categories, preferences, quiet hours, and delivery failures where authorized.',
    permissions: [],
    backendReads: ['list_notifications', 'get_notification_badge_count', 'notification_preferences'],
    backendWrites: ['mark_notification_read', 'mark_all_notifications_read', 'update_notification_preference'],
    status: 'available'
  },
  {
    key: 'analytics',
    label: 'Analytics',
    group: 'Platform',
    description: 'Funnel, source, recruiter, matching, assessment, interview, client, API, and AI usage analytics.',
    permissions: ['analytics.read'],
    backendReads: ['get_recruitment_funnel', 'get_organization_analytics', 'get_job_analytics'],
    backendWrites: ['create_analytics_export_job'],
    status: 'available'
  },
  {
    key: 'billing',
    label: 'Billing',
    group: 'Platform',
    description: 'Current plan, subscription state, trial window, entitlements, usage, limits, and billing gaps.',
    permissions: ['billing.read', 'organization.billing.read'],
    backendReads: ['get_organization_summary', 'check_feature_enabled', 'organizations subscription fields'],
    backendWrites: ['No checkout/customer portal runtime present in this repository'],
    status: 'blocked'
  },
  {
    key: 'integrations',
    label: 'Integrations',
    group: 'Platform',
    description: 'Providers, connection status, health checks, sync jobs, OAuth state, and failure detail.',
    permissions: ['integrations.read'],
    backendReads: ['get_available_integrations', 'get_organization_integrations'],
    backendWrites: ['start_oauth_session', 'test_integration_connection', 'disconnect_integration'],
    status: 'available'
  },
  {
    key: 'search',
    label: 'Search',
    group: 'Platform',
    description: 'Candidate, job, application, saved, semantic, and hybrid search using backend ranking services.',
    permissions: ['search.read'],
    backendReads: ['search_candidates', 'search_jobs', 'search_applications', 'hybrid_search_candidates'],
    backendWrites: ['validate_ai_search_filters before AI-assisted filters'],
    status: 'available'
  },
  {
    key: 'api',
    label: 'Public API',
    group: 'Platform',
    description: 'API apps, keys, scopes, rate limits, request logs, and webhooks without revealing full secrets.',
    permissions: ['api.read', 'api_keys.read'],
    backendReads: ['api_applications', 'api_keys', 'get_api_usage_analytics'],
    backendWrites: ['create_api_application', 'create_api_key', 'rotate_api_key', 'revoke_api_key'],
    status: 'partial'
  },
  {
    key: 'activity',
    label: 'System Activity',
    group: 'Admin',
    description: 'Read-only audit records, request context, security events, user actions, and resource history.',
    permissions: ['audit.read'],
    backendReads: ['audit_logs', 'platform_security_events', 'search_platform_audit_logs'],
    backendWrites: [],
    status: 'available'
  },
  {
    key: 'admin',
    label: 'Platform Settings',
    group: 'Admin',
    description: 'Feature flags, settings, announcements, support sessions, maintenance mode, and system health.',
    permissions: ['platform.admin'],
    backendReads: ['get_platform_dashboard', 'feature_flags', 'platform_settings'],
    backendWrites: ['update_platform_setting', 'create_support_access_session', 'update_feature_flag'],
    status: 'available'
  }
];
