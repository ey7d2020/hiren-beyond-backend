import { createClient, type PostgrestError, type Session } from '@supabase/supabase-js';
import type { Database } from '../types/database.types';
import type { DashboardMetric, FrontendNotification, MyProfile, NotificationBadge, OrganizationSummary, UserOrganization, UserPermission } from '../types/frontend-contract';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const hasSupabaseConfig = Boolean(
  supabaseUrl &&
    supabaseAnonKey &&
    !supabaseAnonKey.includes('your-supabase-anon-key')
);

export const supabase = createClient<Database>(
  supabaseUrl || 'https://example.supabase.co',
  supabaseAnonKey || 'missing-anon-key',
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    }
  }
);

const rpcClient = supabase as unknown as {
  rpc<T>(functionName: string, args?: Record<string, unknown>): Promise<{ data: T | null; error: PostgrestError | null }>;
};

function backendError(error: PostgrestError | Error | null): Error {
  if (!error) return new Error('The backend returned an empty response.');
  if ('message' in error) return new Error(error.message);
  return new Error('The backend request failed.');
}

function firstRow<T>(rows: T[] | null, label: string): T {
  if (!rows || rows.length === 0) {
    throw new Error(`${label} was not returned by the backend.`);
  }
  return rows[0];
}

export async function getSession(): Promise<Session | null> {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw backendError(error);
  return data.session;
}

export async function signIn(email: string, password: string): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw backendError(error);
}

export async function signOut(): Promise<void> {
  const { error } = await supabase.auth.signOut();
  if (error) throw backendError(error);
}

export async function getProfile(): Promise<MyProfile> {
  const { data, error } = await rpcClient.rpc<MyProfile[]>('get_my_profile');
  if (error) throw backendError(error);
  return firstRow(data, 'Profile');
}

export async function getOrganizations(): Promise<UserOrganization[]> {
  const { data, error } = await rpcClient.rpc<UserOrganization[]>('get_user_organizations');
  if (error) throw backendError(error);
  return data ?? [];
}

export async function getPermissions(organizationId: string): Promise<UserPermission[]> {
  const { data, error } = await rpcClient.rpc<UserPermission[]>('get_user_permissions', {
    p_organization_id: organizationId
  });
  if (error) throw backendError(error);
  return data ?? [];
}

export async function getNotificationBadge(organizationId: string): Promise<NotificationBadge> {
  const { data, error } = await rpcClient.rpc<NotificationBadge[]>('get_notification_badge_count', {
    p_organization_id: organizationId
  });
  if (error) throw backendError(error);
  return firstRow(data, 'Notification badge');
}

export async function getOrganizationSummary(organizationId: string): Promise<OrganizationSummary> {
  const { data, error } = await rpcClient.rpc<OrganizationSummary[]>('get_organization_summary', {
    p_organization_id: organizationId
  });
  if (error) throw backendError(error);
  return firstRow(data, 'Organization summary');
}

export async function getDashboardMetrics(organizationId: string, days = 30): Promise<DashboardMetric[]> {
  const { data, error } = await rpcClient.rpc<DashboardMetric[]>('get_dashboard_metrics', {
    p_organization_id: organizationId,
    p_days: days
  });
  if (error) throw backendError(error);
  return data ?? [];
}

export async function listNotifications(organizationId: string): Promise<FrontendNotification[]> {
  const { data, error } = await rpcClient.rpc<Array<{
    id: string;
    notification_type: string;
    title: string;
    body: string | null;
    data: Record<string, unknown> | null;
    channel: string;
    status: string;
    read_at: string | null;
    action_url: string | null;
    created_at: string;
    has_more: boolean;
    next_cursor: string | null;
  }>>('list_notifications', {
    p_organization_id: organizationId,
    p_limit: 20,
    p_cursor: null,
    p_unread_only: false
  });
  if (error) throw backendError(error);
  return (data ?? []).map((item) => ({
    id: item.id,
    notification_type_id: null,
    title: item.title,
    body: item.body,
    data: item.data ?? {},
    priority: item.status,
    read_at: item.read_at,
    created_at: item.created_at,
    has_more: item.has_more,
    next_cursor: item.next_cursor
  }));
}
