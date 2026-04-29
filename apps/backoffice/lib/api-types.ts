/**
 * API tipleri - Go backend (server/internal/<pkg>/models.go) ile eslesir.
 * Snake_case JSON anahtarlarini korur (Go tag'leri boyle).
 */

// --- Auth ---
export interface AdminLoginRequest {
  email: string;
  password: string;
}

export interface AdminUser {
  id: string;
  organization_id: string;
  email: string;
  name: string;
  // DB role from admin_users.role ("admin" | "brand_manager" | "store_manager" | "viewer").
  role: string;
  // Org-level role mapped server-side from `role`. Stamped into the JWT and
  // returned by /auth/admin/login so the frontend can branch on HQ vs store.
  org_role?: UserRole | string;
  store_ids?: string[];
}

export type UserRole =
  | "HQ_ADMIN"
  | "HQ_MANAGER"
  | "RESTAURANT_MANAGER"
  | "RESTAURANT_STAFF"
  | "POS_OPERATOR"
  | "admin"
  | "manager"
  | "staff";

export interface AdminLoginResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: "Bearer";
  user: AdminUser;
}

// --- Menu ---
export interface MenuCategory {
  id: string;
  tenant_id: string;
  name: string;
  display_order: number;
  color?: string | null;
  icon?: string | null;
  parent_id?: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  is_deleted: boolean;
}

export interface MenuProduct {
  id: string;
  tenant_id: string;
  category_id: string;
  name: string;
  description?: string | null;
  price: number; // cents (standard)
  price_takeaway?: number;
  price_delivery?: number;
  cost_price: number;
  tax_group: string;
  image_path?: string | null;
  barcode?: string | null;
  is_active: boolean;
  display_order: number;
  prep_time_minutes?: number | null;
  printer_group: string;
  default_gang?: number | null;
  /** HQ kilidi: undefined = serbest. PRICE_LOCKED = sadece fiyat kilitli. FULLY_LOCKED = hiç düzenlenemez. */
  policy_lock?: "FLEXIBLE" | "PRICE_LOCKED" | "FULLY_LOCKED";
  /** Yerel ürün mü? (HQ master menünden gelmediyse) */
  is_local?: boolean;
  created_at: string;
  updated_at: string;
  is_deleted: boolean;
}

export interface ModifierGroup {
  id: string;
  tenant_id: string;
  name: string;
  selection_type: "single" | "multiple";
  min_selections: number;
  max_selections: number;
  is_required: boolean;
  display_order: number;
  modifiers?: Modifier[];
  created_at: string;
  updated_at: string;
  is_deleted: boolean;
}

export interface Modifier {
  id: string;
  tenant_id: string;
  group_id: string;
  name: string;
  price_delta: number; // cents
  is_default: boolean;
  display_order: number;
  created_at: string;
  updated_at: string;
  is_deleted: boolean;
}

// --- Menu publish (snapshot) ---
export interface MenuSnapshotInfo {
  version: number;
  tenant_id: string;
  published_at: string;
  published_by: string;
  category_count: number;
  product_count: number;
}

// --- Orders ---
export type OrderStatus = "open" | "preparing" | "paid" | "closed" | "cancelled";
export type OrderChannel = "dine_in" | "takeaway" | "delivery" | "online";

export interface Order {
  id: string;
  tenant_id: string;
  number: string | number;
  status: OrderStatus;
  channel: OrderChannel;
  total: number; // cents
  customer_name?: string | null;
  table_id?: string | null;
  created_at: string;
  closed_at?: string | null;
  items?: OrderItem[];
}

export interface OrderItem {
  id: string;
  product_id: string;
  product_name: string;
  quantity: number;
  unit_price: number;
  total: number;
  modifiers?: { name: string; price_delta: number }[];
  notes?: string;
}

// --- Dashboard ---
export interface DashboardStats {
  today_revenue: number; // cents
  order_count: number;
  avg_ticket: number;
  active_orders: number;
  tables_occupied?: number;
}

export interface RevenuePoint {
  date: string; // YYYY-MM-DD
  revenue: number; // cents
  order_count: number;
}

export interface TopSeller {
  product_id: string;
  product_name: string;
  quantity: number;
  revenue: number;
}

// --- Reports ---
export interface DailyReport {
  date: string;
  total_revenue: number;
  total_orders: number;
  by_channel: Record<string, number>;
  by_payment: Record<string, number>;
  tax_breakdown: { rate: number; net: number; tax: number; gross: number }[];
}

// --- Tenants / Stores / Organization (HQ) ---
export interface Tenant {
  id: string;
  name: string;
  organization_id?: string;
  timezone?: string;
  default_language?: string;
}

export interface Organization {
  id: string;
  name: string;
  owner_user_id: string;
  settings?: Record<string, unknown>;
}

export interface Restaurant {
  id: string; // tenant_id
  organization_id: string;
  name: string;
  address?: string;
  is_active: boolean;
  created_at: string;
}

export interface AggregateStats {
  total_revenue: number;
  total_orders: number;
  per_restaurant: { restaurant_id: string; restaurant_name: string; revenue: number; order_count: number }[];
}

// --- Generic API error ---
export interface ApiError {
  code: string;
  message: string;
  status: number;
}
