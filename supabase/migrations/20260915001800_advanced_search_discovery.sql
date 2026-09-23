-- =============================================================================
-- Task 18: Advanced Search & Discovery
-- Migration: 20260915001800_advanced_search_discovery.sql
-- =============================================================================
-- Tables:
--   search_configurations, candidate_search_documents, job_search_documents,
--   search_embeddings, search_history, search_analytics,
--   search_rate_limits, search_alerts
-- RPCs:
--   search_candidates, search_jobs, search_applications,
--   search_talent_pool_candidates, semantic_search_candidates, semantic_search_jobs,
--   hybrid_search_candidates, hybrid_search_jobs,
--   autocomplete_skills, autocomplete_locations, autocomplete_jobs,
--   refresh_candidate_search_document, refresh_job_search_document,
--   record_search_history, get_search_analytics, validate_ai_search_filters
-- =============================================================================

-- Enable pgvector extension for semantic search embeddings
CREATE EXTENSION IF NOT EXISTS vector;

-- =============================================================================
-- 1. SEARCH CONFIGURATIONS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.search_configurations (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id     UUID        REFERENCES public.organizations(id) ON DELETE CASCADE,
    search_type         TEXT        NOT NULL CHECK (search_type IN ('candidate','job','application','talent_pool')),
    configuration       JSONB       NOT NULL DEFAULT '{}'::JSONB,
    is_active           BOOLEAN     NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_search_config_org_type UNIQUE (organization_id, search_type)
);
CREATE INDEX IF NOT EXISTS idx_search_config_org   ON public.search_configurations(organization_id);
CREATE INDEX IF NOT EXISTS idx_search_config_type  ON public.search_configurations(search_type);
CREATE INDEX IF NOT EXISTS idx_search_config_active ON public.search_configurations(is_active);

CREATE TRIGGER trg_search_configurations_updated_at
    BEFORE UPDATE ON public.search_configurations
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Platform-level default configurations (no org_id)
INSERT INTO public.search_configurations (organization_id, search_type, configuration)
VALUES
    (NULL, 'candidate', jsonb_build_object(
        'enabled_fields', ARRAY['headline','professional_summary','skills','experience_titles','languages','education','certifications'],
        'default_sort', 'relevance',
        'minimum_semantic_score', 0.65,
        'weights', jsonb_build_object(
            'fulltext_relevance', 0.4,
            'semantic_similarity', 0.35,
            'match_score', 0.15,
            'profile_completion', 0.10
        ),
        'max_page_size', 50,
        'rate_limit_window_seconds', 60,
        'rate_limit_max_semantic_requests', 10
    )),
    (NULL, 'job', jsonb_build_object(
        'enabled_fields', ARRAY['title','short_description','description','category','skills','languages','location'],
        'default_sort', 'relevance',
        'minimum_semantic_score', 0.60,
        'weights', jsonb_build_object(
            'fulltext_relevance', 0.55,
            'semantic_similarity', 0.30,
            'recency', 0.15
        ),
        'max_page_size', 50
    ))
ON CONFLICT (organization_id, search_type) DO NOTHING;

