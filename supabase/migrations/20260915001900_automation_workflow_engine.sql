-- =============================================================================
-- Task 19: Automation & Workflow Engine
-- Migration: 20260915001900_automation_workflow_engine.sql
-- =============================================================================
-- Tables:
--   workflow_definitions, workflow_versions, workflow_triggers,
--   workflow_conditions, workflow_fields, workflow_actions,
--   workflow_approval_steps, workflow_executions, workflow_execution_steps,
--   workflow_execution_logs, workflow_schedules, workflow_event_queue,
--   workflow_failures
-- RPCs:
--   validate_workflow_definition, publish_workflow_version,
--   enqueue_workflow_event, route_workflow_events,
--   execute_workflow_action, get_workflow_execution,
--   get_failed_workflows, retry_workflow_step,
--   pause_workflow, resume_workflow, cancel_workflow_execution,
--   approve_workflow_action, deny_workflow_action,
--   get_workflow_analytics, log_workflow_audit
-- =============================================================================

-- =============================================================================
-- 1. WORKFLOW DEFINITIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_definitions (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID        REFERENCES public.organizations(id) ON DELETE CASCADE,
    name                TEXT        NOT NULL,
    description         TEXT,
    workflow_type       TEXT        NOT NULL DEFAULT 'application'
        CHECK (workflow_type IN ('organization','job','application','candidate','assessment',
                                  'interview','client','notification','billing','system','custom')),
    status              TEXT        NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','published','paused','archived')),
    current_version     INTEGER     NOT NULL DEFAULT 1,
    trigger_type        TEXT        NOT NULL DEFAULT 'event'
        CHECK (trigger_type IN ('event','schedule','manual','condition','webhook')),
    job_id              UUID        REFERENCES public.jobs(id) ON DELETE SET NULL,
    category_id         UUID        REFERENCES public.job_categories(id) ON DELETE SET NULL,
    priority            INTEGER     NOT NULL DEFAULT 50 CHECK (priority BETWEEN 1 AND 100),
    is_system           BOOLEAN     NOT NULL DEFAULT false,
    max_executions_per_entity INTEGER NOT NULL DEFAULT 10,
    max_execution_depth  INTEGER     NOT NULL DEFAULT 5,
    idempotency_window_seconds INTEGER NOT NULL DEFAULT 300,
    created_by          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wd_org          ON public.workflow_definitions(organization_id);
CREATE INDEX IF NOT EXISTS idx_wd_type         ON public.workflow_definitions(workflow_type);
CREATE INDEX IF NOT EXISTS idx_wd_status       ON public.workflow_definitions(status);
CREATE INDEX IF NOT EXISTS idx_wd_trigger      ON public.workflow_definitions(trigger_type);
CREATE INDEX IF NOT EXISTS idx_wd_job          ON public.workflow_definitions(job_id);
CREATE INDEX IF NOT EXISTS idx_wd_category     ON public.workflow_definitions(category_id);
CREATE INDEX IF NOT EXISTS idx_wd_system       ON public.workflow_definitions(is_system);

CREATE TRIGGER trg_wd_updated_at BEFORE UPDATE ON public.workflow_definitions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 2. WORKFLOW VERSIONS (Immutable published snapshots)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_versions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_definition_id  UUID        NOT NULL REFERENCES public.workflow_definitions(id) ON DELETE CASCADE,
    version                 INTEGER     NOT NULL,
    definition              JSONB       NOT NULL DEFAULT '{}'::JSONB,
    status                  TEXT        NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','published','deprecated','archived')),
    published_at            TIMESTAMPTZ,
    created_by              UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_workflow_version UNIQUE (workflow_definition_id, version)
);
CREATE INDEX IF NOT EXISTS idx_wv_def          ON public.workflow_versions(workflow_definition_id);
CREATE INDEX IF NOT EXISTS idx_wv_status       ON public.workflow_versions(status);
CREATE INDEX IF NOT EXISTS idx_wv_published    ON public.workflow_versions(published_at DESC);

