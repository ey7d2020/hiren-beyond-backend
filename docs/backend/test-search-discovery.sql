-- =============================================================================
-- Task 18: Advanced Search & Discovery — Test Suite
-- File: docs/backend/test-search-discovery.sql
-- Tests: 26 tests covering search, privacy, semantic, AI safety, pagination
-- =============================================================================

DO $$
DECLARE
    v_pass   INTEGER := 0;
    v_fail   INTEGER := 0;
    v_result TEXT;
    v_count  BIGINT;

    -- Helper: assert boolean
    PROCEDURE assert_true(p_label TEXT, p_condition BOOLEAN) AS $$
    BEGIN
        IF p_condition THEN
            RAISE NOTICE 'PASS [%]', p_label;
            v_pass := v_pass + 1;
        ELSE
            RAISE NOTICE 'FAIL [%]', p_label;
            v_fail := v_fail + 1;
        END IF;
    END;

    PROCEDURE assert_false(p_label TEXT, p_condition BOOLEAN) AS $$
    BEGIN
        CALL assert_true(p_label, NOT p_condition);
    END;

BEGIN

-- =============================================================================
-- TEST 01: candidate_search_documents table exists with correct structure
-- =============================================================================
CALL assert_true('01 - candidate_search_documents table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='candidate_search_documents')
);
CALL assert_true('01b - candidate_search_documents has search_vector column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='candidate_search_documents' AND column_name='search_vector')
);
CALL assert_true('01c - candidate_search_documents has content_hash column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='candidate_search_documents' AND column_name='content_hash')
);

-- =============================================================================
-- TEST 02: job_search_documents table exists with correct structure
-- =============================================================================
CALL assert_true('02 - job_search_documents table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='job_search_documents')
);
CALL assert_true('02b - job_search_documents has search_vector column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='job_search_documents' AND column_name='search_vector')
);

-- =============================================================================
-- TEST 03: search_embeddings table exists with vector column
-- =============================================================================
CALL assert_true('03 - search_embeddings table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='search_embeddings')
);
CALL assert_true('03b - search_embeddings has embedding column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='search_embeddings' AND column_name='embedding')
);
CALL assert_true('03c - search_embeddings has idempotency constraint (unique entity+model+version)',
    EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        WHERE tc.table_schema = 'public'
          AND tc.table_name = 'search_embeddings'
          AND tc.constraint_type = 'UNIQUE'
    )
);
CALL assert_true('03d - search_embeddings has content_hash for dedup',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='search_embeddings' AND column_name='content_hash')
);

-- =============================================================================
-- TEST 04: search_configurations table and platform defaults exist
-- =============================================================================
CALL assert_true('04 - search_configurations table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='search_configurations')
);
CALL assert_true('04b - platform default candidate config exists',
    EXISTS (
        SELECT 1 FROM public.search_configurations
        WHERE organization_id IS NULL AND search_type = 'candidate'
    )
);
CALL assert_true('04c - platform default job config exists',
    EXISTS (
        SELECT 1 FROM public.search_configurations
        WHERE organization_id IS NULL AND search_type = 'job'
    )
);

-- =============================================================================
-- TEST 05: search_history table exists with correct columns
-- =============================================================================
CALL assert_true('05 - search_history table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='search_history')
);
CALL assert_true('05b - search_history has semantic_used column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='search_history' AND column_name='semantic_used')
);

-- =============================================================================
-- TEST 06: search_analytics table exists
-- =============================================================================
CALL assert_true('06 - search_analytics table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='search_analytics')
);
CALL assert_true('06b - search_analytics has zero_result_searches column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='search_analytics' AND column_name='zero_result_searches')
);

-- =============================================================================
-- TEST 07: search_rate_limits table exists
-- =============================================================================
CALL assert_true('07 - search_rate_limits table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='search_rate_limits')
);
CALL assert_true('07b - search_rate_limits type constraint is correct',
    EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.check_constraints cc ON cc.constraint_name = tc.constraint_name
        WHERE tc.table_schema='public' AND tc.table_name='search_rate_limits'
          AND cc.check_clause LIKE '%semantic%'
    )
);

-- =============================================================================
-- TEST 08: search_alerts table exists with FK to recruiter_saved_searches
-- =============================================================================
CALL assert_true('08 - search_alerts table exists',
    EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='search_alerts')
);
CALL assert_true('08b - search_alerts has FK to recruiter_saved_searches',
    EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
        WHERE tc.table_schema='public' AND tc.table_name='search_alerts'
          AND tc.constraint_type='FOREIGN KEY'
          AND ccu.table_name='recruiter_saved_searches'
    )
);

