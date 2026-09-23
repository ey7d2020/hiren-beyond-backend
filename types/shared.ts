// ============================================================
// Hiren Beyond — Shared Base Types
// Auto-generated from backend schema. Do not edit manually.
// ============================================================

export type UUID = string;
export type ISOTimestamp = string;    // ISO 8601: "2026-09-15T00:00:00Z"
export type ISODate = string;         // ISO 8601 date: "2026-09-15"
export type JSONObject = Record<string, unknown>;
export type LanguageCode = string;    // BCP-47: "en", "ar", "fr"
export type CountryCode = string;     // ISO 3166-1 alpha-2: "US", "GB"
export type CurrencyCode = string;    // ISO 4217: "USD", "EUR"

// ─── Pagination ────────────────────────────────────────────

export interface PaginationCursor {
  has_more: boolean;
  next_cursor: UUID | null;
  limit: number;
  total_count?: number;
}

export interface PaginationArgs {
  p_limit?: number;        // Default: 20. Max: 100
  p_cursor?: UUID | null;  // Cursor (last row ID from previous page). Null = first page
}

// ─── Base Record Shapes ────────────────────────────────────

export interface TimestampedRecord {
  created_at: ISOTimestamp;
  updated_at: ISOTimestamp;
}

export interface OrganizationScoped {
  organization_id: UUID;
}

// ─── Generic Response Envelopes ───────────────────────────

export interface PaginatedResponse<T> {
  data: T[];
  pagination: PaginationCursor;
}

export interface SingleResponse<T> {
  data: T;
}

// ─── Sort / Filter Helpers ────────────────────────────────

export type SortDirection = 'asc' | 'desc';

// ─── Error Contract ───────────────────────────────────────

export type HBErrorCode =
  // Auth
  | 'AUTH_REQUIRED'
  | 'AUTH_FORBIDDEN'
  | 'AUTH_SESSION_EXPIRED'
  | 'AUTH_INSUFFICIENT_PERMISSIONS'
  // Resource
  | 'NOT_FOUND'
  | 'ALREADY_EXISTS'
  | 'CONFLICT'
  // Validation
  | 'VALIDATION_ERROR'
  | 'INVALID_PARAMETER'
  | 'REQUIRED_FIELD_MISSING'
  // Business logic
  | 'BUSINESS_RULE_VIOLATION'
  | 'WORKFLOW_INVALID_TRANSITION'
  | 'QUOTA_EXCEEDED'
  | 'SUBSCRIPTION_REQUIRED'
  // Public API rate limiting
  | 'RATE_LIMIT_EXCEEDED'
  | 'IDEMPOTENCY_CONFLICT'
  // System
  | 'INTERNAL_ERROR'
  | 'SERVICE_UNAVAILABLE'
  | 'DEPENDENCY_FAILURE';

export interface HBError {
  code: HBErrorCode;
  message: string;
  request_id?: string;
  details?: Record<string, string>;
  hint?: string;
}
