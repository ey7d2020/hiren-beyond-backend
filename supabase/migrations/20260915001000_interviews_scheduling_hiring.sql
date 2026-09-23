-- ============================================================================
-- Hiren Beyond — Task 09: Interviews, Scheduling, Availability, Feedback & Hiring
-- Migration: 20260915001000_interviews_scheduling_hiring.sql
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. SEED INTERVIEW & HIRING PERMISSIONS
-- -----------------------------------------------------------------------------
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('interviews.create', 'Create Interviews', 'Create interview templates, rounds, and schedules', 'interviews'),
    ('interviews.read', 'Read Interviews', 'View interview schedules, participants, and status', 'interviews'),
    ('interviews.update', 'Update Interviews', 'Modify interview logistics, templates, and rounds', 'interviews'),
    ('interviews.cancel', 'Cancel Interviews', 'Cancel scheduled interviews with reason tracking', 'interviews'),
    ('interviews.reschedule', 'Reschedule Interviews', 'Reschedule interviews and maintain schedule history', 'interviews'),
    ('interviews.conduct', 'Conduct Interviews', 'Participate in interviews as an authorized interviewer', 'interviews'),
    ('interviews.feedback', 'Submit Interview Feedback', 'Submit interview scorecards and evaluation feedback', 'interviews'),
    ('interviews.manage_templates', 'Manage Interview Templates', 'Create and publish organization interview templates', 'interviews'),
    ('interviews.decide', 'Record Hiring Decisions', 'Record authoritative company hiring decisions', 'interviews')
ON CONFLICT (key) DO NOTHING;

-- Grant permissions to admin, recruiter, and hiring_manager roles
DO $$
DECLARE
    v_admin_id UUID;
    v_recruiter_id UUID;
    v_hm_id UUID;
    r_perm RECORD;
BEGIN
    SELECT id INTO v_admin_id FROM public.roles WHERE key = 'admin' LIMIT 1;
    SELECT id INTO v_recruiter_id FROM public.roles WHERE key = 'recruiter' LIMIT 1;
    SELECT id INTO v_hm_id FROM public.roles WHERE key = 'hiring_manager' LIMIT 1;

    FOR r_perm IN SELECT id, key FROM public.permissions WHERE category = 'interviews' LOOP
        IF v_admin_id IS NOT NULL THEN
            INSERT INTO public.role_permissions (role_id, permission_id)
            VALUES (v_admin_id, r_perm.id)
            ON CONFLICT DO NOTHING;
        END IF;

        IF v_recruiter_id IS NOT NULL THEN
            INSERT INTO public.role_permissions (role_id, permission_id)
            VALUES (v_recruiter_id, r_perm.id)
            ON CONFLICT DO NOTHING;
        END IF;

        IF v_hm_id IS NOT NULL AND r_perm.key IN ('interviews.read', 'interviews.conduct', 'interviews.feedback', 'interviews.decide') THEN
            INSERT INTO public.role_permissions (role_id, permission_id)
            VALUES (v_hm_id, r_perm.id)
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. INTERVIEW TEMPLATES
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    interview_type VARCHAR(50) NOT NULL CHECK (interview_type IN ('phone', 'video', 'onsite', 'technical', 'language', 'hr', 'manager', 'panel', 'custom')),
    duration_minutes INT NOT NULL DEFAULT 45,
    default_configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    version INT NOT NULL DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_interview_templates_org ON public.interview_templates(organization_id);
CREATE INDEX IF NOT EXISTS idx_interview_templates_type ON public.interview_templates(interview_type);
CREATE INDEX IF NOT EXISTS idx_interview_templates_status ON public.interview_templates(status);

CREATE UNIQUE INDEX IF NOT EXISTS idx_interview_templates_org_name_v
ON public.interview_templates(COALESCE(organization_id, '00000000-0000-0000-0000-000000000000'::uuid), name, version);

-- -----------------------------------------------------------------------------
-- 3. INTERVIEW ROUNDS (Job-Level Sequence)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    round_type VARCHAR(50) NOT NULL CHECK (round_type IN ('screening', 'technical', 'language', 'manager', 'hr', 'final', 'custom')),
    sequence INT NOT NULL DEFAULT 1,
    duration_minutes INT NOT NULL DEFAULT 45,
    is_required BOOLEAN NOT NULL DEFAULT true,
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (job_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_interview_rounds_job ON public.interview_rounds(job_id);
CREATE INDEX IF NOT EXISTS idx_interview_rounds_org ON public.interview_rounds(organization_id);

-- -----------------------------------------------------------------------------
-- 4. APPLICATION INTERVIEW ROUNDS (Application-Level Progression)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.application_interview_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    interview_round_id UUID NOT NULL REFERENCES public.interview_rounds(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'requested', 'scheduled', 'completed', 'cancelled', 'skipped')),
    sequence INT NOT NULL DEFAULT 1,
    required BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (application_id, interview_round_id)
);

CREATE INDEX IF NOT EXISTS idx_app_interview_rounds_app ON public.application_interview_rounds(application_id);
CREATE INDEX IF NOT EXISTS idx_app_interview_rounds_status ON public.application_interview_rounds(status);

