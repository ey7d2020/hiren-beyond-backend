// ============================================================
// Hiren Beyond — Interviews & Hiring Decision Types
// ============================================================
import type {
  UUID, ISOTimestamp, ISODate, CurrencyCode, TimestampedRecord, OrganizationScoped,
} from './shared';

export type InterviewType =
  | 'phone_screen' | 'video' | 'onsite' | 'technical' | 'panel' | 'hr' | 'final';

export type InterviewStatus =
  | 'scheduled' | 'confirmed' | 'in_progress' | 'completed' | 'cancelled' | 'no_show';

export type HiringRecommendation = 'strong_yes' | 'yes' | 'neutral' | 'no' | 'strong_no';
export type Decision = 'offer_extended' | 'rejected' | 'on_hold' | 'withdrawn';
export type CandidateResponse = 'accepted' | 'declined' | 'negotiating' | 'no_response';

export interface Interview extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  application_id: UUID;
  job_id: UUID;
  candidate_id: UUID;
  interview_type: InterviewType;
  status: InterviewStatus;
  scheduled_at: ISOTimestamp;
  duration_minutes: number;
  location: string | null;
  meeting_url: string | null;
  interviewer_ids: UUID[];
  notes: string | null;
  created_by: UUID;
}

export interface InterviewScheduleSlot {
  id: UUID;
  interviewer_id: UUID;
  start_time: ISOTimestamp;
  end_time: ISOTimestamp;
  is_booked: boolean;
  timezone: string;
}

export interface InterviewFeedback extends TimestampedRecord {
  id: UUID;
  interview_id: UUID;
  interviewer_id: UUID;
  candidate_id: UUID;
  overall_rating: number;
  technical_rating: number | null;
  communication_rating: number | null;
  culture_fit_rating: number | null;
  recommendation: HiringRecommendation;
  strengths: string | null;
  concerns: string | null;
  notes: string | null;
  submitted_at: ISOTimestamp | null;
}

export interface HiringDecision extends TimestampedRecord {
  id: UUID;
  application_id: UUID;
  job_id: UUID;
  candidate_id: UUID;
  organization_id: UUID;
  decision: Decision;
  offer_salary: number | null;
  offer_currency: CurrencyCode | null;
  offer_start_date: ISODate | null;
  offer_expires_at: ISOTimestamp | null;
  decision_reason: string | null;
  decided_by: UUID;
  decided_at: ISOTimestamp;
  candidate_response: CandidateResponse | null;
  responded_at: ISOTimestamp | null;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface ScheduleInterviewArgs {
  p_application_id: UUID;
  p_interview_type: InterviewType;
  p_scheduled_at: ISOTimestamp;
  p_duration_minutes?: number;
  p_interviewer_ids: UUID[];
  p_location?: string;
  p_meeting_url?: string;
  p_notes?: string;
}

export interface SubmitInterviewFeedbackArgs {
  p_interview_id: UUID;
  p_overall_rating: number;
  p_recommendation: HiringRecommendation;
  p_technical_rating?: number;
  p_communication_rating?: number;
  p_culture_fit_rating?: number;
  p_strengths?: string;
  p_concerns?: string;
  p_notes?: string;
}

export interface ExtendOfferArgs {
  p_application_id: UUID;
  p_offer_salary?: number;
  p_offer_currency?: CurrencyCode;
  p_offer_start_date?: ISODate;
  p_offer_expires_at?: ISOTimestamp;
  p_decision_reason?: string;
}
