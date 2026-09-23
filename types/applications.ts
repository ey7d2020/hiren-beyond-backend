// ============================================================
// Hiren Beyond — Applications & ATS Pipeline Types
// ============================================================
import type {
  UUID, ISOTimestamp, JSONObject,
  TimestampedRecord, OrganizationScoped, PaginationArgs,
} from './shared';

export type ApplicationStatus =
  | 'new' | 'in_review' | 'shortlisted' | 'interview'
  | 'offer' | 'hired' | 'rejected' | 'withdrawn';

export type ApplicationSource =
  | 'direct' | 'referral' | 'agency' | 'job_board'
  | 'linkedin' | 'api' | 'import' | 'talent_pool';

export type StageType =
  | 'screening' | 'assessment' | 'interview' | 'offer' | 'hired' | 'rejected' | 'custom';

export interface Application extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  job_id: UUID;
  candidate_id: UUID;
  status: ApplicationStatus;
  source: ApplicationSource | null;
  current_stage_id: UUID | null;
  match_score: number | null;
  ranking_position: number | null;
  cover_letter: string | null;
  applied_at: ISOTimestamp;
  reviewed_at: ISOTimestamp | null;
  reviewed_by: UUID | null;
  rejection_reason: string | null;
}

export interface ATSPipeline extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  job_id: UUID;
  name: string;
  description: string | null;
  is_default: boolean;
}

export interface ATSStage extends TimestampedRecord {
  id: UUID;
  pipeline_id: UUID;
  name: string;
  description: string | null;
  stage_order: number;
  stage_type: StageType;
  color: string | null;
  auto_actions: JSONObject | null;
}

export interface ApplicationStageTransition {
  id: UUID;
  application_id: UUID;
  from_stage_id: UUID | null;
  to_stage_id: UUID;
  transitioned_by: UUID;
  transitioned_at: ISOTimestamp;
  reason: string | null;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface CreateApplicationArgs {
  p_job_id: UUID;
  p_candidate_id: UUID;
  p_source?: ApplicationSource;
  p_cover_letter?: string;
}

export interface MoveApplicationStageArgs {
  p_application_id: UUID;
  p_target_stage_id: UUID;
  p_reason?: string;
}

export interface RejectApplicationArgs {
  p_application_id: UUID;
  p_rejection_reason?: string;
}

export interface ListApplicationsArgs extends PaginationArgs {
  p_job_id?: UUID;
  p_status?: ApplicationStatus;
  p_stage_id?: UUID;
  p_min_score?: number;
}

export interface CreatePipelineArgs {
  p_job_id: UUID;
  p_name: string;
  p_description?: string;
}

export interface AddStageArgs {
  p_pipeline_id: UUID;
  p_name: string;
  p_stage_type: StageType;
  p_stage_order: number;
  p_color?: string;
}