-- -----------------------------------------------------------------------------
-- 5. INTERVIEWS TABLE
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    interview_round_id UUID REFERENCES public.interview_rounds(id) ON DELETE SET NULL,
    interview_template_id UUID REFERENCES public.interview_templates(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    interview_type VARCHAR(50) NOT NULL CHECK (interview_type IN ('phone', 'video', 'onsite', 'technical', 'language', 'hr', 'manager', 'panel', 'custom')),
    status VARCHAR(50) NOT NULL DEFAULT 'requested' CHECK (status IN ('draft', 'requested', 'proposed', 'scheduled', 'in_progress', 'completed', 'cancelled', 'no_show', 'rescheduled')),
    scheduled_start_at TIMESTAMPTZ,
    scheduled_end_at TIMESTAMPTZ,
    timezone VARCHAR(100) NOT NULL DEFAULT 'UTC',
    location TEXT,
    meeting_url TEXT,
    meeting_provider VARCHAR(50) CHECK (meeting_provider IS NULL OR meeting_provider IN ('google_meet', 'zoom', 'microsoft_teams', 'custom')),
    calendar_event_id TEXT,
    calendar_provider VARCHAR(50),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    cancellation_reason TEXT,
    completed_at TIMESTAMPTZ,
    CHECK (scheduled_end_at IS NULL OR scheduled_start_at IS NULL OR scheduled_end_at > scheduled_start_at)
);

CREATE INDEX IF NOT EXISTS idx_interviews_app ON public.interviews(application_id);
CREATE INDEX IF NOT EXISTS idx_interviews_job ON public.interviews(job_id);
CREATE INDEX IF NOT EXISTS idx_interviews_cand ON public.interviews(candidate_id);
CREATE INDEX IF NOT EXISTS idx_interviews_org ON public.interviews(organization_id);
CREATE INDEX IF NOT EXISTS idx_interviews_status ON public.interviews(status);
CREATE INDEX IF NOT EXISTS idx_interviews_time ON public.interviews(scheduled_start_at, scheduled_end_at);

-- -----------------------------------------------------------------------------
-- 6. INTERVIEW PARTICIPANTS (Multiple Interviewers / Panel)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_id UUID NOT NULL REFERENCES public.interviews(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    participant_type VARCHAR(50) NOT NULL DEFAULT 'interviewer' CHECK (participant_type IN ('interviewer', 'recruiter', 'observer', 'hiring_manager', 'reviewer')),
    is_required BOOLEAN NOT NULL DEFAULT true,
    response_status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (response_status IN ('pending', 'accepted', 'declined', 'tentative')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (interview_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_interview_participants_int ON public.interview_participants(interview_id);
CREATE INDEX IF NOT EXISTS idx_interview_participants_usr ON public.interview_participants(user_id);

-- -----------------------------------------------------------------------------
-- 7. CANDIDATE AVAILABILITY
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.candidate_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id UUID NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    timezone VARCHAR(100) NOT NULL DEFAULT 'UTC',
    status VARCHAR(50) NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'unavailable', 'reserved', 'expired')),
    source VARCHAR(50) NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'calendar_sync', 'request_response')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_at > start_at)
);

CREATE INDEX IF NOT EXISTS idx_cand_availability_cand ON public.candidate_availability(candidate_id);
CREATE INDEX IF NOT EXISTS idx_cand_availability_time ON public.candidate_availability(start_at, end_at);

-- -----------------------------------------------------------------------------
-- 8. AVAILABILITY REQUESTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.availability_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_id UUID NOT NULL REFERENCES public.interviews(id) ON DELETE CASCADE,
    recipient_type VARCHAR(50) NOT NULL CHECK (recipient_type IN ('candidate', 'interviewer')),
    recipient_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'responded', 'expired', 'cancelled')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_avail_requests_interview ON public.availability_requests(interview_id);
CREATE INDEX IF NOT EXISTS idx_avail_requests_recip ON public.availability_requests(recipient_type, recipient_id);

-- -----------------------------------------------------------------------------
-- 9. AVAILABILITY SLOTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.availability_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    availability_request_id UUID NOT NULL REFERENCES public.availability_requests(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    timezone VARCHAR(100) NOT NULL DEFAULT 'UTC',
    response VARCHAR(50) NOT NULL DEFAULT 'proposed' CHECK (response IN ('proposed', 'accepted', 'declined')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_at > start_at)
);

CREATE INDEX IF NOT EXISTS idx_avail_slots_req ON public.availability_slots(availability_request_id);

-- -----------------------------------------------------------------------------
-- 10. INTERVIEW SCHEDULE HISTORY (Reschedules)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_schedule_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_id UUID NOT NULL REFERENCES public.interviews(id) ON DELETE CASCADE,
    previous_start_at TIMESTAMPTZ NOT NULL,
    previous_end_at TIMESTAMPTZ NOT NULL,
    new_start_at TIMESTAMPTZ NOT NULL,
    new_end_at TIMESTAMPTZ NOT NULL,
    previous_timezone VARCHAR(100),
    new_timezone VARCHAR(100),
    changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_interview_sched_hist_int ON public.interview_schedule_history(interview_id);

