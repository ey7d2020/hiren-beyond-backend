// ============================================================
// Hiren Beyond — Candidate Domain Types
// ============================================================
import type {
  UUID, ISOTimestamp, ISODate, LanguageCode, CountryCode, CurrencyCode,
  TimestampedRecord, OrganizationScoped, PaginationArgs,
} from './shared';

export type CandidateStatus =
  | 'active' | 'inactive' | 'placed' | 'blacklisted' | 'pending_review';

export type AvailabilityStatus =
  | 'immediately' | 'within_2_weeks' | 'within_1_month'
  | 'within_3_months' | 'not_available';

export type RemotePreference = 'remote' | 'hybrid' | 'onsite' | 'flexible';

export interface Candidate extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  user_id: UUID | null;
  first_name: string;
  last_name: string;
  email: string;
  phone: string | null;
  status: CandidateStatus;
  source: string | null;
  tags: string[];
}

export interface SkillEntry {
  name: string;
  level: 'beginner' | 'intermediate' | 'advanced' | 'expert';
  years?: number;
}

export interface LanguageEntry {
  language: LanguageCode;
  proficiency: 'basic' | 'conversational' | 'professional' | 'native';
}

export interface CandidateProfile extends TimestampedRecord {
  id: UUID;
  candidate_id: UUID;
  headline: string | null;
  summary: string | null;
  years_of_experience: number | null;
  current_title: string | null;
  current_company: string | null;
  expected_salary_min: number | null;
  expected_salary_max: number | null;
  salary_currency: CurrencyCode | null;
  country_code: CountryCode | null;
  city: string | null;
  remote_preference: RemotePreference | null;
  availability_status: AvailabilityStatus | null;
  linkedin_url: string | null;
  github_url: string | null;
  portfolio_url: string | null;
  skills: SkillEntry[];
  languages: LanguageEntry[];
}

export type DocumentType = 'cv' | 'cover_letter' | 'portfolio' | 'certificate' | 'other';
export type DocumentStatus = 'uploading' | 'ready' | 'processing' | 'error' | 'deleted';

export interface CandidateDocument extends TimestampedRecord {
  id: UUID;
  candidate_id: UUID;
  organization_id: UUID;
  document_type: DocumentType;
  file_name: string;
  storage_path: string;
  file_size: number;
  mime_type: string;
  status: DocumentStatus;
  is_primary: boolean;
  uploaded_by: UUID;
}

export interface WorkExperience {
  id: UUID;
  candidate_id: UUID;
  company_name: string;
  title: string;
  start_date: ISODate;
  end_date: ISODate | null;
  is_current: boolean;
  description: string | null;
  location: string | null;
}

export interface Education {
  id: UUID;
  candidate_id: UUID;
  institution: string;
  degree: string | null;
  field_of_study: string | null;
  start_date: ISODate | null;
  end_date: ISODate | null;
  is_current: boolean;
  gpa: number | null;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface CreateCandidateArgs {
  p_first_name: string;
  p_last_name: string;
  p_email: string;
  p_phone?: string;
  p_source?: string;
  p_tags?: string[];
}

export interface UpdateCandidateProfileArgs {
  p_candidate_id: UUID;
  p_headline?: string;
  p_summary?: string;
  p_years_of_experience?: number;
  p_current_title?: string;
  p_current_company?: string;
  p_expected_salary_min?: number;
  p_expected_salary_max?: number;
  p_salary_currency?: CurrencyCode;
  p_country_code?: CountryCode;
  p_city?: string;
  p_remote_preference?: RemotePreference;
  p_availability_status?: AvailabilityStatus;
  p_linkedin_url?: string;
  p_github_url?: string;
  p_portfolio_url?: string;
  p_skills?: SkillEntry[];
  p_languages?: LanguageEntry[];
}

export interface ListCandidatesArgs extends PaginationArgs {
  p_status?: CandidateStatus;
  p_search?: string;
  p_availability?: AvailabilityStatus;
  p_country_code?: CountryCode;
  p_tags?: string[];
}

export interface DocumentUploadArgs {
  p_candidate_id: UUID;
  p_document_type: DocumentType;
  p_file_name: string;
  p_file_size: number;
  p_mime_type: string;
}

export interface DocumentUploadSession {
  document_id: UUID;
  storage_path: string;
  upload_url: string;
  expires_at: ISOTimestamp;
}
