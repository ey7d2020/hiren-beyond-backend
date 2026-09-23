// ============================================================
// Hiren Beyond — Notifications Types
// ============================================================
import type {
  UUID, ISOTimestamp, JSONObject, TimestampedRecord, PaginationArgs,
} from './shared';

export type NotificationType =
  | 'application_received' | 'application_stage_change' | 'interview_scheduled'
  | 'interview_reminder' | 'offer_extended' | 'offer_accepted' | 'offer_declined'
  | 'assessment_completed' | 'candidate_matched' | 'ai_analysis_complete'
  | 'cv_processed' | 'system_alert' | 'billing_alert' | 'mention';

export type NotificationChannel = 'in_app' | 'email' | 'sms' | 'push' | 'webhook';
export type NotificationStatus = 'pending' | 'sent' | 'delivered' | 'read' | 'failed';

export interface Notification extends TimestampedRecord {
  id: UUID;
  organization_id: UUID;
  recipient_id: UUID;
  notification_type: NotificationType;
  title: string;
  body: string;
  data: JSONObject | null;
  channel: NotificationChannel;
  status: NotificationStatus;
  read_at: ISOTimestamp | null;
  action_url: string | null;
}

export interface NotificationRealtimePayload {
  event: 'INSERT';
  table: 'notifications';
  new: Notification;
  old: null;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface MarkNotificationReadArgs {
  p_notification_id: UUID;
}

export interface MarkAllNotificationsReadArgs {
  p_organization_id?: UUID;
}

export interface ListNotificationsArgs extends PaginationArgs {
  p_unread_only?: boolean;
  p_notification_type?: NotificationType;
}
