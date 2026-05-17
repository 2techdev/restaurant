/**
 * Server-side veri fetcher'ları (RSC). Cookie'den session okur, backend'i çağırır.
 */

import "server-only";
import { apiGet } from "./api";
import type { SessionPayload } from "./auth";
import type {
  DashboardStats,
  MenuCategory,
  MenuProduct,
  ModifierGroup,
  Order,
  Restaurant,
  RevenuePoint,
  Tenant,
  TopSeller,
  AggregateStats,
  MenuSnapshotInfo,
} from "./api-types";

export async function fetchTenantsForUser(session: SessionPayload): Promise<Tenant[]> {
  // HQ admins (HQ_ADMIN/HQ_MANAGER): list every restaurant the org owns.
  // Restaurant-scoped users: just their own tenant. /stores returns DB_ERROR
  // on this build, so we go through /org/{orgId}/restaurants which 014_hq_chain
  // wired up.
  const orgRole = session.user.org_role;
  const orgId = session.user.organization_id;
  if (orgRole === "HQ_ADMIN" || orgRole === "HQ_MANAGER") {
    try {
      type OrgRestaurant = {
        tenant_id: string;
        name: string;
        is_master?: boolean;
      };
      const data = await apiGet<{ data: OrgRestaurant[] }>(
        `/org/${orgId}/restaurants`,
        { token: session.token, tenantId: session.tenantId }
      );
      const rows = Array.isArray(data?.data) ? data.data : [];
      return rows.map((r) => ({
        id: r.tenant_id,
        name: r.name,
        organization_id: orgId,
      }));
    } catch {
      // fall through to single-tenant fallback
    }
  }

  try {
    const data = await apiGet<{ stores: Tenant[] } | Tenant[]>("/stores", {
      token: session.token,
      tenantId: session.tenantId,
    });
    if (Array.isArray(data)) return data;
    return data.stores ?? [];
  } catch {
    return [
      {
        id: session.tenantId || orgId,
        name: session.user.name || "Restoran",
        organization_id: orgId,
      },
    ];
  }
}

export async function fetchDashboardStats(session: SessionPayload): Promise<DashboardStats | null> {
  try {
    return await apiGet<DashboardStats>("/dashboard/stats", {
      token: session.token,
      tenantId: session.tenantId,
    });
  } catch {
    return null;
  }
}

export async function fetchRevenue7d(session: SessionPayload): Promise<RevenuePoint[]> {
  try {
    const data = await apiGet<{ points: RevenuePoint[] } | RevenuePoint[]>(
      "/dashboard/revenue?days=7",
      { token: session.token, tenantId: session.tenantId }
    );
    if (Array.isArray(data)) return data;
    return data.points ?? [];
  } catch {
    return [];
  }
}

export async function fetchTopSellers(session: SessionPayload, days = 7): Promise<TopSeller[]> {
  try {
    const data = await apiGet<{ items: TopSeller[] } | TopSeller[]>(
      `/reports/products?days=${days}&limit=10`,
      { token: session.token, tenantId: session.tenantId }
    );
    if (Array.isArray(data)) return data;
    return data.items ?? [];
  } catch {
    return [];
  }
}

export async function fetchCategories(session: SessionPayload): Promise<MenuCategory[]> {
  try {
    const data = await apiGet<{ categories: MenuCategory[] } | MenuCategory[]>("/menu/categories", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data) ? data : data.categories ?? [];
  } catch {
    return [];
  }
}

export async function fetchProducts(session: SessionPayload): Promise<MenuProduct[]> {
  try {
    const data = await apiGet<{ products: MenuProduct[] } | MenuProduct[]>("/menu/products", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data) ? data : data.products ?? [];
  } catch {
    return [];
  }
}

export async function fetchModifierGroups(session: SessionPayload): Promise<ModifierGroup[]> {
  try {
    const data = await apiGet<{ groups: ModifierGroup[] } | ModifierGroup[]>("/menu/modifiers", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data) ? data : data.groups ?? [];
  } catch {
    return [];
  }
}