-- -----------------------------------------------------------------------------
-- 11. INTERVIEW SCORECARD SECTIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_scorecard_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_template_id UUID NOT NULL REFERENCES public.interview_templates(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    weight NUMERIC(5,2) NOT NULL DEFAULT 1.00,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scorecard_sections_tmpl ON public.interview_scorecard_sections(interview_template_id);

-- -----------------------------------------------------------------------------
-- 12. INTERVIEW SCORECARD QUESTIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_scorecard_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    section_id UUID NOT NULL REFERENCES public.interview_scorecard_sections(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    rating_type VARCHAR(50) NOT NULL DEFAULT 'numeric' CHECK (rating_type IN ('numeric', 'yes_no', 'text', 'choice')),
    minimum_rating INT DEFAULT 1,
    maximum_rating INT DEFAULT 5,
    is_required BOOLEAN NOT NULL DEFAULT true,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scorecard_questions_sec ON public.interview_scorecard_questions(section_id);

-- -----------------------------------------------------------------------------
-- 13. INTERVIEW FEEDBACK
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_id UUID NOT NULL REFERENCES public.interviews(id) ON DELETE CASCADE,
    interviewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    overall_rating NUMERIC(3,1) CHECK (overall_rating IS NULL OR (overall_rating >= 1.0 AND overall_rating <= 5.0)),
    recommendation VARCHAR(50) NOT NULL CHECK (recommendation IN ('strong_hire', 'hire', 'mixed', 'no_hire', 'strong_no_hire', 'needs_more_evidence')),
    strengths TEXT,
    concerns TEXT,
    notes TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (interview_id, interviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_interview_feedback_int ON public.interview_feedback(interview_id);
CREATE INDEX IF NOT EXISTS idx_interview_feedback_usr ON public.interview_feedback(interviewer_id);

-- -----------------------------------------------------------------------------
-- 14. INTERVIEW SCORECARD RESPONSES
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_scorecard_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feedback_id UUID NOT NULL REFERENCES public.interview_feedback(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES public.interview_scorecard_questions(id) ON DELETE CASCADE,
    numeric_value INT,
    text_value TEXT,
    choice_value TEXT,
    yes_no_value BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (feedback_id, question_id)
);

CREATE INDEX IF NOT EXISTS idx_scorecard_responses_fb ON public.interview_scorecard_responses(feedback_id);

-- -----------------------------------------------------------------------------
-- 15. HIRING DECISIONS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hiring_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    decision VARCHAR(50) NOT NULL CHECK (decision IN ('hire', 'reject', 'hold', 'advance', 'withdraw')),
    decision_reason TEXT NOT NULL,
    decided_by UUID NOT NULL REFERENCES auth.users(id),
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (application_id)
);

CREATE INDEX IF NOT EXISTS idx_hiring_decisions_app ON public.hiring_decisions(application_id);
CREATE INDEX IF NOT EXISTS idx_hiring_decisions_org ON public.hiring_decisions(organization_id);

-- -----------------------------------------------------------------------------
-- 16. HIRING DECISION HISTORY
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hiring_decision_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
    previous_decision VARCHAR(50),
    new_decision VARCHAR(50) NOT NULL,
    reason TEXT,
    changed_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hiring_dec_hist_app ON public.hiring_decision_history(application_id);

-- -----------------------------------------------------------------------------
-- 17. INTERVIEW EVENTS (Notification Queue / Event Emission)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.interview_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interview_id UUID REFERENCES public.interviews(id) ON DELETE CASCADE,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN ('interview_requested', 'availability_requested', 'interview_scheduled', 'interview_rescheduled', 'interview_cancelled', 'interview_completed', 'feedback_requested', 'feedback_submitted', 'hiring_decision_made')),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_interview_events_int ON public.interview_events(interview_id);
CREATE INDEX IF NOT EXISTS idx_interview_events_type ON public.interview_events(event_type);

-- -----------------------------------------------------------------------------
-- 18. ROW LEVEL SECURITY POLICIES
-- -----------------------------------------------------------------------------
ALTER TABLE public.interview_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.application_interview_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.availability_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.availability_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_schedule_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_scorecard_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_scorecard_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_scorecard_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hiring_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hiring_decision_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_events ENABLE ROW LEVEL SECURITY;

-- 18.1 Interview Templates
CREATE POLICY "Read interview templates"
ON public.interview_templates FOR SELECT
TO authenticated
USING (
    organization_id IS NULL 
    OR public.check_user_is_recruiter(organization_id)
);

CREATE POLICY "Manage interview templates"
ON public.interview_templates FOR ALL
TO authenticated
USING (
    organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id)
)
WITH CHECK (
    organization_id IS NOT NULL AND public.check_user_is_recruiter(organization_id)
);

-- 18.2 Interview Rounds
CREATE POLICY "Read interview rounds"
ON public.interview_rounds FOR SELECT
TO authenticated
USING (
    public.check_user_is_recruiter(organization_id)
);

CREATE POLICY "Manage interview rounds"
ON public.interview_rounds FOR ALL
TO authenticated
USING (
    public.check_user_is_recruiter(organization_id)
)
WITH CHECK (
    public.check_user_is_recruiter(organization_id)
);

-- 18.3 Application Interview Rounds
CREATE POLICY "Read application interview rounds"
ON public.application_interview_rounds FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.applications a
        WHERE a.id = application_id
          AND (
              public.check_user_is_recruiter(a.organization_id)
              OR EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = a.candidate_id AND c.user_id = auth.uid())
          )
    )
);

CREATE POLICY "Manage application interview rounds"
ON public.application_interview_rounds FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.applications a
        WHERE a.id = application_id AND public.check_user_is_recruiter(a.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.applications a
        WHERE a.id = application_id AND public.check_user_is_recruiter(a.organization_id)
    )
);

-- 18.4 Interviews (Candidate can see own logistical details; Recruiter & Interviewers have org access)
CREATE POLICY "Read interviews"
ON public.interviews FOR SELECT
TO authenticated
USING (
    public.check_user_is_recruiter(organization_id)
    OR EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.interview_participants ip WHERE ip.interview_id = id AND ip.user_id = auth.uid())
);

CREATE POLICY "Manage interviews"
ON public.interviews FOR ALL
TO authenticated
USING (
    public.check_user_is_recruiter(organization_id)
)
WITH CHECK (
    public.check_user_is_recruiter(organization_id)
);