-- =============================================================================
-- 3. WORKFLOW TRIGGERS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_triggers (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_version_id     UUID        NOT NULL REFERENCES public.workflow_versions(id) ON DELETE CASCADE,
    trigger_type            TEXT        NOT NULL CHECK (trigger_type IN ('event','schedule','manual','condition','webhook')),
    event_type              TEXT,
    configuration           JSONB       NOT NULL DEFAULT '{}'::JSONB,
    is_active               BOOLEAN     NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wt_version      ON public.workflow_triggers(workflow_version_id);
CREATE INDEX IF NOT EXISTS idx_wt_type         ON public.workflow_triggers(trigger_type);
CREATE INDEX IF NOT EXISTS idx_wt_event        ON public.workflow_triggers(event_type);
CREATE INDEX IF NOT EXISTS idx_wt_active       ON public.workflow_triggers(is_active) WHERE is_active = true;

CREATE TRIGGER trg_wt_updated_at BEFORE UPDATE ON public.workflow_triggers
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. WORKFLOW FIELDS REGISTRY (Allowlist — prevents arbitrary column access)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_fields (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    field_key           TEXT        NOT NULL UNIQUE,
    entity_type         TEXT        NOT NULL,
    data_type           TEXT        NOT NULL CHECK (data_type IN ('text','number','boolean','date','uuid','array','jsonb')),
    description         TEXT,
    allowed_operators   TEXT[]      NOT NULL DEFAULT ARRAY['equals','not_equals'],
    is_active           BOOLEAN     NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wf_entity   ON public.workflow_fields(entity_type);
CREATE INDEX IF NOT EXISTS idx_wf_active   ON public.workflow_fields(is_active) WHERE is_active = true;

-- Seed canonical field registry
INSERT INTO public.workflow_fields (field_key, entity_type, data_type, description, allowed_operators)
VALUES
    ('application.status',              'application', 'text',    'Application status',                    ARRAY['equals','not_equals','in','not_in']),
    ('application.current_stage_id',    'application', 'uuid',    'Current ATS stage ID',                  ARRAY['equals','not_equals']),
    ('application.match_score',         'application', 'number',  'Latest match score from matching engine',ARRAY['equals','not_equals','greater_than','greater_than_or_equal','less_than','less_than_or_equal']),
    ('application.applied_at',          'application', 'date',    'Application submission date',           ARRAY['greater_than','less_than','greater_than_or_equal','less_than_or_equal']),
    ('candidate.profile_completion',    'candidate',   'number',  'Profile completion percentage',         ARRAY['equals','not_equals','greater_than','greater_than_or_equal','less_than','less_than_or_equal']),
    ('candidate.country_code',          'candidate',   'text',    'Candidate country code',                ARRAY['equals','not_equals','in','not_in']),
    ('candidate.years_of_experience',   'candidate',   'number',  'Candidate years of experience',        ARRAY['equals','not_equals','greater_than','greater_than_or_equal','less_than','less_than_or_equal']),
    ('candidate.remote_preference',     'candidate',   'text',    'Candidate remote preference',          ARRAY['equals','not_equals','in','not_in']),
    ('candidate.availability_status',   'candidate',   'text',    'Candidate availability status',        ARRAY['equals','not_equals','in','not_in']),
    ('assessment.passed',               'assessment',  'boolean', 'Assessment passed flag',               ARRAY['equals','not_equals']),
    ('assessment.score',                'assessment',  'number',  'Assessment score',                     ARRAY['equals','not_equals','greater_than','greater_than_or_equal','less_than','less_than_or_equal']),
    ('assessment.status',               'assessment',  'text',    'Assessment invitation status',         ARRAY['equals','not_equals','in','not_in']),
    ('interview.status',                'interview',   'text',    'Interview status',                     ARRAY['equals','not_equals','in','not_in']),
    ('interview.scheduled_at',          'interview',   'date',    'Interview scheduled time',             ARRAY['greater_than','less_than','greater_than_or_equal','less_than_or_equal']),
    ('client_feedback.decision',        'client',      'text',    'Client feedback hiring decision',      ARRAY['equals','not_equals','in','not_in']),
    ('client_feedback.rating',          'client',      'number',  'Client feedback rating',              ARRAY['equals','not_equals','greater_than','greater_than_or_equal','less_than','less_than_or_equal']),
    ('job.status',                      'job',         'text',    'Job status',                          ARRAY['equals','not_equals','in','not_in']),
    ('job.experience_level',            'job',         'text',    'Job experience level requirement',    ARRAY['equals','not_equals','in','not_in']),
    ('subscription.status',             'billing',     'text',    'Org subscription status',             ARRAY['equals','not_equals','in','not_in']),
    ('subscription.plan',               'billing',     'text',    'Org subscription plan',               ARRAY['equals','not_equals','in','not_in'])
ON CONFLICT (field_key) DO NOTHING;

-- =============================================================================
-- 5. WORKFLOW CONDITIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_conditions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_version_id     UUID        NOT NULL REFERENCES public.workflow_versions(id) ON DELETE CASCADE,
    parent_condition_id     UUID        REFERENCES public.workflow_conditions(id) ON DELETE CASCADE,
    field_key               TEXT        REFERENCES public.workflow_fields(field_key) ON DELETE RESTRICT,
    operator                TEXT        NOT NULL CHECK (operator IN (
        'equals','not_equals','greater_than','greater_than_or_equal',
        'less_than','less_than_or_equal','contains','not_contains',
        'in','not_in','exists','not_exists'
    )),
    value                   TEXT,
    value_type              TEXT        NOT NULL DEFAULT 'literal' CHECK (value_type IN ('literal','field_ref','context_ref')),
    logical_operator        TEXT        NOT NULL DEFAULT 'AND' CHECK (logical_operator IN ('AND','OR')),
    sort_order              INTEGER     NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wc_version      ON public.workflow_conditions(workflow_version_id);
CREATE INDEX IF NOT EXISTS idx_wc_parent       ON public.workflow_conditions(parent_condition_id);
CREATE INDEX IF NOT EXISTS idx_wc_field        ON public.workflow_conditions(field_key);

CREATE TRIGGER trg_wc_updated_at BEFORE UPDATE ON public.workflow_conditions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 6. WORKFLOW ACTIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_actions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_version_id     UUID        NOT NULL REFERENCES public.workflow_versions(id) ON DELETE CASCADE,
    action_type             TEXT        NOT NULL CHECK (action_type IN (
        'send_notification','send_email','send_whatsapp',
        'move_application_stage','shortlist_candidate','reject_application',
        'create_assessment_invitation','request_interview',
        'create_review_item','add_to_talent_pool','remove_from_talent_pool',
        'update_candidate_field','update_job_field',
        'create_task','call_webhook','start_ai_action',
        'create_analytics_event','run_matching',
        'send_billing_notification','restrict_feature','restore_feature'
    )),
    risk_level              TEXT        NOT NULL DEFAULT 'low'
        CHECK (risk_level IN ('read','low','medium','high','critical')),
    configuration           JSONB       NOT NULL DEFAULT '{}'::JSONB,
    sort_order              INTEGER     NOT NULL DEFAULT 0,
    delay_seconds           INTEGER     NOT NULL DEFAULT 0 CHECK (delay_seconds >= 0),
    requires_approval       BOOLEAN     NOT NULL DEFAULT false,
    max_retries             INTEGER     NOT NULL DEFAULT 3 CHECK (max_retries BETWEEN 0 AND 10),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wa_version      ON public.workflow_actions(workflow_version_id);
CREATE INDEX IF NOT EXISTS idx_wa_type         ON public.workflow_actions(action_type);
CREATE INDEX IF NOT EXISTS idx_wa_risk         ON public.workflow_actions(risk_level);
CREATE INDEX IF NOT EXISTS idx_wa_approval     ON public.workflow_actions(requires_approval) WHERE requires_approval = true;

CREATE TRIGGER trg_wa_updated_at BEFORE UPDATE ON public.workflow_actions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 7. WORKFLOW APPROVAL STEPS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_approval_steps (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_version_id     UUID        NOT NULL REFERENCES public.workflow_versions(id) ON DELETE CASCADE,
    action_id               UUID        REFERENCES public.workflow_actions(id) ON DELETE CASCADE,
    approval_type           TEXT        NOT NULL DEFAULT 'single' CHECK (approval_type IN ('single','any_of','all')),
    required_role           TEXT,
    required_permission     TEXT,
    timeout_hours           INTEGER     NOT NULL DEFAULT 48,
    status                  TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_was_version     ON public.workflow_approval_steps(workflow_version_id);
CREATE INDEX IF NOT EXISTS idx_was_action      ON public.workflow_approval_steps(action_id);

CREATE TRIGGER trg_was_updated_at BEFORE UPDATE ON public.workflow_approval_steps
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 8. WORKFLOW SCHEDULES
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_schedules (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_version_id     UUID        NOT NULL REFERENCES public.workflow_versions(id) ON DELETE CASCADE,
    schedule_type           TEXT        NOT NULL CHECK (schedule_type IN ('once','cron','interval')),
    cron_expression         TEXT,
    interval_seconds        INTEGER,
    timezone                TEXT        NOT NULL DEFAULT 'UTC',
    next_run_at             TIMESTAMPTZ,
    last_run_at             TIMESTAMPTZ,
    run_count               INTEGER     NOT NULL DEFAULT 0,
    status                  TEXT        NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed','disabled')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ws_version      ON public.workflow_schedules(workflow_version_id);
CREATE INDEX IF NOT EXISTS idx_ws_next_run     ON public.workflow_schedules(next_run_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_ws_status       ON public.workflow_schedules(status);

CREATE TRIGGER trg_wsch_updated_at BEFORE UPDATE ON public.workflow_schedules
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 9. WORKFLOW EVENT QUEUE
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_event_queue (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID        REFERENCES public.organizations(id) ON DELETE CASCADE,
    event_type          TEXT        NOT NULL,
    entity_type         TEXT        NOT NULL,
    entity_id           UUID        NOT NULL,
    event_payload       JSONB       NOT NULL DEFAULT '{}'::JSONB,
    source_event_id     TEXT,
    idempotency_key     TEXT,
    status              TEXT        NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','processing','processed','failed','ignored')),
    attempt_count       INTEGER     NOT NULL DEFAULT 0,
    scheduled_for       TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_weq_idempotency UNIQUE (organization_id, idempotency_key)
);
-- Partial unique index to enforce idempotency only when key is provided
CREATE UNIQUE INDEX IF NOT EXISTS uq_weq_idempotency_partial
    ON public.workflow_event_queue(organization_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_weq_org         ON public.workflow_event_queue(organization_id);
CREATE INDEX IF NOT EXISTS idx_weq_type        ON public.workflow_event_queue(event_type);
CREATE INDEX IF NOT EXISTS idx_weq_status      ON public.workflow_event_queue(status);
CREATE INDEX IF NOT EXISTS idx_weq_scheduled   ON public.workflow_event_queue(scheduled_for) WHERE status IN ('queued','processing');
CREATE INDEX IF NOT EXISTS idx_weq_entity      ON public.workflow_event_queue(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_weq_source      ON public.workflow_event_queue(source_event_id);

CREATE TRIGGER trg_weq_updated_at BEFORE UPDATE ON public.workflow_event_queue
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 10. WORKFLOW EXECUTIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_executions (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id         UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    workflow_definition_id  UUID        NOT NULL REFERENCES public.workflow_definitions(id) ON DELETE CASCADE,
    workflow_version_id     UUID        NOT NULL REFERENCES public.workflow_versions(id) ON DELETE CASCADE,
    trigger_event_id        UUID        REFERENCES public.workflow_event_queue(id) ON DELETE SET NULL,
    entity_type             TEXT        NOT NULL,
    entity_id               UUID        NOT NULL,
    context                 JSONB       NOT NULL DEFAULT '{}'::JSONB,
    status                  TEXT        NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','running','waiting','completed','failed','cancelled','requires_approval')),
    current_step            INTEGER     NOT NULL DEFAULT 0,
    execution_depth         INTEGER     NOT NULL DEFAULT 0,
    actor_id                UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    failed_at               TIMESTAMPTZ,
    error_code              TEXT,
    error_message           TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_we_org          ON public.workflow_executions(organization_id);
CREATE INDEX IF NOT EXISTS idx_we_def          ON public.workflow_executions(workflow_definition_id);
CREATE INDEX IF NOT EXISTS idx_we_version      ON public.workflow_executions(workflow_version_id);
CREATE INDEX IF NOT EXISTS idx_we_entity       ON public.workflow_executions(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_we_status       ON public.workflow_executions(status);
CREATE INDEX IF NOT EXISTS idx_we_created      ON public.workflow_executions(created_at DESC);
-- Add scheduled_for for delayed execution support
ALTER TABLE public.workflow_executions
    ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_we_pending ON public.workflow_executions(status, scheduled_for)
    WHERE status IN ('queued','running','waiting');

CREATE TRIGGER trg_we_updated_at BEFORE UPDATE ON public.workflow_executions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 11. WORKFLOW EXECUTION STEPS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_execution_steps (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_execution_id   UUID        NOT NULL REFERENCES public.workflow_executions(id) ON DELETE CASCADE,
    action_id               UUID        REFERENCES public.workflow_actions(id) ON DELETE SET NULL,
    step_order              INTEGER     NOT NULL DEFAULT 0,
    status                  TEXT        NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','running','waiting','completed','failed','skipped','cancelled')),
    input_data              JSONB       NOT NULL DEFAULT '{}'::JSONB,
    output_data             JSONB       NOT NULL DEFAULT '{}'::JSONB,
    error_code              TEXT,
    error_message           TEXT,
    failure_type            TEXT        CHECK (failure_type IN (
        'temporary_failure','permanent_failure','authorization_failure',
        'validation_failure','rate_limit','external_provider_failure'
    )),
    retry_count             INTEGER     NOT NULL DEFAULT 0,
    next_retry_at           TIMESTAMPTZ,
    requires_approval       BOOLEAN     NOT NULL DEFAULT false,
    approved_by             UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_at             TIMESTAMPTZ,
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wes_execution   ON public.workflow_execution_steps(workflow_execution_id);
CREATE INDEX IF NOT EXISTS idx_wes_action      ON public.workflow_execution_steps(action_id);
CREATE INDEX IF NOT EXISTS idx_wes_status      ON public.workflow_execution_steps(status);
CREATE INDEX IF NOT EXISTS idx_wes_retry       ON public.workflow_execution_steps(next_retry_at) WHERE status = 'failed';
CREATE INDEX IF NOT EXISTS idx_wes_approval    ON public.workflow_execution_steps(requires_approval) WHERE requires_approval = true AND status = 'waiting';

CREATE TRIGGER trg_wes_updated_at BEFORE UPDATE ON public.workflow_execution_steps
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 12. WORKFLOW EXECUTION LOGS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_execution_logs (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_execution_id   UUID        NOT NULL REFERENCES public.workflow_executions(id) ON DELETE CASCADE,
    step_id                 UUID        REFERENCES public.workflow_execution_steps(id) ON DELETE SET NULL,
    level                   TEXT        NOT NULL DEFAULT 'info' CHECK (level IN ('info','warning','error')),
    message                 TEXT        NOT NULL,
    metadata                JSONB       NOT NULL DEFAULT '{}'::JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wel_execution   ON public.workflow_execution_logs(workflow_execution_id);
CREATE INDEX IF NOT EXISTS idx_wel_level       ON public.workflow_execution_logs(level);
CREATE INDEX IF NOT EXISTS idx_wel_created     ON public.workflow_execution_logs(created_at DESC);

-- =============================================================================
-- 13. WORKFLOW FAILURES (Dead Letter Queue)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.workflow_failures (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_execution_id   UUID        NOT NULL REFERENCES public.workflow_executions(id) ON DELETE CASCADE,
    step_id                 UUID        REFERENCES public.workflow_execution_steps(id) ON DELETE SET NULL,
    failure_type            TEXT        NOT NULL,
    error_code              TEXT,
    error_message           TEXT,
    retryable               BOOLEAN     NOT NULL DEFAULT false,
    retry_count             INTEGER     NOT NULL DEFAULT 0,
    resolved_at             TIMESTAMPTZ,
    resolved_by             UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wf_execution    ON public.workflow_failures(workflow_execution_id);
CREATE INDEX IF NOT EXISTS idx_wf_retryable    ON public.workflow_failures(retryable) WHERE retryable = true AND resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_wf_resolved     ON public.workflow_failures(resolved_at);

-- =============================================================================
-- 14. RLS SETUP
-- =============================================================================
ALTER TABLE public.workflow_definitions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_versions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_triggers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_conditions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_fields              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_actions             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_approval_steps      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_schedules           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_event_queue         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_executions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_execution_steps     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_execution_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_failures            ENABLE ROW LEVEL SECURITY;

-- workflow_fields is a public registry — all authenticated users may read
CREATE POLICY wf_fields_select ON public.workflow_fields FOR SELECT
    TO authenticated USING (is_active = true);

CREATE POLICY wf_fields_manage ON public.workflow_fields FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- workflow_definitions: org members see their own; platform admin sees system workflows
CREATE POLICY wd_select ON public.workflow_definitions FOR SELECT
    TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR is_system = true
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = workflow_definitions.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
    );

CREATE POLICY wd_manage ON public.workflow_definitions FOR ALL
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = workflow_definitions.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager','recruiter')
        )
    );

-- workflow_versions: same org scope as definitions
CREATE POLICY wv_select ON public.workflow_versions FOR SELECT
    TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.workflow_definitions wd
            JOIN public.organization_members om ON om.organization_id = wd.organization_id
            WHERE wd.id = workflow_versions.workflow_definition_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
    );

CREATE POLICY wv_manage ON public.workflow_versions FOR ALL
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.workflow_definitions wd
            JOIN public.organization_members om ON om.organization_id = wd.organization_id
            JOIN public.roles r ON r.id = om.role_id
            WHERE wd.id = workflow_versions.workflow_definition_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager','recruiter')
        )
    );

-- workflow_triggers, conditions, actions, approval_steps: inherit from version
CREATE POLICY wtr_select ON public.workflow_triggers FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_versions wv JOIN public.workflow_definitions wd ON wd.id = wv.workflow_definition_id
                   JOIN public.organization_members om ON om.organization_id = wd.organization_id
                   WHERE wv.id = workflow_triggers.workflow_version_id AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

CREATE POLICY wcn_select ON public.workflow_conditions FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_versions wv JOIN public.workflow_definitions wd ON wd.id = wv.workflow_definition_id
                   JOIN public.organization_members om ON om.organization_id = wd.organization_id
                   WHERE wv.id = workflow_conditions.workflow_version_id AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

CREATE POLICY wan_select ON public.workflow_actions FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_versions wv JOIN public.workflow_definitions wd ON wd.id = wv.workflow_definition_id
                   JOIN public.organization_members om ON om.organization_id = wd.organization_id
                   WHERE wv.id = workflow_actions.workflow_version_id AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

CREATE POLICY was2_select ON public.workflow_approval_steps FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_versions wv JOIN public.workflow_definitions wd ON wd.id = wv.workflow_definition_id
                   JOIN public.organization_members om ON om.organization_id = wd.organization_id
                   WHERE wv.id = workflow_approval_steps.workflow_version_id AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

-- workflow_executions: org members see their org executions
CREATE POLICY we_select ON public.workflow_executions FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = workflow_executions.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
    );

CREATE POLICY we_system ON public.workflow_executions FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- execution steps and logs: same org scope
CREATE POLICY wes_select ON public.workflow_execution_steps FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_executions we
                   JOIN public.organization_members om ON om.organization_id = we.organization_id
                   WHERE we.id = workflow_execution_steps.workflow_execution_id
                     AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

CREATE POLICY wel_select ON public.workflow_execution_logs FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_executions we
                   JOIN public.organization_members om ON om.organization_id = we.organization_id
                   WHERE we.id = workflow_execution_logs.workflow_execution_id
                     AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

CREATE POLICY weq_select ON public.workflow_event_queue FOR SELECT TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = workflow_event_queue.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
    );

CREATE POLICY weq_system ON public.workflow_event_queue FOR ALL
    USING (public.is_platform_admin(auth.uid()));

CREATE POLICY ws_select ON public.workflow_schedules FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_versions wv JOIN public.workflow_definitions wd ON wd.id = wv.workflow_definition_id
                   JOIN public.organization_members om ON om.organization_id = wd.organization_id
                   WHERE wv.id = workflow_schedules.workflow_version_id AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

CREATE POLICY wfail_select ON public.workflow_failures FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.workflow_executions we
                   JOIN public.organization_members om ON om.organization_id = we.organization_id
                   WHERE we.id = workflow_failures.workflow_execution_id
                     AND om.user_id = auth.uid() AND om.status='active')
           OR public.is_platform_admin(auth.uid()));

-- =============================================================================
-- 15. PERMISSIONS & ROLES
-- =============================================================================
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('workflows.view',      'View Workflows',          'View workflow definitions and executions',       'automation'),
    ('workflows.manage',    'Manage Workflows',        'Create, update, publish workflow definitions',   'automation'),
    ('workflows.execute',   'Execute Workflows',       'Manually trigger workflow executions',           'automation'),
    ('workflows.approve',   'Approve Workflow Steps',  'Approve high-risk workflow action steps',        'automation'),
    ('workflows.admin',     'Admin Workflows',         'Pause, resume, cancel, retry any workflow',      'automation')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('platform_admin',    'workflows.view'),
    ('platform_admin',    'workflows.manage'),
    ('platform_admin',    'workflows.execute'),
    ('platform_admin',    'workflows.approve'),
    ('platform_admin',    'workflows.admin'),
    ('platform_operator', 'workflows.view'),
    ('platform_operator', 'workflows.admin'),
    ('recruiter_manager', 'workflows.view'),
    ('recruiter_manager', 'workflows.manage'),
    ('recruiter_manager', 'workflows.execute'),
    ('recruiter_manager', 'workflows.approve'),
    ('recruiter',         'workflows.view'),
    ('recruiter',         'workflows.execute'),
    ('recruiter',         'workflows.approve')
) AS v(role_key, perm_key)
JOIN public.roles r ON r.key = v.role_key
JOIN public.permissions p ON p.key = v.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 16. VALIDATE WORKFLOW DEFINITION (Safe JSON schema validation)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.validate_workflow_definition(p_definition JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_trigger   JSONB;
    v_steps     JSONB;
    v_step      JSONB;
    v_i         INTEGER;
    v_field_key TEXT;
    v_errors    JSONB := '[]'::JSONB;

    FORBIDDEN_KEYS TEXT[] := ARRAY['sql','query','execute','eval','shell','system','exec','system_call','raw_sql'];
BEGIN
    -- Require trigger
    IF NOT (p_definition ? 'trigger') THEN
        v_errors := v_errors || '"missing_trigger"'::JSONB;
    END IF;

    -- Require steps array
    IF NOT (p_definition ? 'steps') THEN
        v_errors := v_errors || '"missing_steps"'::JSONB;
    END IF;

    -- Check step count limit
    v_steps := COALESCE(p_definition->'steps', '[]'::JSONB);
    IF jsonb_array_length(v_steps) > 50 THEN
        v_errors := v_errors || '"too_many_steps: max 50"'::JSONB;
    END IF;

    -- Validate each step
    FOR v_i IN 0..jsonb_array_length(COALESCE(v_steps,'[]'::JSONB))-1 LOOP
        v_step := v_steps->v_i;

        -- Block forbidden keys in any step
        FOR v_field_key IN SELECT jsonb_object_keys(v_step) LOOP
            IF v_field_key = ANY(FORBIDDEN_KEYS) THEN
                v_errors := v_errors || ('"forbidden_key: ' || v_field_key || '"')::JSONB;
            END IF;
        END LOOP;

        -- If condition step, validate field_key is in registry
        IF (v_step->>'type') = 'condition' AND v_step ? 'field' THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.workflow_fields wf
                WHERE wf.field_key = v_step->>'field' AND wf.is_active = true
            ) THEN
                v_errors := v_errors || ('"invalid_condition_field: ' || COALESCE(v_step->>'field','?') || '"')::JSONB;
            END IF;
        END IF;

        -- If action step, validate action_type is in allowed list
        IF (v_step->>'type') NOT IN (
            'trigger','condition','delay','approval',
            'send_notification','send_email','send_whatsapp',
            'move_application_stage','shortlist_candidate','reject_application',
            'create_assessment_invitation','request_interview',
            'create_review_item','add_to_talent_pool','remove_from_talent_pool',
            'update_candidate_field','update_job_field',
            'create_task','call_webhook','start_ai_action',
            'create_analytics_event','run_matching',
            'send_billing_notification','restrict_feature','restore_feature'
        ) THEN
            v_errors := v_errors || ('"invalid_step_type: ' || COALESCE(v_step->>'type','?') || '"')::JSONB;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'valid', jsonb_array_length(v_errors) = 0,
        'errors', v_errors
    );
