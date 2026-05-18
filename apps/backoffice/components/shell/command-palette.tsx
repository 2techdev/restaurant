"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
  CommandShortcut,
} from "@/components/ui/command";
import {
  LayoutDashboard,
  ShoppingBag,
  UtensilsCrossed,
  BarChart3,
  Settings as SettingsIcon,
  Building2,
  Globe2,
  Lock,
  Tag,
  Package,
  UsersRound,
  UserCog,
  Landmark,
  BarChart4,
  Plus,
  Send,
  Receipt,
  User as UserIcon,
  Pizza,
  Folder,
  type LucideIcon,
} from "lucide-react";
import { useTenant } from "./tenant-context";
import { canManageHq } from "@/lib/roles";
import { NAV_CONFIG, type NavEntry } from "@/lib/nav-config";
import { clientFetch } from "@/lib/api-client";

const ICONS: Record<string, LucideIcon> = {
  LayoutDashboard,
  ShoppingBag,
  UtensilsCrossed,
  BarChart3,
  Settings: SettingsIcon,
  Building2,
  Globe2,
  Lock,
  Tag,
  Package,
  UsersRound,
  UserCog,
  Landmark,
  BarChart4,
};

interface PaletteContextValue {
  open: () => void;
}
const PaletteCtx = React.createContext<PaletteContextValue | null>(null);

interface DynamicIndex {
  products: Array<{ id: string; name: string }>;
  categories: Array<{ id: string; name: string }>;
  users: Array<{ id: string; name: string; email?: string }>;
}

const EMPTY_INDEX: DynamicIndex = { products: [], categories: [], users: [] };

/**
 * Singleton command palette mounted once at the dashboard layout. Bound to
 * ⌘K / Ctrl+K globally; topbar search box opens the same dialog via
 * usePalette(). Lazily fetches a per-tenant index (products / categories /
 * team users) the first time the palette opens, then reuses it for the
 * rest of the session — refreshed when the active tenant changes.
 */
