# Task 18 — Advanced Search & Discovery

**Migration:** `20260915001800_advanced_search_discovery.sql`
**Status:** ✅ COMPLETE — Deployed to remote Supabase

---

## Architecture Overview

Hiren Beyond's search layer sits **above** the source-of-truth tables.
It never duplicates authoritative records — it derives fast-queryable projections
and enforces all authorization before returning results.

```
Search Request
      ↓
validate_ai_search_filters()   ← blocks unsafe AI-generated params
      ↓
Authorization check            ← SECURITY DEFINER + get_caller_org_ids()
      ↓
Full-Text Search               ← tsvector GIN index on *_search_documents
      ↓
Structured Filters             ← B-tree indexes on candidates / jobs tables
      ↓
Optional Semantic Search       ← HNSW vector index on search_embeddings
      ↓
Relevance Ranking              ← ts_rank_cd (FTS) or cosine similarity (semantic)
      ↓
Stable Pagination              ← LIMIT/OFFSET + deterministic tie-breaker (entity_id ASC)
      ↓
Safe Result Projection         ← no private notes / hidden fields returned
```

---

## New Tables (8)

| Table | Purpose |
|-------|---------|
| `search_configurations` | Per-org / platform KV config for weights, limits, fields |
| `candidate_search_documents` | Derived FTS projection of candidate public data |
| `job_search_documents` | Derived FTS projection of job public data |
| `search_embeddings` | Vector embeddings (1536-dim, HNSW index) |
| `search_history` | Per-user search log (never shared publicly) |
| `search_analytics` | Org-level aggregated metrics (popular queries, zero-results) |
| `search_rate_limits` | Sliding-window abuse protection for expensive operations |
| `search_alerts` | Foundation for saved-search alert notifications |

**Additive columns on existing tables:**
- `recruiter_saved_searches`: `query_text`, `semantic_enabled`, `alert_enabled`

---

## Candidate Search Document

`candidate_search_documents` is built from:
- `candidate_profiles`: headline, professional_summary, current_title
- `candidate_cv_profiles`: headline, summary (from CV extraction)
- `candidate_skills`: normalized skill names
- `candidate_languages`: language name + proficiency level
- `candidate_experience`: job titles + company names
- `candidate_education`: institution + field of study
- `candidate_certifications`: cert names

**Never included:**
- Recruiter private notes
- Internal hiring discussions
- Private client feedback
- Confidential assessment recordings
- Salary / billing data

---

## Job Search Document

`job_search_documents` is built from:
- `jobs`: title, short_description, description, country, city, workplace_type, employment_type, experience_level
- `job_categories`: category name
- `job_skills`: skill names
- `job_languages`: language names

---

## Indexes

| Index | Type | Table | Column |
|-------|------|-------|--------|
| `idx_csd_vector` | GIN | `candidate_search_documents` | `search_vector` |
| `idx_jsd_vector` | GIN | `job_search_documents` | `search_vector` |
| `idx_embeddings_vector` | HNSW (cosine) | `search_embeddings` | `embedding` |
| `idx_csd_hash` | B-tree | `candidate_search_documents` | `content_hash` |
| `idx_jsd_hash` | B-tree | `job_search_documents` | `content_hash` |

---

## RPC Functions (15)

| Function | Access | Purpose |
|----------|--------|---------|
| `search_candidates(...)` | Recruiter | Full-text + structured filter candidate search |
| `search_jobs(...)` | Public / Recruiter | FTS job search with marketplace rule enforcement |
| `search_applications(...)` | Recruiter | Application search with ATS/match filters |
| `search_talent_pool_candidates(...)` | Recruiter | Candidate search within a specific talent pool |
| `semantic_search_candidates(...)` | Recruiter | Vector similarity candidate search |
| `semantic_search_jobs(...)` | Public | Vector similarity job search |
| `hybrid_search_candidates(...)` | Recruiter | Weighted FTS + semantic + match + completion |
| `autocomplete_skills(...)` | Public | Skill name suggestions (no private data) |
| `autocomplete_locations(...)` | Public | City/country suggestions |
| `autocomplete_jobs(...)` | Public | Published job title suggestions |
| `autocomplete_candidates(...)` | Recruiter | Candidate name suggestions (auth required) |
| `refresh_candidate_search_document(...)` | System | Rebuild candidate search text + tsvector |
| `refresh_job_search_document(...)` | System | Rebuild job search text + tsvector |
| `validate_ai_search_filters(...)` | System | Allowlist filter fields, reject SQL/unsafe keys |
| `record_search_history(...)` | Authenticated | Log a search event for the current user |
| `get_search_analytics(...)` | Recruiter/Admin | Aggregated search metrics |
| `upsert_search_embedding(...)` | System | Idempotent embedding store/update |
| `check_search_rate_limit(...)` | System | Sliding-window rate limit enforcement |
| `get_caller_org_ids(...)` | System helper | Returns caller's authorized organization IDs |

---

## Search Relevance vs Match Score vs Semantic Similarity

See also: `docs/backend/search-ranking-standard.md`

| Metric | Definition | Source | Used In |
|--------|-----------|--------|---------|
| **FTS Relevance** | `ts_rank_cd(tsvector, query)` — 0.0-1.0, how well the text matches | GIN FTS index | FTS search result ordering |
| **Semantic Similarity** | Cosine similarity between query embedding and entity embedding — 0.0-1.0 | HNSW vector index | Semantic search ordering |
| **Match Score** | Business-level candidate↔job fit score — 0-100 | Task 06 matching engine | ATS pipeline, recruiter decisions |
| **Hybrid Score** | Configurable weighted combination of the above three | `hybrid_search_candidates()` | Hybrid search ordering |