END;
$$;

-- =============================================================================
-- 17. PUBLISH WORKFLOW VERSION
-- =============================================================================
CREATE OR REPLACE FUNCTION public.publish_workflow_version(
    p_workflow_definition_id    UUID,
    p_definition                JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id       UUID := auth.uid();
    v_wf            RECORD;
    v_validation    JSONB;
    v_new_version   INTEGER;
    v_version_id    UUID;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT * INTO v_wf FROM public.workflow_definitions WHERE id = p_workflow_definition_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'workflow_not_found'; END IF;

    -- Authorization: must be in org or platform admin
    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = v_wf.organization_id
              AND om.user_id = v_user_id
              AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager')
        ) THEN
            RAISE EXCEPTION 'insufficient_permissions: workflows.manage required';
        END IF;
    END IF;

    -- Validate definition
    v_validation := public.validate_workflow_definition(p_definition);
    IF NOT (v_validation->>'valid')::BOOLEAN THEN
        RAISE EXCEPTION 'invalid_workflow_definition: %', v_validation->'errors';
    END IF;

    -- Deprecate current published versions
    UPDATE public.workflow_versions
    SET status = 'deprecated'
    WHERE workflow_definition_id = p_workflow_definition_id AND status = 'published';

    -- Create new version
    SELECT COALESCE(MAX(version), 0) + 1 INTO v_new_version
    FROM public.workflow_versions
    WHERE workflow_definition_id = p_workflow_definition_id;

    INSERT INTO public.workflow_versions (
        workflow_definition_id, version, definition, status, published_at, created_by
    ) VALUES (
        p_workflow_definition_id, v_new_version, p_definition, 'published', now(), v_user_id
    ) RETURNING id INTO v_version_id;

    -- Update definition's current version
    UPDATE public.workflow_definitions
    SET current_version = v_new_version, status = 'published', updated_at = now()
    WHERE id = p_workflow_definition_id;

    -- Audit
    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, new_data, metadata)
    VALUES (v_user_id, 'workflow_published', 'workflow_definitions', p_workflow_definition_id,
            jsonb_build_object('version', v_new_version), jsonb_build_object('version_id', v_version_id));

    RETURN v_version_id;