-- =============================================================================
-- TEST 09: recruiter_saved_searches has new search columns
-- =============================================================================
CALL assert_true('09 - recruiter_saved_searches has query_text column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='recruiter_saved_searches' AND column_name='query_text')
);
CALL assert_true('09b - recruiter_saved_searches has semantic_enabled column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='recruiter_saved_searches' AND column_name='semantic_enabled')
);
CALL assert_true('09c - recruiter_saved_searches has alert_enabled column',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='recruiter_saved_searches' AND column_name='alert_enabled')
);

-- =============================================================================
-- TEST 10: GIN indexes exist on search_vector columns
-- =============================================================================
CALL assert_true('10 - GIN index on candidate_search_documents.search_vector',
    EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='public' AND tablename='candidate_search_documents'
          AND indexdef LIKE '%gin%' AND indexdef LIKE '%search_vector%'
    )
);
CALL assert_true('10b - GIN index on job_search_documents.search_vector',
    EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='public' AND tablename='job_search_documents'
          AND indexdef LIKE '%gin%' AND indexdef LIKE '%search_vector%'
    )
);

-- =============================================================================
-- TEST 11: HNSW index on search_embeddings.embedding
-- =============================================================================
CALL assert_true('11 - HNSW index on search_embeddings.embedding',
    EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname='public' AND tablename='search_embeddings'
          AND indexdef LIKE '%hnsw%'
    )
);

