// ============================================================
// Hiren Beyond — Assessments & Evaluation Types
// ============================================================
import type {
  UUID, ISOTimestamp, TimestampedRecord, OrganizationScoped,
} from './shared';

export type AssessmentType =
  | 'language' | 'technical' | 'personality' | 'cognitive'
  | 'situational' | 'voice' | 'video' | 'custom';

export type AssessmentStatus = 'draft' | 'active' | 'archived';

export type AssessmentAttemptStatus =
  | 'not_started' | 'in_progress' | 'submitted' | 'evaluating' | 'completed' | 'expired';

export type QuestionType =
  | 'multiple_choice' | 'single_choice' | 'text' | 'audio'
  | 'video' | 'code' | 'rating_scale' | 'file_upload';

export type LanguageLevel = 'A1' | 'A2' | 'B1' | 'B2' | 'C1' | 'C2';
export type ReadinessLabel = 'not_ready' | 'developing' | 'ready' | 'highly_ready';

export interface Assessment extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  name: string;
  description: string | null;
  assessment_type: AssessmentType;
  status: AssessmentStatus;
  time_limit_minutes: number | null;
  passing_score: number | null;
  total_questions: number;
  is_proctored: boolean;
  instructions: string | null;
  created_by: UUID;
}

export interface QuestionOption {
  id: string;
  text: string;
  is_correct?: boolean;
}

export interface AssessmentQuestion {
  id: UUID;
  assessment_id: UUID;
  question_text: string;
  question_type: QuestionType;
  options: QuestionOption[] | null;
  correct_answer: string | null;
  score_weight: number;
  order_index: number;
  media_url: string | null;
}

export interface AssessmentAttempt extends TimestampedRecord {
  id: UUID;
  assessment_id: UUID;
  candidate_id: UUID;
  application_id: UUID | null;
  organization_id: UUID;
  status: AssessmentAttemptStatus;
  score: number | null;
  passed: boolean | null;
  started_at: ISOTimestamp | null;
  submitted_at: ISOTimestamp | null;
  expires_at: ISOTimestamp | null;
  time_taken_seconds: number | null;
}

export interface LanguageAssessmentResult {
  id: UUID;
  attempt_id: UUID;
  candidate_id: UUID;
  overall_level: LanguageLevel;
  reading: LanguageLevel | null;
  writing: LanguageLevel | null;
  listening: LanguageLevel | null;
  speaking: LanguageLevel | null;
  ai_feedback: string | null;
  assessed_at: ISOTimestamp;
}

export interface CandidateReadiness extends TimestampedRecord {
  id: UUID;
  candidate_id: UUID;
  organization_id: UUID;
  readiness_score: number;
  profile_completeness: number;
  assessment_performance: number;
  experience_relevance: number;
  skills_alignment: number;
  readiness_label: ReadinessLabel;
  recommendations: string[];
}

// ─── RPC Args ─────────────────────────────────────────────

export interface AssignAssessmentArgs {
  p_assessment_id: UUID;
  p_candidate_id: UUID;
  p_application_id?: UUID;
  p_expires_in_hours?: number;
}

export interface SubmitAttemptArgs {
  p_attempt_id: UUID;
  p_answers: Array<{ question_id: UUID; answer: string }>;
}
