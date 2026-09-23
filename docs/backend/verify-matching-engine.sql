-- ============================================================================
-- Hiren Beyond — Task 06 Verification Script: Matching Engine
-- ============================================================================

-- 1. Verify New Tables Exist
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'matching_profiles',
    'match_criteria',
    'skill_aliases',
    'matching_runs',
    'match_dimension_results',
    'match_explanations',
    'match_overrides'
  )
ORDER BY table_name;

-- 2. Verify Row Level Security is Enabled on All Matching Tables
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN (
    'matching_profiles',
    'match_criteria',
    'skill_aliases',
    'matching_runs',
    'match_dimension_results',
    'match_explanations',
    'match_overrides'
  )
ORDER BY tablename;

-- 3. Verify Functions (Engine, Ranking, Recommendations, Overrides, Helpers)
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'normalize_skill_text',
    'get_cefr_level_numeric',
    'get_education_level_numeric',
    'calculate_candidate_job_match',
    'rank_candidates_for_job',
    'get_best_jobs_for_candidate',
    'override_match_score'
  )
ORDER BY routine_name;

-- 4. Verify Global Default Matching Profile
SELECT id, name, is_default, version, configuration->'weights' AS weights
FROM public.matching_profiles
WHERE is_default = true;

-- 5. Verify Common Skill Aliases Seeded
SELECT canonical_skill, alias, normalized_alias, category
FROM public.skill_aliases
WHERE canonical_skill IN ('JavaScript', 'TypeScript', 'React', 'Node.js', 'Python', 'AWS')
ORDER BY canonical_skill, alias;

-- 6. Verify Seeded Permissions
SELECT key, name, category 
FROM public.permissions 
WHERE category = 'matching'
ORDER BY key;

-- 7. Test Skill Normalization Helper
SELECT 
    public.normalize_skill_text('js') AS js_norm,
    public.normalize_skill_text('reactjs') AS react_norm,
    public.normalize_skill_text('typescript') AS ts_norm,
    public.normalize_skill_text('nodejs') AS node_norm,
    public.normalize_skill_text('k8s') AS k8s_norm;

-- 8. Test CEFR & Education Level Numeric Helpers
SELECT 
    public.get_cefr_level_numeric('B2') AS b2_level,
    public.get_cefr_level_numeric('C1') AS c1_level,
    public.get_cefr_level_numeric('native') AS native_level,
    public.get_education_level_numeric('Bachelor of Science') AS bsc_level,
    public.get_education_level_numeric('Master of Business Administration') AS mba_level,
    public.get_education_level_numeric('Ph.D. in Computer Science') AS phd_level;