export function CommandPaletteProvider({
  locale,
  children,
}: {
  locale: string;
  children: React.ReactNode;
}) {
  const tNav = useTranslations("nav");
  const tCmd = useTranslations("cmdk");
  const router = useRouter();
  const tenant = useTenant();
  const isHq = canManageHq(tenant.user.role);

  const [open, setOpen] = React.useState(false);
  const [index, setIndex] = React.useState<DynamicIndex>(EMPTY_INDEX);
  const [indexLoaded, setIndexLoaded] = React.useState<string | null>(null);
  const activeTenantId = tenant.activeTenantId;

  // Global keyboard shortcut: ⌘K (mac) / Ctrl+K (everyone else).
  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // Lazy fetch the dynamic index when palette first opens (or active tenant
  // changes). 401s collapse to empty so the static nav is still useful.
  React.useEffect(() => {
    if (!open) return;
    if (indexLoaded === activeTenantId) return;
    let alive = true;
    (async () => {
      const safe = async <T,>(p: Promise<T>): Promise<T | null> => {
        try { return await p; } catch { return null; }
      };
      const [products, categories, users] = await Promise.all([
        safe(clientFetch<{ products?: Array<{ id: string; name: string }> } | Array<{ id: string; name: string }>>({ path: "/menu/products" })),
        safe(clientFetch<{ categories?: Array<{ id: string; name: string }> } | Array<{ id: string; name: string }>>({ path: "/menu/categories" })),
        safe(clientFetch<Array<{ id: string; name: string; email?: string }>>({ path: "/users" })),
      ]);
      if (!alive) return;
      const unwrap = <T,>(x: unknown, key: string): T[] => {
        if (Array.isArray(x)) return x as T[];
        const obj = x as Record<string, unknown> | null | undefined;
        const arr = obj?.[key];
        return Array.isArray(arr) ? (arr as T[]) : [];
      };
      setIndex({
        products:   unwrap<{ id: string; name: string }>(products,   "products"),
        categories: unwrap<{ id: string; name: string }>(categories, "categories"),
        users:      unwrap<{ id: string; name: string; email?: string }>(users, "data"),
      });
      setIndexLoaded(activeTenantId);
    })();
    return () => { alive = false; };
  }, [open, indexLoaded, activeTenantId]);

  const ctxValue = React.useMemo<PaletteContextValue>(
    () => ({ open: () => setOpen(true) }),
    []
  );

  const go = React.useCallback(
    (href: string) => {
      setOpen(false);
      router.push(href);
    },
    [router]
  );

  // Flatten nav-config to a list of navigable destinations.
  const navItems = React.useMemo(() => {
    const items: Array<{
      key: string;
      label: string;
      href: string;
      icon: LucideIcon;
    }> = [];
    const visible: NavEntry[] = NAV_CONFIG.filter((e) => !e.hqOnly || isHq);
    for (const entry of visible) {
      const Icon = ICONS[entry.icon] ?? LayoutDashboard;
      if (entry.kind === "leaf") {
        items.push({
          key: entry.labelKey,
          label: tNav(entry.labelKey),
          href: entry.href(locale),
          icon: Icon,
        });
      } else {
        for (const sub of entry.items) {
          items.push({
            key: `${entry.id}:${sub.labelKey}`,
            label: `${tNav(entry.labelKey)} → ${tNav(sub.labelKey)}`,
            href: sub.href(locale),
            icon: Icon,
          });
        }
      }
    }
    return items;
  }, [tNav, locale, isHq]);

  return (
    <PaletteCtx.Provider value={ctxValue}>
      {children}
      <CommandDialog open={open} onOpenChange={setOpen}>
        <CommandInput placeholder={tCmd("placeholder")} />
        <CommandList>
          <CommandEmpty>{tCmd("noResults")}</CommandEmpty>

          <CommandGroup heading={tCmd("groupQuickActions")}>
            <CommandItem onSelect={() => go(`/${locale}/orders/new`)}>
              <Plus />
              <span>{tCmd("actionNewOrder")}</span>
              <CommandShortcut>N O</CommandShortcut>
            </CommandItem>
            <CommandItem
              onSelect={() => go(`/${locale}/menu/publish-history`)}
            >
              <Send />
              <span>{tCmd("actionPublishMenu")}</span>
              <CommandShortcut>P M</CommandShortcut>
            </CommandItem>
            <CommandItem onSelect={() => go(`/${locale}/reports/mwst`)}>
              <Receipt />
              <span>{tCmd("actionMwstReport")}</span>
            </CommandItem>
          </CommandGroup>

          <CommandSeparator />

          <CommandGroup heading={tCmd("groupPages")}>
            {navItems.map((it) => {
              const Icon = it.icon;
              return (
                <CommandItem key={it.key} onSelect={() => go(it.href)}>
                  <Icon />
                  <span>{it.label}</span>
                </CommandItem>
              );
            })}
          </CommandGroup>

          {index.products.length > 0 && (
            <>
              <CommandSeparator />
              <CommandGroup heading={tCmd("groupProducts")}>
                {index.products.slice(0, 50).map((p) => (
                  <CommandItem
                    key={`prod-${p.id}`}
                    value={`product ${p.name}`}
                    onSelect={() => go(`/${locale}/menu/products?focus=${p.id}`)}
                  >
                    <Pizza />
                    <span>{p.name}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            </>
          )}

          {index.categories.length > 0 && (
            <>
              <CommandSeparator />
              <CommandGroup heading={tCmd("groupCategories")}>
                {index.categories.slice(0, 30).map((c) => (
                  <CommandItem
                    key={`cat-${c.id}`}
                    value={`category ${c.name}`}
                    onSelect={() => go(`/${locale}/menu`)}
                  >
                    <Folder />
                    <span>{c.name}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            </>
          )}

          {index.users.length > 0 && (
            <>
              <CommandSeparator />
              <CommandGroup heading={tCmd("groupUsers")}>
                {index.users.slice(0, 30).map((u) => (
                  <CommandItem
                    key={`user-${u.id}`}
                    value={`user ${u.name} ${u.email ?? ""}`}
                    onSelect={() => go(`/${locale}/team`)}
                  >
                    <UserIcon />
                    <span>{u.name}</span>
                    {u.email ? (
                      <span className="ml-auto text-xs text-muted-foreground">{u.email}</span>
                    ) : null}
                  </CommandItem>
                ))}
              </CommandGroup>
            </>
          )}

          {tenant.tenants.length > 0 && (
            <>
              <CommandSeparator />
              <CommandGroup heading={tCmd("groupSwitchTenant")}>
                {tenant.tenants.map((x) => (
                  <CommandItem
                    key={x.id}
                    value={`tenant ${x.name}`}
                    onSelect={() => {
                      tenant.setActive(x.id);
                      setOpen(false);
                      router.refresh();
                    }}
                  >
                    <Building2 />
                    <span>{x.name}</span>
                  </CommandItem>
                ))}
              </CommandGroup>
            </>
          )}
        </CommandList>
      </CommandDialog>
    </PaletteCtx.Provider>
  );
}

export function usePalette() {
  const ctx = React.useContext(PaletteCtx);
  if (!ctx) throw new Error("usePalette must be used inside CommandPaletteProvider");
  return ctx;
}
