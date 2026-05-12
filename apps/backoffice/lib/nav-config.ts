/**
 * Sidebar navigation config — single source of truth for groups + sub-items.
 * Renderer lives in `components/shell/sidebar.tsx`.
 *
 * Each top-level entry is either:
 *   - a "leaf" item   → single row, no children
 *   - a "group" item  → click expands; sub-items rendered indented
 *
 * `hqOnly` — only HQ_ADMIN/HQ_MANAGER sees the row.
 * `placeholder` — page is "Yakında" stub; the route exists but renders the
 *   shared <PlaceholderPage>.
 */

/**
 * Optional sub-item indicator dot (designer canvas pattern).
 * Renders as a 6×6 dot beside the label so users get peripheral signal that
 * something is happening on that page (e.g. live orders / failed jobs).
 */
export type NavIndicator = "success" | "warning" | "error" | "info";

export type NavLeaf = {
  kind: "leaf";
  href: (locale: string) => string;
  labelKey: string; // i18n key under namespace `nav`
  icon: string;
  hqOnly?: boolean;
  /** Only renders when the session has admin_users.is_super_admin=TRUE (F1, migration 024). */
  superAdminOnly?: boolean;
  /** Optional count badge (mono, muted) on the right side. */
  badge?: number | string;
  /** Optional dot indicator color. */
  indicator?: NavIndicator;
  /** Keyboard shortcut chip (e.g. "G D" → "Go to Dashboard"). */
  kbd?: string;
};

export type NavSubItem = {
  href: (locale: string) => string;
  labelKey: string;
  placeholder?: boolean;
  badge?: number | string;
  indicator?: NavIndicator;
  kbd?: string;
};

export type NavGroup = {
  kind: "group";
  id: string;
  labelKey: string;
  icon: string;
  hqOnly?: boolean;
  /** Aggregate count rendered beside the group title (mono, muted). */
  count?: number;
  /** Optional inline action shown on the section header — e.g. "+ Yeni". */
  action?: { labelKey: string; href: (locale: string) => string };
  items: NavSubItem[];
};

export type NavEntry = NavLeaf | NavGroup;

