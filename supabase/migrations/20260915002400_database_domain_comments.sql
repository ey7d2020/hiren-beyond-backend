-- ============================================================================
-- Hiren Beyond Backend -- Migration 20260915002400
-- Database visualization organization metadata
-- Adds comments only. No table moves, renames, policy changes, data changes,
-- trigger changes, or business logic changes.
-- ============================================================================

COMMENT ON TABLE public.profiles IS '[DOMAIN:IDENTITY] User profile synchronized with Supabase Auth.';
COMMENT ON TABLE public.organizations IS '[DOMAIN:IDENTITY][DOMAIN:BILLING] Tenant organization and subscription status root.';
COMMENT ON TABLE public.organization_members IS '[DOMAIN:IDENTITY] Membership join between profiles, organizations, and roles.';
COMMENT ON TABLE public.roles IS '[DOMAIN:IDENTITY][DOMAIN:SECURITY] Role definitions used for permission assignment.';
COMMENT ON TABLE public.permissions IS '[DOMAIN:IDENTITY][DOMAIN:SECURITY] Granular permission catalog.';
COMMENT ON TABLE public.role_permissions IS '[DOMAIN:IDENTITY][DOMAIN:SECURITY] Junction table granting permissions to roles.';
COMMENT ON TABLE public.audit_logs IS '[DOMAIN:SECURITY] Cross-domain audit trail for important platform actions.';

COMMENT ON TABLE public.candidates IS '[DOMAIN:CANDIDATES] Canonical candidate record.';
COMMENT ON TABLE public.candidate_profiles IS '[DOMAIN:CANDIDATES] Extended candidate profile.';
COMMENT ON TABLE public.candidate_documents IS '[DOMAIN:CANDIDATES] Candidate document metadata for private storage objects.';

COMMENT ON TABLE public.jobs IS '[DOMAIN:JOBS] Employer job posting root.';
COMMENT ON TABLE public.job_requirements IS '[DOMAIN:JOBS] Structured job requirements.';
COMMENT ON TABLE public.job_skills IS '[DOMAIN:JOBS] Required or preferred job skills.';

COMMENT ON TABLE public.applications IS '[DOMAIN:APPLICATIONS] Candidate-to-job application root and ATS state.';
COMMENT ON TABLE public.ats_stages IS '[DOMAIN:APPLICATIONS] Organization ATS pipeline stages.';
COMMENT ON TABLE public.application_stage_history IS '[DOMAIN:APPLICATIONS] Application stage transition history.';

COMMENT ON TABLE public.cv_processing_jobs IS '[DOMAIN:CV_AI] CV processing queue and lifecycle state.';
COMMENT ON TABLE public.cv_extracted_content IS '[DOMAIN:CV_AI] Extracted text/content produced by CV processing.';
COMMENT ON TABLE public.candidate_cv_profiles IS '[DOMAIN:CV_AI] Structured profile generated from candidate CVs.';
COMMENT ON TABLE public.candidate_cv_ai_analysis IS '[DOMAIN:CV_AI] AI analysis results for candidate CV profiles.';

COMMENT ON TABLE public.matching_profiles IS '[DOMAIN:MATCHING] Matching weight/configuration profile.';
COMMENT ON TABLE public.matching_runs IS '[DOMAIN:MATCHING] Candidate/job matching run.';
COMMENT ON TABLE public.match_dimension_results IS '[DOMAIN:MATCHING] Per-dimension matching scores.';
COMMENT ON TABLE public.match_explanations IS '[DOMAIN:MATCHING] Human-readable match explanation.';

COMMENT ON TABLE public.recruiter_review_queue IS '[DOMAIN:RECRUITER] Recruiter review work queue.';
COMMENT ON TABLE public.candidate_shortlists IS '[DOMAIN:RECRUITER] Recruiter-created candidate shortlist.';
COMMENT ON TABLE public.bulk_screening_runs IS '[DOMAIN:RECRUITER] Bulk candidate screening run.';
COMMENT ON TABLE public.talent_pools IS '[DOMAIN:RECRUITER] Named recruiter talent pool.';

COMMENT ON TABLE public.assessment_templates IS '[DOMAIN:ASSESSMENTS] Assessment template root.';
COMMENT ON TABLE public.assessment_attempts IS '[DOMAIN:ASSESSMENTS] Candidate assessment attempt.';
COMMENT ON TABLE public.assessment_results IS '[DOMAIN:ASSESSMENTS] Assessment scoring result.';
COMMENT ON TABLE public.candidate_readiness IS '[DOMAIN:ASSESSMENTS] Candidate readiness score output.';

COMMENT ON TABLE public.interviews IS '[DOMAIN:INTERVIEWS] Scheduled interview root.';
COMMENT ON TABLE public.interview_feedback IS '[DOMAIN:INTERVIEWS] Interview reviewer feedback.';
COMMENT ON TABLE public.hiring_decisions IS '[DOMAIN:INTERVIEWS] Hiring decision for an application.';

COMMENT ON TABLE public.client_relationships IS '[DOMAIN:CLIENTS] Relationship between recruiting organization and client organization.';
COMMENT ON TABLE public.client_candidate_shares IS '[DOMAIN:CLIENTS] Explicit client access grant for a candidate/application.';
COMMENT ON TABLE public.client_candidate_feedback IS '[DOMAIN:CLIENTS] Client feedback on a shared candidate.';

