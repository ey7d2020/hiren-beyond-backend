// ============================================================
// Hiren Beyond — CV Intelligence Types
// ============================================================
import type { UUID, ISOTimestamp, TimestampedRecord } from './shared';

export type CVProcessingStatus =
  | 'queued' | 'parsing' | 'analyzing' | 'completed' | 'failed';

export interface CVProcessingJob extends TimestampedRecord {
  id: UUID;
  candidate_id: UUID;
  document_id: UUID;
  organization_id: UUID;
  status: CVProcessingStatus;
  error_message: string | null;
  started_at: ISOTimestamp | null;
  completed_at: ISOTimestamp | null;
  retry_count: number;
}

export interface ContactInfo {
  full_name: string | null;
  email: string | null;
  phone: string | null;
  linkedin: string | null;
  github: string | null;
  location: string | null;
}

export interface ParsedWorkExperience {
  company: string;
  title: string;
  start_date: string | null;
  end_date: string | null;
  is_current: boolean;
  description: string | null;
  technologies: string[];
}

export interface ParsedEducation {
  institution: string;
  degree: string | null;
  field: string | null;
  start_year: number | null;
  end_year: number | null;
  gpa: number | null;
}

export interface ParsedSkill {
  name: string;
  category: string | null;
  level: string | null;
}

export interface ParsedLanguage {
  language: string;
  proficiency: string | null;
}

export interface ParsedCertification {
  name: string;
  issuer: string | null;
  issued_date: string | null;
  expires_date: string | null;
}

export interface StructuredCV {
  id: UUID;
  candidate_id: UUID;
  document_id: UUID;
  raw_text: string | null;
  parsed_at: ISOTimestamp;
  confidence_score: number | null;
  contact_info: ContactInfo;
  work_experience: ParsedWorkExperience[];
  education: ParsedEducation[];
  skills: ParsedSkill[];
  languages: ParsedLanguage[];
  certifications: ParsedCertification[];
  summary: string | null;
}

export interface CVAnalysis extends TimestampedRecord {
  id: UUID;
  candidate_id: UUID;
  document_id: UUID;
  organization_id: UUID;
  overall_score: number;
  experience_score: number;
  skills_score: number;
  education_score: number;
  presentation_score: number;
  strengths: string[];
  weaknesses: string[];
  recommendations: string[];
  ai_summary: string | null;
  model_version: string | null;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface QueueCVProcessingArgs {
  p_document_id: UUID;
}

export interface GetCVProcessingStatusArgs {
  p_document_id: UUID;
}