export const NAV_CONFIG: NavEntry[] = [
  {
    kind: "leaf",
    href: (l) => `/${l}/dashboard`,
    labelKey: "dashboard",
    icon: "LayoutDashboard",
    kbd: "G D",
  },
  {
    kind: "group",
    id: "orders",
    labelKey: "orders",
    icon: "ShoppingBag",
    count: 87,
    items: [
      {
        href: (l) => `/${l}/orders`,
        labelKey: "ordersActive",
        badge: 3,
        indicator: "success",
        kbd: "G O",
      },
      { href: (l) => `/${l}/orders/history`, labelKey: "ordersHistory" },
      {
        href: (l) => `/${l}/orders/refunds`,
        labelKey: "ordersRefunds",
        indicator: "warning",
      },
      { href: (l) => `/${l}/orders/filters`, labelKey: "ordersFilters" },
    ],
  },
  {
    kind: "group",
    id: "menu",
    labelKey: "menu",
    icon: "UtensilsCrossed",
    items: [
      { href: (l) => `/${l}/menu`, labelKey: "menuCategories", kbd: "G M" },
      { href: (l) => `/${l}/menu/products`, labelKey: "menuProducts" },
      { href: (l) => `/${l}/menu/modifiers`, labelKey: "menuModifiers" },
      { href: (l) => `/${l}/menu/publish-history`, labelKey: "menuPublishHistory" },
    ],
  },
  {
    kind: "group",
    id: "promotions",
    labelKey: "promotions",
    icon: "Tag",
    items: [
      { href: (l) => `/${l}/promotions`, labelKey: "promotionsCampaigns" },
      { href: (l) => `/${l}/promotions/happy-hour`, labelKey: "promotionsHappyHour" },
      { href: (l) => `/${l}/promotions/discounts`, labelKey: "promotionsDiscounts" },
    ],
  },
  {
    kind: "group",
    id: "reports",
    labelKey: "reports",
    icon: "BarChart3",
    items: [
      { href: (l) => `/${l}/reports`, labelKey: "reportsRevenue" },
      { href: (l) => `/${l}/reports/top-sellers`, labelKey: "reportsTopSellers" },
      { href: (l) => `/${l}/reports/hourly`, labelKey: "reportsHourly" },
      { href: (l) => `/${l}/reports/mwst`, labelKey: "reportsMwst" },
      { href: (l) => `/${l}/reports/export`, labelKey: "reportsExport" },
    ],
  },
  {
    kind: "group",
    id: "customers",
    labelKey: "customers",
    icon: "UsersRound",
    items: [
      { href: (l) => `/${l}/customers`, labelKey: "customersList" },
      { href: (l) => `/${l}/customers/loyalty`, labelKey: "customersLoyalty" },
      { href: (l) => `/${l}/customers/feedback`, labelKey: "customersFeedback" },
    ],
  },
  {
    kind: "group",
    id: "inventory",
    labelKey: "inventory",
    icon: "Package",
    items: [
      { href: (l) => `/${l}/inventory`, labelKey: "inventoryStock" },
      { href: (l) => `/${l}/inventory/suppliers`, labelKey: "inventorySuppliers" },
      { href: (l) => `/${l}/inventory/reorder`, labelKey: "inventoryReorder" },
    ],
  },
  {
    kind: "leaf",
    href: (l) => `/${l}/team`,
    labelKey: "team",
    icon: "Users",
  },
  {
    kind: "group",
    id: "users",
    labelKey: "users",
    icon: "UserCog",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/users`, labelKey: "usersList" },
      { href: (l) => `/${l}/users/roles`, labelKey: "usersRoles" },
      { href: (l) => `/${l}/users/activity`, labelKey: "usersActivity" },
    ],
  },
  {
    kind: "group",
    id: "restaurant-management",
    labelKey: "restaurantManagement",
    icon: "Building2",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/organization/restaurants`, labelKey: "rmList" },
      { href: (l) => `/${l}/restaurant-management/devices`, labelKey: "rmDevices", placeholder: true },
      { href: (l) => `/${l}/restaurant-management/opening-hours`, labelKey: "rmOpeningHours" },
      { href: (l) => `/${l}/restaurant-management/tax-profiles`, labelKey: "rmTaxProfiles" },
      { href: (l) => `/${l}/restaurant-management/receipt-templates`, labelKey: "rmReceiptTemplates" },
      { href: (l) => `/${l}/restaurant-management/payment-methods`, labelKey: "rmPaymentMethods" },
    ],
  },
  // ─────── HEADQUARTERS section ───────
  {
    kind: "group",
    id: "master-menu",
    labelKey: "masterMenu",
    icon: "Globe2",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/organization/menu`, labelKey: "masterMenuCategories" },
      { href: (l) => `/${l}/organization/menu/products`, labelKey: "masterMenuProducts" },
      { href: (l) => `/${l}/organization/menu/publish-history`, labelKey: "masterMenuPublish" },
    ],
  },
  {
    kind: "group",
    id: "menu-policies",
    labelKey: "menuPolicies",
    icon: "Lock",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/organization/menu-policies`, labelKey: "policiesList" },
      { href: (l) => `/${l}/organization/menu-policies/new`, labelKey: "policiesNew" },
    ],
  },
  {
    kind: "group",
    id: "aggregate-reports",
    labelKey: "aggregateReports",
    icon: "BarChart4",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/organization/reports`, labelKey: "aggregateRevenue" },
      { href: (l) => `/${l}/organization/reports/comparison`, labelKey: "aggregateComparison" },
      { href: (l) => `/${l}/organization/reports/by-location`, labelKey: "aggregateByLocation" },
    ],
  },
  {
    kind: "group",
    id: "organization",
    labelKey: "organization",
    icon: "Landmark",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/organization/info`, labelKey: "orgInfo" },
      { href: (l) => `/${l}/organization/billing`, labelKey: "orgBilling" },
      { href: (l) => `/${l}/organization/plan`, labelKey: "orgPlan" },
    ],
  },
  {
    kind: "group",
    id: "settings",
    labelKey: "settings",
    icon: "Settings",
    items: [
      { href: (l) => `/${l}/settings`, labelKey: "settingsProfile" },
      { href: (l) => `/${l}/settings?tab=password`, labelKey: "settingsPassword" },
      { href: (l) => `/${l}/settings?tab=notifications`, labelKey: "settingsNotifications" },
      { href: (l) => `/${l}/settings?tab=apikeys`, labelKey: "settingsApiKeys" },
      { href: (l) => `/${l}/settings/integrations`, labelKey: "settingsIntegrations" },
      { href: (l) => `/${l}/settings?tab=audit`, labelKey: "settingsAudit" },
    ],
  },
  // F1 — Super admin only (admin_users.is_super_admin=TRUE, migration 024).
  // Renders below settings as a leaf row; sidebar renderer filters out unless
  // the prop `isSuperAdmin` on Sidebar is true.
  {
    kind: "leaf",
    href: (l) => `/${l}/admin/tenants`,
    labelKey: "tenants",
    icon: "ShieldCheck",
    superAdminOnly: true,
  },
];

// Mark groups in the bottom (HQ headquarters) section so the renderer can
// inject a section header above them.
export const HQ_SECTION_GROUP_IDS = new Set([
  "master-menu",
  "menu-policies",
  "aggregate-reports",
  "organization",
]);