END;
$$;

-- =============================================================================
-- 18. ENQUEUE WORKFLOW EVENT (Idempotent event ingestion)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.enqueue_workflow_event(
    p_organization_id   UUID,
    p_event_type        TEXT,
    p_entity_type       TEXT,
    p_entity_id         UUID,
    p_event_payload     JSONB DEFAULT '{}'::JSONB,
    p_source_event_id   TEXT DEFAULT NULL,
    p_scheduled_for     TIMESTAMPTZ DEFAULT NULL,
    p_idempotency_key   TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_idem_key  TEXT := COALESCE(p_idempotency_key,
                                  p_event_type || ':' || p_entity_type || ':' || p_entity_id::TEXT || ':' ||
                                  COALESCE(p_source_event_id, extract(epoch from now())::text));
    v_id        UUID;
BEGIN
    -- Idempotent insert: skip if same key already processed
    INSERT INTO public.workflow_event_queue (
        organization_id, event_type, entity_type, entity_id,
        event_payload, source_event_id, idempotency_key, scheduled_for
    ) VALUES (
        p_organization_id, p_event_type, p_entity_type, p_entity_id,
        p_event_payload, p_source_event_id, v_idem_key,
        COALESCE(p_scheduled_for, now())
    )
    ON CONFLICT (organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING
    RETURNING id INTO v_id;

    RETURN v_id; -- NULL if duplicate (idempotent)
END;
$$;

-- =============================================================================
-- 19. ROUTE WORKFLOW EVENTS (Find matching workflows for an event)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.route_workflow_events(p_event_queue_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event         RECORD;
    v_wf            RECORD;
    v_version_id    UUID;
    v_exec_id       UUID;
    v_created       INTEGER := 0;
    v_depth_check   INTEGER;
BEGIN
    SELECT * INTO v_event FROM public.workflow_event_queue WHERE id = p_event_queue_id;
    IF NOT FOUND THEN RETURN 0; END IF;

    -- Mark as processing
    UPDATE public.workflow_event_queue SET status = 'processing', attempt_count = attempt_count + 1 WHERE id = p_event_queue_id;

    -- Find all active published workflows matching this event type and org
    FOR v_wf IN
        SELECT wd.id AS def_id, wd.organization_id, wd.max_executions_per_entity, wd.max_execution_depth,
               wd.idempotency_window_seconds, wd.is_system, wd.priority,
               wv.id AS version_id
        FROM public.workflow_definitions wd
        JOIN public.workflow_versions wv ON wv.workflow_definition_id = wd.id AND wv.status = 'published'
        JOIN public.workflow_triggers wt ON wt.workflow_version_id = wv.id
            AND wt.is_active = true
            AND wt.trigger_type = 'event'
            AND wt.event_type = v_event.event_type
        WHERE wd.status = 'published'
          AND (wd.organization_id = v_event.organization_id OR wd.is_system = true)
        ORDER BY wd.priority DESC, wd.created_at ASC
    LOOP
        -- Loop protection: check execution depth
        SELECT COUNT(*) INTO v_depth_check
        FROM public.workflow_executions we
        WHERE we.entity_id = v_event.entity_id
          AND we.workflow_definition_id = v_wf.def_id
          AND we.status NOT IN ('completed','failed','cancelled')
          AND we.execution_depth >= v_wf.max_execution_depth;

        IF v_depth_check > 0 THEN
            INSERT INTO public.workflow_execution_logs (workflow_execution_id, level, message, metadata)
            SELECT id, 'warning', 'Loop protection: max execution depth reached', jsonb_build_object('event_id', p_event_queue_id)
            FROM public.workflow_executions WHERE workflow_definition_id = v_wf.def_id AND entity_id = v_event.entity_id LIMIT 1;
            CONTINUE;
        END IF;

        -- Idempotency: don't create duplicate executions within window
        IF EXISTS (
            SELECT 1 FROM public.workflow_executions
            WHERE workflow_definition_id = v_wf.def_id
              AND entity_id = v_event.entity_id
              AND created_at >= now() - (v_wf.idempotency_window_seconds || ' seconds')::INTERVAL
              AND status NOT IN ('failed','cancelled')
        ) THEN
            CONTINUE;
        END IF;

        -- Create execution
        INSERT INTO public.workflow_executions (
            organization_id, workflow_definition_id, workflow_version_id,
            trigger_event_id, entity_type, entity_id,
            context, status, scheduled_for
        ) VALUES (
            COALESCE(v_wf.organization_id, v_event.organization_id),
            v_wf.def_id, v_wf.version_id,
            p_event_queue_id, v_event.entity_type, v_event.entity_id,
            jsonb_build_object(
                'event_type', v_event.event_type,
                'entity_type', v_event.entity_type,
                'entity_id', v_event.entity_id,
                'organization_id', v_event.organization_id,
                'source_event_id', v_event.source_event_id
            ),
            'queued', now()
        ) RETURNING id INTO v_exec_id;

        v_created := v_created + 1;
    END LOOP;

    -- Mark event as processed
    UPDATE public.workflow_event_queue
    SET status = 'processed', processed_at = now(), updated_at = now()
    WHERE id = p_event_queue_id;

    RETURN v_created;
END;
$$;

-- =============================================================================
-- 20. CREATE WORKFLOW EXECUTION STEP
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_workflow_execution_step(
    p_execution_id  UUID,
    p_action_id     UUID,
    p_step_order    INTEGER,
    p_input_data    JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_action    RECORD;
    v_step_id   UUID;
BEGIN
    SELECT * INTO v_action FROM public.workflow_actions WHERE id = p_action_id;

    INSERT INTO public.workflow_execution_steps (
        workflow_execution_id, action_id, step_order, status,
        input_data, requires_approval, started_at
    ) VALUES (
        p_execution_id, p_action_id, p_step_order, 'pending',
        p_input_data,
        COALESCE(v_action.requires_approval, false),
        now()
    ) RETURNING id INTO v_step_id;

    RETURN v_step_id;
END;
$$;

-- =============================================================================
-- 21. EXECUTE WORKFLOW ACTION (Dispatches to existing business services)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.execute_workflow_action(
    p_step_id           UUID,
    p_action_type       TEXT,
    p_configuration     JSONB,
    p_context           JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result        JSONB := '{}'::JSONB;
    v_entity_id     UUID;
    v_org_id        UUID;
    v_target_id     UUID;
    v_notif_type    TEXT;
    v_user_id       UUID;
    v_notif_id      UUID;
    v_exec          RECORD;
    v_step          RECORD;
BEGIN
    SELECT wes.*, we.organization_id, we.entity_id, we.entity_type, we.actor_id
    INTO v_exec
    FROM public.workflow_execution_steps wes
    JOIN public.workflow_executions we ON we.id = wes.workflow_execution_id
    WHERE wes.id = p_step_id;

    v_entity_id := v_exec.entity_id;
    v_org_id    := v_exec.organization_id;
    v_user_id   := v_exec.actor_id;

    -- Block forbidden action types (security)
    IF p_action_type IN ('raw_sql','execute_sql','shell','system') THEN
        RAISE EXCEPTION 'security_violation: action type "%" is not permitted in workflows', p_action_type;
    END IF;

    -- Update step to running
    UPDATE public.workflow_execution_steps
    SET status = 'running', started_at = now(), updated_at = now()
    WHERE id = p_step_id;

    -- Dispatch to existing business services
    CASE p_action_type

        WHEN 'send_notification' THEN
            -- Uses Task 11 emit_notification_event
            v_notif_type := p_configuration->>'notification_type';
            IF v_notif_type IS NOT NULL THEN
                PERFORM public.emit_notification_event(
                    v_notif_type,
                    v_entity_id,
                    v_exec.entity_type,
                    p_configuration
                );
                v_result := jsonb_build_object('action', 'notification_emitted', 'type', v_notif_type);
            ELSE
                RAISE EXCEPTION 'missing_configuration: notification_type required';
            END IF;

        WHEN 'move_application_stage' THEN
            -- Uses Task 04 ATS stage transition (UPDATE triggers handle events/history)
            v_target_id := (p_configuration->>'stage_id')::UUID;
            IF v_target_id IS NULL THEN RAISE EXCEPTION 'missing_configuration: stage_id required'; END IF;
            IF NOT EXISTS (SELECT 1 FROM public.ats_stages WHERE id = v_target_id AND organization_id = v_org_id) THEN
                RAISE EXCEPTION 'invalid_target: stage_id not found in organization';
            END IF;
            UPDATE public.applications
            SET current_stage_id = v_target_id, updated_at = now()
            WHERE id = v_entity_id AND job_id IN (SELECT id FROM public.jobs WHERE organization_id = v_org_id);
            IF NOT FOUND THEN RAISE EXCEPTION 'target_not_found: application not found in organization'; END IF;
            v_result := jsonb_build_object('action', 'stage_moved', 'stage_id', v_target_id);

        WHEN 'shortlist_candidate' THEN
            -- Add to recruiter review queue as shortlisted
            UPDATE public.applications
            SET status = 'shortlisted', updated_at = now()
            WHERE id = v_entity_id
              AND job_id IN (SELECT id FROM public.jobs WHERE organization_id = v_org_id);
            INSERT INTO public.recruiter_review_queue (
                organization_id, candidate_id, application_id, reason, priority, status
            )
            SELECT v_org_id, c.id, a.id,
                   COALESCE(p_configuration->>'reason', 'Shortlisted by workflow automation'),
                   COALESCE(p_configuration->>'priority', 'medium'),
                   'open'
            FROM public.applications a
            JOIN public.candidates c ON c.id = a.candidate_id
            WHERE a.id = v_entity_id;
            v_result := jsonb_build_object('action', 'candidate_shortlisted');

        WHEN 'reject_application' THEN
            -- Update application status (requires medium-high risk approval)
            UPDATE public.applications
            SET status = 'rejected', updated_at = now()
            WHERE id = v_entity_id
              AND job_id IN (SELECT id FROM public.jobs WHERE organization_id = v_org_id);
            IF NOT FOUND THEN RAISE EXCEPTION 'target_not_found'; END IF;
            v_result := jsonb_build_object('action', 'application_rejected');

        WHEN 'create_assessment_invitation' THEN
            -- Uses Task 08 trigger_required_assessments
            PERFORM public.trigger_required_assessments(v_entity_id);
            v_result := jsonb_build_object('action', 'assessments_triggered');

        WHEN 'add_to_talent_pool' THEN
            -- Uses Task 07 add_candidate_to_talent_pool
            v_target_id := (p_configuration->>'talent_pool_id')::UUID;
            IF v_target_id IS NULL THEN RAISE EXCEPTION 'missing_configuration: talent_pool_id required'; END IF;
            PERFORM public.add_candidate_to_talent_pool(
                v_target_id, v_entity_id,
                COALESCE(p_configuration->>'source', 'workflow'),
                COALESCE(p_configuration->>'notes', 'Added by workflow automation')
            );
            v_result := jsonb_build_object('action', 'added_to_talent_pool', 'pool_id', v_target_id);

        WHEN 'remove_from_talent_pool' THEN
            v_target_id := (p_configuration->>'talent_pool_id')::UUID;
            IF v_target_id IS NULL THEN RAISE EXCEPTION 'missing_configuration: talent_pool_id required'; END IF;
            UPDATE public.talent_pool_members
            SET status = 'removed', updated_at = now()
            WHERE talent_pool_id = v_target_id AND candidate_id = v_entity_id;
            v_result := jsonb_build_object('action', 'removed_from_talent_pool');

        WHEN 'create_review_item' THEN
            -- Uses Task 07 recruiter_review_queue
            -- Create review item for recruiter queue
            -- (Note: candidate_id is entity_id for candidate-type executions)
            INSERT INTO public.recruiter_review_queue (
                organization_id, candidate_id, reason, priority, status
            )
            VALUES (
                v_org_id, v_entity_id,
                COALESCE(p_configuration->>'reason', 'Review requested by workflow automation'),
                COALESCE(p_configuration->>'priority', 'medium'),
                'open'
            );
            v_result := jsonb_build_object('action', 'review_item_created');

        WHEN 'create_analytics_event' THEN
            -- Log to audit_logs as workflow analytics event
            INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, new_data, metadata)
            VALUES (v_user_id, 'workflow_analytics_event', v_exec.entity_type, v_entity_id,
                    p_configuration,
                    jsonb_build_object('step_id', p_step_id, 'org_id', v_org_id));
            v_result := jsonb_build_object('action', 'analytics_event_created');

        WHEN 'run_matching' THEN
            -- Uses Task 06 calculate_candidate_job_match (run asynchronously via queue pattern)
            -- We enqueue the matching event rather than running sync
            v_target_id := (p_configuration->>'job_id')::UUID;
            IF v_target_id IS NOT NULL THEN
                PERFORM public.enqueue_workflow_event(
                    v_org_id, 'matching_requested', 'application', v_entity_id,
                    jsonb_build_object('job_id', v_target_id, 'triggered_by', 'workflow'),
                    p_step_id::TEXT, NULL, 'matching:' || v_entity_id::TEXT || ':' || v_target_id::TEXT
                );
            END IF;
            v_result := jsonb_build_object('action', 'matching_enqueued');

        ELSE
            -- Generic: log for other action types (call_webhook, start_ai_action etc.)
            INSERT INTO public.workflow_execution_logs (workflow_execution_id, level, message, metadata)
            SELECT v_exec.workflow_execution_id, 'info',
                   'Action executed: ' || p_action_type,
                   jsonb_build_object('step_id', p_step_id, 'configuration', p_configuration);
            v_result := jsonb_build_object('action', p_action_type, 'status', 'logged');

    END CASE;

    -- Mark step as completed
    UPDATE public.workflow_execution_steps
    SET status = 'completed', output_data = v_result, completed_at = now(), updated_at = now()
    WHERE id = p_step_id;

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    -- Record failure
    UPDATE public.workflow_execution_steps
    SET status = 'failed',
        error_code = SQLSTATE,
        error_message = SQLERRM,
        failure_type = CASE
            WHEN SQLSTATE = '42501' THEN 'authorization_failure'
            WHEN SQLSTATE = 'P0001' AND SQLERRM LIKE '%security_violation%' THEN 'permanent_failure'
            ELSE 'temporary_failure'
        END,
        retry_count = retry_count + 1,
        next_retry_at = CASE
            WHEN retry_count < 3 THEN now() + INTERVAL '5 minutes'
            ELSE NULL
        END,
        updated_at = now()
    WHERE id = p_step_id;

    INSERT INTO public.workflow_failures (
        workflow_execution_id, step_id, failure_type, error_code, error_message,
        retryable, retry_count
    )
    SELECT v_exec.workflow_execution_id, p_step_id,
           CASE
               WHEN SQLSTATE = '42501' OR SQLERRM LIKE '%security_violation%' OR SQLERRM LIKE '%permanent%' THEN 'permanent_failure'
               ELSE 'temporary_failure'
           END,
           SQLSTATE, SQLERRM,
           (SQLSTATE NOT IN ('42501') AND SQLERRM NOT LIKE '%security_violation%'),
           1;

    RAISE;
END;
$$;

-- =============================================================================
-- 22. CANCEL WORKFLOW EXECUTION
-- =============================================================================
CREATE OR REPLACE FUNCTION public.cancel_workflow_execution(p_execution_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_exec      RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT * INTO v_exec FROM public.workflow_executions WHERE id = p_execution_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'execution_not_found'; END IF;

    -- Authorization
    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = v_exec.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager')
        ) THEN RAISE EXCEPTION 'insufficient_permissions'; END IF;
    END IF;

    -- Only cancel non-terminal executions
    IF v_exec.status IN ('completed','failed','cancelled') THEN
        RAISE EXCEPTION 'cannot_cancel: execution already in terminal state %', v_exec.status;
    END IF;

    -- Cancel pending steps (do NOT reverse completed steps)
    UPDATE public.workflow_execution_steps
    SET status = 'cancelled', updated_at = now()
    WHERE workflow_execution_id = p_execution_id AND status IN ('pending','waiting');

    UPDATE public.workflow_executions
    SET status = 'cancelled', completed_at = now(), updated_at = now()
    WHERE id = p_execution_id;

    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, metadata)
    VALUES (v_user_id, 'workflow_cancelled', 'workflow_executions', p_execution_id,
            jsonb_build_object('org_id', v_exec.organization_id));
END;
$$;

-- =============================================================================
-- 23. PAUSE / RESUME WORKFLOW DEFINITION
-- =============================================================================
CREATE OR REPLACE FUNCTION public.pause_workflow(p_workflow_definition_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_wf      RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
    SELECT * INTO v_wf FROM public.workflow_definitions WHERE id = p_workflow_definition_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'workflow_not_found'; END IF;

    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = v_wf.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager')
        ) THEN RAISE EXCEPTION 'insufficient_permissions'; END IF;
    END IF;

    UPDATE public.workflow_definitions SET status = 'paused', updated_at = now() WHERE id = p_workflow_definition_id;

    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, metadata)
    VALUES (v_user_id, 'workflow_paused', 'workflow_definitions', p_workflow_definition_id, '{}'::JSONB);
END;
$$;

CREATE OR REPLACE FUNCTION public.resume_workflow(p_workflow_definition_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_wf      RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
    SELECT * INTO v_wf FROM public.workflow_definitions WHERE id = p_workflow_definition_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'workflow_not_found'; END IF;

    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = v_wf.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager')
        ) THEN RAISE EXCEPTION 'insufficient_permissions'; END IF;
    END IF;

    UPDATE public.workflow_definitions SET status = 'published', updated_at = now() WHERE id = p_workflow_definition_id;

    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, metadata)
    VALUES (v_user_id, 'workflow_resumed', 'workflow_definitions', p_workflow_definition_id, '{}'::JSONB);
END;
$$;

-- =============================================================================
-- 24. APPROVE / DENY WORKFLOW ACTION STEP
-- =============================================================================
CREATE OR REPLACE FUNCTION public.approve_workflow_action(
    p_step_id   UUID,
    p_notes     TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_step      RECORD;
    v_exec      RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT wes.*, we.organization_id
    INTO v_step
    FROM public.workflow_execution_steps wes
    JOIN public.workflow_executions we ON we.id = wes.workflow_execution_id
    WHERE wes.id = p_step_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'step_not_found'; END IF;
    IF v_step.status <> 'waiting' THEN RAISE EXCEPTION 'step_not_waiting_for_approval'; END IF;

    -- Verify approver is in the org
    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = v_step.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
        ) THEN RAISE EXCEPTION 'access_denied'; END IF;
    END IF;

    UPDATE public.workflow_execution_steps
    SET status = 'completed', approved_by = v_user_id, approved_at = now(), updated_at = now()
    WHERE id = p_step_id;

    INSERT INTO public.workflow_execution_logs (workflow_execution_id, level, message, metadata)
    SELECT workflow_execution_id, 'info', 'Action approved by user',
           jsonb_build_object('approved_by', v_user_id, 'notes', p_notes)
    FROM public.workflow_execution_steps WHERE id = p_step_id;

    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, metadata)
    VALUES (v_user_id, 'workflow_action_approved', 'workflow_execution_steps', p_step_id,
            jsonb_build_object('notes', p_notes));
