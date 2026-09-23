import type {
  DashboardMetric,
  FrontendNotification,
  MyProfile,
  NotificationBadge,
  OrganizationSummary,
  UserOrganization,
  UserPermission
} from '../types/frontend-contract';

export type ViewKey =
  | 'overview'
  | 'organizations'
  | 'users'
  | 'candidates'
  | 'jobs'
  | 'applications'
  | 'matching'
  | 'assessments'
  | 'interviews'
  | 'clients'
  | 'notifications'
  | 'analytics'
  | 'billing'
  | 'integrations'
  | 'search'
  | 'workflows'
  | 'api'
  | 'activity'
  | 'admin'
  | 'ai';

export interface SessionState {
  profile: MyProfile | null;
  organizations: UserOrganization[];
  activeOrg: UserOrganization | null;
  permissions: UserPermission[];
  notificationBadge: NotificationBadge | null;
  organizationSummary: OrganizationSummary | null;
  dashboardMetrics: DashboardMetric[];
  notifications: FrontendNotification[];
}

export interface Loadable<T> {
  data: T;
  loading: boolean;
  error: string | null;
}

export interface ModuleDefinition {
  key: ViewKey;
  label: string;
  group: 'Dashboard' | 'Recruitment' | 'Clients' | 'AI & Automation' | 'Platform' | 'Admin';
  description: string;
  permissions: string[];
  backendReads: string[];
  backendWrites: string[];
  status: 'available' | 'partial' | 'blocked';
}
