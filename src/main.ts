import './styles.css';
import {
  getDashboardMetrics,
  getNotificationBadge,
  getOrganizations,
  getOrganizationSummary,
  getPermissions,
  getProfile,
  getSession,
  listNotifications,
  signOut,
  supabase
} from './backend';
import { modules } from './modules';
import type { ModuleDefinition, SessionState, ViewKey } from './types';

const appRoot = document.querySelector<HTMLDivElement>('#app');

if (!appRoot) {
  throw new Error('App root not found.');
}

const app = appRoot;

let state: SessionState = {
  profile: null,
  organizations: [],
  activeOrg: null,
  permissions: [],
  notificationBadge: null,
  organizationSummary: null,
  dashboardMetrics: [],
  notifications: []
};

let currentView: ViewKey = 'overview';
let busy = false;
let error: string | null = null;
let authMode: 'connected' | 'open' = 'open';

function permissionKeys(): Set<string> {
  return new Set(state.permissions.map((permission) => permission.permission_key));
}

function isPlatformAdmin(): boolean {
  if (authMode === 'open') return true;
  const role = state.activeOrg?.role_name.toLowerCase() ?? '';
  const keys = permissionKeys();
  return role.includes('platform') || keys.has('platform.admin');
}

function canAccess(module: ModuleDefinition): boolean {
  if (authMode === 'open') return true;
  if (module.permissions.length === 0) return true;
  const keys = permissionKeys();
  return module.permissions.some((permission) => keys.has(permission)) || isPlatformAdmin();
}

function allowedModules(): ModuleDefinition[] {
  return modules.filter(canAccess);
}

function setRoute(view: ViewKey): void {
  currentView = view;
  window.location.hash = view;
  render();
}

async function hydrate(): Promise<void> {
  busy = true;
  error = null;
  render();

  try {
    const session = await getSession();
    if (!session) {
      authMode = 'open';
      state = {
        profile: {
          id: 'open-dashboard',
          email: 'open-dashboard@hiren-beyond.local',
          full_name: 'Open Dashboard',
          avatar_url: null,
          phone: null,
          timezone: null,
          locale: null,
          is_active: true,
          last_seen_at: null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        },
        organizations: [],
        activeOrg: {
          organization_id: 'open-dashboard',
          organization_name: 'Hiren Beyond',
          organization_slug: 'hiren-beyond',
          logo_url: null,
          subscription_plan: null,
          subscription_status: null,
          role_name: 'open_dashboard',
          role_display_name: 'Open Dashboard',
          is_active: true,
          joined_at: new Date().toISOString()
        },
        permissions: [],
        notificationBadge: null,
        organizationSummary: null,
        dashboardMetrics: [],
        notifications: []
      };
      return;
    }

    const [profile, organizations] = await Promise.all([getProfile(), getOrganizations()]);
    authMode = 'connected';
    const storedOrg = window.localStorage.getItem('hb_active_org');
    const activeOrg =
      organizations.find((organization) => organization.organization_id === storedOrg && organization.is_active) ??
      organizations.find((organization) => organization.is_active) ??
      null;

    if (!activeOrg) {
      state = {
        profile,
        organizations,
        activeOrg: null,
        permissions: [],
        notificationBadge: null,
        organizationSummary: null,
        dashboardMetrics: [],
        notifications: []
      };
      return;
    }

    window.localStorage.setItem('hb_active_org', activeOrg.organization_id);

    const [permissions, notificationBadge, organizationSummary, dashboardMetrics, notifications] = await Promise.all([
      getPermissions(activeOrg.organization_id),
      getNotificationBadge(activeOrg.organization_id),
      getOrganizationSummary(activeOrg.organization_id),
      getDashboardMetrics(activeOrg.organization_id),
      listNotifications(activeOrg.organization_id)
    ]);

    state = {
      profile,
      organizations,
      activeOrg,
      permissions,
      notificationBadge,
      organizationSummary,
      dashboardMetrics,
      notifications
    };

    if (!canAccess(modules.find((module) => module.key === currentView) ?? modules[0])) {
      currentView = 'overview';
    }
  } catch (caught) {
    error = caught instanceof Error ? caught.message : 'The dashboard could not load.';
  } finally {
    busy = false;
    render();
  }
}

async function onLogout(): Promise<void> {
  await signOut();
  await hydrate();
}

async function onOrgChange(event: Event): Promise<void> {
  const organizationId = (event.target as HTMLSelectElement).value;
  window.localStorage.setItem('hb_active_org', organizationId);
  await hydrate();
}

function emptyState(title: string, body: string): string {
  return `<section class="state-panel"><h2>${title}</h2><p>${body}</p></section>`;
}

function badge(text: string, tone = 'neutral'): string {
  return `<span class="badge ${tone}">${text}</span>`;
}

function trend(direction: string): string {
  if (direction === 'up') return 'positive';
  if (direction === 'down') return 'negative';
  return 'neutral';
}