-- =============================================================================
-- 2. CANDIDATE SEARCH DOCUMENTS (Derived Projection — NOT source of truth)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.candidate_search_documents (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    candidate_id        UUID        NOT NULL REFERENCES public.candidates(id) ON DELETE CASCADE,
    organization_scope  UUID        REFERENCES public.organizations(id) ON DELETE CASCADE,
    search_text         TEXT        NOT NULL DEFAULT '',
    search_vector       TSVECTOR    GENERATED ALWAYS AS (to_tsvector('english', search_text)) STORED,
    index_version       INTEGER     NOT NULL DEFAULT 1,
    content_hash        TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_csd_candidate_org UNIQUE (candidate_id, organization_scope)
);
CREATE INDEX IF NOT EXISTS idx_csd_candidate    ON public.candidate_search_documents(candidate_id);
CREATE INDEX IF NOT EXISTS idx_csd_org_scope    ON public.candidate_search_documents(organization_scope);
CREATE INDEX IF NOT EXISTS idx_csd_updated      ON public.candidate_search_documents(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_csd_vector       ON public.candidate_search_documents USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_csd_hash         ON public.candidate_search_documents(content_hash);

-- =============================================================================
-- 3. JOB SEARCH DOCUMENTS (Derived Projection — NOT source of truth)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.job_search_documents (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id          UUID        NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    search_text     TEXT        NOT NULL DEFAULT '',
    search_vector   TSVECTOR    GENERATED ALWAYS AS (to_tsvector('english', search_text)) STORED,
    index_version   INTEGER     NOT NULL DEFAULT 1,
    content_hash    TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_jsd_job UNIQUE (job_id)
);
CREATE INDEX IF NOT EXISTS idx_jsd_job      ON public.job_search_documents(job_id);
CREATE INDEX IF NOT EXISTS idx_jsd_updated  ON public.job_search_documents(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_jsd_vector   ON public.job_search_documents USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_jsd_hash     ON public.job_search_documents(content_hash);

-- =============================================================================
-- 4. SEARCH EMBEDDINGS (Semantic Search Foundation)
-- =============================================================================
-- Dimension-flexible: use 1536 as default (OpenAI ada-002 / text-embedding-3-small)
-- Can be reconfigured per provider; hash prevents duplicate computation
CREATE TABLE IF NOT EXISTS public.search_embeddings (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type         TEXT        NOT NULL CHECK (entity_type IN ('candidate','job','skill')),
    entity_id           UUID        NOT NULL,
    embedding           vector(1536),
    embedding_model     TEXT        NOT NULL DEFAULT 'text-embedding-ada-002',
    embedding_version   TEXT        NOT NULL DEFAULT 'v1',
    embedding_provider  TEXT        NOT NULL DEFAULT 'openai' CHECK (embedding_provider IN ('openai','google','anthropic','cohere','custom')),
    content_hash        TEXT        NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_embedding_entity_model UNIQUE (entity_type, entity_id, embedding_model, embedding_version)
);
CREATE INDEX IF NOT EXISTS idx_embeddings_entity     ON public.search_embeddings(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_embeddings_model      ON public.search_embeddings(embedding_model, embedding_version);
CREATE INDEX IF NOT EXISTS idx_embeddings_hash       ON public.search_embeddings(content_hash);
-- HNSW index for fast ANN (approximate nearest neighbor) search
CREATE INDEX IF NOT EXISTS idx_embeddings_vector     ON public.search_embeddings USING hnsw(embedding vector_cosine_ops);

CREATE TRIGGER trg_search_embeddings_updated_at
    BEFORE UPDATE ON public.search_embeddings
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 5. SEARCH HISTORY
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.search_history (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    organization_id UUID        REFERENCES public.organizations(id) ON DELETE SET NULL,
    search_type     TEXT        NOT NULL CHECK (search_type IN ('candidate','job','application','talent_pool','semantic')),
    query_text      TEXT,
    filters         JSONB       NOT NULL DEFAULT '{}'::JSONB,
    sort_by         TEXT,
    result_count    INTEGER     NOT NULL DEFAULT 0,
    semantic_used   BOOLEAN     NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sh_user      ON public.search_history(user_id);
CREATE INDEX IF NOT EXISTS idx_sh_org       ON public.search_history(organization_id);
CREATE INDEX IF NOT EXISTS idx_sh_type      ON public.search_history(search_type);
CREATE INDEX IF NOT EXISTS idx_sh_created   ON public.search_history(created_at DESC);

-- =============================================================================
-- 6. SEARCH ANALYTICS (Aggregated Metrics)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.search_analytics (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id         UUID        REFERENCES public.organizations(id) ON DELETE CASCADE,
    search_type             TEXT        NOT NULL CHECK (search_type IN ('candidate','job','application','talent_pool','semantic')),
    period_date             DATE        NOT NULL DEFAULT CURRENT_DATE,
    total_searches          INTEGER     NOT NULL DEFAULT 0,
    zero_result_searches    INTEGER     NOT NULL DEFAULT 0,
    avg_result_count        NUMERIC(8,2) NOT NULL DEFAULT 0,
    semantic_searches       INTEGER     NOT NULL DEFAULT 0,
    top_queries             JSONB       NOT NULL DEFAULT '[]'::JSONB,
    top_filters             JSONB       NOT NULL DEFAULT '[]'::JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_sa_org_type_date UNIQUE (organization_id, search_type, period_date)
);
CREATE INDEX IF NOT EXISTS idx_sa_org       ON public.search_analytics(organization_id);
CREATE INDEX IF NOT EXISTS idx_sa_date      ON public.search_analytics(period_date DESC);
CREATE INDEX IF NOT EXISTS idx_sa_type      ON public.search_analytics(search_type);

CREATE TRIGGER trg_search_analytics_updated_at
    BEFORE UPDATE ON public.search_analytics
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 7. SEARCH RATE LIMITS (Abuse Protection)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.search_rate_limits (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    search_type         TEXT        NOT NULL CHECK (search_type IN ('candidate','semantic','autocomplete')),
    window_start        TIMESTAMPTZ NOT NULL DEFAULT now(),
    request_count       INTEGER     NOT NULL DEFAULT 1,
    CONSTRAINT uq_srl_user_type_window UNIQUE (user_id, search_type, window_start)
);
CREATE INDEX IF NOT EXISTS idx_srl_user    ON public.search_rate_limits(user_id);
CREATE INDEX IF NOT EXISTS idx_srl_window  ON public.search_rate_limits(window_start);

-- =============================================================================
-- 8. SEARCH ALERTS FOUNDATION (Future: notify on new matches for saved searches)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.search_alerts (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    saved_search_id     UUID        NOT NULL REFERENCES public.recruiter_saved_searches(id) ON DELETE CASCADE,
    user_id             UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    organization_id     UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    is_active           BOOLEAN     NOT NULL DEFAULT true,
    frequency           TEXT        NOT NULL DEFAULT 'daily' CHECK (frequency IN ('immediate','daily','weekly')),
    last_triggered_at   TIMESTAMPTZ,
    last_result_count   INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_alert_search_user UNIQUE (saved_search_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_alerts_saved_search ON public.search_alerts(saved_search_id);
CREATE INDEX IF NOT EXISTS idx_alerts_user         ON public.search_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_alerts_org          ON public.search_alerts(organization_id);
CREATE INDEX IF NOT EXISTS idx_alerts_active       ON public.search_alerts(is_active) WHERE is_active = true;

CREATE TRIGGER trg_search_alerts_updated_at
    BEFORE UPDATE ON public.search_alerts
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 9. EXTEND recruiter_saved_searches (add search fields if missing)
-- =============================================================================
ALTER TABLE public.recruiter_saved_searches
    ADD COLUMN IF NOT EXISTS query_text        TEXT,
    ADD COLUMN IF NOT EXISTS semantic_enabled  BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS alert_enabled     BOOLEAN NOT NULL DEFAULT false;

-- =============================================================================
-- 10. RLS SETUP
-- =============================================================================
ALTER TABLE public.search_configurations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.candidate_search_documents   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_search_documents         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_embeddings            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_history               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_analytics             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_rate_limits           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_alerts                ENABLE ROW LEVEL SECURITY;

-- search_configurations: org members can read their org config; platform admin reads all
CREATE POLICY search_config_select ON public.search_configurations FOR SELECT
    USING (
        organization_id IS NULL  -- platform defaults are public
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = search_configurations.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
        OR public.is_platform_admin(auth.uid())
    );

CREATE POLICY search_config_manage ON public.search_configurations FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- candidate_search_documents: recruiters can see docs in their org scope; never public candidate reads
CREATE POLICY csd_select ON public.candidate_search_documents FOR SELECT
    USING (
        -- Platform admin sees all
        public.is_platform_admin(auth.uid())
        OR (
            -- Recruiter in the scoped org (roles joined through role_id FK)
            organization_scope IS NOT NULL
            AND EXISTS (
                SELECT 1 FROM public.organization_members om
                JOIN public.roles r ON r.id = om.role_id
                WHERE om.organization_id = candidate_search_documents.organization_scope
                  AND om.user_id = auth.uid()
                  AND om.status = 'active'
                  AND r.key IN ('platform_admin','recruiter_manager','recruiter','recruiter_junior')
            )
        )
    );

CREATE POLICY csd_system_write ON public.candidate_search_documents FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- job_search_documents: public read for published jobs; org members read own org's drafts
CREATE POLICY jsd_select ON public.job_search_documents FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.jobs j
            WHERE j.id = job_search_documents.job_id
              AND (
                j.status = 'published'
                OR EXISTS (
                    SELECT 1 FROM public.organization_members om
                    WHERE om.organization_id = j.organization_id
                      AND om.user_id = auth.uid()
                      AND om.status = 'active'
                )
                OR public.is_platform_admin(auth.uid())
              )
        )
    );

CREATE POLICY jsd_system_write ON public.job_search_documents FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- search_embeddings: org members and platform admin read; no anonymous access
CREATE POLICY embed_select ON public.search_embeddings FOR SELECT
    TO authenticated
    USING (
        public.is_platform_admin(auth.uid())
        OR (
            entity_type = 'job'
            AND EXISTS (
                SELECT 1 FROM public.jobs j
                WHERE j.id = search_embeddings.entity_id
                  AND j.status = 'published'
            )
        )
    );

CREATE POLICY embed_system_write ON public.search_embeddings FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- search_history: own records only
CREATE POLICY sh_own ON public.search_history FOR SELECT
    USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));

CREATE POLICY sh_insert ON public.search_history FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- search_analytics: org members read org analytics; platform admin reads all
CREATE POLICY sa_select ON public.search_analytics FOR SELECT
    USING (
        public.is_platform_admin(auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.organization_members om
            WHERE om.organization_id = search_analytics.organization_id
              AND om.user_id = auth.uid()
              AND om.status = 'active'
        )
    );

CREATE POLICY sa_system_write ON public.search_analytics FOR ALL
    USING (public.is_platform_admin(auth.uid()));

-- search_rate_limits: own records only
CREATE POLICY srl_own ON public.search_rate_limits FOR ALL
    USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));

-- search_alerts: own records only
CREATE POLICY alert_select ON public.search_alerts FOR SELECT
    USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));

CREATE POLICY alert_manage ON public.search_alerts FOR ALL
    USING (user_id = auth.uid() OR public.is_platform_admin(auth.uid()));

