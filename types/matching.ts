// ============================================================
// Hiren Beyond — Matching Engine & Talent Pool Types
// ============================================================
import type {
  UUID, ISOTimestamp, JSONObject,
  TimestampedRecord, OrganizationScoped, PaginationArgs,
} from './shared';

export type PoolType = 'manual' | 'smart' | 'saved_search';

export interface MatchScore extends TimestampedRecord {
  id: UUID;
  job_id: UUID;
  candidate_id: UUID;
  organization_id: UUID;
  overall_score: number;
  skills_match: number;
  experience_match: number;
  education_match: number;
  salary_match: number | null;
  location_match: number | null;
  culture_fit: number | null;
  match_explanation: JSONObject | null;
  algorithm_version: string;
  is_manual_override: boolean;
}

export interface CandidateRanking {
  application_id: UUID;
  candidate_id: UUID;
  job_id: UUID;
  overall_score: number;
  ranking_position: number;
  first_name: string;
  last_name: string;
  headline: string | null;
  current_title: string | null;
  years_of_experience: number | null;
  match_explanation: JSONObject | null;
}

export interface TalentPool extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  name: string;
  description: string | null;
  pool_type: PoolType;
  criteria: JSONObject | null;
  candidate_count: number;
  is_active: boolean;
  created_by: UUID;
}

export interface TalentPoolMember {
  id: UUID;
  pool_id: UUID;
  candidate_id: UUID;
  added_at: ISOTimestamp;
  added_by: UUID | null;
  score: number | null;
  notes: string | null;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface TriggerMatchingArgs {
  p_job_id: UUID;
  p_candidate_ids?: UUID[];
  p_force_recalculate?: boolean;
}

export interface BulkScreeningArgs {
  p_job_id: UUID;
  p_min_score?: number;
  p_limit?: number;
}

export interface GetRankedCandidatesArgs extends PaginationArgs {
  p_job_id: UUID;
  p_min_score?: number;
}

export interface CreateTalentPoolArgs {
  p_name: string;
  p_description?: string;
  p_pool_type?: PoolType;
  p_criteria?: JSONObject;
}

export interface AddToPoolArgs {
  p_pool_id: UUID;
  p_candidate_id: UUID;
  p_notes?: string;
}
