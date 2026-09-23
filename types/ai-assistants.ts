// ============================================================
// Hiren Beyond — AI Assistant & Copilot Types
// ============================================================
import type {
  UUID, ISOTimestamp, JSONObject, TimestampedRecord,
} from './shared';

export type AssistantType =
  | 'recruiter_copilot' | 'cv_analyst' | 'jd_writer'
  | 'interview_coach' | 'email_composer' | 'offer_negotiator';

export type ConversationStatus = 'active' | 'archived' | 'deleted';
export type MessageRole = 'user' | 'assistant' | 'system';
export type MessageStatus = 'pending' | 'streaming' | 'complete' | 'error';

export interface AIConversation extends TimestampedRecord {
  id: UUID;
  organization_id: UUID;
  user_id: UUID;
  assistant_type: AssistantType;
  status: ConversationStatus;
  title: string | null;
  context: JSONObject | null;
  message_count: number;
  last_message_at: ISOTimestamp | null;
}

export interface AIMessage extends TimestampedRecord {
  id: UUID;
  conversation_id: UUID;
  role: MessageRole;
  content: string;
  status: MessageStatus;
  tokens_used: number | null;
  model_version: string | null;
  metadata: JSONObject | null;
}

export interface AIStreamChunk {
  conversation_id: UUID;
  message_id: UUID;
  delta: string;
  is_complete: boolean;
  total_tokens?: number;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface StartConversationArgs {
  p_assistant_type: AssistantType;
  p_initial_message: string;
  p_context?: JSONObject;
}

export interface SendMessageArgs {
  p_conversation_id: UUID;
  p_message: string;
}

export interface ArchiveConversationArgs {
  p_conversation_id: UUID;
}
