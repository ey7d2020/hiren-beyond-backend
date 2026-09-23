-- =============================================================================
-- Migration: 20260915000500_applications_ats_pipeline.sql
-- Description: Applications, ATS Pipeline, Candidate Application Tracking & Status
-- Author: Hiren Beyond Engineering
-- Schema: ats_stages, applications, application_events, application_notes,
--         application_screening_answers, application_stage_history,
--         recruiter_application_views
-- =============================================================================

-- =============================================================================
-- 1. EXTEND PERMISSIONS CATALOG
-- =============================================================================

INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('applications.view_all',      'View All Applications',      'View all applications across the organization', 'applications'),
    ('applications.view_assigned', 'View Assigned Applications', 'View applications assigned to the recruiter', 'applications'),
    ('applications.review',        'Review Applications',        'Change application status and stage within the ATS pipeline', 'applications'),
    ('applications.shortlist',     'Shortlist Candidates',       'Mark candidates as shortlisted or move to interview stage', 'applications'),
    ('applications.reject',        'Reject Applications',        'Reject or archive candidate applications', 'applications'),
    ('applications.make_offer',    'Make Offer',                 'Create and send offer letters to candidates', 'applications'),
    ('applications.add_notes',     'Add Recruiter Notes',        'Add private recruiter notes to applications', 'applications'),
    ('applications.export',        'Export Applications',        'Export application data and reports', 'applications'),
    ('ats.manage_stages',          'Manage ATS Stages',          'Create, edit, sort, and delete ATS pipeline stages', 'ats'),
    ('ats.view_pipeline',          'View ATS Pipeline',          'View the ATS pipeline board and stage metrics', 'ats')
ON CONFLICT (key) DO UPDATE
SET name        = EXCLUDED.name,
    description = EXCLUDED.description,
    category    = EXCLUDED.category;