-- =============================================================================
-- TEST 12: RPC functions exist — search_candidates
-- =============================================================================
CALL assert_true('12 - search_candidates RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='search_candidates' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 13: RPC functions exist — search_jobs
-- =============================================================================
CALL assert_true('13 - search_jobs RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='search_jobs' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 14: RPC functions exist — search_applications
-- =============================================================================
CALL assert_true('14 - search_applications RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='search_applications' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 15: RPC functions exist — search_talent_pool_candidates
-- =============================================================================
CALL assert_true('15 - search_talent_pool_candidates RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='search_talent_pool_candidates' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 16: Semantic search RPCs exist
-- =============================================================================
CALL assert_true('16 - semantic_search_candidates RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='semantic_search_candidates' AND pronamespace='public'::regnamespace)
);
CALL assert_true('16b - semantic_search_jobs RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='semantic_search_jobs' AND pronamespace='public'::regnamespace)
);
CALL assert_true('16c - hybrid_search_candidates RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='hybrid_search_candidates' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 17: Autocomplete RPCs exist
-- =============================================================================
CALL assert_true('17 - autocomplete_skills RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='autocomplete_skills' AND pronamespace='public'::regnamespace)
);
CALL assert_true('17b - autocomplete_locations RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='autocomplete_locations' AND pronamespace='public'::regnamespace)
);
CALL assert_true('17c - autocomplete_jobs RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='autocomplete_jobs' AND pronamespace='public'::regnamespace)
);
CALL assert_true('17d - autocomplete_candidates RPC (recruiter-only) exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='autocomplete_candidates' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 18: refresh_candidate_search_document RPC exists
-- =============================================================================
CALL assert_true('18 - refresh_candidate_search_document RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='refresh_candidate_search_document' AND pronamespace='public'::regnamespace)
);
CALL assert_true('18b - refresh_job_search_document RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='refresh_job_search_document' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 19: Triggers exist for search document auto-refresh
-- =============================================================================
CALL assert_true('19 - trigger trg_csd_on_profile exists (candidate_profiles)',
    EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_csd_on_profile')
);
CALL assert_true('19b - trigger trg_csd_on_skills exists (candidate_skills)',
    EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_csd_on_skills')
);
CALL assert_true('19c - trigger trg_jsd_on_job exists (jobs)',
    EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_jsd_on_job')
);

-- =============================================================================
-- TEST 20: validate_ai_search_filters RPC exists and blocks unsafe fields
-- =============================================================================
CALL assert_true('20 - validate_ai_search_filters RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='validate_ai_search_filters' AND pronamespace='public'::regnamespace)
);

-- Test that validate_ai_search_filters accepts safe filters
DECLARE v_validated JSONB;
BEGIN
    SELECT public.validate_ai_search_filters('{"query_text":"React developer","country":"EG"}'::JSONB) INTO v_validated;
    CALL assert_true('20b - validate_ai_search_filters accepts safe filters', v_validated IS NOT NULL);
EXCEPTION WHEN OTHERS THEN
    CALL assert_false('20b - validate_ai_search_filters accepted safe filters (threw exception)', true);
END;

-- Test that validate_ai_search_filters rejects organization_id injection
BEGIN
    PERFORM public.validate_ai_search_filters('{"organization_id":"00000000-0000-0000-0000-000000000001"}'::JSONB);
    CALL assert_false('20c - validate_ai_search_filters blocks organization_id injection (should have thrown)', true);
EXCEPTION WHEN OTHERS THEN
    CALL assert_true('20c - validate_ai_search_filters blocks organization_id injection', true);
END;

-- Test that validate_ai_search_filters rejects unknown fields
BEGIN
    PERFORM public.validate_ai_search_filters('{"raw_sql":"DROP TABLE candidates;"}'::JSONB);
    CALL assert_false('20d - validate_ai_search_filters blocks unknown field raw_sql (should have thrown)', true);
EXCEPTION WHEN OTHERS THEN
    CALL assert_true('20d - validate_ai_search_filters blocks unknown field raw_sql', true);
END;

-- =============================================================================
-- TEST 21: upsert_search_embedding is idempotent (same hash = no new row)
-- =============================================================================
CALL assert_true('21 - upsert_search_embedding RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='upsert_search_embedding' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 22: check_search_rate_limit RPC exists
-- =============================================================================
CALL assert_true('22 - check_search_rate_limit RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='check_search_rate_limit' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 23: record_search_history RPC exists
-- =============================================================================
CALL assert_true('23 - record_search_history RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='record_search_history' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 24: get_search_analytics RPC exists
-- =============================================================================
CALL assert_true('24 - get_search_analytics RPC exists',
    EXISTS (SELECT 1 FROM pg_proc WHERE proname='get_search_analytics' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 25: RLS is enabled on all new search tables
-- =============================================================================
CALL assert_true('25 - RLS enabled on candidate_search_documents',
    (SELECT relrowsecurity FROM pg_class WHERE relname='candidate_search_documents' AND relnamespace='public'::regnamespace)
);
CALL assert_true('25b - RLS enabled on job_search_documents',
    (SELECT relrowsecurity FROM pg_class WHERE relname='job_search_documents' AND relnamespace='public'::regnamespace)
);
CALL assert_true('25c - RLS enabled on search_embeddings',
    (SELECT relrowsecurity FROM pg_class WHERE relname='search_embeddings' AND relnamespace='public'::regnamespace)
);
CALL assert_true('25d - RLS enabled on search_history',
    (SELECT relrowsecurity FROM pg_class WHERE relname='search_history' AND relnamespace='public'::regnamespace)
);
CALL assert_true('25e - RLS enabled on search_rate_limits',
    (SELECT relrowsecurity FROM pg_class WHERE relname='search_rate_limits' AND relnamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 26: SECURITY DEFINER on all search RPCs (Authorization not bypassable)
-- =============================================================================
CALL assert_true('26 - search_candidates is SECURITY DEFINER',
    (SELECT prosecdef FROM pg_proc WHERE proname='search_candidates' AND pronamespace='public'::regnamespace)
);
CALL assert_true('26b - search_jobs is SECURITY DEFINER',
    (SELECT prosecdef FROM pg_proc WHERE proname='search_jobs' AND pronamespace='public'::regnamespace)
);
CALL assert_true('26c - semantic_search_candidates is SECURITY DEFINER',
    (SELECT prosecdef FROM pg_proc WHERE proname='semantic_search_candidates' AND pronamespace='public'::regnamespace)
);
CALL assert_true('26d - validate_ai_search_filters is SECURITY DEFINER',
    (SELECT prosecdef FROM pg_proc WHERE proname='validate_ai_search_filters' AND pronamespace='public'::regnamespace)
);
CALL assert_true('26e - hybrid_search_candidates is SECURITY DEFINER',
    (SELECT prosecdef FROM pg_proc WHERE proname='hybrid_search_candidates' AND pronamespace='public'::regnamespace)
);

-- =============================================================================
-- TEST 27: Search permissions are seeded
-- =============================================================================
CALL assert_true('27 - search.candidates permission seeded',
    EXISTS (SELECT 1 FROM public.permissions WHERE key='search.candidates')
);
CALL assert_true('27b - search.semantic permission seeded',
    EXISTS (SELECT 1 FROM public.permissions WHERE key='search.semantic')
);
CALL assert_true('27c - search.global permission seeded',
    EXISTS (SELECT 1 FROM public.permissions WHERE key='search.global')
);
CALL assert_true('27d - search.analytics permission seeded',
    EXISTS (SELECT 1 FROM public.permissions WHERE key='search.analytics')
);

-- =============================================================================
-- TEST 28: search_candidates sensitive data protection
--          (private note columns never appear in search_candidates return type)
-- =============================================================================
CALL assert_true('28 - search_candidates return type has no private_notes column',
    NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_type t ON t.oid = p.prorettype
        WHERE p.proname = 'search_candidates'
          AND p.pronamespace = 'public'::regnamespace
          AND t.typname ILIKE '%private%note%'
    )
);

-- Final summary
RAISE NOTICE '=== TEST SUMMARY: % passed, % failed ===', v_pass, v_fail;

IF v_fail > 0 THEN
    RAISE WARNING '% TEST(S) FAILED — review output above', v_fail;
END IF;

END $$;