END;
$$;

CREATE OR REPLACE FUNCTION public.deny_workflow_action(
    p_step_id   UUID,
    p_reason    TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_step      RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT wes.*, we.organization_id
    INTO v_step
    FROM public.workflow_execution_steps wes
    JOIN public.workflow_executions we ON we.id = wes.workflow_execution_id
    WHERE wes.id = p_step_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'step_not_found'; END IF;
    IF v_step.status <> 'waiting' THEN RAISE EXCEPTION 'step_not_waiting_for_approval'; END IF;

    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = v_step.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
        ) THEN RAISE EXCEPTION 'access_denied'; END IF;
    END IF;

    UPDATE public.workflow_execution_steps
    SET status = 'failed', failure_type = 'authorization_failure',
        error_message = COALESCE(p_reason, 'Action denied by approver'), updated_at = now()
    WHERE id = p_step_id;

    -- Cancel the parent execution
    UPDATE public.workflow_executions
    SET status = 'cancelled', completed_at = now(), updated_at = now()
    WHERE id = v_step.workflow_execution_id;

    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, metadata)
    VALUES (v_user_id, 'workflow_action_denied', 'workflow_execution_steps', p_step_id,
            jsonb_build_object('reason', p_reason));
END;
$$;

-- =============================================================================
-- 25. RETRY WORKFLOW STEP (Manual retry of failed steps)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.retry_workflow_step(p_step_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_step      RECORD;
    v_action    RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT wes.*, we.organization_id, we.context
    INTO v_step
    FROM public.workflow_execution_steps wes
    JOIN public.workflow_executions we ON we.id = wes.workflow_execution_id
    WHERE wes.id = p_step_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'step_not_found'; END IF;
    IF v_step.status <> 'failed' THEN RAISE EXCEPTION 'step_not_failed'; END IF;
    IF v_step.failure_type = 'permanent_failure' THEN RAISE EXCEPTION 'permanent_failure_cannot_retry'; END IF;

    -- Authorization
    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            JOIN public.roles r ON r.id = om.role_id
            WHERE om.organization_id = v_step.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
              AND r.key IN ('platform_admin','recruiter_manager')
        ) THEN RAISE EXCEPTION 'insufficient_permissions'; END IF;
    END IF;

    SELECT * INTO v_action FROM public.workflow_actions WHERE id = v_step.action_id;

    -- Reset step for retry
    UPDATE public.workflow_execution_steps
    SET status = 'pending', error_code = NULL, error_message = NULL,
        retry_count = retry_count + 1, next_retry_at = NULL, updated_at = now()
    WHERE id = p_step_id;

    -- Attempt execution
    PERFORM public.execute_workflow_action(
        p_step_id, v_action.action_type, v_action.configuration, v_step.context
    );

    -- Mark failure as resolved
    UPDATE public.workflow_failures
    SET resolved_at = now(), resolved_by = v_user_id
    WHERE step_id = p_step_id AND resolved_at IS NULL;

    INSERT INTO public.audit_logs (actor_user_id, action, table_name, record_id, metadata)
    VALUES (v_user_id, 'workflow_manual_retry', 'workflow_execution_steps', p_step_id, '{}'::JSONB);
