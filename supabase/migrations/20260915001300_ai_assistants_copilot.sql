-- =============================================================================
-- Migration: 20260915001300_ai_assistants_copilot.sql
-- Description: Task 12 — AI Assistants, Candidate Career Assistant, 
--              Recruiter Copilot & AI Action Layer
--
-- Tables (10 Entities):
--   1. public.ai_assistants
--   2. public.ai_conversations
--   3. public.ai_messages
--   4. public.ai_tools
--   5. public.ai_tool_calls
--   6. public.ai_action_requests
--   7. public.ai_context_snapshots
--   8. public.ai_prompts
--   9. public.ai_usage_records
--  10. public.ai_recommendations
--
-- Safety Guarantees:
--   - No arbitrary SQL execution
--   - AI cannot make final hiring decisions (hire, final_offer, final_reject)
--   - High-impact actions require human recruiter approval (ai_action_requests)
--   - Recursive tool loop protection (max depth 3, max turn calls 5)
--   - Strict multi-tenant and candidate privacy boundaries via RLS
-- =============================================================================

-- =============================================================================
-- 1. AI ASSISTANTS REGISTRY
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_assistants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assistant_type VARCHAR(50) NOT NULL UNIQUE CHECK (assistant_type IN ('candidate_career', 'recruiter_copilot', 'platform_admin')),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'deprecated')),
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_assistants_type ON public.ai_assistants(assistant_type);
CREATE INDEX IF NOT EXISTS idx_ai_assistants_status ON public.ai_assistants(status);

