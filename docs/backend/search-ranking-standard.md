# Hiren Beyond Search Ranking Standard

This document defines the three distinct relevance signals used in Hiren Beyond's
Advanced Search & Discovery system. These signals MUST NOT be treated as equivalent
or interchangeable.

---

## 1. Search Relevance (Full-Text Score)

**Definition:** How well a document's text matches a search query using PostgreSQL
full-text search.

**Source:** `ts_rank_cd(search_vector, plainto_tsquery('english', query_text))`

**Range:** 0.0 (no match) to 1.0 (strong match) — normalized by ts_rank_cd

**Computed by:** `search_candidates()`, `search_jobs()`

**Interpretation:**
> "This document contains the search terms the recruiter typed."

**NOT equivalent to:** candidate qualification, match score, or semantic meaning.

---

## 2. Match Score (Business Fit Score)

**Definition:** A structured, multi-dimensional assessment of how well a specific
candidate fits a specific job, computed by the Hiren Beyond Matching Engine (Task 06).

**Source:** `matching_runs.final_score` — computed by `run_candidate_job_matching()`

**Range:** 0–100 (integer or decimal, represents percentage fit)

**Dimensions:** Skills, language proficiency, experience, education, location,
availability, certifications, ATS history

**Computed by:** Task 06 Matching Engine (never recomputed inside search)

**Interpretation:**
> "This candidate is estimated to be X% qualified for this specific job, based
> on structured assessment of their verified attributes."

**NOT equivalent to:** text relevance, semantic similarity, or profile completeness.

**IMPORTANT:** The search engine NEVER recomputes Match Score. It only filters
and sorts by the pre-computed value from `matching_runs`. Creating a new "match
score" inside the search layer is explicitly prohibited.

---

## 3. Semantic Similarity

**Definition:** Cosine similarity between an embedding vector of the search query
and an embedding vector of a candidate or job document.

**Source:** `1 - (search_embeddings.embedding <=> query_embedding)` (cosine distance → similarity)

**Range:** 0.0 (no semantic similarity) to 1.0 (identical meaning)

**Computed by:** `semantic_search_candidates()`, `semantic_search_jobs()`, `hybrid_search_candidates()`

**Interpretation:**
> "The meaning of this document is semantically close to the search query."

**NOT equivalent to:** candidate qualification, text keyword presence, or match score.

**IMPORTANT:** Semantic similarity is a relevance signal only. It must never be
presented as proof of candidate qualification or job fit.

---

## 4. Hybrid Score (Composite Ranking Signal)

**Definition:** A configurable weighted combination of the three signals above,
used to produce a unified ranking for hybrid search.

**Formula:**
```
hybrid_score =
    fts_score          × fts_weight        (default 0.40)
  + semantic_score     × semantic_weight   (default 0.35)
  + (match_score/100)  × match_weight      (default 0.15)
  + (completion/100)   × completion_weight (default 0.10)
```

**Weights:** Configurable per-request and stored in `search_configurations`.

**Interpretation:**
> "A composite signal for sorting results in hybrid search mode. Not a
> standalone qualification metric."

**NOT equivalent to:** any individual signal above. Must not be displayed to
candidates as a "fit score."

---

## Summary Table

| Signal | Range | Source | Meaning | Recomputed in Search? |
|--------|-------|--------|---------|----------------------|
| FTS Relevance | 0.0–1.0 | tsvector GIN index | Text keyword match | No (index lookup) |
| Semantic Similarity | 0.0–1.0 | HNSW vector index | Semantic meaning proximity | No (vector lookup) |
| Match Score | 0–100 | Task 06 matching engine | Structured candidate-job fit | NEVER |
| Hybrid Score | 0.0–1.0 | Weighted formula | Composite ranking signal | N/A (composite) |

---

## Rules for Implementation

1. **Never display Match Score as a Search Relevance Score** to users.
2. **Never display Semantic Similarity as a qualification proof** to candidates.
3. **Never recompute Match Score inside the search layer** — always read from `matching_runs`.
4. **Always document the hybrid formula** when weights are non-default.
5. **Provide semantic explainability context** when returning semantic similarity scores
   (see `semantic_details` field in `semantic_search_jobs()`).