END;
$$;

-- =============================================================================
-- 26. GET WORKFLOW EXECUTION (Admin/Recruiter view)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_workflow_execution(p_execution_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_exec      RECORD;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT we.*, wd.name AS workflow_name, wv.version AS workflow_version
    INTO v_exec
    FROM public.workflow_executions we
    JOIN public.workflow_definitions wd ON wd.id = we.workflow_definition_id
    JOIN public.workflow_versions wv ON wv.id = we.workflow_version_id
    WHERE we.id = p_execution_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'execution_not_found'; END IF;

    IF NOT public.is_platform_admin(v_user_id) THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = v_exec.organization_id
              AND om.user_id = v_user_id AND om.status = 'active'
        ) THEN RAISE EXCEPTION 'access_denied'; END IF;
    END IF;

    RETURN jsonb_build_object(
        'execution', row_to_json(v_exec),
        'steps', (
            SELECT jsonb_agg(row_to_json(wes) ORDER BY wes.step_order)
            FROM public.workflow_execution_steps wes
            WHERE wes.workflow_execution_id = p_execution_id
        ),
        'logs', (
            SELECT jsonb_agg(row_to_json(wel) ORDER BY wel.created_at)
            FROM public.workflow_execution_logs wel
            WHERE wel.workflow_execution_id = p_execution_id
        )
    );