-- 18.5 Interview Participants
CREATE POLICY "Read interview participants"
ON public.interview_participants FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR i.candidate_id IN (SELECT c.id FROM public.candidates c WHERE c.user_id = auth.uid())
              OR user_id = auth.uid()
          )
    )
);

CREATE POLICY "Manage interview participants"
ON public.interview_participants FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
);

-- 18.6 Candidate Availability
CREATE POLICY "Candidate manage own availability"
ON public.candidate_availability FOR ALL
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
)
WITH CHECK (
    EXISTS (SELECT 1 FROM public.candidates c WHERE c.id = candidate_id AND c.user_id = auth.uid())
);

CREATE POLICY "Recruiters read candidate availability"
ON public.candidate_availability FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.applications a
        WHERE a.candidate_id = candidate_availability.candidate_id
          AND public.check_user_is_recruiter(a.organization_id)
    )
);

-- 18.7 Availability Requests & Slots
CREATE POLICY "Read availability requests"
ON public.availability_requests FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR (recipient_type = 'candidate' AND recipient_id IN (SELECT c.id FROM public.candidates c WHERE c.user_id = auth.uid()))
              OR (recipient_type = 'interviewer' AND recipient_id = auth.uid())
          )
    )
);

CREATE POLICY "Manage availability requests"
ON public.availability_requests FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
);

CREATE POLICY "Read availability slots"
ON public.availability_slots FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.availability_requests ar
        JOIN public.interviews i ON i.id = ar.interview_id
        WHERE ar.id = availability_request_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR (ar.recipient_type = 'candidate' AND ar.recipient_id IN (SELECT c.id FROM public.candidates c WHERE c.user_id = auth.uid()))
              OR (ar.recipient_type = 'interviewer' AND ar.recipient_id = auth.uid())
          )
    )
);

CREATE POLICY "Manage availability slots"
ON public.availability_slots FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.availability_requests ar
        JOIN public.interviews i ON i.id = ar.interview_id
        WHERE ar.id = availability_request_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR (ar.recipient_type = 'candidate' AND ar.recipient_id IN (SELECT c.id FROM public.candidates c WHERE c.user_id = auth.uid()))
              OR (ar.recipient_type = 'interviewer' AND ar.recipient_id = auth.uid())
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.availability_requests ar
        JOIN public.interviews i ON i.id = ar.interview_id
        WHERE ar.id = availability_request_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR (ar.recipient_type = 'candidate' AND ar.recipient_id IN (SELECT c.id FROM public.candidates c WHERE c.user_id = auth.uid()))
              OR (ar.recipient_type = 'interviewer' AND ar.recipient_id = auth.uid())
          )
    )
);

-- 18.8 Schedule History
CREATE POLICY "Read schedule history"
ON public.interview_schedule_history FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR i.candidate_id IN (SELECT c.id FROM public.candidates c WHERE c.user_id = auth.uid())
          )
    )
);

-- 18.9 Scorecards
CREATE POLICY "Read scorecard sections"
ON public.interview_scorecard_sections FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interview_templates it
        WHERE it.id = interview_template_id
          AND (it.organization_id IS NULL OR public.check_user_is_recruiter(it.organization_id))
    )
);

CREATE POLICY "Read scorecard questions"
ON public.interview_scorecard_questions FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interview_scorecard_sections iss
        JOIN public.interview_templates it ON it.id = iss.interview_template_id
        WHERE iss.id = section_id
          AND (it.organization_id IS NULL OR public.check_user_is_recruiter(it.organization_id))
    )
);

-- 18.10 Feedback & Responses (Candidate Strictly Blocked!)
CREATE POLICY "Read feedback"
ON public.interview_feedback FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR interviewer_id = auth.uid()
          )
    )
);

CREATE POLICY "Interviewer manage own feedback"
ON public.interview_feedback FOR ALL
TO authenticated
USING (
    interviewer_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
)
WITH CHECK (
    interviewer_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
);

CREATE POLICY "Read scorecard responses"
ON public.interview_scorecard_responses FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interview_feedback fb
        JOIN public.interviews i ON i.id = fb.interview_id
        WHERE fb.id = feedback_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR fb.interviewer_id = auth.uid()
          )
    )
);

CREATE POLICY "Manage scorecard responses"
ON public.interview_scorecard_responses FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interview_feedback fb
        JOIN public.interviews i ON i.id = fb.interview_id
        WHERE fb.id = feedback_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR fb.interviewer_id = auth.uid()
          )
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.interview_feedback fb
        JOIN public.interviews i ON i.id = fb.interview_id
        WHERE fb.id = feedback_id
          AND (
              public.check_user_is_recruiter(i.organization_id)
              OR fb.interviewer_id = auth.uid()
          )
    )
);

-- 18.11 Hiring Decisions & History (Candidates Blocked!)
CREATE POLICY "Recruiters read hiring decisions"
ON public.hiring_decisions FOR SELECT
TO authenticated
USING (
    public.check_user_is_recruiter(organization_id)
);

CREATE POLICY "Recruiters manage hiring decisions"
ON public.hiring_decisions FOR ALL
TO authenticated
USING (
    public.check_user_is_recruiter(organization_id)
)
WITH CHECK (
    public.check_user_is_recruiter(organization_id)
);

CREATE POLICY "Recruiters read hiring decision history"
ON public.hiring_decision_history FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.applications a
        WHERE a.id = application_id AND public.check_user_is_recruiter(a.organization_id)
    )
);

-- 18.12 Interview Events
CREATE POLICY "Recruiters read interview events"
ON public.interview_events FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.interviews i
        WHERE i.id = interview_id AND public.check_user_is_recruiter(i.organization_id)
    )
);

