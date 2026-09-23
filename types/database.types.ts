// ============================================================
// Hiren Beyond — Supabase Database Type Stub
// 
// IMPORTANT: This file is a manually curated stub that defines
// the TypeScript types for Supabase table RPCs and schemas.
// 
// For production, generate the full version via:
//   npx supabase gen types typescript --project-id <ref> > types/database.types.ts
// ============================================================

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export interface Database {
  public: {
    Tables: {
      organizations: {
        Row: {
          id: string;
          name: string;
          slug: string;
          logo_url: string | null;
          subscription_plan: string;
          subscription_status: string;
          is_active: boolean;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          name: string;
          slug: string;
          subscription_plan?: string;
        };
        Update: Partial<Database['public']['Tables']['organizations']['Insert']>;
      };
      profiles: {
        Row: {
          id: string;
          email: string;
          full_name: string | null;
          avatar_url: string | null;
          phone: string | null;
          timezone: string | null;
          locale: string | null;
          is_active: boolean;
          last_seen_at: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          email: string;
          full_name?: string | null;
        };
        Update: Partial<Omit<Database['public']['Tables']['profiles']['Row'], 'id'>>;
      };
      notifications: {
        Row: {
          id: string;
          organization_id: string;
          recipient_id: string;
          notification_type: string;
          title: string;
          body: string;
          data: Json | null;
          channel: string;
          status: string;
          read_at: string | null;
          action_url: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          organization_id: string;
          recipient_id: string;
          notification_type: string;
          title: string;
          body: string;
          channel?: string;
          status?: string;
        };
        Update: Partial<Omit<Database['public']['Tables']['notifications']['Row'], 'id' | 'created_at'>>;
      };
    };
    Views: Record<string, never>;
    Functions: {
      get_user_organizations: {
        Args: Record<string, never>;
        Returns: Array<{
          organization_id: string;
          organization_name: string;
          organization_slug: string;
          logo_url: string | null;
          subscription_plan: string;
          subscription_status: string;
          role_name: string;
          role_display_name: string;
          is_active: boolean;
          joined_at: string;
        }>;
      };
      get_user_permissions: {
        Args: { p_organization_id: string };
        Returns: Array<{
          permission_key: string;
          permission_name: string;
          category: string;
          role_name: string;
        }>;
      };
      get_my_profile: {
        Args: Record<string, never>;
        Returns: Array<{
          id: string;
          email: string;
          full_name: string | null;
          avatar_url: string | null;
          phone: string | null;
          timezone: string | null;
          locale: string | null;
          is_active: boolean;
          last_seen_at: string | null;
          created_at: string;
          updated_at: string;
        }>;
      };
      update_my_profile: {
        Args: {
          p_full_name?: string | null;
          p_phone?: string | null;
          p_timezone?: string | null;
          p_locale?: string | null;
          p_avatar_url?: string | null;
        };
        Returns: Array<{ success: boolean; updated_at: string }>;
      };
      get_notification_badge_count: {
        Args: { p_organization_id: string };
        Returns: Array<{ unread_count: number; has_urgent: boolean }>;
      };
      get_frontend_config: {
        Args: Record<string, never>;
        Returns: Array<{ config_key: string; config_value: string; category: string }>;
      };
      mark_notification_read: {
        Args: { p_notification_id: string };
        Returns: Array<{ success: boolean; notification_id: string }>;
      };
      mark_all_notifications_read: {
        Args: { p_organization_id: string };
        Returns: Array<{ success: boolean; updated_count: number }>;
      };
      get_organization_summary: {
        Args: { p_organization_id: string };
        Returns: Array<{
          organization_id: string;
          name: string;
          slug: string;
          logo_url: string | null;
          subscription_plan: string;
          subscription_status: string;
          trial_ends_at: string | null;
          active_jobs_count: number;
          active_candidates_count: number;
          pending_applications: number;
          team_member_count: number;
        }>;
      };
      get_dashboard_metrics: {
        Args: { p_organization_id: string; p_days?: number };
        Returns: Array<{
          metric_name: string;
          metric_value: number;
          metric_unit: string;
          trend_delta: number;
          trend_direction: string;
        }>;
      };
      list_notifications: {
        Args: {
          p_organization_id: string;
          p_limit?: number;
          p_cursor?: string | null;
          p_unread_only?: boolean;
        };
        Returns: Array<{
          id: string;
          notification_type: string;
          title: string;
          body: string;
          data: Json | null;
          channel: string;
          status: string;
          read_at: string | null;
          action_url: string | null;
          created_at: string;
          has_more: boolean;
          next_cursor: string | null;
        }>;
      };
    };
    Enums: Record<string, never>;
  };
}