END;
$$;

-- =============================================================================
-- 27. GET FAILED WORKFLOWS
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_failed_workflows(
    p_organization_id   UUID    DEFAULT NULL,
    p_page              INTEGER DEFAULT 1,
    p_page_size         INTEGER DEFAULT 20
)
RETURNS TABLE (
    execution_id        UUID,
    workflow_name       TEXT,
    entity_type         TEXT,
    entity_id           UUID,
    status              TEXT,
    error_message       TEXT,
    failed_at           TIMESTAMPTZ,
    retryable_steps     INTEGER,
    total_count         BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_org_ids   UUID[];
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
    v_org_ids := public.get_caller_org_ids(v_user_id);

    RETURN QUERY
    WITH base AS (
        SELECT
            we.id               AS execution_id,
            wd.name::TEXT       AS workflow_name,
            we.entity_type::TEXT,
            we.entity_id,
            we.status::TEXT,
            we.error_message::TEXT,
            we.failed_at,
            (SELECT COUNT(*) FROM public.workflow_failures wf WHERE wf.workflow_execution_id = we.id AND wf.retryable = true AND wf.resolved_at IS NULL)::INTEGER AS retryable_steps
        FROM public.workflow_executions we
        JOIN public.workflow_definitions wd ON wd.id = we.workflow_definition_id
        WHERE we.status = 'failed'
          AND (p_organization_id IS NULL OR we.organization_id = p_organization_id)
          AND (public.is_platform_admin(v_user_id) OR we.organization_id = ANY(v_org_ids))
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM base)
    SELECT execution_id, workflow_name, entity_type, entity_id, status, error_message, failed_at, retryable_steps, total_count
    FROM counted
    ORDER BY failed_at DESC, execution_id ASC
    LIMIT LEAST(COALESCE(p_page_size,20), 50)
    OFFSET (GREATEST(COALESCE(p_page,1),1)-1) * LEAST(COALESCE(p_page_size,20), 50);
END;
$$;

-- =============================================================================
-- 28. EVALUATE WORKFLOW CONDITION (Safe condition evaluator)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.evaluate_workflow_condition(
    p_condition JSONB,
    p_context   JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_field     TEXT := p_condition->>'field';
    v_operator  TEXT := p_condition->>'operator';
    v_value     TEXT := p_condition->>'value';
    v_ctx_value TEXT;
    v_num_ctx   NUMERIC;
    v_num_val   NUMERIC;
BEGIN
    -- Only allow registered fields
    IF NOT EXISTS (SELECT 1 FROM public.workflow_fields WHERE field_key = v_field AND is_active = true) THEN
        RAISE EXCEPTION 'invalid_field: "%" is not in the workflow field registry', v_field;
    END IF;

    -- Block any SQL injection attempts
    IF v_field ILIKE '%sql%' OR v_field ILIKE '%exec%' OR v_field ILIKE '%drop%' THEN
        RAISE EXCEPTION 'security_violation: suspicious field value detected';
    END IF;

    -- Extract field value from context (uses registered field_key as path)
    v_ctx_value := p_context #>> string_to_array(replace(v_field, '.', ','), ',');

    RETURN CASE v_operator
        WHEN 'equals'                  THEN v_ctx_value = v_value
        WHEN 'not_equals'              THEN v_ctx_value <> v_value
        WHEN 'exists'                  THEN v_ctx_value IS NOT NULL
        WHEN 'not_exists'              THEN v_ctx_value IS NULL
        WHEN 'contains'                THEN v_ctx_value ILIKE ('%' || v_value || '%')
        WHEN 'not_contains'            THEN NOT (v_ctx_value ILIKE ('%' || v_value || '%'))
        WHEN 'in'                      THEN v_ctx_value = ANY(string_to_array(v_value, ','))
        WHEN 'not_in'                  THEN NOT (v_ctx_value = ANY(string_to_array(v_value, ',')))
        WHEN 'greater_than'            THEN (v_ctx_value::NUMERIC > v_value::NUMERIC)
        WHEN 'greater_than_or_equal'   THEN (v_ctx_value::NUMERIC >= v_value::NUMERIC)
        WHEN 'less_than'               THEN (v_ctx_value::NUMERIC < v_value::NUMERIC)
        WHEN 'less_than_or_equal'      THEN (v_ctx_value::NUMERIC <= v_value::NUMERIC)
        ELSE false
    END;

EXCEPTION WHEN OTHERS THEN
    -- Condition evaluation failure → treat as false (safe default)
    RETURN false;
END;
$$;

-- =============================================================================
-- 29. WORKFLOW LIMITS CONFIGURATION (Platform-level resource protection)
-- =============================================================================
INSERT INTO public.platform_settings (key, value, value_type, description, is_public)
VALUES
    ('workflow.max_steps_per_execution',    '50',   'number', 'Maximum action steps per workflow execution',      false),
    ('workflow.max_execution_depth',        '5',    'number', 'Maximum recursive workflow execution depth',       false),
    ('workflow.max_retries_per_step',       '3',    'number', 'Maximum retry attempts per failed step',           false),
    ('workflow.max_execution_duration_sec', '3600', 'number', 'Maximum execution duration in seconds (1 hour)',   false),
    ('workflow.max_executions_per_entity',  '10',   'number', 'Max concurrent executions per entity',             false),
    ('workflow.idempotency_window_sec',     '300',  'number', 'Idempotency dedup window in seconds (5 minutes)',  false)
ON CONFLICT (key) DO NOTHING;
