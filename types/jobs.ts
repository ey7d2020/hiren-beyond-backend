// ============================================================
// Hiren Beyond — Jobs & Marketplace Types
// ============================================================
import type {
  UUID, ISOTimestamp, ISODate, CountryCode, CurrencyCode,
  TimestampedRecord, OrganizationScoped, PaginationArgs,
} from './shared';

export type JobStatus = 'draft' | 'published' | 'closed' | 'archived' | 'on_hold';
export type JobType = 'full_time' | 'part_time' | 'contract' | 'internship' | 'freelance';
export type ExperienceLevel = 'entry' | 'mid' | 'senior' | 'lead' | 'executive';
export type RequirementType = 'skill' | 'experience' | 'education' | 'language' | 'certification' | 'other';

export interface Job extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  title: string;
  description: string | null;
  status: JobStatus;
  job_type: JobType;
  experience_level: ExperienceLevel | null;
  location: string | null;
  country_code: CountryCode | null;
  is_remote: boolean;
  salary_min: number | null;
  salary_max: number | null;
  salary_currency: CurrencyCode | null;
  published_at: ISOTimestamp | null;
  closes_at: ISOTimestamp | null;
  department: string | null;
  headcount: number;
  created_by: UUID;
}

export interface JobRequirement {
  id: UUID;
  job_id: UUID;
  requirement_type: RequirementType;
  description: string;
  is_mandatory: boolean;
  weight: number;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface CreateJobArgs {
  p_title: string;
  p_description?: string;
  p_job_type?: JobType;
  p_experience_level?: ExperienceLevel;
  p_location?: string;
  p_country_code?: CountryCode;
  p_is_remote?: boolean;
  p_salary_min?: number;
  p_salary_max?: number;
  p_salary_currency?: CurrencyCode;
  p_closes_at?: ISOTimestamp;
  p_department?: string;
  p_headcount?: number;
}

export interface UpdateJobArgs extends Partial<CreateJobArgs> {
  p_job_id: UUID;
}

export interface PublishJobArgs {
  p_job_id: UUID;
}

export interface CloseJobArgs {
  p_job_id: UUID;
  p_reason?: string;
}

export interface ListJobsArgs extends PaginationArgs {
  p_status?: JobStatus;
  p_job_type?: JobType;
  p_search?: string;
  p_department?: string;
}

export interface AddJobRequirementArgs {
  p_job_id: UUID;
  p_requirement_type: RequirementType;
  p_description: string;
  p_is_mandatory?: boolean;
  p_weight?: number;
}