-- =============================================================================
-- 11. HELPER: get_caller_org_ids (returns authorized org IDs for the caller)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_caller_org_ids(p_user_id UUID DEFAULT NULL)
RETURNS UUID[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := COALESCE(p_user_id, auth.uid());
    v_org_ids UUID[];
BEGIN
    SELECT ARRAY_AGG(DISTINCT organization_id)
    INTO v_org_ids
    FROM public.organization_members
    WHERE user_id = v_user_id
      AND status = 'active';

    RETURN COALESCE(v_org_ids, ARRAY[]::UUID[]);
END;
$$;

-- =============================================================================
-- 12. SEARCH RATE LIMIT CHECKER
-- =============================================================================
CREATE OR REPLACE FUNCTION public.check_search_rate_limit(
    p_user_id       UUID,
    p_search_type   TEXT,
    p_window_secs   INTEGER DEFAULT 60,
    p_max_requests  INTEGER DEFAULT 10
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_window_start TIMESTAMPTZ := date_trunc('minute', now());
    v_count        INTEGER;
BEGIN
    -- Count requests in current window
    SELECT COALESCE(SUM(request_count), 0)
    INTO v_count
    FROM public.search_rate_limits
    WHERE user_id     = p_user_id
      AND search_type = p_search_type
      AND window_start >= (now() - (p_window_secs || ' seconds')::INTERVAL);

    IF v_count >= p_max_requests THEN
        RETURN false; -- rate limited
    END IF;

    -- Record this request
    INSERT INTO public.search_rate_limits (user_id, search_type, window_start, request_count)
    VALUES (p_user_id, p_search_type, v_window_start, 1)
    ON CONFLICT (user_id, search_type, window_start)
    DO UPDATE SET request_count = search_rate_limits.request_count + 1;

    RETURN true; -- allowed
END;
$$;

-- =============================================================================
-- 13. REFRESH CANDIDATE SEARCH DOCUMENT
-- =============================================================================
CREATE OR REPLACE FUNCTION public.refresh_candidate_search_document(
    p_candidate_id      UUID,
    p_organization_id   UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_search_text   TEXT;
    v_content_hash  TEXT;
    v_skills        TEXT;
    v_languages     TEXT;
    v_exp_titles    TEXT;
    v_edu           TEXT;
    v_certs         TEXT;
BEGIN
    -- Aggregate candidate public search fields (NO private notes, NO hidden data)
    SELECT
        string_agg(DISTINCT cs.skill_name, ' ')
    INTO v_skills
    FROM public.candidate_skills cs
    WHERE cs.candidate_id = p_candidate_id;

    SELECT
        string_agg(DISTINCT cl.language_name || ' ' || cl.proficiency_level, ' ')
    INTO v_languages
    FROM public.candidate_languages cl
    WHERE cl.candidate_id = p_candidate_id;

    SELECT
        string_agg(DISTINCT ce.job_title || ' ' || COALESCE(ce.company_name,''), ' ')
    INTO v_exp_titles
    FROM public.candidate_experience ce
    WHERE ce.candidate_id = p_candidate_id;

    SELECT
        string_agg(DISTINCT COALESCE(ced.institution_name,'') || ' ' || COALESCE(ced.field_of_study,''), ' ')
    INTO v_edu
    FROM public.candidate_education ced
    WHERE ced.candidate_id = p_candidate_id;

    SELECT
        string_agg(DISTINCT cc.name, ' ')
    INTO v_certs
    FROM public.candidate_certifications cc
    WHERE cc.candidate_id = p_candidate_id;

    -- Compose search text from approved public fields only
    SELECT
        TRIM(
            COALESCE(cp.headline, '') || ' ' ||
            COALESCE(cp.professional_summary, '') || ' ' ||
            COALESCE(cp.current_title, '') || ' ' ||
            COALESCE(cvp.headline, '') || ' ' ||
            COALESCE(cvp.summary, '') || ' ' ||
            COALESCE(v_skills, '') || ' ' ||
            COALESCE(v_languages, '') || ' ' ||
            COALESCE(v_exp_titles, '') || ' ' ||
            COALESCE(v_edu, '') || ' ' ||
            COALESCE(v_certs, '')
        )
    INTO v_search_text
    FROM public.candidates c
    LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
    LEFT JOIN public.candidate_cv_profiles cvp ON cvp.candidate_id = c.id AND cvp.is_current = true
    WHERE c.id = p_candidate_id;

    v_search_text := COALESCE(v_search_text, '');
    v_content_hash := md5(v_search_text);

    -- Upsert the search document (skip if hash unchanged)
    INSERT INTO public.candidate_search_documents
        (candidate_id, organization_scope, search_text, index_version, content_hash, updated_at)
    VALUES
        (p_candidate_id, p_organization_id, v_search_text, 1, v_content_hash, now())
    ON CONFLICT (candidate_id, organization_scope)
    DO UPDATE SET
        search_text   = CASE WHEN candidate_search_documents.content_hash <> v_content_hash THEN v_search_text ELSE candidate_search_documents.search_text END,
        content_hash  = v_content_hash,
        index_version = CASE WHEN candidate_search_documents.content_hash <> v_content_hash THEN candidate_search_documents.index_version + 1 ELSE candidate_search_documents.index_version END,
        updated_at    = CASE WHEN candidate_search_documents.content_hash <> v_content_hash THEN now() ELSE candidate_search_documents.updated_at END;
END;
$$;

-- =============================================================================
-- 14. REFRESH JOB SEARCH DOCUMENT
-- =============================================================================
CREATE OR REPLACE FUNCTION public.refresh_job_search_document(p_job_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_search_text   TEXT;
    v_content_hash  TEXT;
    v_skills        TEXT;
    v_languages     TEXT;
BEGIN
    SELECT string_agg(DISTINCT js.skill_name, ' ')
    INTO v_skills
    FROM public.job_skills js
    WHERE js.job_id = p_job_id;

    SELECT string_agg(DISTINCT jl.language_name, ' ')
    INTO v_languages
    FROM public.job_languages jl
    WHERE jl.job_id = p_job_id;

    SELECT TRIM(
        COALESCE(j.title,'') || ' ' ||
        COALESCE(j.short_description,'') || ' ' ||
        COALESCE(j.description,'') || ' ' ||
        COALESCE(j.country,'') || ' ' ||
        COALESCE(j.city,'') || ' ' ||
        COALESCE(j.workplace_type,'') || ' ' ||
        COALESCE(j.employment_type,'') || ' ' ||
        COALESCE(j.experience_level,'') || ' ' ||
        COALESCE(jc.name,'') || ' ' ||
        COALESCE(v_skills,'') || ' ' ||
        COALESCE(v_languages,'')
    )
    INTO v_search_text
    FROM public.jobs j
    LEFT JOIN public.job_categories jc ON jc.id = j.category_id
    WHERE j.id = p_job_id;

    v_search_text := COALESCE(v_search_text, '');
    v_content_hash := md5(v_search_text);

    INSERT INTO public.job_search_documents (job_id, search_text, index_version, content_hash, updated_at)
    VALUES (p_job_id, v_search_text, 1, v_content_hash, now())
    ON CONFLICT (job_id)
    DO UPDATE SET
        search_text   = CASE WHEN job_search_documents.content_hash <> v_content_hash THEN v_search_text ELSE job_search_documents.search_text END,
        content_hash  = v_content_hash,
        index_version = CASE WHEN job_search_documents.content_hash <> v_content_hash THEN job_search_documents.index_version + 1 ELSE job_search_documents.index_version END,
        updated_at    = CASE WHEN job_search_documents.content_hash <> v_content_hash THEN now() ELSE job_search_documents.updated_at END;
END;
$$;

-- =============================================================================
-- 15. TRIGGERS: Auto-refresh search documents on source data changes
-- =============================================================================

-- Candidate search document refresh function (trigger wrapper)
CREATE OR REPLACE FUNCTION public.trg_refresh_candidate_search_doc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_candidate_id UUID;
BEGIN
    v_candidate_id := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.candidate_id
        ELSE NEW.candidate_id
    END;
    PERFORM public.refresh_candidate_search_document(v_candidate_id, NULL);
    RETURN NULL;
END;
$$;

-- Attach triggers to candidate source tables
DROP TRIGGER IF EXISTS trg_csd_on_profile ON public.candidate_profiles;
CREATE TRIGGER trg_csd_on_profile
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_profiles
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_candidate_search_doc();

DROP TRIGGER IF EXISTS trg_csd_on_skills ON public.candidate_skills;
CREATE TRIGGER trg_csd_on_skills
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_skills
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_candidate_search_doc();

DROP TRIGGER IF EXISTS trg_csd_on_languages ON public.candidate_languages;
CREATE TRIGGER trg_csd_on_languages
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_languages
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_candidate_search_doc();

DROP TRIGGER IF EXISTS trg_csd_on_experience ON public.candidate_experience;
CREATE TRIGGER trg_csd_on_experience
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_experience
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_candidate_search_doc();

DROP TRIGGER IF EXISTS trg_csd_on_education ON public.candidate_education;
CREATE TRIGGER trg_csd_on_education
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_education
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_candidate_search_doc();

DROP TRIGGER IF EXISTS trg_csd_on_certifications ON public.candidate_certifications;
CREATE TRIGGER trg_csd_on_certifications
    AFTER INSERT OR UPDATE OR DELETE ON public.candidate_certifications
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_candidate_search_doc();

-- Job search document refresh trigger
CREATE OR REPLACE FUNCTION public.trg_refresh_job_search_doc()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_job_id UUID;
BEGIN
    v_job_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.job_id ELSE NEW.job_id END;
    IF v_job_id IS NULL THEN
        v_job_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
    END IF;
    PERFORM public.refresh_job_search_document(v_job_id);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_jsd_on_job ON public.jobs;
CREATE TRIGGER trg_jsd_on_job
    AFTER INSERT OR UPDATE ON public.jobs
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_job_search_doc();

CREATE OR REPLACE FUNCTION public.trg_refresh_job_search_doc_skills()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    PERFORM public.refresh_job_search_document(CASE WHEN TG_OP='DELETE' THEN OLD.job_id ELSE NEW.job_id END);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_jsd_on_skills ON public.job_skills;
CREATE TRIGGER trg_jsd_on_skills
    AFTER INSERT OR UPDATE OR DELETE ON public.job_skills
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_job_search_doc_skills();

DROP TRIGGER IF EXISTS trg_jsd_on_languages ON public.job_languages;
CREATE TRIGGER trg_jsd_on_languages
    AFTER INSERT OR UPDATE OR DELETE ON public.job_languages
    FOR EACH ROW EXECUTE FUNCTION public.trg_refresh_job_search_doc_skills();

-- =============================================================================
-- 16. RECORD SEARCH HISTORY
-- =============================================================================
CREATE OR REPLACE FUNCTION public.record_search_history(
    p_search_type   TEXT,
    p_query_text    TEXT DEFAULT NULL,
    p_filters       JSONB DEFAULT '{}'::JSONB,
    p_sort_by       TEXT DEFAULT NULL,
    p_result_count  INTEGER DEFAULT 0,
    p_semantic_used BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_org_ids   UUID[];
    v_org_id    UUID;
    v_id        UUID;
BEGIN
    IF v_user_id IS NULL THEN RETURN NULL; END IF;

    v_org_ids := public.get_caller_org_ids(v_user_id);
    v_org_id  := CASE WHEN array_length(v_org_ids, 1) > 0 THEN v_org_ids[1] ELSE NULL END;

    INSERT INTO public.search_history (user_id, organization_id, search_type, query_text, filters, sort_by, result_count, semantic_used)
    VALUES (v_user_id, v_org_id, p_search_type, p_query_text, p_filters, p_sort_by, p_result_count, p_semantic_used)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- =============================================================================
-- 17. SEARCH CANDIDATES (Full-Text + Structured Filters)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.search_candidates(
    p_query_text            TEXT        DEFAULT NULL,
    p_skills                TEXT[]      DEFAULT NULL,
    p_languages             TEXT[]      DEFAULT NULL,
    p_language_level        TEXT        DEFAULT NULL,
    p_experience_years_min  NUMERIC     DEFAULT NULL,
    p_experience_years_max  NUMERIC     DEFAULT NULL,
    p_country               TEXT        DEFAULT NULL,
    p_city                  TEXT        DEFAULT NULL,
    p_workplace_type        TEXT        DEFAULT NULL,
    p_career_level          TEXT        DEFAULT NULL,
    p_profile_completion_min INTEGER    DEFAULT NULL,
    p_match_score_min       NUMERIC     DEFAULT NULL,
    p_job_id                UUID        DEFAULT NULL,
    p_talent_pool_id        UUID        DEFAULT NULL,
    p_sort_by               TEXT        DEFAULT 'relevance',
    p_page                  INTEGER     DEFAULT 1,
    p_page_size             INTEGER     DEFAULT 20
)
RETURNS TABLE (
    candidate_id            UUID,
    full_name               TEXT,
    headline                TEXT,
    current_title           TEXT,
    country                 TEXT,
    city                    TEXT,
    years_of_experience     NUMERIC,
    remote_preference       TEXT,
    top_skills              TEXT[],
    languages               TEXT[],
    career_level            TEXT,
    profile_completion      INTEGER,
    latest_match_score      NUMERIC,
    relevance_score         FLOAT,
    total_count             BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id       UUID := auth.uid();
    v_org_ids       UUID[];
    v_offset        INTEGER;
    v_page_size     INTEGER;
BEGIN
    -- Authorization: caller must be an authenticated recruiter
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required';
    END IF;

    -- Derive authorized org scope — never trust caller-supplied org_id
    v_org_ids := public.get_caller_org_ids(v_user_id);

    -- Platform admins may search globally
    IF public.is_platform_admin(v_user_id) THEN
        v_org_ids := NULL; -- NULL means unrestricted
    ELSIF array_length(v_org_ids, 1) IS NULL OR array_length(v_org_ids, 1) = 0 THEN
        RAISE EXCEPTION 'insufficient_permissions: no active organization membership';
    END IF;

    v_page_size := LEAST(COALESCE(p_page_size, 20), 50);
    v_offset    := (GREATEST(COALESCE(p_page, 1), 1) - 1) * v_page_size;

    RETURN QUERY
    WITH base AS (
        SELECT DISTINCT
            c.id                                            AS candidate_id,
            p.full_name::TEXT                              AS full_name,
            cp.headline::TEXT                              AS headline,
            cp.current_title::TEXT                         AS current_title,
            cp.country_code::TEXT                          AS country,
            cp.city::TEXT                                  AS city,
            COALESCE(cp.years_of_experience, 0)            AS years_of_experience,
            cp.remote_preference::TEXT                     AS remote_preference,
            ARRAY(
                SELECT cs.skill_name
                FROM public.candidate_skills cs
                WHERE cs.candidate_id = c.id
                ORDER BY cs.is_verified DESC, cs.proficiency_level DESC
                LIMIT 6
            )::TEXT[]                                      AS top_skills,
            ARRAY(
                SELECT cl.language_name || ' (' || cl.proficiency_level || ')'
                FROM public.candidate_languages cl
                WHERE cl.candidate_id = c.id
                LIMIT 4
            )::TEXT[]                                      AS languages,
            cvp.career_level_estimate::TEXT                AS career_level,
            c.profile_completion_percentage                AS profile_completion,
            -- Latest match score for the specified job (if any), else NULL
            (
                SELECT mr.final_score
                FROM public.matching_runs mr
                WHERE mr.candidate_id = c.id
                  AND (p_job_id IS NULL OR mr.job_id = p_job_id)
                  AND mr.status = 'completed'
                ORDER BY mr.created_at DESC
                LIMIT 1
            )                                              AS latest_match_score,
            -- Full-text relevance score (0.0-1.0 normalized)
            CASE
                WHEN p_query_text IS NOT NULL AND csd.search_vector IS NOT NULL THEN
                    ts_rank_cd(csd.search_vector, plainto_tsquery('english', p_query_text))
                ELSE 0.0
            END                                            AS relevance_score
        FROM public.candidates c
        JOIN public.profiles p ON p.id = c.user_id
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        LEFT JOIN public.candidate_cv_profiles cvp ON cvp.candidate_id = c.id AND cvp.is_current = true
        LEFT JOIN public.candidate_search_documents csd ON csd.candidate_id = c.id AND csd.organization_scope IS NULL
        -- Scope authorization
        WHERE (
            v_org_ids IS NULL  -- platform admin global
            OR EXISTS (
                SELECT 1 FROM public.organization_members om
                WHERE om.user_id = v_user_id
                  AND om.status = 'active'
                  AND om.organization_id = ANY(v_org_ids)
            )
        )
        -- Candidate status: only active
        AND c.status = 'active'
        -- Full-text filter
        AND (
            p_query_text IS NULL
            OR (
                csd.search_vector @@ plainto_tsquery('english', p_query_text)
            )
        )
        -- Skills filter
        AND (
            p_skills IS NULL
            OR EXISTS (
                SELECT 1 FROM public.candidate_skills cs
                WHERE cs.candidate_id = c.id
                  AND cs.normalized_skill_name = ANY(p_skills)
            )
        )
        -- Language filter
        AND (
            p_languages IS NULL
            OR EXISTS (
                SELECT 1 FROM public.candidate_languages cl
                WHERE cl.candidate_id = c.id
                  AND (cl.language_code = ANY(p_languages) OR cl.normalized_language_name = ANY(p_languages))
                  AND (p_language_level IS NULL OR cl.proficiency_level = p_language_level)
            )
        )
        -- Experience range filter
        AND (p_experience_years_min IS NULL OR COALESCE(cp.years_of_experience, 0) >= p_experience_years_min)
        AND (p_experience_years_max IS NULL OR COALESCE(cp.years_of_experience, 0) <= p_experience_years_max)
        -- Country filter
        AND (p_country IS NULL OR cp.country_code ILIKE p_country)
        -- City filter
        AND (p_city IS NULL OR cp.city ILIKE ('%' || p_city || '%'))
        -- Workplace type
        AND (p_workplace_type IS NULL OR cp.remote_preference = p_workplace_type)
        -- Career level
        AND (p_career_level IS NULL OR cvp.career_level_estimate = p_career_level)
        -- Profile completion minimum
        AND (p_profile_completion_min IS NULL OR c.profile_completion_percentage >= p_profile_completion_min)
        -- Match score filter (from existing matching engine — Task 06)
        AND (
            p_match_score_min IS NULL
            OR EXISTS (
                SELECT 1 FROM public.matching_runs mr
                WHERE mr.candidate_id = c.id
                  AND (p_job_id IS NULL OR mr.job_id = p_job_id)
                  AND mr.status = 'completed'
                  AND mr.final_score >= p_match_score_min
            )
        )
        -- Talent pool filter (from Task 07)
        AND (
            p_talent_pool_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.talent_pool_members tpm
                WHERE tpm.candidate_id = c.id
                  AND tpm.talent_pool_id = p_talent_pool_id
                  AND tpm.status = 'active'
            )
        )
    ),
    counted AS (
        SELECT *, COUNT(*) OVER() AS total_count FROM base
    )
    SELECT
        candidate_id, full_name, headline, current_title, country, city,
        years_of_experience, remote_preference, top_skills, languages,
        career_level, profile_completion, latest_match_score, relevance_score,
        total_count
    FROM counted
    ORDER BY
        CASE WHEN p_sort_by = 'relevance'          THEN relevance_score END             DESC NULLS LAST,
        CASE WHEN p_sort_by = 'match_score'        THEN latest_match_score END          DESC NULLS LAST,
        CASE WHEN p_sort_by = 'experience'         THEN years_of_experience END         DESC NULLS LAST,
        CASE WHEN p_sort_by = 'profile_completion' THEN profile_completion END          DESC NULLS LAST,
        -- Default secondary tie-breaker: most recent
        candidate_id ASC
    LIMIT v_page_size
    OFFSET v_offset;
END;
$$;

-- =============================================================================
-- 18. SEARCH JOBS (Public + Recruiter)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.search_jobs(
    p_query_text        TEXT    DEFAULT NULL,
    p_category_slug     TEXT    DEFAULT NULL,
    p_country           TEXT    DEFAULT NULL,
    p_city              TEXT    DEFAULT NULL,
    p_workplace_type    TEXT    DEFAULT NULL,
    p_employment_type   TEXT    DEFAULT NULL,
    p_experience_level  TEXT    DEFAULT NULL,
    p_language          TEXT    DEFAULT NULL,
    p_salary_min        NUMERIC DEFAULT NULL,
    p_salary_max        NUMERIC DEFAULT NULL,
    p_featured_only     BOOLEAN DEFAULT false,
    p_organization_id   UUID    DEFAULT NULL,
    p_status_filter     TEXT    DEFAULT NULL,
    p_sort_by           TEXT    DEFAULT 'relevance',
    p_page              INTEGER DEFAULT 1,
    p_page_size         INTEGER DEFAULT 20
)
RETURNS TABLE (
    job_id          UUID,
    title           TEXT,
    short_description TEXT,
    country         TEXT,
    city            TEXT,
    workplace_type  TEXT,
    employment_type TEXT,
    experience_level TEXT,
    salary_min      NUMERIC,
    salary_max      NUMERIC,
    salary_currency TEXT,
    is_featured     BOOLEAN,
    status          TEXT,
    published_at    TIMESTAMPTZ,
    category_name   TEXT,
    organization_name TEXT,
    relevance_score FLOAT,
    total_count     BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id       UUID := auth.uid();
    v_caller_orgs   UUID[];
    v_is_admin      BOOLEAN := false;
    v_offset        INTEGER;
    v_page_size     INTEGER;
    v_recruiter_mode BOOLEAN := false;
BEGIN
    v_page_size := LEAST(COALESCE(p_page_size, 20), 50);
    v_offset    := (GREATEST(COALESCE(p_page, 1), 1) - 1) * v_page_size;

    IF v_user_id IS NOT NULL THEN
        v_caller_orgs  := public.get_caller_org_ids(v_user_id);
        v_is_admin     := public.is_platform_admin(v_user_id);
        -- Recruiter mode: org filter explicitly requested and caller is a member
        v_recruiter_mode := (
            p_organization_id IS NOT NULL
            AND (v_is_admin OR p_organization_id = ANY(v_caller_orgs))
        );
    END IF;

    RETURN QUERY
    WITH base AS (
        SELECT DISTINCT
            j.id                AS job_id,
            j.title::TEXT       AS title,
            j.short_description::TEXT AS short_description,
            j.country::TEXT     AS country,
            j.city::TEXT        AS city,
            j.workplace_type::TEXT AS workplace_type,
            j.employment_type::TEXT AS employment_type,
            j.experience_level::TEXT AS experience_level,
            j.salary_min,
            j.salary_max,
            j.salary_currency::TEXT AS salary_currency,
            j.is_featured,
            j.status::TEXT      AS status,
            j.published_at,
            jc.name::TEXT       AS category_name,
            o.name::TEXT        AS organization_name,
            CASE
                WHEN p_query_text IS NOT NULL AND jsd.search_vector IS NOT NULL THEN
                    ts_rank_cd(jsd.search_vector, plainto_tsquery('english', p_query_text))
                ELSE 0.0
            END                 AS relevance_score
        FROM public.jobs j
        LEFT JOIN public.job_categories jc ON jc.id = j.category_id
        LEFT JOIN public.organizations o ON o.id = j.organization_id
        LEFT JOIN public.job_search_documents jsd ON jsd.job_id = j.id
        WHERE
            -- Access scope:
            -- Recruiter mode: org-scoped, all statuses or filtered
            -- Public/candidate mode: published + public + active org only
            (
                v_recruiter_mode
                AND j.organization_id = p_organization_id
                AND (p_status_filter IS NULL OR j.status = p_status_filter)
            )
            OR (
                NOT v_recruiter_mode
                AND j.status = 'published'
                AND j.visibility = 'public'
                AND o.status = 'active'
                AND (j.application_deadline IS NULL OR j.application_deadline > now())
            )
            -- Full-text search
            AND (
                p_query_text IS NULL
                OR jsd.search_vector @@ plainto_tsquery('english', p_query_text)
            )
            -- Structured filters
            AND (p_category_slug IS NULL OR jc.slug = p_category_slug)
            AND (p_country IS NULL OR j.country ILIKE p_country)
            AND (p_city IS NULL OR j.city ILIKE ('%' || p_city || '%'))
            AND (p_workplace_type IS NULL OR j.workplace_type = p_workplace_type)
            AND (p_employment_type IS NULL OR j.employment_type = p_employment_type)
            AND (p_experience_level IS NULL OR j.experience_level = p_experience_level)
            AND (p_salary_min IS NULL OR j.salary_max IS NULL OR j.salary_max >= p_salary_min)
            AND (p_salary_max IS NULL OR j.salary_min IS NULL OR j.salary_min <= p_salary_max)
            AND (NOT p_featured_only OR j.is_featured = true)
            AND (p_language IS NULL OR EXISTS (
                SELECT 1 FROM public.job_languages jl
                WHERE jl.job_id = j.id AND (jl.language_code = p_language OR jl.language_name ILIKE p_language)
            ))
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM base)
    SELECT
        job_id, title, short_description, country, city,
        workplace_type, employment_type, experience_level,
        salary_min, salary_max, salary_currency, is_featured, status,
        published_at, category_name, organization_name, relevance_score,
        total_count
    FROM counted
    ORDER BY
        CASE WHEN p_sort_by = 'relevance'  THEN relevance_score END DESC NULLS LAST,
        CASE WHEN p_sort_by = 'newest'     THEN published_at END     DESC NULLS LAST,
        CASE WHEN p_sort_by = 'featured'   THEN is_featured::INTEGER END DESC NULLS LAST,
        -- Stable tie-breaker
        job_id ASC
    LIMIT v_page_size
    OFFSET v_offset;
END;
$$;

-- =============================================================================
-- 19. SEARCH APPLICATIONS
-- =============================================================================
CREATE OR REPLACE FUNCTION public.search_applications(
    p_candidate_id      UUID        DEFAULT NULL,
    p_job_id            UUID        DEFAULT NULL,
    p_status            TEXT        DEFAULT NULL,
    p_ats_stage         TEXT        DEFAULT NULL,
    p_match_score_min   NUMERIC     DEFAULT NULL,
    p_date_from         TIMESTAMPTZ DEFAULT NULL,
    p_date_to           TIMESTAMPTZ DEFAULT NULL,
    p_sort_by           TEXT        DEFAULT 'newest',
    p_page              INTEGER     DEFAULT 1,
    p_page_size         INTEGER     DEFAULT 20
)
RETURNS TABLE (
    application_id      UUID,
    candidate_id        UUID,
    candidate_name      TEXT,
    job_id              UUID,
    job_title           TEXT,
    status              TEXT,
    ats_stage           TEXT,
    match_score         NUMERIC,
    applied_at          TIMESTAMPTZ,
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

    IF NOT public.is_platform_admin(v_user_id) AND (array_length(v_org_ids,1) IS NULL OR array_length(v_org_ids,1) = 0) THEN
        RAISE EXCEPTION 'insufficient_permissions';
    END IF;

    RETURN QUERY
    WITH base AS (
        SELECT
            a.id                        AS application_id,
            a.candidate_id,
            p.full_name::TEXT           AS candidate_name,
            a.job_id,
            j.title::TEXT               AS job_title,
            a.status::TEXT              AS status,
            a.current_stage::TEXT       AS ats_stage,
            mr.final_score              AS match_score,
            a.applied_at
        FROM public.applications a
        JOIN public.jobs j ON j.id = a.job_id
        JOIN public.candidates c ON c.id = a.candidate_id
        JOIN public.profiles p ON p.id = c.user_id
        LEFT JOIN LATERAL (
            SELECT final_score FROM public.matching_runs
            WHERE candidate_id = a.candidate_id AND job_id = a.job_id AND status = 'completed'
            ORDER BY created_at DESC LIMIT 1
        ) mr ON true
        WHERE
            -- Org scope authorization
            (
                public.is_platform_admin(v_user_id)
                OR j.organization_id = ANY(v_org_ids)
            )
            AND (p_candidate_id IS NULL OR a.candidate_id = p_candidate_id)
            AND (p_job_id IS NULL OR a.job_id = p_job_id)
            AND (p_status IS NULL OR a.status = p_status)
            AND (p_ats_stage IS NULL OR a.current_stage = p_ats_stage)
            AND (p_match_score_min IS NULL OR mr.final_score >= p_match_score_min)
            AND (p_date_from IS NULL OR a.applied_at >= p_date_from)
            AND (p_date_to IS NULL OR a.applied_at <= p_date_to)
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM base)
    SELECT application_id, candidate_id, candidate_name, job_id, job_title,
           status, ats_stage, match_score, applied_at, total_count
    FROM counted
    ORDER BY
        CASE WHEN p_sort_by = 'newest'      THEN applied_at END      DESC NULLS LAST,
        CASE WHEN p_sort_by = 'match_score' THEN match_score END      DESC NULLS LAST,
        application_id ASC
    LIMIT LEAST(COALESCE(p_page_size,20), 50)
    OFFSET (GREATEST(COALESCE(p_page,1),1) - 1) * LEAST(COALESCE(p_page_size,20), 50);
END;
$$;

-- =============================================================================
-- 20. SEARCH TALENT POOL CANDIDATES
-- =============================================================================
CREATE OR REPLACE FUNCTION public.search_talent_pool_candidates(
    p_talent_pool_id        UUID,
    p_query_text            TEXT    DEFAULT NULL,
    p_skills                TEXT[]  DEFAULT NULL,
    p_country               TEXT    DEFAULT NULL,
    p_match_score_min       NUMERIC DEFAULT NULL,
    p_sort_by               TEXT    DEFAULT 'relevance',
    p_page                  INTEGER DEFAULT 1,
    p_page_size             INTEGER DEFAULT 20
)
RETURNS TABLE (
    candidate_id        UUID,
    full_name           TEXT,
    headline            TEXT,
    country             TEXT,
    top_skills          TEXT[],
    match_score         NUMERIC,
    pool_status         TEXT,
    pool_added_at       TIMESTAMPTZ,
    relevance_score     FLOAT,
    total_count         BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_pool_org  UUID;
    v_org_ids   UUID[];
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    SELECT organization_id INTO v_pool_org FROM public.talent_pools WHERE id = p_talent_pool_id;
    IF v_pool_org IS NULL THEN RAISE EXCEPTION 'talent_pool_not_found'; END IF;

    v_org_ids := public.get_caller_org_ids(v_user_id);

    IF NOT public.is_platform_admin(v_user_id) AND NOT (v_pool_org = ANY(v_org_ids)) THEN
        RAISE EXCEPTION 'access_denied: not a member of the talent pool organization';
    END IF;

    RETURN QUERY
    WITH base AS (
        SELECT
            c.id                AS candidate_id,
            p.full_name::TEXT   AS full_name,
            cp.headline::TEXT   AS headline,
            cp.country_code::TEXT AS country,
            ARRAY(
                SELECT cs.skill_name FROM public.candidate_skills cs
                WHERE cs.candidate_id = c.id
                ORDER BY cs.is_verified DESC LIMIT 5
            )::TEXT[]           AS top_skills,
            (
                SELECT final_score FROM public.matching_runs
                WHERE candidate_id = c.id AND status = 'completed'
                ORDER BY created_at DESC LIMIT 1
            )                   AS match_score,
            tpm.status::TEXT    AS pool_status,
            tpm.created_at      AS pool_added_at,
            CASE
                WHEN p_query_text IS NOT NULL AND csd.search_vector IS NOT NULL THEN
                    ts_rank_cd(csd.search_vector, plainto_tsquery('english', p_query_text))
                ELSE 0.0
            END                 AS relevance_score
        FROM public.talent_pool_members tpm
        JOIN public.candidates c ON c.id = tpm.candidate_id
        JOIN public.profiles p ON p.id = c.user_id
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        LEFT JOIN public.candidate_search_documents csd ON csd.candidate_id = c.id AND csd.organization_scope IS NULL
        WHERE tpm.talent_pool_id = p_talent_pool_id
          AND tpm.status = 'active'
          AND (p_query_text IS NULL OR csd.search_vector @@ plainto_tsquery('english', p_query_text))
          AND (p_skills IS NULL OR EXISTS (
              SELECT 1 FROM public.candidate_skills cs
              WHERE cs.candidate_id = c.id AND cs.normalized_skill_name = ANY(p_skills)
          ))
          AND (p_country IS NULL OR cp.country_code ILIKE p_country)
          AND (p_match_score_min IS NULL OR (
              SELECT final_score FROM public.matching_runs
              WHERE candidate_id = c.id AND status = 'completed'
              ORDER BY created_at DESC LIMIT 1
          ) >= p_match_score_min)
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM base)
    SELECT candidate_id, full_name, headline, country, top_skills, match_score,
           pool_status, pool_added_at, relevance_score, total_count
    FROM counted
    ORDER BY
        CASE WHEN p_sort_by = 'relevance'   THEN relevance_score END DESC NULLS LAST,
        CASE WHEN p_sort_by = 'match_score' THEN match_score END     DESC NULLS LAST,
        candidate_id ASC
    LIMIT LEAST(COALESCE(p_page_size,20), 50)
    OFFSET (GREATEST(COALESCE(p_page,1),1) - 1) * LEAST(COALESCE(p_page_size,20), 50);
END;
$$;

-- =============================================================================
-- 21. SEMANTIC SEARCH CANDIDATES (Foundation — requires embeddings pre-computed)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.semantic_search_candidates(
    p_query_embedding   vector(1536),
    p_min_similarity    FLOAT       DEFAULT 0.65,
    p_skills            TEXT[]      DEFAULT NULL,
    p_country           TEXT        DEFAULT NULL,
    p_page              INTEGER     DEFAULT 1,
    p_page_size         INTEGER     DEFAULT 20
)
RETURNS TABLE (
    candidate_id        UUID,
    full_name           TEXT,
    headline            TEXT,
    similarity_score    FLOAT,
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

    IF NOT public.is_platform_admin(v_user_id) AND (array_length(v_org_ids,1) IS NULL OR array_length(v_org_ids,1) = 0) THEN
        RAISE EXCEPTION 'insufficient_permissions';
    END IF;

    -- Rate limit: max 10 semantic searches per minute
    IF NOT public.check_search_rate_limit(v_user_id, 'semantic', 60, 10) THEN
        RAISE EXCEPTION 'rate_limit_exceeded: semantic search limit reached';
    END IF;

    RETURN QUERY
    WITH sims AS (
        SELECT
            se.entity_id                                            AS candidate_id,
            1 - (se.embedding <=> p_query_embedding)               AS similarity_score
        FROM public.search_embeddings se
        WHERE se.entity_type = 'candidate'
          AND 1 - (se.embedding <=> p_query_embedding) >= p_min_similarity
    ),
    filtered AS (
        SELECT
            s.candidate_id,
            pr.full_name::TEXT  AS full_name,
            cp.headline::TEXT   AS headline,
            s.similarity_score
        FROM sims s
        JOIN public.candidates c ON c.id = s.candidate_id AND c.status = 'active'
        JOIN public.profiles pr ON pr.id = c.user_id
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        WHERE
            (public.is_platform_admin(v_user_id) OR EXISTS (
                SELECT 1 FROM public.organization_members om
                WHERE om.user_id = v_user_id AND om.status = 'active'
                  AND om.organization_id = ANY(v_org_ids)
            ))
            AND (p_skills IS NULL OR EXISTS (
                SELECT 1 FROM public.candidate_skills cs
                WHERE cs.candidate_id = c.id AND cs.normalized_skill_name = ANY(p_skills)
            ))
            AND (p_country IS NULL OR cp.country_code ILIKE p_country)
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM filtered)
    SELECT candidate_id, full_name, headline, similarity_score::FLOAT, total_count
    FROM counted
    ORDER BY similarity_score DESC, candidate_id ASC
    LIMIT LEAST(COALESCE(p_page_size,20), 50)
    OFFSET (GREATEST(COALESCE(p_page,1),1) - 1) * LEAST(COALESCE(p_page_size,20), 50);
END;
$$;

-- =============================================================================
-- 22. SEMANTIC SEARCH JOBS
-- =============================================================================
CREATE OR REPLACE FUNCTION public.semantic_search_jobs(
    p_query_embedding   vector(1536),
    p_min_similarity    FLOAT   DEFAULT 0.60,
    p_country           TEXT    DEFAULT NULL,
    p_workplace_type    TEXT    DEFAULT NULL,
    p_page              INTEGER DEFAULT 1,
    p_page_size         INTEGER DEFAULT 20
)
RETURNS TABLE (
    job_id              UUID,
    title               TEXT,
    country             TEXT,
    workplace_type      TEXT,
    similarity_score    FLOAT,
    semantic_details    JSONB,
    total_count         BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
BEGIN
    -- Public candidates and authenticated users can semantic-search jobs
    RETURN QUERY
    WITH sims AS (
        SELECT
            se.entity_id                                        AS job_id,
            1 - (se.embedding <=> p_query_embedding)           AS similarity_score
        FROM public.search_embeddings se
        WHERE se.entity_type = 'job'
          AND 1 - (se.embedding <=> p_query_embedding) >= p_min_similarity
    ),
    filtered AS (
        SELECT
            s.job_id,
            j.title::TEXT           AS title,
            j.country::TEXT         AS country,
            j.workplace_type::TEXT  AS workplace_type,
            s.similarity_score,
            jsonb_build_object(
                'semantic_similarity', ROUND(s.similarity_score::NUMERIC, 4),
                'note', 'Semantic similarity is a relevance signal, not a qualification proof'
            ) AS semantic_details
        FROM sims s
        JOIN public.jobs j ON j.id = s.job_id
            AND j.status = 'published'
            AND j.visibility = 'public'
            AND (j.application_deadline IS NULL OR j.application_deadline > now())
        LEFT JOIN public.organizations o ON o.id = j.organization_id AND o.status = 'active'
        WHERE
            (p_country IS NULL OR j.country ILIKE p_country)
            AND (p_workplace_type IS NULL OR j.workplace_type = p_workplace_type)
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM filtered)
    SELECT job_id, title, country, workplace_type, similarity_score::FLOAT, semantic_details, total_count
    FROM counted
    ORDER BY similarity_score DESC, job_id ASC
    LIMIT LEAST(COALESCE(p_page_size,20), 50)
    OFFSET (GREATEST(COALESCE(p_page,1),1) - 1) * LEAST(COALESCE(p_page_size,20), 50);
END;
$$;

-- =============================================================================
-- 23. HYBRID SEARCH CANDIDATES (FTS + Semantic + Structured)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.hybrid_search_candidates(
    p_query_text        TEXT            DEFAULT NULL,
    p_query_embedding   vector(1536)    DEFAULT NULL,
    p_skills            TEXT[]          DEFAULT NULL,
    p_country           TEXT            DEFAULT NULL,
    p_match_score_min   NUMERIC         DEFAULT NULL,
    p_fts_weight        FLOAT           DEFAULT 0.4,
    p_semantic_weight   FLOAT           DEFAULT 0.35,
    p_match_weight      FLOAT           DEFAULT 0.15,
    p_completion_weight FLOAT           DEFAULT 0.10,
    p_page              INTEGER         DEFAULT 1,
    p_page_size         INTEGER         DEFAULT 20
)
RETURNS TABLE (
    candidate_id        UUID,
    full_name           TEXT,
    headline            TEXT,
    fts_score           FLOAT,
    semantic_score      FLOAT,
    match_score         NUMERIC,
    hybrid_score        FLOAT,
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

    IF NOT public.is_platform_admin(v_user_id)
       AND (array_length(v_org_ids,1) IS NULL OR array_length(v_org_ids,1) = 0) THEN
        RAISE EXCEPTION 'insufficient_permissions';
    END IF;

    RETURN QUERY
    WITH fts_results AS (
        SELECT
            c.id AS candidate_id,
            CASE
                WHEN p_query_text IS NOT NULL AND csd.search_vector IS NOT NULL THEN
                    LEAST(ts_rank_cd(csd.search_vector, plainto_tsquery('english', p_query_text))::FLOAT, 1.0)
                ELSE 0.0
            END AS fts_score
        FROM public.candidates c
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        LEFT JOIN public.candidate_search_documents csd ON csd.candidate_id = c.id AND csd.organization_scope IS NULL
        WHERE c.status = 'active'
          AND (p_query_text IS NULL OR csd.search_vector @@ plainto_tsquery('english', p_query_text))
          AND (p_skills IS NULL OR EXISTS (
              SELECT 1 FROM public.candidate_skills cs
              WHERE cs.candidate_id = c.id AND cs.normalized_skill_name = ANY(p_skills)
          ))
          AND (p_country IS NULL OR cp.country_code ILIKE p_country)
    ),
    sem_results AS (
        SELECT
            se.entity_id AS candidate_id,
            GREATEST(1 - (se.embedding <=> p_query_embedding), 0)::FLOAT AS semantic_score
        FROM public.search_embeddings se
        WHERE se.entity_type = 'candidate'
          AND p_query_embedding IS NOT NULL
    ),
    combined AS (
        SELECT
            COALESCE(f.candidate_id, s.candidate_id) AS candidate_id,
            COALESCE(f.fts_score, 0.0)               AS fts_score,
            COALESCE(s.semantic_score, 0.0)           AS semantic_score
        FROM fts_results f
        FULL OUTER JOIN sem_results s ON s.candidate_id = f.candidate_id
    ),
    scored AS (
        SELECT
            cm.candidate_id,
            pr.full_name::TEXT  AS full_name,
            cp.headline::TEXT   AS headline,
            cm.fts_score,
            cm.semantic_score,
            mr.final_score      AS match_score,
            -- Hybrid score formula (documented and configurable)
            (
                cm.fts_score * p_fts_weight +
                cm.semantic_score * p_semantic_weight +
                COALESCE(mr.final_score / 100.0, 0) * p_match_weight +
                (c.profile_completion_percentage / 100.0) * p_completion_weight
            )::FLOAT AS hybrid_score
        FROM combined cm
        JOIN public.candidates c ON c.id = cm.candidate_id AND c.status = 'active'
        JOIN public.profiles pr ON pr.id = c.user_id
        LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
        LEFT JOIN LATERAL (
            SELECT final_score FROM public.matching_runs
            WHERE candidate_id = c.id AND status = 'completed'
            ORDER BY created_at DESC LIMIT 1
        ) mr ON true
        WHERE
            (public.is_platform_admin(v_user_id) OR EXISTS (
                SELECT 1 FROM public.organization_members om
                WHERE om.user_id = v_user_id AND om.status = 'active'
                  AND om.organization_id = ANY(v_org_ids)
            ))
            AND (p_match_score_min IS NULL OR COALESCE(mr.final_score, 0) >= p_match_score_min)
    ),
    counted AS (SELECT *, COUNT(*) OVER() AS total_count FROM scored)
    SELECT candidate_id, full_name, headline, fts_score, semantic_score, match_score, hybrid_score, total_count
    FROM counted
    ORDER BY hybrid_score DESC, candidate_id ASC
    LIMIT LEAST(COALESCE(p_page_size,20), 50)
    OFFSET (GREATEST(COALESCE(p_page,1),1) - 1) * LEAST(COALESCE(p_page_size,20), 50);
END;
$$;

-- =============================================================================
-- 24. AUTOCOMPLETE FUNCTIONS
-- =============================================================================

-- Autocomplete skills (public — uses normalized skill names from candidate_skills)
CREATE OR REPLACE FUNCTION public.autocomplete_skills(p_prefix TEXT, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (skill_name TEXT, occurrence_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT normalized_skill_name AS skill_name, COUNT(*) AS occurrence_count
    FROM public.candidate_skills
    WHERE normalized_skill_name ILIKE (p_prefix || '%')
    GROUP BY normalized_skill_name
    ORDER BY occurrence_count DESC, normalized_skill_name ASC
    LIMIT LEAST(p_limit, 30);
$$;

-- Autocomplete locations (public — uses candidate_profiles country+city)
CREATE OR REPLACE FUNCTION public.autocomplete_locations(p_prefix TEXT, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (location_label TEXT, occurrence_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT location_label, SUM(cnt) AS occurrence_count
    FROM (
        SELECT (city || ', ' || country_code) AS location_label, COUNT(*) AS cnt
        FROM public.candidate_profiles
        WHERE city IS NOT NULL AND country_code IS NOT NULL
          AND (city ILIKE (p_prefix || '%') OR country_code ILIKE (p_prefix || '%'))
        GROUP BY city, country_code

        UNION ALL

        SELECT country_code AS location_label, COUNT(*) AS cnt
        FROM public.candidate_profiles
        WHERE country_code ILIKE (p_prefix || '%')
        GROUP BY country_code
    ) sub
    GROUP BY location_label
    ORDER BY occurrence_count DESC, location_label ASC
    LIMIT LEAST(p_limit, 30);
$$;

-- Autocomplete jobs (public — only published jobs)
CREATE OR REPLACE FUNCTION public.autocomplete_jobs(p_prefix TEXT, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (job_title TEXT, job_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT DISTINCT title AS job_title, id AS job_id
    FROM public.jobs
    WHERE status = 'published'
      AND visibility = 'public'
      AND title ILIKE (p_prefix || '%')
      AND (application_deadline IS NULL OR application_deadline > now())
    ORDER BY title ASC
    LIMIT LEAST(p_limit, 30);
$$;

-- Autocomplete candidates (RECRUITER ONLY — never public)
CREATE OR REPLACE FUNCTION public.autocomplete_candidates(p_prefix TEXT, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (candidate_id UUID, full_name TEXT, headline TEXT)
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

    IF NOT public.is_platform_admin(v_user_id)
       AND (array_length(v_org_ids,1) IS NULL OR array_length(v_org_ids,1) = 0) THEN
        RAISE EXCEPTION 'insufficient_permissions';
    END IF;

    RETURN QUERY
    SELECT c.id AS candidate_id, p.full_name::TEXT, cp.headline::TEXT
    FROM public.candidates c
    JOIN public.profiles p ON p.id = c.user_id
    LEFT JOIN public.candidate_profiles cp ON cp.candidate_id = c.id
    WHERE c.status = 'active'
      AND p.full_name ILIKE (p_prefix || '%')
      AND (public.is_platform_admin(v_user_id) OR EXISTS (
          SELECT 1 FROM public.organization_members om
          WHERE om.user_id = v_user_id AND om.status = 'active'
            AND om.organization_id = ANY(v_org_ids)
      ))
    ORDER BY p.full_name ASC
    LIMIT LEAST(p_limit, 20);
END;
$$;

-- =============================================================================
-- 25. VALIDATE AI SEARCH FILTERS (Prevents AI from injecting unsafe filters)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.validate_ai_search_filters(p_filters JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_allowed_keys TEXT[] := ARRAY[
        'query_text','skills','languages','language_level',
        'experience_years_min','experience_years_max',
        'country','city','workplace_type','career_level',
        'profile_completion_min','match_score_min',
        'employment_type','experience_level',
        'sort_by','page','page_size','featured_only',
        'category_slug','salary_min','salary_max'
    ];
    v_key TEXT;
    v_validated JSONB := '{}'::JSONB;
BEGIN
    -- Reject any keys not in the allowlist
    FOR v_key IN SELECT jsonb_object_keys(p_filters)
    LOOP
        IF NOT (v_key = ANY(v_allowed_keys)) THEN
            RAISE EXCEPTION 'invalid_search_filter: field "%" is not permitted in AI-generated search filters', v_key;
        END IF;
        v_validated := v_validated || jsonb_build_object(v_key, p_filters->v_key);
    END LOOP;

    -- Block attempt to inject organization_id
    IF p_filters ? 'organization_id' THEN
        RAISE EXCEPTION 'security_violation: organization_id cannot be set via AI search filters';
    END IF;

    RETURN v_validated;
END;
$$;

-- =============================================================================
-- 26. GET SEARCH ANALYTICS
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_search_analytics(
    p_organization_id   UUID    DEFAULT NULL,
    p_search_type       TEXT    DEFAULT NULL,
    p_days              INTEGER DEFAULT 30
)
RETURNS TABLE (
    organization_id     UUID,
    search_type         TEXT,
    period_date         DATE,
    total_searches      INTEGER,
    zero_result_searches INTEGER,
    avg_result_count    NUMERIC,
    semantic_searches   INTEGER,
    top_queries         JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;

    -- Admins can view all orgs; org members can view their own org only
    IF NOT public.is_platform_admin(v_user_id) THEN
        IF p_organization_id IS NULL THEN
            RAISE EXCEPTION 'organization_id required for non-admin users';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members
            WHERE user_id = v_user_id AND organization_id = p_organization_id AND status = 'active'
        ) THEN
            RAISE EXCEPTION 'access_denied';
        END IF;
    END IF;

    RETURN QUERY
    SELECT
        sa.organization_id, sa.search_type::TEXT, sa.period_date,
        sa.total_searches, sa.zero_result_searches, sa.avg_result_count,
        sa.semantic_searches, sa.top_queries
    FROM public.search_analytics sa
    WHERE (p_organization_id IS NULL OR sa.organization_id = p_organization_id)
      AND (p_search_type IS NULL OR sa.search_type = p_search_type)
      AND sa.period_date >= CURRENT_DATE - (p_days || ' days')::INTERVAL
    ORDER BY sa.period_date DESC, sa.search_type ASC;
END;
$$;

-- =============================================================================
-- 27. UPSERT SEARCH EMBEDDING (Idempotent — skips if content_hash unchanged)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.upsert_search_embedding(
    p_entity_type       TEXT,
    p_entity_id         UUID,
    p_embedding         vector(1536),
    p_content_hash      TEXT,
    p_model             TEXT DEFAULT 'text-embedding-ada-002',
    p_version           TEXT DEFAULT 'v1',
    p_provider          TEXT DEFAULT 'openai'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    -- Idempotent: if same hash already exists for this entity+model+version, skip
    SELECT id INTO v_id
    FROM public.search_embeddings
    WHERE entity_type = p_entity_type
      AND entity_id = p_entity_id
      AND embedding_model = p_model
      AND embedding_version = p_version;

    IF FOUND THEN
        -- Only update if content changed
        UPDATE public.search_embeddings
        SET embedding = p_embedding,
            content_hash = p_content_hash,
            updated_at = now()
        WHERE id = v_id
          AND content_hash <> p_content_hash;
    ELSE
        INSERT INTO public.search_embeddings
            (entity_type, entity_id, embedding, embedding_model, embedding_version, embedding_provider, content_hash)
        VALUES (p_entity_type, p_entity_id, p_embedding, p_model, p_version, p_provider, p_content_hash)
        RETURNING id INTO v_id;
    END IF;

    RETURN v_id;
END;
$$;

-- =============================================================================
-- 28. PERMISSIONS & ROLES FOR SEARCH
-- =============================================================================
INSERT INTO public.permissions (key, name, description, category)
VALUES
    ('search.candidates',      'Search Candidates',       'Search and filter the candidate pool',           'search'),
    ('search.jobs',            'Search Jobs',             'Search the job marketplace',                     'search'),
    ('search.applications',    'Search Applications',     'Search and filter applications',                 'search'),
    ('search.talent_pools',    'Search Talent Pools',     'Search within talent pools',                     'search'),
    ('search.semantic',        'Semantic Search',         'Use AI/vector-based semantic search',            'search'),
    ('search.analytics',       'View Search Analytics',   'Access aggregated search usage analytics',       'search'),
    ('search.global',          'Global Search',           'Search across all organizations (admin only)',   'search')
ON CONFLICT (key) DO NOTHING;

-- Map search permissions to roles (using id FK lookups)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
    ('platform_admin',    'search.candidates'),
    ('platform_admin',    'search.jobs'),
    ('platform_admin',    'search.applications'),
    ('platform_admin',    'search.talent_pools'),
    ('platform_admin',    'search.semantic'),
    ('platform_admin',    'search.analytics'),
    ('platform_admin',    'search.global'),
    ('platform_operator', 'search.candidates'),
    ('platform_operator', 'search.jobs'),
    ('platform_operator', 'search.applications'),
    ('platform_operator', 'search.analytics'),
    ('recruiter_manager', 'search.candidates'),
    ('recruiter_manager', 'search.jobs'),
    ('recruiter_manager', 'search.applications'),
    ('recruiter_manager', 'search.talent_pools'),
    ('recruiter_manager', 'search.semantic'),
    ('recruiter_manager', 'search.analytics'),
    ('recruiter',         'search.candidates'),
    ('recruiter',         'search.jobs'),
    ('recruiter',         'search.applications'),
    ('recruiter',         'search.talent_pools'),
    ('recruiter',         'search.semantic'),
    ('recruiter_junior',  'search.candidates'),
    ('recruiter_junior',  'search.jobs'),
    ('client_admin',      'search.jobs'),
    ('client_viewer',     'search.jobs')
) AS v(role_key, permission_key)
JOIN public.roles r ON r.key = v.role_key
JOIN public.permissions p ON p.key = v.permission_key
ON CONFLICT (role_id, permission_id) DO NOTHING;
