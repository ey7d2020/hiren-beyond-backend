import type { UUID, ISOTimestamp, JSONObject, PaginationCursor } from './shared';

export type ImplementationStatus =
  | 'implemented_deployed'
  | 'implemented_unverified'
  | 'documentation_only'
  | 'requires_future_implementation';

export interface FrontendConfigItem {
  config_key: string;
  config_value: string;
  category: string;
}

export interface UserOrganization {
  organization_id: UUID;
  organization_name: string;
  organization_slug: string;
  logo_url: string | null;
  subscription_plan: string | null;
  subscription_status: string | null;
  role_name: string;
  role_display_name: string;
  is_active: boolean;
  joined_at: ISOTimestamp;
}

export interface UserPermission {
  permission_key: string;
  permission_name: string;
  category: string;
  role_name: string;
}

export interface MyProfile {
  id: UUID;
  email: string;
  full_name: string | null;
  avatar_url: string | null;
  phone: string | null;
  timezone: string | null;
  locale: string | null;
  is_active: boolean;
  last_seen_at: ISOTimestamp | null;
  created_at: ISOTimestamp;
  updated_at: ISOTimestamp;
}

export interface FrontendNotification {
  id: UUID;
  notification_type_id: UUID | null;
  title: string;
  body: string | null;
  data: JSONObject;
  priority: string;
  read_at: ISOTimestamp | null;
  created_at: ISOTimestamp;
  has_more: boolean;
  next_cursor: UUID | null;
}

export interface NotificationBadge {
  unread_count: number;
  has_urgent: boolean;
}

export interface OrganizationSummary {
  organization_id: UUID;
  name: string;
  slug: string;
  logo_url: string | null;
  subscription_plan: string | null;
  subscription_status: string | null;
  trial_ends_at: ISOTimestamp | null;
  active_jobs_count: number;
  active_candidates_count: number;
  pending_applications: number;
  team_member_count: number;
}

export interface DashboardMetric {
  metric_name: string;
  metric_value: number;
  metric_unit: string;
  trend_delta: number;
  trend_direction: 'up' | 'down' | 'neutral' | string;
}

export type FileUploadStatus =
  | 'not_started'
  | 'uploading'
  | 'uploaded'
  | 'queued'
  | 'processing'
  | 'review_required'
  | 'completed'
  | 'failed';

export type ProcessingStatus =
  | 'queued'
  | 'extracting'
  | 'analyzing'
  | 'review_required'
  | 'completed'
  | 'failed'
  | string;

export interface SearchResult<T> {
  item: T;
  score?: number;
  highlights?: JSONObject;
  explanation?: string;
}

export interface ApiResponse<T> {
  data: T;
  request_id?: string;
  meta?: JSONObject;
}

export interface ApiListResponse<T> {
  data: T[];
  pagination: PaginationCursor;
  request_id?: string;
  meta?: JSONObject;
}

export interface ApiError {
  code: string;
  message: string;
  details?: JSONObject;
  request_id?: string;
}

