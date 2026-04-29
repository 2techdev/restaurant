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

export type NavLeaf = {
  kind: "leaf";
  href: (locale: string) => string;
  labelKey: string; // i18n key under namespace `nav`
  icon: string;
  hqOnly?: boolean;
};

export type NavGroup = {
  kind: "group";
  id: string;
  labelKey: string;
  icon: string;
  hqOnly?: boolean;
  items: {
    href: (locale: string) => string;
    labelKey: string;
    placeholder?: boolean;
  }[];
};

export type NavEntry = NavLeaf | NavGroup;

export const NAV_CONFIG: NavEntry[] = [
  {
    kind: "leaf",
    href: (l) => `/${l}/dashboard`,
    labelKey: "dashboard",
    icon: "LayoutDashboard",
  },
  {
    kind: "group",
    id: "orders",
    labelKey: "orders",
    icon: "ShoppingBag",
    items: [
      { href: (l) => `/${l}/orders`, labelKey: "ordersActive" },
      { href: (l) => `/${l}/orders/history`, labelKey: "ordersHistory", placeholder: true },
      { href: (l) => `/${l}/orders/refunds`, labelKey: "ordersRefunds", placeholder: true },
      { href: (l) => `/${l}/orders/filters`, labelKey: "ordersFilters", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "menu",
    labelKey: "menu",
    icon: "UtensilsCrossed",
    items: [
      { href: (l) => `/${l}/menu`, labelKey: "menuCategories" },
      { href: (l) => `/${l}/menu/products`, labelKey: "menuProducts", placeholder: true },
      { href: (l) => `/${l}/menu/modifiers`, labelKey: "menuModifiers", placeholder: true },
      { href: (l) => `/${l}/menu/publish-history`, labelKey: "menuPublishHistory", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "promotions",
    labelKey: "promotions",
    icon: "Tag",
    items: [
      { href: (l) => `/${l}/promotions`, labelKey: "promotionsCampaigns" },
      { href: (l) => `/${l}/promotions/happy-hour`, labelKey: "promotionsHappyHour", placeholder: true },
      { href: (l) => `/${l}/promotions/discounts`, labelKey: "promotionsDiscounts", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "reports",
    labelKey: "reports",
    icon: "BarChart3",
    items: [
      { href: (l) => `/${l}/reports`, labelKey: "reportsRevenue" },
      { href: (l) => `/${l}/reports/top-sellers`, labelKey: "reportsTopSellers", placeholder: true },
      { href: (l) => `/${l}/reports/hourly`, labelKey: "reportsHourly", placeholder: true },
      { href: (l) => `/${l}/reports/mwst`, labelKey: "reportsMwst", placeholder: true },
      { href: (l) => `/${l}/reports/export`, labelKey: "reportsExport", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "customers",
    labelKey: "customers",
    icon: "UsersRound",
    items: [
      { href: (l) => `/${l}/customers`, labelKey: "customersList", placeholder: true },
      { href: (l) => `/${l}/customers/loyalty`, labelKey: "customersLoyalty", placeholder: true },
      { href: (l) => `/${l}/customers/feedback`, labelKey: "customersFeedback", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "inventory",
    labelKey: "inventory",
    icon: "Package",
    items: [
      { href: (l) => `/${l}/inventory`, labelKey: "inventoryStock", placeholder: true },
      { href: (l) => `/${l}/inventory/suppliers`, labelKey: "inventorySuppliers", placeholder: true },
      { href: (l) => `/${l}/inventory/reorder`, labelKey: "inventoryReorder", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "users",
    labelKey: "users",
    icon: "UserCog",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/users`, labelKey: "usersList" },
      { href: (l) => `/${l}/users/roles`, labelKey: "usersRoles", placeholder: true },
      { href: (l) => `/${l}/users/activity`, labelKey: "usersActivity", placeholder: true },
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
      { href: (l) => `/${l}/restaurant-management/opening-hours`, labelKey: "rmOpeningHours", placeholder: true },
      { href: (l) => `/${l}/restaurant-management/tax-profiles`, labelKey: "rmTaxProfiles", placeholder: true },
      { href: (l) => `/${l}/restaurant-management/receipt-templates`, labelKey: "rmReceiptTemplates", placeholder: true },
      { href: (l) => `/${l}/restaurant-management/payment-methods`, labelKey: "rmPaymentMethods", placeholder: true },
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
      { href: (l) => `/${l}/organization/menu/products`, labelKey: "masterMenuProducts", placeholder: true },
      { href: (l) => `/${l}/organization/menu/publish-history`, labelKey: "masterMenuPublish", placeholder: true },
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
      { href: (l) => `/${l}/organization/menu-policies/new`, labelKey: "policiesNew", placeholder: true },
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
      { href: (l) => `/${l}/organization/reports/comparison`, labelKey: "aggregateComparison", placeholder: true },
      { href: (l) => `/${l}/organization/reports/by-location`, labelKey: "aggregateByLocation", placeholder: true },
    ],
  },
  {
    kind: "group",
    id: "organization",
    labelKey: "organization",
    icon: "Landmark",
    hqOnly: true,
    items: [
      { href: (l) => `/${l}/organization/info`, labelKey: "orgInfo", placeholder: true },
      { href: (l) => `/${l}/organization/billing`, labelKey: "orgBilling", placeholder: true },
      { href: (l) => `/${l}/organization/plan`, labelKey: "orgPlan", placeholder: true },
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
      { href: (l) => `/${l}/settings/integrations`, labelKey: "settingsIntegrations", placeholder: true },
      { href: (l) => `/${l}/settings?tab=audit`, labelKey: "settingsAudit" },
    ],
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