function metricLabel(name: string): string {
  return name
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function renderShell(): string {
  if (!state.activeOrg) {
    return `
      <main class="blocked-page">
        ${emptyState('No active organization', 'Your account is authenticated, but no active organization membership was returned. Ask an administrator to invite or reactivate your user.')}
        <button id="logout" class="secondary">Sign out</button>
      </main>
    `;
  }

  const grouped = allowedModules().reduce<Record<string, ModuleDefinition[]>>((acc, module) => {
    acc[module.group] = [...(acc[module.group] ?? []), module];
    return acc;
  }, {});

  const nav = Object.entries(grouped)
    .map(
      ([group, groupModules]) => `
        <div class="nav-group">
          <div class="nav-heading">${group}</div>
          ${groupModules
            .map(
              (module) => `
                <button class="nav-item ${module.key === currentView ? 'active' : ''}" data-view="${module.key}">
                  <span>${module.label}</span>
                  ${module.status === 'blocked' ? badge('Gap', 'warning') : module.status === 'partial' ? badge('Partial') : ''}
                </button>
              `
            )
            .join('')}
        </div>
      `
    )
    .join('');

  return `
    <div class="app-shell">
      <aside class="sidebar">
        <div class="brand">
          <div class="brand-mark">HB</div>
          <div>
            <strong>Hiren Beyond</strong>
            <span>Control Center</span>
          </div>
        </div>
        <nav>${nav}</nav>
      </aside>
      <section class="workspace">
        <header class="topbar">
          <div>
            <div class="breadcrumb">Dashboard / ${modules.find((module) => module.key === currentView)?.label ?? 'Overview'}</div>
            <h1>${state.activeOrg.organization_name}</h1>
          </div>
          <div class="topbar-actions">
            <select id="org-select" aria-label="Organization">
              ${(state.organizations.length ? state.organizations : state.activeOrg ? [state.activeOrg] : [])
                .map(
                  (organization) =>
                    `<option value="${organization.organization_id}" ${organization.organization_id === state.activeOrg?.organization_id ? 'selected' : ''}>${organization.organization_name}</option>`
                )
                .join('')}
            </select>
            <div class="user-chip">
              <span>${state.profile?.full_name ?? state.profile?.email ?? 'User'}</span>
              ${state.notificationBadge?.unread_count ? badge(`${state.notificationBadge.unread_count} unread`, state.notificationBadge.has_urgent ? 'danger' : 'neutral') : ''}
            </div>
            ${authMode === 'connected' ? '<button id="logout" class="secondary">Sign out</button>' : ''}
          </div>
        </header>
        ${
          authMode === 'open'
            ? '<div class="alert">Open dashboard mode is enabled. Live metrics and protected records require an authenticated Supabase session, so empty states are shown instead of fake data.</div>'
            : ''
        }
        ${error ? `<div class="alert danger">${error}</div>` : ''}
        ${busy ? `<div class="loading-bar"></div>` : ''}
        <main class="content">${renderView()}</main>
      </section>
    </div>
  `;
}

function renderView(): string {
  if (currentView === 'overview') return renderOverview();
  if (currentView === 'notifications') return renderNotifications();

  const module = modules.find((item) => item.key === currentView);
  if (!module) return emptyState('Not found', 'This dashboard page is not registered.');
  if (!canAccess(module)) {
    return emptyState('Forbidden', 'Your current organization role does not expose this section. Backend permissions still decide final access.');
  }

  return renderModule(module);
}

function renderOverview(): string {
  const summary = state.organizationSummary;
  const metrics = state.dashboardMetrics;

  return `
    <section class="hero-band">
      <div>
        <p class="eyebrow">Overview</p>
        <h2>Recruitment operations at a glance</h2>
        <p>All values on this page are loaded from backend RPCs for the active organization.</p>
      </div>
      <div class="summary-card">
        <span>Plan</span>
        <strong>${summary?.subscription_plan ?? 'Unavailable'}</strong>
        ${badge(summary?.subscription_status ?? 'Unknown')}
      </div>
    </section>

    <section class="metric-grid">
      ${summary
        ? `
          <article class="metric-card"><span>Active jobs</span><strong>${summary.active_jobs_count}</strong></article>
          <article class="metric-card"><span>Active candidates</span><strong>${summary.active_candidates_count}</strong></article>
          <article class="metric-card"><span>Pending applications</span><strong>${summary.pending_applications}</strong></article>
          <article class="metric-card"><span>Team members</span><strong>${summary.team_member_count}</strong></article>
        `
        : emptyState('Summary unavailable', 'The organization summary RPC did not return data.')}
      ${metrics
        .map(
          (metric) => `
            <article class="metric-card">
              <span>${metricLabel(metric.metric_name)}</span>
              <strong>${metric.metric_value}${metric.metric_unit && metric.metric_unit !== 'count' ? ` ${metric.metric_unit}` : ''}</strong>
              <small class="${trend(metric.trend_direction)}">${metric.trend_delta} ${metric.trend_direction}</small>
            </article>
          `
        )
        .join('')}
    </section>

    <section class="two-column">
      <article class="panel">
        <div class="panel-header"><h3>Authorized Modules</h3><span>${allowedModules().length} visible</span></div>
        <div class="module-list">
          ${allowedModules()
            .slice(0, 8)
            .map((module) => `<button data-view="${module.key}" class="module-row"><span>${module.label}</span>${badge(module.status)}</button>`)
            .join('')}
        </div>
      </article>
      <article class="panel">
        <div class="panel-header"><h3>Recent Notifications</h3><span>${state.notifications.length}</span></div>
        ${state.notifications.length
          ? state.notifications
              .slice(0, 5)
              .map((notification) => `<div class="feed-item"><strong>${notification.title}</strong><p>${notification.body ?? 'No message body.'}</p><span>${new Date(notification.created_at).toLocaleString()}</span></div>`)
              .join('')
          : '<p class="muted">No notifications were returned by the backend.</p>'}
      </article>
    </section>
  `;
}

function renderNotifications(): string {
  return `
    <section class="page-header">
      <div>
        <p class="eyebrow">Platform</p>
        <h2>Notifications Center</h2>
        <p>Backed by <code>list_notifications</code> and notification preference RPCs.</p>
      </div>
      ${state.notificationBadge ? badge(`${state.notificationBadge.unread_count} unread`, state.notificationBadge.has_urgent ? 'danger' : 'neutral') : ''}
    </section>
    <section class="panel">
      ${state.notifications.length
        ? `<table>
            <thead><tr><th>Notification</th><th>Status</th><th>Created</th></tr></thead>
            <tbody>
              ${state.notifications
                .map(
                  (notification) => `
                    <tr>
                      <td><strong>${notification.title}</strong><p>${notification.body ?? ''}</p></td>
                      <td>${notification.read_at ? badge('Read') : badge('Unread', 'warning')}</td>
                      <td>${new Date(notification.created_at).toLocaleString()}</td>
                    </tr>
                  `
                )
                .join('')}
            </tbody>
          </table>`
        : emptyState('No notifications', 'The notification RPC returned an empty list for this account.')}
    </section>
  `;
}

function renderModule(module: ModuleDefinition): string {
  const statusTone = module.status === 'blocked' ? 'warning' : module.status === 'partial' ? 'neutral' : 'positive';
  return `
    <section class="page-header">
      <div>
        <p class="eyebrow">${module.group}</p>
        <h2>${module.label}</h2>
        <p>${module.description}</p>
      </div>
      ${badge(module.status, statusTone)}
    </section>
    <section class="toolbar">
      <input type="search" placeholder="Search ${module.label.toLowerCase()}" aria-label="Search" />
      <select aria-label="Filter status"><option>All statuses</option><option>Active</option><option>Needs attention</option><option>Archived</option></select>
      <select aria-label="Date range"><option>Last 30 days</option><option>Last 90 days</option><option>This year</option></select>
      <button class="secondary" disabled>Export</button>
    </section>
    <section class="two-column">
      <article class="panel">
        <div class="panel-header"><h3>Backend Reads</h3><span>${module.backendReads.length}</span></div>
        <ul class="check-list">${module.backendReads.map((item) => `<li><code>${item}</code></li>`).join('')}</ul>
      </article>
      <article class="panel">
        <div class="panel-header"><h3>Authorized Actions</h3><span>${module.backendWrites.length}</span></div>
        ${
          module.backendWrites.length
            ? `<ul class="check-list">${module.backendWrites.map((item) => `<li><code>${item}</code></li>`).join('')}</ul>`
            : '<p class="muted">Read-only in the normal dashboard surface.</p>'
        }
      </article>
    </section>
    <section class="panel">
      <div class="panel-header">
        <h3>${module.label} Data</h3>
        <span>Server-side pagination required</span>
      </div>
      ${emptyState('Ready for live records', 'This surface is wired as a role-gated dashboard page. Record lists must call the mapped backend RPC/table surface and render only returned data; no fake fallback rows are used.')}
    </section>
  `;
}

function bindEvents(): void {
  document.querySelector<HTMLButtonElement>('#logout')?.addEventListener('click', () => {
    void onLogout();
  });
  document.querySelector<HTMLSelectElement>('#org-select')?.addEventListener('change', (event) => {
    void onOrgChange(event);
  });
  document.querySelectorAll<HTMLElement>('[data-view]').forEach((element) => {
    element.addEventListener('click', () => {
      const view = element.dataset.view as ViewKey | undefined;
      if (view) setRoute(view);
    });
  });
}

function render(): void {
  app.innerHTML = renderShell();
  bindEvents();
}

const route = window.location.hash.replace('#', '') as ViewKey;
if (modules.some((module) => module.key === route)) {
  currentView = route;
}

supabase.auth.onAuthStateChange(() => {
  void hydrate();
});

void hydrate();