export async function fetchOrders(
  session: SessionPayload,
  params: { from?: string; to?: string; status?: string } = {}
): Promise<Order[]> {
  const q = new URLSearchParams();
  if (params.from) q.set("from", params.from);
  if (params.to) q.set("to", params.to);
  if (params.status && params.status !== "all") q.set("status", params.status);
  const path = `/orders${q.toString() ? `?${q}` : ""}`;
  try {
    const data = await apiGet<{ orders: Order[] } | Order[]>(path, {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data) ? data : data.orders ?? [];
  } catch {
    return [];
  }
}

export async function fetchPublishHistory(session: SessionPayload): Promise<MenuSnapshotInfo[]> {
  try {
    const data = await apiGet<{ snapshots: MenuSnapshotInfo[] } | MenuSnapshotInfo[]>(
      "/menu/snapshots?limit=5",
      { token: session.token, tenantId: session.tenantId }
    );
    return Array.isArray(data) ? data : data.snapshots ?? [];
  } catch {
    return [];
  }
}

export async function fetchRestaurants(session: SessionPayload): Promise<Restaurant[]> {
  // HQ admins: org-scoped /org/:orgId/restaurants (014_hq_chain). Returns
  // tenant_id+name+is_master+joined_at+last_activity_at+today_revenue.
  // The legacy /admin/stores returns DB_ERROR on this build.
  const orgId = session.user.organization_id;
  const orgRole = session.user.org_role;
  if (orgId && (orgRole === "HQ_ADMIN" || orgRole === "HQ_MANAGER")) {
    try {
      type Row = {
        tenant_id: string;
        name: string;
        is_master?: boolean;
        joined_at?: string;
        last_activity_at?: string;
        today_revenue?: number;
      };
      const data = await apiGet<{ data: Row[] }>(
        `/org/${orgId}/restaurants`,
        { token: session.token, tenantId: session.tenantId }
      );
      const rows = Array.isArray(data?.data) ? data.data : [];
      return rows.map<Restaurant>((r) => ({
        id: r.tenant_id,
        organization_id: orgId,
        name: r.name,
        is_active: true,
        created_at: r.joined_at ?? new Date().toISOString(),
      }));
    } catch {
      // fall through
    }
  }
  try {
    const data = await apiGet<{ stores: Restaurant[] } | Restaurant[]>("/admin/stores", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data) ? data : data.stores ?? [];
  } catch {
    return [];
  }
}

export interface AdminUserRow {
  id: string;
  organization_id: string;
  email: string;
  name: string;
  role: string;
  store_ids?: string[];
  status: string;
  last_login_at?: string | null;
  created_at: string;
  updated_at: string;
}

export async function fetchAdminUsers(session: SessionPayload): Promise<AdminUserRow[]> {
  try {
    const data = await apiGet<{ data: AdminUserRow[] }>("/admin/users", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data?.data) ? data.data : [];
  } catch {
    return [];
  }
}

export async function fetchAggregateStats(session: SessionPayload): Promise<AggregateStats | null> {
  try {
    return await apiGet<AggregateStats>("/admin/dashboard", {
      token: session.token,
      tenantId: session.tenantId,
    });
  } catch {
    return null;
  }
}

// =============================================================================
// Reporting automation (041)
// =============================================================================

export interface ScheduledReportRow {
  id: string;
  tenant_id: string;
  name: string;
  report_type: string;
  schedule_cron: string;
  recipients_emails: string[];
  format: string;
  filters: Record<string, unknown>;
  locale: string;
  is_active: boolean;
  last_sent_at?: string | null;
  last_status?: string | null;
  next_run_at?: string | null;
  created_at: string;
  updated_at: string;
}

export interface ReportLogRow {
  id: string;
  scheduled_report_id?: string | null;
  report_type: string;
  sent_at: string;
  sent_to_emails: string[];
  sent_recipients_count: number;
  status: string;
  error_message?: string | null;
  duration_ms?: number;
  trigger_source: string;
}

export interface ThresholdAlertRow {
  id: string;
  tenant_id: string;
  name: string;
  alert_type: string;
  threshold: Record<string, unknown>;
  recipients_emails: string[];
  cooldown_minutes: number;
  locale: string;
  is_active: boolean;
  last_triggered_at?: string | null;
  last_value?: number | null;
  created_at: string;
  updated_at: string;
}

export interface AlertLogRow {
  id: string;
  alert_id?: string | null;
  triggered_at: string;
  value?: number | null;
  message: string;
  sent_to: string[];
  status: string;
  error_message?: string | null;
}

export async function fetchScheduledReports(session: SessionPayload): Promise<ScheduledReportRow[]> {
  try {
    const data = await apiGet<{ data: ScheduledReportRow[] }>("/reporting/scheduled", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data?.data) ? data.data : [];
  } catch {
    return [];
  }
}

export async function fetchReportLogs(session: SessionPayload, limit = 50): Promise<ReportLogRow[]> {
  try {
    const data = await apiGet<{ data: ReportLogRow[] }>(`/reporting/logs?limit=${limit}`, {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data?.data) ? data.data : [];
  } catch {
    return [];
  }
}

export async function fetchThresholdAlerts(session: SessionPayload): Promise<ThresholdAlertRow[]> {
  try {
    const data = await apiGet<{ data: ThresholdAlertRow[] }>("/reporting/alerts", {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data?.data) ? data.data : [];
  } catch {
    return [];
  }
}

export async function fetchAlertLogs(session: SessionPayload, limit = 50): Promise<AlertLogRow[]> {
  try {
    const data = await apiGet<{ data: AlertLogRow[] }>(`/reporting/alerts/logs?limit=${limit}`, {
      token: session.token,
      tenantId: session.tenantId,
    });
    return Array.isArray(data?.data) ? data.data : [];
  } catch {
    return [];
  }
}
