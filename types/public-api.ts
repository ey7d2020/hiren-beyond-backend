// ============================================================
// Hiren Beyond — Public API & Developer Platform Types
// NOTE: These types are used for the REST API (/api/v1/*),
//       NOT for Supabase RPC calls.
// ============================================================
import type {
  UUID, ISOTimestamp, PaginationCursor, TimestampedRecord, OrganizationScoped,
} from './shared';

export type APIClientType = 'server' | 'web' | 'mobile' | 'partner' | 'internal';
export type APIApplicationStatus = 'active' | 'suspended' | 'revoked';
export type APIKeyStatus = 'active' | 'revoked' | 'expired';

export interface APIApplication extends TimestampedRecord, OrganizationScoped {
  id: UUID;
  name: string;
  description: string | null;
  client_type: APIClientType;
  status: APIApplicationStatus;
  created_by: UUID;
}

export interface APIKey extends TimestampedRecord {
  id: UUID;
  api_application_id: UUID;
  organization_id: UUID;
  name: string;
  key_prefix: string;
  status: APIKeyStatus;
  expires_at: ISOTimestamp | null;
  last_used_at: ISOTimestamp | null;
  revoked_at: ISOTimestamp | null;
  /**
   * IMPORTANT: key_value is ONLY present in the CreateAPIKey response.
   * It is NEVER returned again after creation. Store it securely immediately.
   */
  key_value?: string;
}

export interface APIRateLimit {
  requests_per_minute: number;
  requests_per_day: number;
  current_minute_count: number;
  current_day_count: number;
  reset_at: ISOTimestamp;
}

export interface APIUsageMetrics {
  api_key_id: UUID;
  period: string;
  total_requests: number;
  successful_requests: number;
  failed_requests: number;
  avg_latency_ms: number | null;
}

// ─── REST API Response Envelopes ──────────────────────────

export interface APIListResponse<T> {
  data: T[];
  pagination: PaginationCursor;
  request_id: string;
}

export interface APISingleResponse<T> {
  data: T;
  request_id: string;
}

export interface APIErrorResponse {
  code: string;
  message: string;
  request_id: string;
  details?: Record<string, string>;
}

// ─── REST API Request Bodies ──────────────────────────────

export interface CreateAPIKeyBody {
  name: string;
  scopes: string[];
  expires_in_days?: number;
}

export interface CreateWebhookSubscriptionBody {
  target_url: string;
  secret: string;
  event_types?: string[];
}
