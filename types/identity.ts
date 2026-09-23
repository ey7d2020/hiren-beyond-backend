// ============================================================
// Hiren Beyond — Identity & Organization Types
// ============================================================
import type { UUID, ISOTimestamp, LanguageCode, CountryCode, TimestampedRecord } from './shared';

export interface Profile extends TimestampedRecord {
  id: UUID;
  email: string;
  full_name: string | null;
  avatar_url: string | null;
  phone: string | null;
  timezone: string | null;
  locale: LanguageCode | null;
  is_active: boolean;
  last_seen_at: ISOTimestamp | null;
}

export type OrganizationSize =
  | '1-10' | '11-50' | '51-200' | '201-500'
  | '501-1000' | '1001-5000' | '5000+';

export type SubscriptionPlan = 'free' | 'starter' | 'growth' | 'enterprise';
export type SubscriptionStatus = 'active' | 'trialing' | 'past_due' | 'canceled' | 'suspended';

export interface Organization extends TimestampedRecord {
  id: UUID;
  name: string;
  slug: string;
  logo_url: string | null;
  website_url: string | null;
  industry: string | null;
  size_range: OrganizationSize | null;
  country_code: CountryCode | null;
  subscription_plan: SubscriptionPlan;
  subscription_status: SubscriptionStatus;
  trial_ends_at: ISOTimestamp | null;
}

export interface OrganizationMember extends TimestampedRecord {
  id: UUID;
  organization_id: UUID;
  user_id: UUID;
  role_id: UUID;
  role_name: string;
  is_active: boolean;
  invited_by: UUID | null;
  joined_at: ISOTimestamp | null;
}

export interface Role {
  id: UUID;
  name: string;
  display_name: string;
  description: string | null;
  is_system: boolean;
  permissions: string[];
}

export interface Permission {
  id: UUID;
  key: string;
  name: string;
  description: string | null;
  category: string;
}

// ─── RPC Result Shapes ────────────────────────────────────

export interface UserOrganizationResult {
  organization_id: UUID;
  organization_name: string;
  role_name: string;
  is_active: boolean;
  joined_at: ISOTimestamp;
}

export interface UserPermissionsResult {
  permissions: string[];
  role_name: string;
  organization_id: UUID;
}

// ─── RPC Args ─────────────────────────────────────────────

export interface InviteMemberArgs {
  p_email: string;
  p_role_id: UUID;
}

export interface UpdateMemberRoleArgs {
  p_member_id: UUID;
  p_role_id: UUID;
}