-- -----------------------------------------------------------------------------
-- 19. STORED PROCEDURES (RPC FUNCTIONS)
-- -----------------------------------------------------------------------------

-- 19.1 Conflict Detection Engine
CREATE OR REPLACE FUNCTION public.check_scheduling_conflict(
    p_candidate_id UUID,
    p_interviewer_ids UUID[],
    p_start_at TIMESTAMPTZ,
    p_end_at TIMESTAMPTZ,
    p_exclude_interview_id UUID DEFAULT NULL
)
RETURNS TABLE (
    has_conflict BOOLEAN,
    conflict_type VARCHAR(50),
    conflicting_interview_id UUID,
    conflict_description TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    r_conf RECORD;
BEGIN
    -- Check Candidate double-booking
    SELECT i.id, i.title, i.scheduled_start_at, i.scheduled_end_at INTO r_conf
    FROM public.interviews i
    WHERE i.candidate_id = p_candidate_id
      AND i.status IN ('scheduled', 'in_progress')
      AND (p_exclude_interview_id IS NULL OR i.id <> p_exclude_interview_id)
      AND (i.scheduled_start_at < p_end_at AND i.scheduled_end_at > p_start_at)
    LIMIT 1;

    IF FOUND THEN
        RETURN QUERY SELECT true, 'candidate_conflict'::VARCHAR, r_conf.id,
            'Candidate already has scheduled interview: ' || r_conf.title || ' (' || r_conf.scheduled_start_at || ' - ' || r_conf.scheduled_end_at || ')';
        RETURN;
    END IF;

    -- Check Required Interviewers double-booking
    IF p_interviewer_ids IS NOT NULL AND array_length(p_interviewer_ids, 1) > 0 THEN
        SELECT i.id, i.title, ip.user_id, i.scheduled_start_at, i.scheduled_end_at INTO r_conf
        FROM public.interviews i
        JOIN public.interview_participants ip ON ip.interview_id = i.id
        WHERE ip.user_id = ANY(p_interviewer_ids)
          AND ip.is_required = true
          AND i.status IN ('scheduled', 'in_progress')
          AND (p_exclude_interview_id IS NULL OR i.id <> p_exclude_interview_id)
          AND (i.scheduled_start_at < p_end_at AND i.scheduled_end_at > p_start_at)
        LIMIT 1;

        IF FOUND THEN
            RETURN QUERY SELECT true, 'interviewer_conflict'::VARCHAR, r_conf.id,
                'Interviewer ' || r_conf.user_id || ' has overlapping interview: ' || r_conf.title;
            RETURN;
        END IF;
    END IF;

    RETURN QUERY SELECT false, 'none'::VARCHAR, NULL::UUID, 'No conflict detected'::TEXT;
END;
$$;

-- 19.2 Schedule Interview (Atomic with Conflict Check)
CREATE OR REPLACE FUNCTION public.schedule_interview(
    p_interview_id UUID,
    p_start_at TIMESTAMPTZ,
    p_end_at TIMESTAMPTZ,
    p_timezone TEXT DEFAULT 'UTC',
    p_location TEXT DEFAULT NULL,
    p_meeting_url TEXT DEFAULT NULL,
    p_meeting_provider TEXT DEFAULT 'google_meet'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_int RECORD;
    v_interviewers UUID[];
    v_conflict RECORD;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_int.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller cannot schedule interview for organization %', v_int.organization_id;
    END IF;

    IF p_end_at <= p_start_at THEN
        RAISE EXCEPTION 'Scheduled end time must be after start time';
    END IF;

    -- Fetch required interviewers
    SELECT array_agg(user_id) INTO v_interviewers
    FROM public.interview_participants
    WHERE interview_id = p_interview_id AND is_required = true;

    -- Conflict Check
    SELECT * INTO v_conflict
    FROM public.check_scheduling_conflict(v_int.candidate_id, v_interviewers, p_start_at, p_end_at, p_interview_id);

    IF v_conflict.has_conflict THEN
        RAISE EXCEPTION 'Scheduling conflict: %', v_conflict.conflict_description;
    END IF;

    -- Update interview
    UPDATE public.interviews
    SET status = 'scheduled',
        scheduled_start_at = p_start_at,
        scheduled_end_at = p_end_at,
        timezone = p_timezone,
        location = p_location,
        meeting_url = p_meeting_url,
        meeting_provider = p_meeting_provider,
        updated_at = now()
    WHERE id = p_interview_id;

    -- Advance ATS application stage to 'interview' if currently 'screening' or 'shortlisted'
    UPDATE public.applications
    SET status = 'interview',
        last_activity_at = now(),
        updated_at = now()
    WHERE id = v_int.application_id AND status IN ('submitted', 'screening', 'shortlisted');

    -- Record application timeline event
    INSERT INTO public.application_events (
        application_id, actor_id, event_type, from_status, to_status, notes
    )
    VALUES (
        v_int.application_id, auth.uid(), 'status_changed', 'shortlisted', 'interview',
        'Interview scheduled for ' || p_start_at || ' (' || p_timezone || ')'
    );

    -- Log audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        v_int.organization_id, auth.uid(), 'interview_scheduled', 'interviews', p_interview_id,
        jsonb_build_object('start_at', p_start_at, 'end_at', p_end_at, 'timezone', p_timezone)
    );

    -- Emit interview event
    INSERT INTO public.interview_events (
        interview_id, event_type, payload
    )
    VALUES (
        p_interview_id, 'interview_scheduled',
        jsonb_build_object('start_at', p_start_at, 'end_at', p_end_at, 'timezone', p_timezone)
    );

    RETURN p_interview_id;
END;
$$;

-- 19.3 Reschedule Interview (With Schedule History)
CREATE OR REPLACE FUNCTION public.reschedule_interview(
    p_interview_id UUID,
    p_new_start_at TIMESTAMPTZ,
    p_new_end_at TIMESTAMPTZ,
    p_new_timezone TEXT,
    p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_int RECORD;
    v_interviewers UUID[];
    v_conflict RECORD;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_int.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller cannot reschedule interview for organization %', v_int.organization_id;
    END IF;

    IF p_new_end_at <= p_new_start_at THEN
        RAISE EXCEPTION 'New scheduled end time must be after start time';
    END IF;

    -- Fetch interviewers
    SELECT array_agg(user_id) INTO v_interviewers
    FROM public.interview_participants
    WHERE interview_id = p_interview_id AND is_required = true;

    -- Check conflicts
    SELECT * INTO v_conflict
    FROM public.check_scheduling_conflict(v_int.candidate_id, v_interviewers, p_new_start_at, p_new_end_at, p_interview_id);

    IF v_conflict.has_conflict THEN
        RAISE EXCEPTION 'Scheduling conflict: %', v_conflict.conflict_description;
    END IF;

    -- Record Schedule History
    INSERT INTO public.interview_schedule_history (
        interview_id, previous_start_at, previous_end_at, new_start_at, new_end_at,
        previous_timezone, new_timezone, changed_by, reason
    )
    VALUES (
        p_interview_id, v_int.scheduled_start_at, v_int.scheduled_end_at, p_new_start_at, p_new_end_at,
        v_int.timezone, p_new_timezone, auth.uid(), p_reason
    );

    -- Update interview
    UPDATE public.interviews
    SET status = 'rescheduled',
        scheduled_start_at = p_new_start_at,
        scheduled_end_at = p_new_end_at,
        timezone = p_new_timezone,
        updated_at = now()
    WHERE id = p_interview_id;

    -- Application timeline event
    INSERT INTO public.application_events (
        application_id, actor_id, event_type, notes
    )
    VALUES (
        v_int.application_id, auth.uid(), 'system_action',
        'Interview rescheduled: ' || p_reason
    );

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        v_int.organization_id, auth.uid(), 'interview_rescheduled', 'interviews', p_interview_id,
        jsonb_build_object('reason', p_reason, 'new_start_at', p_new_start_at)
    );

    -- Emit interview event
    INSERT INTO public.interview_events (
        interview_id, event_type, payload
    )
    VALUES (
        p_interview_id, 'interview_rescheduled',
        jsonb_build_object('new_start_at', p_new_start_at, 'reason', p_reason)
    );

    RETURN p_interview_id;
END;
$$;

-- 19.4 Cancel Interview (With Cancellation Metadata)
CREATE OR REPLACE FUNCTION public.cancel_interview(
    p_interview_id UUID,
    p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_int RECORD;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_int.organization_id) THEN
        RAISE EXCEPTION 'Access denied: cannot cancel interview for organization %', v_int.organization_id;
    END IF;

    UPDATE public.interviews
    SET status = 'cancelled',
        cancelled_at = now(),
        cancelled_by = auth.uid(),
        cancellation_reason = p_reason,
        updated_at = now()
    WHERE id = p_interview_id;

    -- Application timeline event
    INSERT INTO public.application_events (
        application_id, actor_id, event_type, notes
    )
    VALUES (
        v_int.application_id, auth.uid(), 'system_action',
        'Interview cancelled: ' || p_reason
    );

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        v_int.organization_id, auth.uid(), 'interview_cancelled', 'interviews', p_interview_id,
        jsonb_build_object('reason', p_reason)
    );

    -- Emit interview event
    INSERT INTO public.interview_events (
        interview_id, event_type, payload
    )
    VALUES (
        p_interview_id, 'interview_cancelled', jsonb_build_object('reason', p_reason)
    );

    RETURN p_interview_id;