WITH new_mappings (role_key, perm_key) AS (
    VALUES
        ('platform_admin', 'applications.view_all'),
        ('platform_admin', 'applications.view_assigned'),
        ('platform_admin', 'applications.review'),
        ('platform_admin', 'applications.shortlist'),
        ('platform_admin', 'applications.reject'),
        ('platform_admin', 'applications.make_offer'),
        ('platform_admin', 'applications.add_notes'),
        ('platform_admin', 'applications.export'),
        ('platform_admin', 'ats.manage_stages'),
        ('platform_admin', 'ats.view_pipeline'),
        ('platform_operations', 'applications.view_all'),
        ('platform_operations', 'applications.review'),
        ('platform_operations', 'applications.export'),
        ('platform_operations', 'ats.view_pipeline'),
        ('recruiter_manager', 'applications.view_all'),
        ('recruiter_manager', 'applications.review'),
        ('recruiter_manager', 'applications.shortlist'),
        ('recruiter_manager', 'applications.reject'),
        ('recruiter_manager', 'applications.make_offer'),
        ('recruiter_manager', 'applications.add_notes'),
        ('recruiter_manager', 'applications.export'),
        ('recruiter_manager', 'ats.manage_stages'),
        ('recruiter_manager', 'ats.view_pipeline'),
        ('recruiter', 'applications.view_assigned'),
        ('recruiter', 'applications.review'),
        ('recruiter', 'applications.shortlist'),
        ('recruiter', 'applications.reject'),
        ('recruiter', 'applications.add_notes'),
        ('recruiter', 'ats.view_pipeline'),
        ('client_admin', 'applications.view_all'),
        ('client_admin', 'applications.review'),
        ('client_admin', 'applications.shortlist'),
        ('client_admin', 'applications.add_notes'),
        ('client_admin', 'ats.view_pipeline'),
        ('candidate', 'applications.view_assigned')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM new_mappings m
JOIN public.roles r ON r.key = m.role_key
JOIN public.permissions p ON p.key = m.perm_key
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =============================================================================
-- 2. ATS_STAGES
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ats_stages (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    slug            TEXT        NOT NULL,
    description     TEXT,
    stage_type      TEXT        NOT NULL DEFAULT 'custom'
        CHECK (stage_type IN (
            'applied','screening','assessment','interview',
            'shortlisted','offer','hired','rejected',
            'withdrawn','on_hold','custom'
        )),
    color           VARCHAR(10) DEFAULT '#6366f1',
    icon            TEXT,
    sort_order      INTEGER     NOT NULL DEFAULT 0,
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    is_default      BOOLEAN     NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_ats_stage_org_slug UNIQUE (organization_id, slug),
    CONSTRAINT chk_ats_stage_name_length CHECK (char_length(name) BETWEEN 1 AND 100)
);

CREATE INDEX IF NOT EXISTS idx_ats_stages_org     ON public.ats_stages(organization_id);
CREATE INDEX IF NOT EXISTS idx_ats_stages_type    ON public.ats_stages(stage_type);
CREATE INDEX IF NOT EXISTS idx_ats_stages_sort    ON public.ats_stages(organization_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_ats_stages_active  ON public.ats_stages(is_active);
CREATE INDEX IF NOT EXISTS idx_ats_stages_default ON public.ats_stages(organization_id, is_default);

CREATE TRIGGER trg_ats_stages_updated_at
    BEFORE UPDATE ON public.ats_stages
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 3. APPLICATIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.applications (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id                  UUID        NOT NULL REFERENCES public.jobs(id) ON DELETE RESTRICT,
    candidate_id            UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE RESTRICT,
    organization_id         UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    current_stage_id        UUID        REFERENCES public.ats_stages(id) ON DELETE SET NULL,
    assigned_recruiter_id   UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    status                  TEXT        NOT NULL DEFAULT 'submitted'
        CHECK (status IN (
            'submitted','under_review','screening','assessment',
            'interview','shortlisted','offer_pending','offer_sent',
            'offer_accepted','offer_declined','hired',
            'rejected','withdrawn','on_hold','archived'
        )),
    source                  TEXT        NOT NULL DEFAULT 'platform'
        CHECK (source IN ('platform','referral','partner','recruiter','import','api')),
    source_reference        TEXT,
    resume_snapshot         JSONB,
    resume_document_id      UUID        REFERENCES public.candidate_documents(id) ON DELETE SET NULL,
    cover_letter            TEXT,
    match_score             NUMERIC(5,2) CHECK (match_score IS NULL OR (match_score >= 0 AND match_score <= 100)),
    match_score_breakdown   JSONB,
    match_score_computed_at TIMESTAMPTZ,
    ai_recommendation       TEXT
        CHECK (ai_recommendation IS NULL OR ai_recommendation IN (
            'strong_match','good_match','partial_match','weak_match','no_match'
        )),
    is_eligible             BOOLEAN,
    ineligibility_reasons   TEXT[],
    screening_completed_at  TIMESTAMPTZ,
    is_flagged              BOOLEAN     NOT NULL DEFAULT false,
    flag_reason             TEXT,
    submitted_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at             TIMESTAMPTZ,
    shortlisted_at          TIMESTAMPTZ,
    rejected_at             TIMESTAMPTZ,
    withdrawn_at            TIMESTAMPTZ,
    hired_at                TIMESTAMPTZ,
    rejection_reason        TEXT,
    rejection_category      TEXT
        CHECK (rejection_category IS NULL OR rejection_category IN (
            'underqualified','overqualified','location_mismatch','salary_mismatch',
            'culture_fit','duplicate','position_filled','candidate_unresponsive','other'
        )),
    withdrawal_reason       TEXT,
    internal_tags           TEXT[]      NOT NULL DEFAULT ARRAY[]::TEXT[],
    metadata                JSONB       NOT NULL DEFAULT '{}'::JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_applications_candidate_job UNIQUE (candidate_id, job_id),
    CONSTRAINT chk_application_hired_requires_time
        CHECK (status != 'hired' OR hired_at IS NOT NULL),
    CONSTRAINT chk_application_rejected_needs_category
        CHECK (status != 'rejected' OR rejection_category IS NOT NULL),
    CONSTRAINT chk_application_withdrawn_needs_time
        CHECK (status != 'withdrawn' OR withdrawn_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_applications_job         ON public.applications(job_id);
CREATE INDEX IF NOT EXISTS idx_applications_candidate   ON public.applications(candidate_id);
CREATE INDEX IF NOT EXISTS idx_applications_org         ON public.applications(organization_id);
CREATE INDEX IF NOT EXISTS idx_applications_status      ON public.applications(status);
CREATE INDEX IF NOT EXISTS idx_applications_stage       ON public.applications(current_stage_id);
CREATE INDEX IF NOT EXISTS idx_applications_recruiter   ON public.applications(assigned_recruiter_id);
CREATE INDEX IF NOT EXISTS idx_applications_submitted   ON public.applications(submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_applications_activity    ON public.applications(last_activity_at DESC);
CREATE INDEX IF NOT EXISTS idx_applications_match_score ON public.applications(match_score DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_applications_source      ON public.applications(source);
CREATE INDEX IF NOT EXISTS idx_applications_eligible    ON public.applications(is_eligible);
CREATE INDEX IF NOT EXISTS idx_applications_flagged     ON public.applications(is_flagged);
CREATE INDEX IF NOT EXISTS idx_applications_tags        ON public.applications USING GIN(internal_tags);
CREATE INDEX IF NOT EXISTS idx_applications_metadata    ON public.applications USING GIN(metadata);
CREATE INDEX IF NOT EXISTS idx_applications_org_status  ON public.applications(organization_id, status);
CREATE INDEX IF NOT EXISTS idx_applications_job_status  ON public.applications(job_id, status);

CREATE TRIGGER trg_applications_updated_at
    BEFORE UPDATE ON public.applications
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 4. APPLICATION_EVENTS (immutable audit trail)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.application_events (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  UUID        NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    actor_id        UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    event_type      TEXT        NOT NULL
        CHECK (event_type IN (
            'submitted','status_changed','stage_moved',
            'recruiter_assigned','recruiter_unassigned',
            'flag_set','flag_cleared','note_added','note_deleted',
            'screening_completed','match_score_updated',
            'offer_created','offer_sent','offer_accepted','offer_declined',
            'hired','rejected','withdrawn','archived','restored',
            'tag_added','tag_removed','document_attached','document_removed','system_action'
        )),
    from_status     TEXT,
    to_status       TEXT,
    from_stage_id   UUID        REFERENCES public.ats_stages(id) ON DELETE SET NULL,
    to_stage_id     UUID        REFERENCES public.ats_stages(id) ON DELETE SET NULL,
    payload         JSONB       NOT NULL DEFAULT '{}'::JSONB,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_app_events_application ON public.application_events(application_id);
CREATE INDEX IF NOT EXISTS idx_app_events_actor       ON public.application_events(actor_id);
CREATE INDEX IF NOT EXISTS idx_app_events_type        ON public.application_events(event_type);
CREATE INDEX IF NOT EXISTS idx_app_events_created     ON public.application_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_events_app_time    ON public.application_events(application_id, created_at DESC);

-- =============================================================================
-- 5. APPLICATION_STAGE_HISTORY
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.application_stage_history (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  UUID        NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    stage_id        UUID        NOT NULL REFERENCES public.ats_stages(id) ON DELETE RESTRICT,
    moved_by        UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
    entered_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    exited_at       TIMESTAMPTZ,
    duration_hours  NUMERIC(10,2),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stage_history_application ON public.application_stage_history(application_id);
CREATE INDEX IF NOT EXISTS idx_stage_history_stage       ON public.application_stage_history(stage_id);
CREATE INDEX IF NOT EXISTS idx_stage_history_entered     ON public.application_stage_history(entered_at DESC);
CREATE INDEX IF NOT EXISTS idx_stage_history_open        ON public.application_stage_history(application_id) WHERE exited_at IS NULL;

-- =============================================================================
-- 6. APPLICATION_NOTES
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.application_notes (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  UUID        NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    author_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    content         TEXT        NOT NULL,
    is_private      BOOLEAN     NOT NULL DEFAULT true,
    is_pinned       BOOLEAN     NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_note_content_not_empty CHECK (char_length(trim(content)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_app_notes_application ON public.application_notes(application_id);
CREATE INDEX IF NOT EXISTS idx_app_notes_author      ON public.application_notes(author_id);
CREATE INDEX IF NOT EXISTS idx_app_notes_pinned      ON public.application_notes(application_id, is_pinned);
CREATE INDEX IF NOT EXISTS idx_app_notes_created     ON public.application_notes(created_at DESC);

CREATE TRIGGER trg_application_notes_updated_at
    BEFORE UPDATE ON public.application_notes
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 7. APPLICATION_SCREENING_ANSWERS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.application_screening_answers (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id   UUID        NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    question_id      UUID        NOT NULL REFERENCES public.job_questions(id) ON DELETE RESTRICT,
    answer_text      TEXT,
    answer_boolean   BOOLEAN,
    answer_number    NUMERIC,
    answer_options   TEXT[],
    is_disqualifying BOOLEAN     NOT NULL DEFAULT false,
    screened_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_screening_answer UNIQUE (application_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_screening_answers_app      ON public.application_screening_answers(application_id);
CREATE INDEX IF NOT EXISTS idx_screening_answers_question ON public.application_screening_answers(question_id);

CREATE TRIGGER trg_screening_answers_updated_at
    BEFORE UPDATE ON public.application_screening_answers
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 8. RECRUITER_APPLICATION_VIEWS
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.recruiter_application_views (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  UUID        NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    viewer_id       UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    viewed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_recruiter_view UNIQUE (application_id, viewer_id)
);

CREATE INDEX IF NOT EXISTS idx_recruiter_views_app    ON public.recruiter_application_views(application_id);
CREATE INDEX IF NOT EXISTS idx_recruiter_views_viewer ON public.recruiter_application_views(viewer_id);
CREATE INDEX IF NOT EXISTS idx_recruiter_views_time   ON public.recruiter_application_views(viewed_at DESC);

-- =============================================================================
-- 9. TRIGGER FUNCTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sync_application_activity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    NEW.last_activity_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_application_activity
    BEFORE UPDATE ON public.applications
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status
       OR OLD.current_stage_id IS DISTINCT FROM NEW.current_stage_id
       OR OLD.assigned_recruiter_id IS DISTINCT FROM NEW.assigned_recruiter_id)
    EXECUTE FUNCTION public.sync_application_activity();

CREATE OR REPLACE FUNCTION public.sync_application_timestamps()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        CASE NEW.status
            WHEN 'under_review' THEN NEW.reviewed_at    := COALESCE(OLD.reviewed_at, now());
            WHEN 'shortlisted'  THEN NEW.shortlisted_at := COALESCE(OLD.shortlisted_at, now());
            WHEN 'rejected'     THEN NEW.rejected_at    := COALESCE(OLD.rejected_at, now());
            WHEN 'withdrawn'    THEN NEW.withdrawn_at   := COALESCE(OLD.withdrawn_at, now());
            WHEN 'hired'        THEN NEW.hired_at       := COALESCE(OLD.hired_at, now());
            ELSE NULL;
        END CASE;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_application_timestamps
    BEFORE UPDATE ON public.applications
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.sync_application_timestamps();

CREATE OR REPLACE FUNCTION public.log_application_status_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.application_events (
            application_id, actor_id, event_type, from_status, to_status, payload
        ) VALUES (
            NEW.id, auth.uid(), 'status_changed', OLD.status, NEW.status,
            jsonb_build_object('previous_status', OLD.status, 'new_status', NEW.status)
        );
    END IF;

    IF OLD.current_stage_id IS DISTINCT FROM NEW.current_stage_id THEN
        INSERT INTO public.application_events (
            application_id, actor_id, event_type, from_stage_id, to_stage_id, payload
        ) VALUES (
            NEW.id, auth.uid(), 'stage_moved', OLD.current_stage_id, NEW.current_stage_id,
            jsonb_build_object('from_stage_id', OLD.current_stage_id, 'to_stage_id', NEW.current_stage_id)
        );

        UPDATE public.application_stage_history
        SET exited_at      = now(),
            duration_hours = EXTRACT(EPOCH FROM (now() - entered_at)) / 3600
        WHERE application_id = NEW.id
          AND exited_at IS NULL
          AND stage_id = OLD.current_stage_id;

        IF NEW.current_stage_id IS NOT NULL THEN
            INSERT INTO public.application_stage_history (application_id, stage_id, moved_by, entered_at)
            VALUES (NEW.id, NEW.current_stage_id, auth.uid(), now());
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_application_changes
    AFTER UPDATE ON public.applications
    FOR EACH ROW EXECUTE FUNCTION public.log_application_status_change();

CREATE OR REPLACE FUNCTION public.log_application_submitted()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO public.application_events (
        application_id, actor_id, event_type, to_status, payload
    ) VALUES (
        NEW.id, auth.uid(), 'submitted', NEW.status,
        jsonb_build_object('job_id', NEW.job_id, 'source', NEW.source, 'submitted_at', NEW.submitted_at)
    );

    IF NEW.current_stage_id IS NOT NULL THEN
        INSERT INTO public.application_stage_history (application_id, stage_id, moved_by, entered_at)
        VALUES (NEW.id, NEW.current_stage_id, auth.uid(), now());
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_application_submitted
    AFTER INSERT ON public.applications
    FOR EACH ROW EXECUTE FUNCTION public.log_application_submitted();

CREATE OR REPLACE FUNCTION public.log_application_to_audit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (actor_id, action, table_name, record_id, new_data)
        VALUES (auth.uid(), 'application.submitted', 'applications', NEW.id, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.audit_logs (actor_id, action, table_name, record_id, old_data, new_data)
        VALUES (
            auth.uid(), 'application.status_changed', 'applications', NEW.id,
            jsonb_build_object('status', OLD.status),
            jsonb_build_object('status', NEW.status)
        );
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_audit_applications
    AFTER INSERT OR UPDATE ON public.applications
    FOR EACH ROW EXECUTE FUNCTION public.log_application_to_audit();

-- =============================================================================
-- 10. ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE public.ats_stages                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.applications                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_events            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_stage_history     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_notes             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_screening_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recruiter_application_views   ENABLE ROW LEVEL SECURITY;

-- ATS_STAGES POLICIES
CREATE POLICY "ats_stages_select_org_member" ON public.ats_stages FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.organization_members om
        WHERE om.organization_id = ats_stages.organization_id
          AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "ats_stages_insert_manager" ON public.ats_stages FOR INSERT TO authenticated
    WITH CHECK (public.has_org_permission(organization_id, 'ats.manage_stages'));

CREATE POLICY "ats_stages_update_manager" ON public.ats_stages FOR UPDATE TO authenticated
    USING (public.has_org_permission(organization_id, 'ats.manage_stages'))
    WITH CHECK (public.has_org_permission(organization_id, 'ats.manage_stages'));

CREATE POLICY "ats_stages_delete_manager" ON public.ats_stages FOR DELETE TO authenticated
    USING (public.has_org_permission(organization_id, 'ats.manage_stages'));

-- APPLICATIONS POLICIES
CREATE POLICY "applications_select_own_candidate" ON public.applications FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.candidates c
        WHERE c.id = applications.candidate_id AND c.user_id = auth.uid()));

CREATE POLICY "applications_select_recruiter_view_all" ON public.applications FOR SELECT TO authenticated
    USING (public.has_org_permission(organization_id, 'applications.view_all'));

CREATE POLICY "applications_select_recruiter_assigned" ON public.applications FOR SELECT TO authenticated
    USING (assigned_recruiter_id = auth.uid()
        AND public.has_org_permission(organization_id, 'applications.view_assigned'));

CREATE POLICY "applications_insert_candidate" ON public.applications FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.candidates c
            WHERE c.id = applications.candidate_id AND c.user_id = auth.uid() AND c.status = 'active')
        AND EXISTS (SELECT 1 FROM public.jobs j
            WHERE j.id = applications.job_id AND j.status = 'published'
              AND (j.application_deadline IS NULL OR j.application_deadline > now()))
    );

CREATE POLICY "applications_update_recruiter" ON public.applications FOR UPDATE TO authenticated
    USING (public.has_org_permission(organization_id, 'applications.review'))
    WITH CHECK (public.has_org_permission(organization_id, 'applications.review'));

CREATE POLICY "applications_update_candidate_withdraw" ON public.applications FOR UPDATE TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.candidates c
            WHERE c.id = applications.candidate_id AND c.user_id = auth.uid())
        AND status NOT IN ('withdrawn', 'archived', 'hired'))
    WITH CHECK (
        status = 'withdrawn'
        AND EXISTS (SELECT 1 FROM public.candidates c
            WHERE c.id = applications.candidate_id AND c.user_id = auth.uid()));

CREATE POLICY "applications_no_delete" ON public.applications FOR DELETE TO authenticated USING (false);

-- APPLICATION_EVENTS POLICIES (immutable)
CREATE POLICY "app_events_select_org_member" ON public.application_events FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.organization_members om ON om.organization_id = a.organization_id
        WHERE a.id = application_events.application_id
          AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "app_events_select_own_candidate" ON public.application_events FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.candidates c ON c.id = a.candidate_id
        WHERE a.id = application_events.application_id AND c.user_id = auth.uid()));

CREATE POLICY "app_events_no_insert" ON public.application_events FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "app_events_no_update" ON public.application_events FOR UPDATE TO authenticated USING (false);
CREATE POLICY "app_events_no_delete" ON public.application_events FOR DELETE TO authenticated USING (false);

-- APPLICATION_STAGE_HISTORY POLICIES
CREATE POLICY "stage_history_select_org" ON public.application_stage_history FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.organization_members om ON om.organization_id = a.organization_id
        WHERE a.id = application_stage_history.application_id
          AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "stage_history_no_direct_insert" ON public.application_stage_history FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY "stage_history_no_delete" ON public.application_stage_history FOR DELETE TO authenticated USING (false);

-- APPLICATION_NOTES POLICIES
CREATE POLICY "app_notes_select_org_member" ON public.application_notes FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.organization_members om ON om.organization_id = a.organization_id
        WHERE a.id = application_notes.application_id
          AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "app_notes_insert_recruiter" ON public.application_notes FOR INSERT TO authenticated
    WITH CHECK (
        author_id = auth.uid()
        AND EXISTS (SELECT 1 FROM public.applications a
            WHERE a.id = application_notes.application_id
              AND public.has_org_permission(a.organization_id, 'applications.add_notes')));

CREATE POLICY "app_notes_update_author" ON public.application_notes FOR UPDATE TO authenticated
    USING (author_id = auth.uid()) WITH CHECK (author_id = auth.uid());

CREATE POLICY "app_notes_delete_author" ON public.application_notes FOR DELETE TO authenticated
    USING (author_id = auth.uid());

-- APPLICATION_SCREENING_ANSWERS POLICIES
CREATE POLICY "screening_answers_select_candidate" ON public.application_screening_answers FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.candidates c ON c.id = a.candidate_id
        WHERE a.id = application_screening_answers.application_id AND c.user_id = auth.uid()));

CREATE POLICY "screening_answers_select_org" ON public.application_screening_answers FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.organization_members om ON om.organization_id = a.organization_id
        WHERE a.id = application_screening_answers.application_id
          AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "screening_answers_insert_candidate" ON public.application_screening_answers FOR INSERT TO authenticated
    WITH CHECK (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.candidates c ON c.id = a.candidate_id
        WHERE a.id = application_screening_answers.application_id
          AND c.user_id = auth.uid() AND a.status = 'submitted'));

-- RECRUITER_APPLICATION_VIEWS POLICIES
CREATE POLICY "recruiter_views_select_org" ON public.recruiter_application_views FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.applications a
        JOIN public.organization_members om ON om.organization_id = a.organization_id
        WHERE a.id = recruiter_application_views.application_id
          AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "recruiter_views_insert_self" ON public.recruiter_application_views FOR INSERT TO authenticated
    WITH CHECK (
        viewer_id = auth.uid()
        AND EXISTS (SELECT 1 FROM public.applications a
            JOIN public.organization_members om ON om.organization_id = a.organization_id
            WHERE a.id = recruiter_application_views.application_id
              AND om.user_id = auth.uid() AND om.status = 'active'));

CREATE POLICY "recruiter_views_update_self" ON public.recruiter_application_views FOR UPDATE TO authenticated
    USING (viewer_id = auth.uid()) WITH CHECK (viewer_id = auth.uid());

-- =============================================================================
-- 11. RPC FUNCTIONS
-- =============================================================================

-- A. submit_application
CREATE OR REPLACE FUNCTION public.submit_application(
    p_job_id             UUID,
    p_resume_document_id UUID    DEFAULT NULL,
    p_cover_letter       TEXT    DEFAULT NULL,
    p_source             TEXT    DEFAULT 'platform',
    p_source_reference   TEXT    DEFAULT NULL,
    p_screening_answers  JSONB   DEFAULT '[]'::JSONB
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_candidate_id    UUID;
    v_organization_id UUID;
    v_default_stage   UUID;
    v_application_id  UUID;
    v_answer          JSONB;
BEGIN
    SELECT id INTO v_candidate_id FROM public.candidates
    WHERE user_id = auth.uid() AND status = 'active';

    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No active candidate profile found');
    END IF;

    SELECT organization_id INTO v_organization_id FROM public.jobs
    WHERE id = p_job_id AND status = 'published'
      AND (application_deadline IS NULL OR application_deadline > now());

    IF v_organization_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Job is not available for applications');
    END IF;

    IF EXISTS (SELECT 1 FROM public.applications
               WHERE candidate_id = v_candidate_id AND job_id = p_job_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'You have already applied to this job');
    END IF;

    SELECT id INTO v_default_stage FROM public.ats_stages
    WHERE organization_id = v_organization_id AND is_default = true AND is_active = true LIMIT 1;

    INSERT INTO public.applications (
        job_id, candidate_id, organization_id, current_stage_id,
        status, source, source_reference, resume_document_id, cover_letter, submitted_at
    ) VALUES (
        p_job_id, v_candidate_id, v_organization_id, v_default_stage,
        'submitted', p_source, p_source_reference, p_resume_document_id, p_cover_letter, now()
    ) RETURNING id INTO v_application_id;

    IF jsonb_array_length(p_screening_answers) > 0 THEN
        FOR v_answer IN SELECT * FROM jsonb_array_elements(p_screening_answers) LOOP
            INSERT INTO public.application_screening_answers (
                application_id, question_id, answer_text, answer_boolean, answer_number, answer_options
            ) VALUES (
                v_application_id,
                (v_answer->>'question_id')::UUID,
                v_answer->>'answer_text',
                (v_answer->>'answer_boolean')::BOOLEAN,
                (v_answer->>'answer_number')::NUMERIC,
                ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_answer->'answer_options', '[]'::JSONB)))
            ) ON CONFLICT (application_id, question_id) DO NOTHING;
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true, 'application_id', v_application_id, 'status', 'submitted');
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- B. advance_application_stage
CREATE OR REPLACE FUNCTION public.advance_application_stage(
    p_application_id UUID,
    p_new_stage_id   UUID,
    p_new_status     TEXT DEFAULT NULL,
    p_notes          TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_app public.applications%ROWTYPE;
BEGIN
    SELECT * INTO v_app FROM public.applications WHERE id = p_application_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Application not found');
    END IF;

    IF NOT public.has_org_permission(v_app.organization_id, 'applications.review') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient permissions');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.ats_stages
                   WHERE id = p_new_stage_id AND organization_id = v_app.organization_id AND is_active = true) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or inactive ATS stage');
    END IF;

    UPDATE public.applications
    SET current_stage_id = p_new_stage_id, status = COALESCE(p_new_status, status)
    WHERE id = p_application_id;

    IF p_notes IS NOT NULL AND char_length(trim(p_notes)) > 0 THEN
        INSERT INTO public.application_notes (application_id, author_id, content, is_private)
        VALUES (p_application_id, auth.uid(), p_notes, true);
    END IF;

    RETURN jsonb_build_object(
        'success', true, 'application_id', p_application_id,
        'new_stage_id', p_new_stage_id, 'new_status', COALESCE(p_new_status, v_app.status)
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- C. get_pipeline_board
CREATE OR REPLACE FUNCTION public.get_pipeline_board(
    p_organization_id UUID,
    p_job_id          UUID DEFAULT NULL
)
RETURNS TABLE (
    stage_id          UUID,
    stage_name        TEXT,
    stage_type        TEXT,
    stage_color       VARCHAR(10),
    sort_order        INTEGER,
    application_count BIGINT,
    applications      JSONB
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_org_permission(p_organization_id, 'ats.view_pipeline') THEN
        RAISE EXCEPTION 'Insufficient permissions to view pipeline';
    END IF;

    RETURN QUERY
    SELECT
        s.id, s.name, s.stage_type, s.color, s.sort_order,
        COUNT(a.id),
        COALESCE(
            jsonb_agg(jsonb_build_object(
                'id', a.id, 'status', a.status,
                'submitted_at', a.submitted_at, 'last_activity_at', a.last_activity_at,
                'match_score', a.match_score, 'is_flagged', a.is_flagged, 'job_id', a.job_id
            ) ORDER BY a.last_activity_at DESC) FILTER (WHERE a.id IS NOT NULL),
            '[]'::JSONB
        )
    FROM public.ats_stages s
    LEFT JOIN public.applications a
        ON a.current_stage_id = s.id
        AND a.organization_id = p_organization_id
        AND (p_job_id IS NULL OR a.job_id = p_job_id)
        AND a.status NOT IN ('withdrawn', 'archived')
    WHERE s.organization_id = p_organization_id AND s.is_active = true
    GROUP BY s.id, s.name, s.stage_type, s.color, s.sort_order
    ORDER BY s.sort_order ASC;
END;
$$;

-- D. get_my_applications
CREATE OR REPLACE FUNCTION public.get_my_applications(
    p_status  TEXT    DEFAULT NULL,
    p_limit   INTEGER DEFAULT 20,
    p_offset  INTEGER DEFAULT 0
)
RETURNS TABLE (
    application_id UUID,
    job_id         UUID,
    job_title      TEXT,
    org_name       TEXT,
    status         TEXT,
    match_score    NUMERIC,
    submitted_at   TIMESTAMPTZ,
    last_activity  TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_candidate_id UUID;
BEGIN
    SELECT id INTO v_candidate_id FROM public.candidates WHERE user_id = auth.uid();
    IF v_candidate_id IS NULL THEN RAISE EXCEPTION 'No candidate profile found'; END IF;

    RETURN QUERY
    SELECT a.id, a.job_id, j.title, o.name, a.status,
           a.match_score, a.submitted_at, a.last_activity_at
    FROM public.applications a
    JOIN public.jobs j ON j.id = a.job_id
    JOIN public.organizations o ON o.id = a.organization_id
    WHERE a.candidate_id = v_candidate_id
      AND (p_status IS NULL OR a.status = p_status)
    ORDER BY a.last_activity_at DESC
    LIMIT LEAST(p_limit, 100) OFFSET p_offset;
END;
$$;

-- E. search_applications
CREATE OR REPLACE FUNCTION public.search_applications(
    p_organization_id UUID,
    p_job_id          UUID    DEFAULT NULL,
    p_stage_id        UUID    DEFAULT NULL,
    p_status          TEXT    DEFAULT NULL,
    p_assigned_to     UUID    DEFAULT NULL,
    p_min_match_score NUMERIC DEFAULT NULL,
    p_source          TEXT    DEFAULT NULL,
    p_is_flagged      BOOLEAN DEFAULT NULL,
    p_limit           INTEGER DEFAULT 20,
    p_offset          INTEGER DEFAULT 0
)
RETURNS TABLE (
    application_id        UUID,
    candidate_id          UUID,
    job_id                UUID,
    status                TEXT,
    current_stage_id      UUID,
    assigned_recruiter_id UUID,
    match_score           NUMERIC,
    ai_recommendation     TEXT,
    is_flagged            BOOLEAN,
    source                TEXT,
    submitted_at          TIMESTAMPTZ,
    last_activity_at      TIMESTAMPTZ,
    total_count           BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT public.has_org_permission(p_organization_id, 'applications.view_all')
       AND NOT public.has_org_permission(p_organization_id, 'applications.view_assigned') THEN
        RAISE EXCEPTION 'Insufficient permissions to search applications';
    END IF;

    RETURN QUERY
    SELECT
        a.id, a.candidate_id, a.job_id, a.status,
        a.current_stage_id, a.assigned_recruiter_id,
        a.match_score, a.ai_recommendation, a.is_flagged, a.source,
        a.submitted_at, a.last_activity_at,
        COUNT(*) OVER() AS total_count
    FROM public.applications a
    WHERE a.organization_id = p_organization_id
      AND (p_job_id IS NULL OR a.job_id = p_job_id)
      AND (p_stage_id IS NULL OR a.current_stage_id = p_stage_id)
      AND (p_status IS NULL OR a.status = p_status)
      AND (p_assigned_to IS NULL OR a.assigned_recruiter_id = p_assigned_to)
      AND (p_min_match_score IS NULL OR a.match_score >= p_min_match_score)
      AND (p_source IS NULL OR a.source = p_source)
      AND (p_is_flagged IS NULL OR a.is_flagged = p_is_flagged)
      AND (
          public.has_org_permission(p_organization_id, 'applications.view_all')
          OR a.assigned_recruiter_id = auth.uid()
      )
    ORDER BY a.last_activity_at DESC
    LIMIT LEAST(p_limit, 100) OFFSET p_offset;
END;
$$;

-- =============================================================================
-- 12. VERIFICATION
-- =============================================================================

DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
          'ats_stages','applications','application_events',
          'application_stage_history','application_notes',
          'application_screening_answers','recruiter_application_views'
      );
    ASSERT v_count = 7, 'Expected 7 Task-04 tables, found ' || v_count;

    SELECT COUNT(*) INTO v_count FROM information_schema.routines
    WHERE routine_schema = 'public'
      AND routine_name IN (
          'submit_application','advance_application_stage',
          'get_pipeline_board','get_my_applications','search_applications'
      );
    ASSERT v_count = 5, 'Expected 5 RPC functions, found ' || v_count;

    RAISE NOTICE 'Task 04 -- Applications and ATS Pipeline: All assertions passed.';
END;
$$;