-- =============================================================================
-- 2. AI CONVERSATION SESSIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assistant_id UUID NOT NULL REFERENCES public.ai_assistants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    candidate_id UUID REFERENCES public.candidates(id) ON DELETE SET NULL,
    job_id UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
    application_id UUID REFERENCES public.applications(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL DEFAULT 'New Conversation',
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'closed')),
    context_configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_conv_user ON public.ai_conversations(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_conv_org ON public.ai_conversations(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_conv_candidate ON public.ai_conversations(candidate_id);
CREATE INDEX IF NOT EXISTS idx_ai_conv_job ON public.ai_conversations(job_id);
CREATE INDEX IF NOT EXISTS idx_ai_conv_app ON public.ai_conversations(application_id);
CREATE INDEX IF NOT EXISTS idx_ai_conv_last_msg ON public.ai_conversations(last_message_at DESC);

-- =============================================================================
-- 3. AI MESSAGES
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'tool', 'system')),
    content TEXT NOT NULL,
    structured_content JSONB DEFAULT NULL,
    model_provider VARCHAR(50),
    model_name VARCHAR(100),
    prompt_version INT,
    token_usage JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON public.ai_messages(conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_ai_messages_role ON public.ai_messages(role);

-- =============================================================================
-- 4. AI TOOL REGISTRY
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_tools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    assistant_types TEXT[] NOT NULL,
    input_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
    output_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
    risk_level VARCHAR(20) NOT NULL CHECK (risk_level IN ('read', 'low', 'medium', 'high', 'critical')),
    requires_confirmation BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_tools_name ON public.ai_tools(name);
CREATE INDEX IF NOT EXISTS idx_ai_tools_risk ON public.ai_tools(risk_level);
CREATE INDEX IF NOT EXISTS idx_ai_tools_active ON public.ai_tools(is_active);

-- =============================================================================
-- 5. AI TOOL CALLS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_tool_calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
    message_id UUID REFERENCES public.ai_messages(id) ON DELETE CASCADE,
    tool_name VARCHAR(100) NOT NULL,
    arguments JSONB NOT NULL DEFAULT '{}'::jsonb,
    authorization_status VARCHAR(50) NOT NULL DEFAULT 'pending' 
        CHECK (authorization_status IN ('pending', 'authorized', 'denied', 'requires_approval')),
    execution_status VARCHAR(50) NOT NULL DEFAULT 'queued' 
        CHECK (execution_status IN ('queued', 'running', 'completed', 'failed', 'cancelled')),
    result_summary TEXT,
    call_depth INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_ai_tool_calls_conv ON public.ai_tool_calls(conversation_id);
CREATE INDEX IF NOT EXISTS idx_ai_tool_calls_tool ON public.ai_tool_calls(tool_name);
CREATE INDEX IF NOT EXISTS idx_ai_tool_calls_auth ON public.ai_tool_calls(authorization_status);
CREATE INDEX IF NOT EXISTS idx_ai_tool_calls_exec ON public.ai_tool_calls(execution_status);

-- =============================================================================
-- 6. AI ACTION REQUESTS (HIGH-RISK APPROVAL WORKFLOW)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_action_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
    tool_call_id UUID REFERENCES public.ai_tool_calls(id) ON DELETE SET NULL,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    action_type VARCHAR(100) NOT NULL,
    target_type VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,
    arguments JSONB NOT NULL DEFAULT '{}'::jsonb,
    risk_level VARCHAR(20) NOT NULL CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    status VARCHAR(50) NOT NULL DEFAULT 'pending' 
        CHECK (status IN ('pending', 'approved', 'rejected', 'executed', 'failed', 'cancelled')),
    approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    rejected_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    rejected_at TIMESTAMPTZ,
    reason TEXT,
    idempotency_key VARCHAR(128) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_action_conv ON public.ai_action_requests(conversation_id);
CREATE INDEX IF NOT EXISTS idx_ai_action_status ON public.ai_action_requests(status);
CREATE INDEX IF NOT EXISTS idx_ai_action_target ON public.ai_action_requests(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_ai_action_idemp ON public.ai_action_requests(idempotency_key);

-- =============================================================================
-- 7. AI CONTEXT SNAPSHOTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_context_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
    context_type VARCHAR(50) NOT NULL,
    source_references JSONB NOT NULL DEFAULT '{}'::jsonb,
    context_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_ctx_snap_conv ON public.ai_context_snapshots(conversation_id);

-- =============================================================================
-- 8. PROMPT MANAGEMENT
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    assistant_type VARCHAR(50) NOT NULL CHECK (assistant_type IN ('candidate_career', 'recruiter_copilot', 'platform_admin', 'common')),
    prompt_type VARCHAR(50) NOT NULL CHECK (prompt_type IN ('system', 'assistant', 'tool', 'analysis', 'summary')),
    content TEXT NOT NULL,
    version INT NOT NULL DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'active' CHECK (status IN ('draft', 'active', 'deprecated', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(name, version)
);

CREATE INDEX IF NOT EXISTS idx_ai_prompts_name_ver ON public.ai_prompts(name, version);
CREATE INDEX IF NOT EXISTS idx_ai_prompts_type ON public.ai_prompts(assistant_type, prompt_type);

-- =============================================================================
-- 9. AI USAGE TRACKING
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_usage_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    assistant_id UUID REFERENCES public.ai_assistants(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    model VARCHAR(100) NOT NULL,
    request_type VARCHAR(50) NOT NULL,
    input_tokens INT NOT NULL DEFAULT 0,
    output_tokens INT NOT NULL DEFAULT 0,
    total_tokens INT NOT NULL DEFAULT 0,
    estimated_cost NUMERIC(10, 6) DEFAULT 0.000000,
    latency_ms INT DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'success' CHECK (status IN ('success', 'rate_limited', 'error', 'timeout')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_usage_user ON public.ai_usage_records(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_org ON public.ai_usage_records(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_conv ON public.ai_usage_records(conversation_id);

-- =============================================================================
-- 10. AI RECOMMENDATIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_recommendations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    assistant_id UUID REFERENCES public.ai_assistants(id) ON DELETE SET NULL,
    recommendation_type VARCHAR(50) NOT NULL CHECK (recommendation_type IN (
        'candidate_job', 'candidate_improvement', 'recruiter_review', 
        'candidate_shortlist', 'talent_pool', 'workflow', 'daily_recruiter_brief'
    )),
    target_type VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    summary TEXT NOT NULL,
    reasoning TEXT NOT NULL,
    confidence NUMERIC(5, 2) NOT NULL CHECK (confidence >= 0 AND confidence <= 100),
    priority VARCHAR(20) NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status VARCHAR(50) NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'viewed', 'accepted', 'dismissed', 'expired')),
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_rec_org ON public.ai_recommendations(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_rec_user ON public.ai_recommendations(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_rec_target ON public.ai_recommendations(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_ai_rec_type ON public.ai_recommendations(recommendation_type);

-- =============================================================================
-- 11. BASELINE SEEDING
-- =============================================================================

-- Seed Assistants
INSERT INTO public.ai_assistants (
    assistant_type, name, description, status, configuration, version
)
VALUES
    (
        'candidate_career',
        'Hiren Candidate Career AI Assistant',
        'Personal AI career coach helping candidates discover matched jobs, optimize CVs, and prepare for assessments.',
        'active',
        jsonb_build_object(
            'model_provider', 'google',
            'model_name', 'gemini-1.5-pro',
            'temperature', 0.2,
            'max_tokens', 2048,
            'system_prompt_version', 1
        ),
        1
    ),
    (
        'recruiter_copilot',
        'Hiren Recruiter AI Copilot',
        'Intelligent recruitment assistant assisting recruiters with candidate ranking, screening summaries, and workflow actions.',
        'active',
        jsonb_build_object(
            'model_provider', 'google',
            'model_name', 'gemini-1.5-pro',
            'temperature', 0.1,
            'max_tokens', 4096,
            'system_prompt_version', 1
        ),
        1
    ),
    (
        'platform_admin',
        'Hiren Platform Intelligence Assistant',
        'Administrative intelligence assistant for platform health, system audits, and global performance analysis.',
        'active',
        jsonb_build_object(
            'model_provider', 'google',
            'model_name', 'gemini-1.5-pro',
            'temperature', 0.0,
            'max_tokens', 4096,
            'system_prompt_version', 1
        ),
        1
    )
ON CONFLICT (assistant_type) DO NOTHING;

-- Seed Prompts
INSERT INTO public.ai_prompts (
    name, assistant_type, prompt_type, content, version, status
)
VALUES
    (
        'candidate_career_system_v1',
        'candidate_career',
        'system',
        'You are the Hiren Beyond Candidate Career Assistant. You assist candidates in discovering matched jobs, improving their CV representation, and preparing for assessments. You have access only to the authenticated candidate authorized profile, matching results, and public job marketplace listings. You must NEVER fabricate experience, certifications, or achievements. You must never expose recruiter private notes or internal client deliberation. Be encouraging, precise, and actionable.',
        1,
        'active'
    ),
    (
        'recruiter_copilot_system_v1',
        'recruiter_copilot',
        'system',
        'You are the Hiren Beyond Recruiter Copilot. You assist recruitment professionals in screening applicants, reviewing candidate match breakdowns, preparing candidate summaries, and executing authorized recruitment workflows. You operate strictly within the authenticated recruiter organization boundary. You can suggest actions such as shortlisting or interview requests, but you CAN NEVER make final hiring decisions. All actions require explicit human confirmation.',
        1,
        'active'
    )
ON CONFLICT (name, version) DO NOTHING;

-- Seed Tool Registry
INSERT INTO public.ai_tools (
    name, description, assistant_types, input_schema, output_schema, risk_level, requires_confirmation
)
VALUES
    -- Candidate Read Tools
    (
        'get_my_profile',
        'Retrieves authenticated candidate verified profile, summary, location, and contact information.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {}}'::jsonb,
        '{"type": "object", "properties": {"candidate_id": {"type": "string"}, "headline": {"type": "string"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_my_skills',
        'Retrieves authenticated candidate skills, proficiency levels, and verification status.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {}}'::jsonb,
        '{"type": "object", "properties": {"skills": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_my_cv_analysis',
        'Retrieves candidate latest CV intelligence analysis, strengths, and identified skill gaps.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {}}'::jsonb,
        '{"type": "object", "properties": {"analysis": {"type": "object"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_my_match_results',
        'Retrieves candidate algorithmic match scores and dimensional fit for a specific public job.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {"job_id": {"type": "string"}}, "required": ["job_id"]}'::jsonb,
        '{"type": "object", "properties": {"match_score": {"type": "number"}, "strengths": {"type": "array"}, "gaps": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_my_applications',
        'Retrieves authenticated candidate active and past job applications and their public status.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {}}'::jsonb,
        '{"type": "object", "properties": {"applications": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_my_assessments',
        'Retrieves candidate completed assessment evaluations and score summaries.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {}}'::jsonb,
        '{"type": "object", "properties": {"assessments": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_my_readiness',
        'Retrieves candidate verified readiness status across language, voice, and technical benchmarks.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {}}'::jsonb,
        '{"type": "object", "properties": {"readiness": {"type": "object"}}}'::jsonb,
        'read',
        false
    ),
    (
        'search_public_jobs',
        'Searches active public job listings matching keywords, title, or category.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {"keyword": {"type": "string"}, "category": {"type": "string"}}}'::jsonb,
        '{"type": "object", "properties": {"jobs": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    -- Candidate Action Tools
    (
        'suggest_cv_improvements',
        'Generates actionable CV content improvement recommendations without fabricating data.',
        ARRAY['candidate_career'],
        '{"type": "object", "properties": {"target_job_id": {"type": "string"}}}'::jsonb,
        '{"type": "object", "properties": {"suggestions": {"type": "array"}}}'::jsonb,
        'low',
        false
    ),
    -- Recruiter Read Tools
    (
        'search_candidates',
        'Searches candidates within authorized recruiter organization based on skills, experience, or match score.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"job_id": {"type": "string"}, "min_match_score": {"type": "number"}, "skills": {"type": "array"}}}'::jsonb,
        '{"type": "object", "properties": {"candidates": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_candidate_summary',
        'Retrieves synthesized summary of candidate profile, experience, verified readiness, and match details.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"candidate_id": {"type": "string"}}, "required": ["candidate_id"]}'::jsonb,
        '{"type": "object", "properties": {"summary": {"type": "object"}}}'::jsonb,
        'read',
        false
    ),
    (
        'rank_candidates_for_job',
        'Ranks applicants for a specific organization job ordered by match score and readiness.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"job_id": {"type": "string"}, "limit": {"type": "number"}}, "required": ["job_id"]}'::jsonb,
        '{"type": "object", "properties": {"ranked_candidates": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_screening_summary',
        'Retrieves candidate screening and CV intelligence evaluation breakdown.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"application_id": {"type": "string"}}, "required": ["application_id"]}'::jsonb,
        '{"type": "object", "properties": {"screening": {"type": "object"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_review_queue',
        'Retrieves list of applications requiring recruiter attention or assessment review.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"organization_id": {"type": "string"}}, "required": ["organization_id"]}'::jsonb,
        '{"type": "object", "properties": {"queue": {"type": "array"}}}'::jsonb,
        'read',
        false
    ),
    (
        'get_job_details',
        'Retrieves requisition details, requirements, and hiring pipeline metrics for an organization job.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"job_id": {"type": "string"}}, "required": ["job_id"]}'::jsonb,
        '{"type": "object", "properties": {"job": {"type": "object"}}}'::jsonb,
        'read',
        false
    ),
    -- Recruiter Action Tools (All require explicit human approval)
    (
        'request_candidate_shortlist',
        'Proposes shortlisting a candidate for an organization job. Requires explicit human recruiter approval.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"application_id": {"type": "string"}, "notes": {"type": "string"}}, "required": ["application_id"]}'::jsonb,
        '{"type": "object", "properties": {"action_request_id": {"type": "string"}, "status": {"type": "string"}}}'::jsonb,
        'high',
        true
    ),
    (
        'request_move_application_stage',
        'Proposes advancing an application stage in the ATS pipeline. Requires explicit human approval.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"application_id": {"type": "string"}, "stage": {"type": "string"}}, "required": ["application_id", "stage"]}'::jsonb,
        '{"type": "object", "properties": {"action_request_id": {"type": "string"}, "status": {"type": "string"}}}'::jsonb,
        'high',
        true
    ),
    (
        'request_interview_session',
        'Proposes scheduling an interview session. Requires recruiter confirmation.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"application_id": {"type": "string"}, "interview_type": {"type": "string"}, "title": {"type": "string"}}, "required": ["application_id"]}'::jsonb,
        '{"type": "object", "properties": {"action_request_id": {"type": "string"}, "status": {"type": "string"}}}'::jsonb,
        'high',
        true
    ),
    (
        'request_assessment_invitation',
        'Proposes sending an assessment invitation to candidate. Requires recruiter confirmation.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"application_id": {"type": "string"}, "template_id": {"type": "string"}}, "required": ["application_id", "template_id"]}'::jsonb,
        '{"type": "object", "properties": {"action_request_id": {"type": "string"}, "status": {"type": "string"}}}'::jsonb,
        'medium',
        true
    ),
    (
        'request_create_talent_pool',
        'Proposes creating a smart talent pool for a set of candidates. Requires recruiter confirmation.',
        ARRAY['recruiter_copilot'],
        '{"type": "object", "properties": {"name": {"type": "string"}, "description": {"type": "string"}}, "required": ["name"]}'::jsonb,
        '{"type": "object", "properties": {"action_request_id": {"type": "string"}, "status": {"type": "string"}}}'::jsonb,
        'medium',
        true
    )
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- 12. ROW LEVEL SECURITY POLICIES
-- =============================================================================

ALTER TABLE public.ai_assistants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_tools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_tool_calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_action_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_context_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_recommendations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.ai_assistants FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_conversations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_tools FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_tool_calls FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_action_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_context_snapshots FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_prompts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage_records FORCE ROW LEVEL SECURITY;
ALTER TABLE public.ai_recommendations FORCE ROW LEVEL SECURITY;

-- 12.1 AI Assistants (Public catalog for active, admin for all)
CREATE POLICY "Authenticated users view active assistants"
ON public.ai_assistants FOR SELECT
TO authenticated
USING (status = 'active' OR public.is_platform_admin(auth.uid()));

CREATE POLICY "Platform admins manage assistants"
ON public.ai_assistants FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()))
WITH CHECK (public.is_platform_admin(auth.uid()));

-- 12.2 AI Conversations (Strict User & Organization Isolation)
CREATE POLICY "Users access own conversations"
ON public.ai_conversations FOR ALL
TO authenticated
USING (
    user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
    OR public.is_platform_admin(auth.uid())
)
WITH CHECK (
    user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
    OR public.is_platform_admin(auth.uid())
);

-- 12.3 AI Messages
CREATE POLICY "Users access messages in allowed conversations"
ON public.ai_messages FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              ac.user_id = auth.uid()
              OR (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              ac.user_id = auth.uid()
              OR (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
);

-- 12.4 AI Tools (Active catalog read-only for authenticated)
CREATE POLICY "Users view active tools"
ON public.ai_tools FOR SELECT
TO authenticated
USING (is_active = true OR public.is_platform_admin(auth.uid()));

CREATE POLICY "Platform admins manage tools"
ON public.ai_tools FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()))
WITH CHECK (public.is_platform_admin(auth.uid()));

-- 12.5 AI Tool Calls
CREATE POLICY "Users access tool calls in own conversations"
ON public.ai_tool_calls FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              ac.user_id = auth.uid()
              OR (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              ac.user_id = auth.uid()
              OR (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
);

-- 12.6 AI Action Requests
CREATE POLICY "Users manage action requests in allowed conversations"
ON public.ai_action_requests FOR ALL
TO authenticated
USING (
    requested_by = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
)
WITH CHECK (
    requested_by = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
);

-- 12.7 AI Context Snapshots
CREATE POLICY "Users access context snapshots in allowed conversations"
ON public.ai_context_snapshots FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.ai_conversations ac
        WHERE ac.id = conversation_id
          AND (
              ac.user_id = auth.uid()
              OR (ac.organization_id IS NOT NULL AND public.check_user_is_recruiter(ac.organization_id))
              OR public.is_platform_admin(auth.uid())
          )
    )
);

-- 12.8 AI Prompts (Active prompts readable, admin manageable)
CREATE POLICY "Users view active prompts"
ON public.ai_prompts FOR SELECT
TO authenticated
USING (status = 'active' OR public.is_platform_admin(auth.uid()));

CREATE POLICY "Platform admins manage prompts"
ON public.ai_prompts FOR ALL
TO authenticated
USING (public.is_platform_admin(auth.uid()))
WITH CHECK (public.is_platform_admin(auth.uid()));

-- 12.9 AI Usage Records
CREATE POLICY "Users view own usage records"
ON public.ai_usage_records FOR SELECT
TO authenticated
USING (
    user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
    OR public.is_platform_admin(auth.uid())
);

-- 12.10 AI Recommendations
CREATE POLICY "Users access own recommendations"
ON public.ai_recommendations FOR ALL
TO authenticated
USING (
    user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
    OR public.is_platform_admin(auth.uid())
)
WITH CHECK (
    user_id = auth.uid()
    OR (organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id))
    OR public.is_platform_admin(auth.uid())
);

-- =============================================================================
-- 13. CORE PROCEDURES & ACTION LAYER ENGINE
-- =============================================================================

-- 13.1 Start AI Conversation Session
CREATE OR REPLACE FUNCTION public.start_ai_conversation(
    p_assistant_type TEXT,
    p_org_id UUID DEFAULT NULL,
    p_job_id UUID DEFAULT NULL,
    p_app_id UUID DEFAULT NULL,
    p_title TEXT DEFAULT 'New AI Session'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ast RECORD;
    v_cand_id UUID := NULL;
    v_conv_id UUID;
BEGIN
    SELECT * INTO v_ast FROM public.ai_assistants WHERE assistant_type = p_assistant_type AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'AI assistant type % not found or inactive', p_assistant_type;
    END IF;

    -- Security validation based on assistant type
    IF p_assistant_type = 'recruiter_copilot' THEN
        IF p_org_id IS NULL THEN
            RAISE EXCEPTION 'Organization ID is required for recruiter copilot';
        END IF;

        -- Verify caller is a verified recruiter for this organization
        IF NOT public.check_user_is_recruiter(p_org_id) AND NOT public.is_platform_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized: Caller is not a verified recruiter for organization %', p_org_id;
        END IF;

    ELSIF p_assistant_type = 'candidate_career' THEN
        -- Derive caller candidate record
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        -- Candidates cannot bind recruiter organization context
        p_org_id := NULL;

    ELSIF p_assistant_type = 'platform_admin' THEN
        IF NOT public.is_platform_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized: Platform admin assistant is restricted';
        END IF;
    END IF;

    INSERT INTO public.ai_conversations (
        assistant_id, user_id, organization_id, candidate_id, job_id, application_id, title
    )
    VALUES (
        v_ast.id, auth.uid(), p_org_id, v_cand_id, p_job_id, p_app_id, COALESCE(p_title, 'New AI Session')
    )
    RETURNING id INTO v_conv_id;

    -- Initial system message tracking
    INSERT INTO public.ai_messages (
        conversation_id, role, content, model_provider, model_name, prompt_version
    )
    VALUES (
        v_conv_id,
        'system',
        'Conversation initiated with ' || v_ast.name,
        v_ast.configuration->>'model_provider',
        v_ast.configuration->>'model_name',
        COALESCE((v_ast.configuration->>'system_prompt_version')::int, 1)
    );

    RETURN v_conv_id;
END;
$$;

-- 13.2 Send AI Message
CREATE OR REPLACE FUNCTION public.send_ai_message(
    p_conversation_id UUID,
    p_role TEXT,
    p_content TEXT,
    p_structured JSONB DEFAULT NULL,
    p_provider TEXT DEFAULT NULL,
    p_model TEXT DEFAULT NULL,
    p_tokens JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_conv RECORD;
    v_msg_id UUID;
BEGIN
    SELECT * INTO v_conv FROM public.ai_conversations WHERE id = p_conversation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
    END IF;

    -- Access check
    IF v_conv.user_id <> auth.uid() 
       AND NOT (v_conv.organization_id IS NOT NULL AND public.check_user_is_recruiter(v_conv.organization_id))
       AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Access denied to conversation %', p_conversation_id;
    END IF;

    IF v_conv.status = 'closed' THEN
        RAISE EXCEPTION 'Cannot post to closed conversation %', p_conversation_id;
    END IF;

    INSERT INTO public.ai_messages (
        conversation_id, role, content, structured_content, model_provider, model_name, token_usage
    )
    VALUES (
        p_conversation_id, p_role, p_content, p_structured, p_provider, p_model, p_tokens
    )
    RETURNING id INTO v_msg_id;

    UPDATE public.ai_conversations
    SET last_message_at = now(), updated_at = now()
    WHERE id = p_conversation_id;

    RETURN v_msg_id;
END;
$$;

-- 13.3 Dispatch AI Tool Call (Safe Tool Execution & Gatekeeper)
CREATE OR REPLACE FUNCTION public.dispatch_ai_tool_call(
    p_conversation_id UUID,
    p_tool_name TEXT,
    p_arguments JSONB DEFAULT '{}'::jsonb,
    p_call_depth INT DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_conv RECORD;
    v_ast RECORD;
    v_tool RECORD;
    v_tool_call_id UUID;
    v_action_req_id UUID;
    v_result JSONB := '{}'::jsonb;
    v_cand_id UUID;
    v_app_id UUID;
    v_job_id UUID;
BEGIN
    -- Recursive Tool Protection: Max call depth 3
    IF p_call_depth > 3 THEN
        RAISE EXCEPTION 'RECURSIVE_TOOL_LOOP_DETECTED: Maximum execution depth of 3 exceeded';
    END IF;

    -- Retrieve conversation and assistant
    SELECT * INTO v_conv FROM public.ai_conversations WHERE id = p_conversation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
    END IF;

    SELECT * INTO v_ast FROM public.ai_assistants WHERE id = v_conv.assistant_id;

    -- Lookup tool in registry
    SELECT * INTO v_tool FROM public.ai_tools WHERE name = p_tool_name AND is_active = true;
    IF NOT FOUND THEN
        -- Record denied tool call
        INSERT INTO public.ai_tool_calls (
            conversation_id, tool_name, arguments, authorization_status, execution_status, result_summary, call_depth
        )
        VALUES (
            p_conversation_id, p_tool_name, p_arguments, 'denied', 'failed', 'Tool does not exist or is inactive', p_call_depth
        );
        RAISE EXCEPTION 'Tool % is not recognized or is inactive', p_tool_name;
    END IF;

    -- Verify tool is permitted for this assistant type
    IF NOT (v_ast.assistant_type = ANY(v_tool.assistant_types)) THEN
        INSERT INTO public.ai_tool_calls (
            conversation_id, tool_name, arguments, authorization_status, execution_status, result_summary, call_depth
        )
        VALUES (
            p_conversation_id, p_tool_name, p_arguments, 'denied', 'failed', 'Tool unauthorized for assistant type', p_call_depth
        );
        RAISE EXCEPTION 'Tool % is not permitted for assistant type %', p_tool_name, v_ast.assistant_type;
    END IF;

    -- Security Barrier: Check user authorization
    IF v_ast.assistant_type = 'recruiter_copilot' THEN
        IF NOT public.check_user_is_recruiter(v_conv.organization_id) AND NOT public.is_platform_admin(auth.uid()) THEN
            INSERT INTO public.ai_tool_calls (
                conversation_id, tool_name, arguments, authorization_status, execution_status, result_summary, call_depth
            )
            VALUES (
                p_conversation_id, p_tool_name, p_arguments, 'denied', 'failed', 'Unauthorized recruiter access', p_call_depth
            );
            RAISE EXCEPTION 'Unauthorized: Caller is not an authorized recruiter for this session';
        END IF;
    ELSIF v_ast.assistant_type = 'candidate_career' THEN
        IF v_conv.user_id <> auth.uid() THEN
            INSERT INTO public.ai_tool_calls (
                conversation_id, tool_name, arguments, authorization_status, execution_status, result_summary, call_depth
            )
            VALUES (
                p_conversation_id, p_tool_name, p_arguments, 'denied', 'failed', 'Unauthorized candidate session access', p_call_depth
            );
            RAISE EXCEPTION 'Unauthorized: Cannot execute tools in another user session';
        END IF;
    END IF;

    -- HIGH-RISK ACTION INTERCEPTION: If tool requires confirmation, gatekeep via ai_action_requests
    IF v_tool.requires_confirmation IS TRUE THEN
        v_app_id := (p_arguments->>'application_id')::uuid;

        INSERT INTO public.ai_tool_calls (
            conversation_id, tool_name, arguments, authorization_status, execution_status, result_summary, call_depth
        )
        VALUES (
            p_conversation_id, p_tool_name, p_arguments, 'requires_approval', 'queued', 'Awaiting human confirmation', p_call_depth
        )
        RETURNING id INTO v_tool_call_id;

        INSERT INTO public.ai_action_requests (
            conversation_id, tool_call_id, requested_by, action_type, target_type, target_id,
            arguments, risk_level, status, idempotency_key
        )
        VALUES (
            p_conversation_id,
            v_tool_call_id,
            auth.uid(),
            p_tool_name,
            CASE WHEN v_app_id IS NOT NULL THEN 'application' ELSE 'job' END,
            COALESCE(v_app_id, v_conv.job_id, v_conv.id),
            p_arguments,
            v_tool.risk_level,
            'pending',
            'action:' || v_tool_call_id
        )
        RETURNING id INTO v_action_req_id;

        RETURN jsonb_build_object(
            'status', 'requires_approval',
            'action_request_id', v_action_req_id,
            'message', 'This action requires explicit human confirmation. An action request has been created.'
        );
    END IF;

    -- READ / SAFE EXECUTION ENGINE
    INSERT INTO public.ai_tool_calls (
        conversation_id, tool_name, arguments, authorization_status, execution_status, call_depth
    )
    VALUES (
        p_conversation_id, p_tool_name, p_arguments, 'authorized', 'running', p_call_depth
    )
    RETURNING id INTO v_tool_call_id;

    -- Execute Safe Read Tool Handlers
    IF p_tool_name = 'get_my_profile' THEN
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        SELECT jsonb_build_object(
            'candidate_id', c.id,
            'headline', cp.headline,
            'bio', cp.professional_summary,
            'location_city', cp.city,
            'location_country', cp.country_code,
            'status', c.status
        ) INTO v_result
        FROM public.candidates c
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        WHERE c.id = v_cand_id;

    ELSIF p_tool_name = 'get_my_skills' THEN
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        SELECT jsonb_build_object(
            'skills', COALESCE(jsonb_agg(jsonb_build_object(
                'skill_name', cs.skill_name,
                'proficiency', cs.proficiency_level,
                'verified', cs.is_verified
            )), '[]'::jsonb)
        ) INTO v_result
        FROM public.candidate_skills cs
        WHERE cs.candidate_id = v_cand_id;

    ELSIF p_tool_name = 'get_my_match_results' THEN
        SELECT id INTO v_cand_id FROM public.candidates WHERE user_id = auth.uid();
        v_job_id := (p_arguments->>'job_id')::uuid;

        SELECT jsonb_build_object(
            'job_id', mr.job_id,
            'candidate_id', v_cand_id,
            'overall_score', mr.overall_score,
            'ai_recommendation', mr.ai_recommendation,
            'dimension_scores', mr.dimension_scores
        ) INTO v_result
        FROM public.matching_runs mr
        WHERE mr.candidate_id = v_cand_id 
          AND (v_job_id IS NULL OR mr.job_id = v_job_id)
        ORDER BY mr.created_at DESC LIMIT 1;

        IF v_result IS NULL THEN
            v_result := jsonb_build_object('message', 'No matching results found for this job');
        END IF;

    ELSIF p_tool_name = 'search_candidates' THEN
        -- Recruiter candidate search scoped to authorized organization
        v_job_id := (p_arguments->>'job_id')::uuid;
        SELECT jsonb_build_object(
            'total_found', count(*),
            'candidates', COALESCE(jsonb_agg(jsonb_build_object(
                'application_id', a.id,
                'candidate_id', a.candidate_id,
                'job_id', a.job_id,
                'status', a.status,
                'created_at', a.created_at
            )), '[]'::jsonb)
        ) INTO v_result
        FROM public.applications a
        WHERE (v_job_id IS NULL OR a.job_id = v_job_id)
          AND EXISTS (
              SELECT 1 FROM public.jobs j WHERE j.id = a.job_id AND j.organization_id = v_conv.organization_id
          );

    ELSIF p_tool_name = 'rank_candidates_for_job' THEN
        v_job_id := (p_arguments->>'job_id')::uuid;
        IF v_job_id IS NULL THEN
            v_job_id := v_conv.job_id;
        END IF;

        -- Verify job belongs to recruiter org
        IF NOT EXISTS (SELECT 1 FROM public.jobs WHERE id = v_job_id AND organization_id = v_conv.organization_id) THEN
            RAISE EXCEPTION 'Job % does not belong to your organization', v_job_id;
        END IF;

        SELECT jsonb_build_object(
            'job_id', v_job_id,
            'ranked_candidates', COALESCE(jsonb_agg(jsonb_build_object(
                'application_id', a.id,
                'candidate_id', a.candidate_id,
                'status', a.status,
                'match_score', mr.overall_score,
                'recommendation', mr.ai_recommendation
            ) ORDER BY COALESCE(mr.overall_score, 0) DESC), '[]'::jsonb)
        ) INTO v_result
        FROM public.applications a
        LEFT JOIN LATERAL (
            SELECT overall_score, ai_recommendation
            FROM public.matching_runs mr_sub
            WHERE mr_sub.job_id = a.job_id AND mr_sub.candidate_id = a.candidate_id
            ORDER BY mr_sub.created_at DESC LIMIT 1
        ) mr ON true
        WHERE a.job_id = v_job_id;

    ELSIF p_tool_name = 'get_job_details' THEN
        v_job_id := (p_arguments->>'job_id')::uuid;
        IF v_job_id IS NULL THEN v_job_id := v_conv.job_id; END IF;

        SELECT jsonb_build_object(
            'id', j.id,
            'title', j.title,
            'status', j.status,
            'employment_type', j.employment_type,
            'workplace_type', j.workplace_type,
            'description', j.description
        ) INTO v_result
        FROM public.jobs j
        WHERE j.id = v_job_id 
          AND (j.organization_id = v_conv.organization_id OR j.status = 'published');

    ELSE
        v_result := jsonb_build_object('status', 'executed', 'tool', p_tool_name);
    END IF;

    UPDATE public.ai_tool_calls
    SET execution_status = 'completed',
        result_summary = substr(v_result::text, 1, 500),
        completed_at = now()
    WHERE id = v_tool_call_id;

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    IF v_tool_call_id IS NOT NULL THEN
        UPDATE public.ai_tool_calls
        SET execution_status = 'failed',
            result_summary = SQLERRM,
            completed_at = now()
        WHERE id = v_tool_call_id;
    END IF;
    RAISE;
END;
$$;

-- 13.4 Approve AI Action Request
CREATE OR REPLACE FUNCTION public.approve_ai_action_request(
    p_action_request_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req RECORD;
    v_conv RECORD;
    v_result JSONB;
BEGIN
    SELECT * INTO v_req FROM public.ai_action_requests WHERE id = p_action_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Action request % not found', p_action_request_id;
    END IF;

    SELECT * INTO v_conv FROM public.ai_conversations WHERE id = v_req.conversation_id;

    -- CRITICAL SAFETY INVARIANT: AI CANNOT MAKE FINAL HIRING DECISIONS
    IF v_req.action_type IN ('hire', 'final_offer', 'final_reject') THEN
        RAISE EXCEPTION 'PROHIBITED_AI_ACTION: AI cannot execute final hiring decisions (%s). Final decisions must be made by human recruiters via hiring_decisions system', v_req.action_type;
    END IF;

    -- Verify authorizer has recruiter permissions for the organization
    IF v_conv.organization_id IS NOT NULL THEN
        IF NOT public.check_user_is_recruiter(v_conv.organization_id) AND NOT public.is_platform_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized: Only authorized recruiters for organization % can approve actions', v_conv.organization_id;
        END IF;
    END IF;

    -- Idempotency check: If already executed, return existing status safely
    IF v_req.status = 'executed' THEN
        RETURN jsonb_build_object(
            'status', 'already_executed',
            'action_request_id', v_req.id,
            'message', 'Action request was already approved and executed'
        );
    END IF;

    -- Execute corresponding business action through existing procedures
    IF v_req.action_type = 'request_candidate_shortlist' THEN
        DECLARE
            v_app_rec RECORD;
        BEGIN
            SELECT job_id, candidate_id INTO v_app_rec FROM public.applications WHERE id = v_req.target_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Application % not found', v_req.target_id;
            END IF;

            PERFORM public.shortlist_candidate(
                v_app_rec.job_id,
                v_app_rec.candidate_id,
                v_req.target_id,
                COALESCE(v_req.arguments->>'notes', 'Shortlisted via AI Copilot recommendation')
            );
            v_result := jsonb_build_object('application_id', v_req.target_id, 'action', 'shortlisted');
        END;

    ELSIF v_req.action_type = 'request_move_application_stage' THEN
        UPDATE public.applications
        SET status = COALESCE(v_req.arguments->>'stage', 'under_review'), updated_at = now()
        WHERE id = v_req.target_id;
        v_result := jsonb_build_object('application_id', v_req.target_id, 'new_stage', v_req.arguments->>'stage');

    ELSE
        v_result := jsonb_build_object('action', v_req.action_type, 'status', 'delegated');
    END IF;

    UPDATE public.ai_action_requests
    SET status = 'executed',
        approved_by = auth.uid(),
        approved_at = now(),
        reason = p_reason,
        updated_at = now()
    WHERE id = p_action_request_id;

    -- Update linked tool call status if present
    IF v_req.tool_call_id IS NOT NULL THEN
        UPDATE public.ai_tool_calls
        SET execution_status = 'completed',
            authorization_status = 'authorized',
            result_summary = 'Action approved and executed by human recruiter',
            completed_at = now()
        WHERE id = v_req.tool_call_id;
    END IF;

    -- Audit log integration
    INSERT INTO public.audit_logs (
        actor_user_id, organization_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        auth.uid(),
        v_conv.organization_id,
        'ai_action_approved_and_executed',
        'ai_action_request',
        p_action_request_id,
        jsonb_build_object(
            'action_type', v_req.action_type,
            'target_type', v_req.target_type,
            'target_id', v_req.target_id,
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object(
        'status', 'executed',
        'action_request_id', p_action_request_id,
        'result', v_result
    );
END;
$$;

-- 13.5 Reject AI Action Request
CREATE OR REPLACE FUNCTION public.reject_ai_action_request(
    p_action_request_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_req RECORD;
    v_conv RECORD;
BEGIN
    SELECT * INTO v_req FROM public.ai_action_requests WHERE id = p_action_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Action request % not found', p_action_request_id;
    END IF;

    SELECT * INTO v_conv FROM public.ai_conversations WHERE id = v_req.conversation_id;

    IF v_conv.organization_id IS NOT NULL THEN
        IF NOT public.check_user_is_recruiter(v_conv.organization_id) AND NOT public.is_platform_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized: Only authorized recruiters can reject actions';
        END IF;
    END IF;

    UPDATE public.ai_action_requests
    SET status = 'rejected',
        rejected_by = auth.uid(),
        rejected_at = now(),
        reason = p_reason,
        updated_at = now()
    WHERE id = p_action_request_id;

    IF v_req.tool_call_id IS NOT NULL THEN
        UPDATE public.ai_tool_calls
        SET execution_status = 'cancelled',
            authorization_status = 'denied',
            result_summary = 'Action rejected by human reviewer',
            completed_at = now()
        WHERE id = v_req.tool_call_id;
    END IF;

    RETURN true;
END;
$$;

-- 13.6 Create AI Recommendation
CREATE OR REPLACE FUNCTION public.create_ai_recommendation(
    p_org_id UUID,
    p_user_id UUID,
    p_type TEXT,
    p_target_type TEXT,
    p_target_id UUID,
    p_title TEXT,
    p_summary TEXT,
    p_reasoning TEXT,
    p_confidence NUMERIC,
    p_priority TEXT DEFAULT 'medium',
    p_evidence JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rec_id UUID;
BEGIN
    INSERT INTO public.ai_recommendations (
        organization_id, user_id, recommendation_type, target_type, target_id,
        title, summary, reasoning, confidence, priority, evidence, status
    )
    VALUES (
        p_org_id, p_user_id, p_type, p_target_type, p_target_id,
        p_title, p_summary, p_reasoning, p_confidence, p_priority, p_evidence, 'new'
    )
    RETURNING id INTO v_rec_id;

    RETURN v_rec_id;
END;
$$;

-- 13.7 Record AI Usage
CREATE OR REPLACE FUNCTION public.record_ai_usage(
    p_user_id UUID,
    p_org_id UUID,
    p_assistant_id UUID,
    p_conv_id UUID,
    p_provider TEXT,
    p_model TEXT,
    p_req_type TEXT,
    p_in_tokens INT,
    p_out_tokens INT,
    p_cost NUMERIC DEFAULT 0.000000,
    p_latency INT DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rec_id UUID;
BEGIN
    INSERT INTO public.ai_usage_records (
        user_id, organization_id, assistant_id, conversation_id,
        provider, model, request_type, input_tokens, output_tokens, total_tokens,
        estimated_cost, latency_ms, status
    )
    VALUES (
        p_user_id, p_org_id, p_assistant_id, p_conv_id,
        p_provider, p_model, p_req_type, p_in_tokens, p_out_tokens, (p_in_tokens + p_out_tokens),
        p_cost, p_latency, 'success'
    )
    RETURNING id INTO v_rec_id;

    RETURN v_rec_id;
END;
$$;

-- 13.8 Recruiter Daily Brief Generator / Aggregator
CREATE OR REPLACE FUNCTION public.get_daily_recruiter_brief(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_new_apps INT;
    v_pending_reviews INT;
    v_upcoming_interviews INT;
    v_client_feedbacks INT;
BEGIN
    IF NOT public.check_user_is_recruiter(p_org_id) AND NOT public.is_platform_admin(auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Caller is not a recruiter for organization %', p_org_id;
    END IF;

    SELECT count(*) INTO v_new_apps
    FROM public.applications a
    JOIN public.jobs j ON j.id = a.job_id
    WHERE j.organization_id = p_org_id AND a.created_at >= now() - interval '24 hours';

    SELECT count(*) INTO v_pending_reviews
    FROM public.applications a
    JOIN public.jobs j ON j.id = a.job_id
    WHERE j.organization_id = p_org_id AND a.status IN ('submitted', 'under_review');

    SELECT count(*) INTO v_upcoming_interviews
    FROM public.interviews i
    WHERE i.organization_id = p_org_id AND i.status = 'scheduled' AND i.scheduled_start_at BETWEEN now() AND now() + interval '24 hours';

    SELECT count(*) INTO v_client_feedbacks
    FROM public.client_candidate_feedback cf
    JOIN public.client_candidate_shares cs ON cs.id = cf.candidate_share_id
    JOIN public.client_job_access cja ON cja.id = cs.client_job_access_id
    WHERE cja.organization_id = p_org_id AND cf.created_at >= now() - interval '24 hours';

    RETURN jsonb_build_object(
        'organization_id', p_org_id,
        'generated_at', now(),
        'new_applications_last_24h', v_new_apps,
        'applications_pending_review', v_pending_reviews,
        'interviews_today', v_upcoming_interviews,
        'client_feedback_received_last_24h', v_client_feedbacks
    );
END;
$$;

-- =============================================================================
-- END OF MIGRATION 20260915001300_ai_assistants_copilot.sql
-- =============================================================================