END;
$$;

-- 19.5 Submit Interview Feedback & Scorecard Responses
CREATE OR REPLACE FUNCTION public.submit_interview_feedback(
    p_interview_id UUID,
    p_overall_rating NUMERIC,
    p_recommendation TEXT,
    p_strengths TEXT,
    p_concerns TEXT,
    p_notes TEXT,
    p_scorecard_responses JSONB DEFAULT '[]'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_int RECORD;
    v_feedback_id UUID;
    v_item JSONB;
    v_qid UUID;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    -- Verify caller is participant or recruiter
    IF NOT (
        public.check_user_is_recruiter(v_int.organization_id)
        OR EXISTS (SELECT 1 FROM public.interview_participants WHERE interview_id = p_interview_id AND user_id = auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: caller is not an authorized interviewer for interview %', p_interview_id;
    END IF;

    IF p_overall_rating < 1.0 OR p_overall_rating > 5.0 THEN
        RAISE EXCEPTION 'Overall rating must be between 1.0 and 5.0';
    END IF;

    IF p_recommendation NOT IN ('strong_hire', 'hire', 'mixed', 'no_hire', 'strong_no_hire', 'needs_more_evidence') THEN
        RAISE EXCEPTION 'Invalid recommendation: %', p_recommendation;
    END IF;

    -- Upsert feedback
    INSERT INTO public.interview_feedback (
        interview_id, interviewer_id, overall_rating, recommendation,
        strengths, concerns, notes, submitted_at, updated_at
    )
    VALUES (
        p_interview_id, auth.uid(), p_overall_rating, p_recommendation,
        p_strengths, p_concerns, p_notes, now(), now()
    )
    ON CONFLICT (interview_id, interviewer_id) DO UPDATE
    SET overall_rating = EXCLUDED.overall_rating,
        recommendation = EXCLUDED.recommendation,
        strengths = EXCLUDED.strengths,
        concerns = EXCLUDED.concerns,
        notes = EXCLUDED.notes,
        updated_at = now()
    RETURNING id INTO v_feedback_id;

    -- Record scorecard responses if provided
    IF p_scorecard_responses IS NOT NULL AND jsonb_array_length(p_scorecard_responses) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_scorecard_responses) LOOP
            v_qid := (v_item->>'question_id')::UUID;

            INSERT INTO public.interview_scorecard_responses (
                feedback_id, question_id, numeric_value, text_value, choice_value, yes_no_value
            )
            VALUES (
                v_feedback_id, v_qid,
                (v_item->>'numeric_value')::INT,
                v_item->>'text_value',
                v_item->>'choice_value',
                (v_item->>'yes_no_value')::BOOLEAN
            )
            ON CONFLICT (feedback_id, question_id) DO UPDATE
            SET numeric_value = EXCLUDED.numeric_value,
                text_value = EXCLUDED.text_value,
                choice_value = EXCLUDED.choice_value,
                yes_no_value = EXCLUDED.yes_no_value,
                updated_at = now();
        END LOOP;
    END IF;

    -- Check if all participants submitted feedback, update interview status to 'completed'
    IF NOT EXISTS (
        SELECT 1 FROM public.interview_participants ip
        WHERE ip.interview_id = p_interview_id
          AND ip.is_required = true
          AND NOT EXISTS (
              SELECT 1 FROM public.interview_feedback ifb
              WHERE ifb.interview_id = p_interview_id AND ifb.interviewer_id = ip.user_id
          )
    ) THEN
        UPDATE public.interviews
        SET status = 'completed', completed_at = now(), updated_at = now()
        WHERE id = p_interview_id AND status <> 'completed';
    END IF;

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        v_int.organization_id, auth.uid(), 'feedback_submitted', 'interviews', p_interview_id,
        jsonb_build_object('rating', p_overall_rating, 'recommendation', p_recommendation)
    );

    -- Emit event
    INSERT INTO public.interview_events (
        interview_id, event_type, payload
    )
    VALUES (
        p_interview_id, 'feedback_submitted',
        jsonb_build_object('interviewer_id', auth.uid(), 'rating', p_overall_rating, 'recommendation', p_recommendation)
    );

    RETURN v_feedback_id;
END;
$$;

-- 19.6 Multiple Interviewer Feedback Aggregation
CREATE OR REPLACE FUNCTION public.get_interview_feedback_summary(p_interview_id UUID)
RETURNS TABLE (
    interview_id UUID,
    feedback_count BIGINT,
    average_rating NUMERIC(3,2),
    recommendation_distribution JSONB,
    strengths_summary TEXT[],
    concerns_summary TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_int RECORD;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    IF NOT (
        public.check_user_is_recruiter(v_int.organization_id)
        OR EXISTS (SELECT 1 FROM public.interview_participants ip WHERE ip.interview_id = p_interview_id AND ip.user_id = auth.uid())
    ) THEN
        RAISE EXCEPTION 'Access denied: cannot view feedback summary for interview %', p_interview_id;
    END IF;

    RETURN QUERY
    SELECT
        p_interview_id,
        COUNT(*)::BIGINT AS feedback_count,
        ROUND(AVG(sub.overall_rating), 2) AS average_rating,
        jsonb_object_agg(COALESCE(sub.recommendation, 'none'), sub.count_rec) AS recommendation_distribution,
        array_agg(sub.strengths) FILTER (WHERE sub.strengths IS NOT NULL) AS strengths_summary,
        array_agg(sub.concerns) FILTER (WHERE sub.concerns IS NOT NULL) AS concerns_summary
    FROM (
        SELECT 
            fb.overall_rating,
            fb.recommendation,
            fb.strengths,
            fb.concerns,
            count(*) OVER(PARTITION BY fb.recommendation) AS count_rec
        FROM public.interview_feedback fb
        WHERE fb.interview_id = p_interview_id
    ) sub;
END;
$$;

-- 19.7 Record Authoritative Hiring Decision
CREATE OR REPLACE FUNCTION public.record_hiring_decision(
    p_application_id UUID,
    p_decision TEXT,
    p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_app RECORD;
    v_existing_dec RECORD;
    v_dec_id UUID;
    v_new_status TEXT;
BEGIN
    SELECT * INTO v_app FROM public.applications WHERE id = p_application_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application % not found', p_application_id;
    END IF;

    IF NOT public.check_user_is_recruiter(v_app.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not authorized to make hiring decisions for organization %', v_app.organization_id;
    END IF;

    IF p_decision NOT IN ('hire', 'reject', 'hold', 'advance', 'withdraw') THEN
        RAISE EXCEPTION 'Invalid hiring decision: %', p_decision;
    END IF;

    SELECT * INTO v_existing_dec FROM public.hiring_decisions WHERE application_id = p_application_id;

    IF FOUND THEN
        -- Record Decision History
        INSERT INTO public.hiring_decision_history (
            application_id, previous_decision, new_decision, reason, changed_by
        )
        VALUES (
            p_application_id, v_existing_dec.decision, p_decision, p_reason, auth.uid()
        );

        UPDATE public.hiring_decisions
        SET decision = p_decision,
            decision_reason = p_reason,
            decided_by = auth.uid(),
            decided_at = now(),
            updated_at = now()
        WHERE id = v_existing_dec.id
        RETURNING id INTO v_dec_id;
    ELSE
        INSERT INTO public.hiring_decisions (
            application_id, organization_id, decision, decision_reason, decided_by, decided_at
        )
        VALUES (
            p_application_id, v_app.organization_id, p_decision, p_reason, auth.uid(), now()
        )
        RETURNING id INTO v_dec_id;
    END IF;

    -- Synchronize ATS Application Status safely
    CASE p_decision
        WHEN 'hire' THEN v_new_status := 'hired';
        WHEN 'reject' THEN v_new_status := 'rejected';
        WHEN 'withdraw' THEN v_new_status := 'withdrawn';
        ELSE v_new_status := v_app.status;
    END CASE;

    IF v_new_status <> v_app.status THEN
        UPDATE public.applications
        SET status = v_new_status,
            rejection_reason = CASE WHEN p_decision = 'reject' THEN p_reason ELSE rejection_reason END,
            hired_at = CASE WHEN p_decision = 'hire' THEN now() ELSE hired_at END,
            rejected_at = CASE WHEN p_decision = 'reject' THEN now() ELSE rejected_at END,
            last_activity_at = now(),
            updated_at = now()
        WHERE id = p_application_id;

        INSERT INTO public.application_events (
            application_id, actor_id, event_type, from_status, to_status, notes
        )
        VALUES (
            p_application_id, auth.uid(), 'status_changed', v_app.status, v_new_status,
            'Hiring decision: ' || p_decision || '. ' || p_reason
        );
    END IF;

    -- Audit log
    INSERT INTO public.audit_logs (
        organization_id, actor_user_id, action, entity_type, entity_id, metadata
    )
    VALUES (
        v_app.organization_id, auth.uid(), 'hiring_decision_made', 'applications', p_application_id,
        jsonb_build_object('decision', p_decision, 'reason', p_reason)
    );

    RETURN v_dec_id;
END;
$$;

-- 19.8 Candidate Interview View (Logistics Only, Privacy Protected)
CREATE OR REPLACE FUNCTION public.get_candidate_interview_view(p_interview_id UUID)
RETURNS TABLE (
    interview_id UUID,
    title VARCHAR(255),
    interview_type VARCHAR(50),
    status VARCHAR(50),
    scheduled_start_at TIMESTAMPTZ,
    scheduled_end_at TIMESTAMPTZ,
    timezone VARCHAR(100),
    location TEXT,
    meeting_url TEXT,
    meeting_provider VARCHAR(50)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_int RECORD;
BEGIN
    SELECT * INTO v_int FROM public.interviews WHERE id = p_interview_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Interview % not found', p_interview_id;
    END IF;

    -- Verify candidate is the interviewee
    IF NOT EXISTS (
        SELECT 1 FROM public.candidates c
        WHERE c.id = v_int.candidate_id AND c.user_id = auth.uid()
    ) AND NOT public.check_user_is_recruiter(v_int.organization_id) THEN
        RAISE EXCEPTION 'Access denied: caller cannot view interview %', p_interview_id;
    END IF;

    RETURN QUERY
    SELECT 
        v_int.id,
        v_int.title,
        v_int.interview_type,
        v_int.status,
        v_int.scheduled_start_at,
        v_int.scheduled_end_at,
        v_int.timezone,
        v_int.location,
        v_int.meeting_url,
        v_int.meeting_provider;
END;
$$;

-- 19.9 Recruiter Interview Dashboard
CREATE OR REPLACE FUNCTION public.get_recruiter_interview_dashboard(
    p_org_id UUID,
    p_job_id UUID DEFAULT NULL,
    p_status TEXT DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    interview_id UUID,
    application_id UUID,
    candidate_id UUID,
    candidate_name TEXT,
    job_title TEXT,
    interview_title VARCHAR(255),
    interview_type VARCHAR(50),
    status VARCHAR(50),
    scheduled_start_at TIMESTAMPTZ,
    scheduled_end_at TIMESTAMPTZ,
    timezone VARCHAR(100),
    feedback_count BIGINT,
    latest_decision VARCHAR(50)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.check_user_is_recruiter(p_org_id) THEN
        RAISE EXCEPTION 'Access denied: caller is not an authorized recruiter for organization %', p_org_id;
    END IF;

    RETURN QUERY
    SELECT
        i.id AS interview_id,
        i.application_id,
        i.candidate_id,
        COALESCE(p.full_name, 'Candidate ' || substr(c.id::text, 1, 8)) AS candidate_name,
        j.title AS job_title,
        i.title AS interview_title,
        i.interview_type,
        i.status,
        i.scheduled_start_at,
        i.scheduled_end_at,
        i.timezone,
        (SELECT count(*) FROM public.interview_feedback fb WHERE fb.interview_id = i.id)::BIGINT AS feedback_count,
        (SELECT hd.decision FROM public.hiring_decisions hd WHERE hd.application_id = i.application_id) AS latest_decision
    FROM public.interviews i
    JOIN public.jobs j ON j.id = i.job_id
    JOIN public.candidates c ON c.id = i.candidate_id
    LEFT JOIN public.profiles p ON p.id = c.user_id
    WHERE i.organization_id = p_org_id
      AND (p_job_id IS NULL OR i.job_id = p_job_id)
      AND (p_status IS NULL OR i.status = p_status)
    ORDER BY i.scheduled_start_at ASC NULLS LAST, i.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;