> **IMPORTANT:** Search Relevance ≠ Match Score ≠ Semantic Similarity.
> They must never be presented as equivalent metrics to users or clients.

---

## Hybrid Search Formula

```
hybrid_score =
    fts_score   × p_fts_weight        (default 0.40)
  + sem_score   × p_semantic_weight   (default 0.35)
  + match/100   × p_match_weight      (default 0.15)
  + completion  × p_completion_weight (default 0.10)
```

Weights are configurable per-call and stored in `search_configurations`.

---

## Semantic Search Foundation

- Vector type: `vector(1536)` (compatible with OpenAI `text-embedding-ada-002` / `text-embedding-3-small`)
- Index: HNSW with `vector_cosine_ops` for fast ANN search
- Provider abstraction: `embedding_provider` field supports `openai`, `google`, `anthropic`, `cohere`, `custom`
- Idempotency: `UNIQUE (entity_type, entity_id, embedding_model, embedding_version)` prevents duplicate computation
- Hash-based change detection: `content_hash` (md5) prevents re-embedding unchanged content
- Generation: asynchronous (never synchronous during a search request)

> **IMPORTANT:** `semantic_search_*` functions require embeddings to be pre-computed.
> Without populated `search_embeddings`, semantic results will be empty.
> This is by design — the foundation is in place; embedding pipeline is a separate concern.

---

## Search Index Refresh

Triggers auto-refresh `candidate_search_documents` when source data changes:
- `trg_csd_on_profile` → `candidate_profiles`
- `trg_csd_on_skills` → `candidate_skills`
- `trg_csd_on_languages` → `candidate_languages`
- `trg_csd_on_experience` → `candidate_experience`
- `trg_csd_on_education` → `candidate_education`
- `trg_csd_on_certifications` → `candidate_certifications`

Job search documents refresh on:
- `trg_jsd_on_job` → `jobs`
- `trg_jsd_on_skills` → `job_skills`
- `trg_jsd_on_languages` → `job_languages`

**Versioning:** Each refresh increments `index_version` only when `content_hash` changes.

---

## Authorization Model

### Recruiters
- `search_candidates()`: scoped to their org(s) via `get_caller_org_ids()` (never trust caller-supplied org_id)
- `search_jobs()`: scoped to their org via `p_organization_id` + membership check
- `search_applications()`: scoped to org jobs
- `search_talent_pool_candidates()`: validates pool org membership

### Candidates (Public)
- `search_jobs()`: public mode — only `published + public + active org + not expired`
- `autocomplete_*`: skill, location, job autocomplete are public-safe
- Cannot call `search_candidates()` or `autocomplete_candidates()`

### Clients
- Can use `search_jobs()` in public mode only
- Cannot search candidate pool (no `search.candidates` permission)

### Platform Admin
- All search functions with global scope (NULL org filter in `get_caller_org_ids()`)

### Anonymous
- `search_jobs()` public mode only
- `autocomplete_skills()`, `autocomplete_locations()`, `autocomplete_jobs()` only

---

## AI Search Safety

1. `validate_ai_search_filters()` enforces a strict allowlist of 20 safe filter keys
2. `organization_id` is explicitly blocked — org scope always derived server-side
3. No arbitrary SQL execution path exists in any search RPC
4. Unknown/unsafe field names throw `invalid_search_filter` exception
5. Match score is always from Task 06 matching engine — AI cannot inject a synthetic score

---

## Rate Limiting

`check_search_rate_limit()` enforces sliding-window limits per user per search type:
- Default: 10 semantic searches / 60 seconds
- Default config stored in `search_configurations.configuration.rate_limit_*`
- `search_rate_limits` table tracks per-user windowed request counts

---

## Pagination Contract

All search RPCs return:
```
items[]        — result rows
total_count    — total matching rows (via COUNT(*) OVER())
```

Caller derives:
```
page           — current page
page_size      — items per page (max 50)
has_more       — total_count > page * page_size
```

Stable ordering uses `entity_id ASC` as tie-breaker to prevent inconsistent pages when scores tie.

---

## Privacy

- `candidate_search_documents` is a derived projection — never a copy of private data
- RLS prevents anonymous or unauthorized access to candidate documents
- Search results never include: private_notes, recruiter_notes, internal_feedback, assessment_recordings
- Sensitive fields are excluded by the search projection query design (not just filtered out)

---

## Deployment

```bash
supabase db push
# Applied: 20260915001800_advanced_search_discovery.sql
```

---

## Test Results — 28/28 Tests Passed

All 28 tests in `docs/backend/test-search-discovery.sql` passed, verifying:
- Table structure and GIN/HNSW indexes
- Search document fields and content_hash for versioning
- RPC existence and SECURITY DEFINER coverage
- RLS enabled on all new tables
- AI filter validation (safe accept + org_id block + unknown field block)
- Trigger existence for auto-refresh
- Permission seeding
- Sensitive field exclusion from search result types

---

## Blockers

None. Task 18 is fully deployed and operational.

> **Note:** Semantic search requires `search_embeddings` to be populated by
> an external embedding pipeline (OpenAI API, Google, etc.). The schema,
> indexes, and RPCs are in place. Activation of live semantic search is
> a configuration/infrastructure step, not a blocker for the search layer itself.