COMMENT ON TABLE public.notifications IS '[DOMAIN:NOTIFICATIONS] In-app notification record.';
COMMENT ON TABLE public.notification_events IS '[DOMAIN:NOTIFICATIONS] Notification event source queue.';
COMMENT ON TABLE public.notification_deliveries IS '[DOMAIN:NOTIFICATIONS] Notification delivery channel record.';

COMMENT ON TABLE public.ai_conversations IS '[DOMAIN:AI] AI assistant conversation.';
COMMENT ON TABLE public.ai_messages IS '[DOMAIN:AI] Message within an AI conversation.';
COMMENT ON TABLE public.ai_tool_calls IS '[DOMAIN:AI] Tool invocation requested by an AI assistant.';
COMMENT ON TABLE public.ai_action_requests IS '[DOMAIN:AI] Approval-gated AI action request.';

COMMENT ON TABLE public.analytics_events IS '[DOMAIN:ANALYTICS] Raw analytics event stream.';
COMMENT ON TABLE public.organization_daily_metrics IS '[DOMAIN:ANALYTICS] Organization-level daily aggregate metrics.';
COMMENT ON TABLE public.analytics_export_jobs IS '[DOMAIN:ANALYTICS] Analytics export job for private storage output.';

COMMENT ON TABLE public.feature_flags IS '[DOMAIN:BILLING][DOMAIN:ADMIN] Feature flag and entitlement catalog.';
COMMENT ON TABLE public.organization_feature_overrides IS '[DOMAIN:BILLING][DOMAIN:ADMIN] Organization-specific feature entitlement override.';

COMMENT ON TABLE public.integration_providers IS '[DOMAIN:INTEGRATIONS] External integration provider catalog.';
COMMENT ON TABLE public.integration_connections IS '[DOMAIN:INTEGRATIONS] Organization integration connection.';
COMMENT ON TABLE public.integration_jobs IS '[DOMAIN:INTEGRATIONS] Integration job execution record.';
COMMENT ON TABLE public.outbound_webhooks IS '[DOMAIN:INTEGRATIONS] Outbound webhook definition.';

COMMENT ON TABLE public.countries IS '[DOMAIN:GLOBALIZATION] Country reference data.';
COMMENT ON TABLE public.currencies IS '[DOMAIN:GLOBALIZATION] Currency reference data.';
COMMENT ON TABLE public.languages IS '[DOMAIN:GLOBALIZATION] Language reference data.';
COMMENT ON TABLE public.localization_translations IS '[DOMAIN:GLOBALIZATION] Localized translation values.';

COMMENT ON TABLE public.platform_settings IS '[DOMAIN:ADMIN] Platform-wide settings.';
COMMENT ON TABLE public.platform_announcements IS '[DOMAIN:ADMIN] Platform announcement configuration.';
COMMENT ON TABLE public.support_access_sessions IS '[DOMAIN:ADMIN][DOMAIN:SECURITY] Time-boxed support access session.';
COMMENT ON TABLE public.platform_security_events IS '[DOMAIN:ADMIN][DOMAIN:SECURITY] Platform security event record.';

COMMENT ON TABLE public.search_configurations IS '[DOMAIN:SEARCH] Search configuration.';
COMMENT ON TABLE public.candidate_search_documents IS '[DOMAIN:SEARCH] Candidate search document/index row.';
COMMENT ON TABLE public.job_search_documents IS '[DOMAIN:SEARCH] Job search document/index row.';
COMMENT ON TABLE public.search_embeddings IS '[DOMAIN:SEARCH] Vector embedding records for semantic search.';

COMMENT ON TABLE public.workflow_definitions IS '[DOMAIN:WORKFLOWS] Workflow definition root.';
COMMENT ON TABLE public.workflow_versions IS '[DOMAIN:WORKFLOWS] Versioned workflow definition.';
COMMENT ON TABLE public.workflow_executions IS '[DOMAIN:WORKFLOWS] Workflow execution record.';
COMMENT ON TABLE public.workflow_execution_steps IS '[DOMAIN:WORKFLOWS] Workflow execution step.';

COMMENT ON TABLE public.api_applications IS '[DOMAIN:PUBLIC_API] External API application registration.';
COMMENT ON TABLE public.api_keys IS '[DOMAIN:PUBLIC_API][DOMAIN:SECURITY] Hashed external API key record.';
COMMENT ON TABLE public.api_scopes IS '[DOMAIN:PUBLIC_API][DOMAIN:SECURITY] Public API scope catalog.';
COMMENT ON TABLE public.api_request_logs IS '[DOMAIN:PUBLIC_API] Public API request log.';

COMMENT ON FUNCTION public.get_user_organizations() IS '[DOMAIN:IDENTITY] Frontend-safe active organization list for authenticated user.';
COMMENT ON FUNCTION public.get_user_permissions(UUID) IS '[DOMAIN:IDENTITY][DOMAIN:SECURITY] Frontend-safe permission list for a user in an organization.';
COMMENT ON FUNCTION public.search_candidates(TEXT, TEXT[], TEXT[], TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER, NUMERIC, UUID, UUID, TEXT, INTEGER, INTEGER) IS '[DOMAIN:SEARCH] Candidate search RPC with validated filter inputs.';
COMMENT ON FUNCTION public.queue_cv_processing(UUID, TEXT, TEXT, TEXT) IS '[DOMAIN:CV_AI] Enqueue candidate document for CV processing.';
COMMENT ON FUNCTION public.advance_application_stage(UUID, UUID, TEXT, TEXT) IS '[DOMAIN:APPLICATIONS] Move an application through the ATS pipeline.';
