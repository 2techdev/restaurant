"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
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
  ChevronRight,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { canManageHq } from "@/lib/roles";
import type { UserRole } from "@/lib/api-types";
import {
  NAV_CONFIG,
  HQ_SECTION_GROUP_IDS,
  type NavEntry,
  type NavGroup,
} from "@/lib/nav-config";

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

const STORAGE_KEY = "bo_sidebar_expanded";

function pathOf(href: string): string {
  const q = href.indexOf("?");
  return q >= 0 ? href.slice(0, q) : href;
}

function isItemActive(itemHref: string, pathname: string): boolean {
  // Exact match wins; otherwise treat the item path as a prefix (so
  // /tr/orders/history under /tr/orders still highlights its row).
  return pathname === itemHref || pathname.startsWith(itemHref + "/");
}

function groupContainsActive(group: NavGroup, locale: string, pathname: string): boolean {
  return group.items.some((it) => isItemActive(pathOf(it.href(locale)), pathname));
}

export function Sidebar({ locale, role }: { locale: string; role: UserRole | string }) {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const isHq = canManageHq(role);

  const visible = NAV_CONFIG.filter((e) => !e.hqOnly || isHq);

  // Each group's expanded state. Default: groups containing the active route
  // start expanded. After hydration we merge with localStorage so the user's
  // last preference wins.
  const initialExpanded = React.useMemo<Record<string, boolean>>(() => {
    const out: Record<string, boolean> = {};
    for (const e of visible) {
      if (e.kind !== "group") continue;
      out[e.id] = groupContainsActive(e, locale, pathname);
    }
    return out;
  }, [visible, locale, pathname]);

  const [expanded, setExpanded] = React.useState<Record<string, boolean>>(initialExpanded);
  const [hydrated, setHydrated] = React.useState(false);

  React.useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const saved = JSON.parse(raw) as Record<string, boolean>;
        setExpanded((prev) => ({ ...prev, ...saved }));
      }
    } catch {
      // ignore — default expansion still applies
    }
    setHydrated(true);
  }, []);

  React.useEffect(() => {
    if (!hydrated) return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(expanded));
    } catch {
      // ignore quota / private mode
    }
  }, [expanded, hydrated]);

  // When the user navigates to a new route, ensure that route's group is
  // expanded (auto-open on click of an indirect entry).
  React.useEffect(() => {
    setExpanded((prev) => {
      const next = { ...prev };
      let changed = false;
      for (const e of visible) {
        if (e.kind !== "group") continue;
        if (groupContainsActive(e, locale, pathname) && !next[e.id]) {
          next[e.id] = true;
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [visible, locale, pathname]);

  const toggle = (id: string) =>
    setExpanded((prev) => ({ ...prev, [id]: !prev[id] }));

  return (
    <aside className="flex w-64 flex-col border-r bg-card/50 backdrop-blur-sm">
      <div className="flex h-16 items-center px-6 border-b">
        <span className="text-lg font-bold tracking-tight">GastroCore</span>
      </div>
      <nav className="flex-1 overflow-y-auto p-3 space-y-0.5">
        {visible.map((entry, idx) => {
          const isFirstHq =
            entry.kind === "group" &&
            HQ_SECTION_GROUP_IDS.has(entry.id) &&
            !visible
              .slice(0, idx)
              .some((e) => e.kind === "group" && HQ_SECTION_GROUP_IDS.has(e.id));
          return (
            <NavRow
              key={entryKey(entry)}
              entry={entry}
              locale={locale}
              pathname={pathname}
              expandedMap={expanded}
              onToggle={toggle}
              t={t}
              insertHqHeader={isFirstHq}
            />
          );
        })}
      </nav>
      <div className="px-4 py-3 text-[10px] text-muted-foreground border-t">
        v0.2 · pilot
      </div>
    </aside>
  );
}

function entryKey(e: NavEntry): string {
  if (e.kind === "leaf") return "leaf:" + e.labelKey;
  return "group:" + e.id;
}

function NavRow({
  entry,
  locale,
  pathname,
  expandedMap,
  onToggle,
  t,
  insertHqHeader,
}: {
  entry: NavEntry;
  locale: string;
  pathname: string;
  expandedMap: Record<string, boolean>;
  onToggle: (id: string) => void;
  t: (key: string) => string;
  insertHqHeader?: boolean;
}) {
  if (entry.kind === "leaf") {
    const Icon = ICONS[entry.icon] ?? LayoutDashboard;
    const href = entry.href(locale);
    const active = isItemActive(pathOf(href), pathname);
    return (
      <>
        {insertHqHeader && <HqSectionHeader />}
        <Link
          href={href}
          className={cn(
            "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
            active
              ? "bg-accent text-accent-foreground"
              : "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
          )}
        >
          <Icon className="h-4 w-4" />
          {t(entry.labelKey)}
        </Link>
      </>
    );
  }

  // group
  const Icon = ICONS[entry.icon] ?? LayoutDashboard;
  const isOpen = !!expandedMap[entry.id];
  const groupActive = groupContainsActive(entry, locale, pathname);

  return (
    <>
      {insertHqHeader && <HqSectionHeader />}
      <button
        type="button"
        onClick={() => onToggle(entry.id)}
        aria-expanded={isOpen}
        className={cn(
          "w-full flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
          groupActive
            ? "text-foreground"
            : "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
        )}
      >
        <Icon
          className={cn(
            "h-4 w-4 shrink-0",
            groupActive && "text-primary"
          )}
        />
        <span className={cn("flex-1 text-left", groupActive && "font-semibold")}>
          {t(entry.labelKey)}
        </span>
        <ChevronRight
          className={cn(
            "h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-200",
            isOpen && "rotate-90"
          )}
        />
      </button>

      <div
        className={cn(
          "grid transition-all duration-200 ease-in-out",
          isOpen ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"
        )}
      >
        <div className="overflow-hidden">
          <ul className="ml-4 mt-0.5 mb-1 border-l border-border space-y-0.5">
            {entry.items.map((it) => {
              const href = it.href(locale);
              const active = isItemActive(pathOf(href), pathname);
              return (
                <li key={it.labelKey}>
                  <Link
                    href={href}
                    className={cn(
                      "block rounded-r-md py-1.5 pr-3 text-[13px] transition-colors -ml-px border-l-2",
                      active
                        ? "border-primary bg-primary/10 text-foreground font-medium pl-4"
                        : "border-transparent text-muted-foreground hover:text-foreground hover:bg-accent/40 pl-4"
                    )}
                  >
                    {t(it.labelKey)}
                    {it.placeholder && (
                      <span className="ml-1.5 text-[10px] uppercase opacity-50">
                        ·
                      </span>
                    )}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </>
  );
}

function HqSectionHeader() {
  const t = useTranslations("nav");
  return (
    <div className="mt-4 mb-1 flex items-center gap-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
      <span className="h-px flex-1 bg-border" aria-hidden />
      {t("headquarters")}
      <span className="h-px flex-1 bg-border" aria-hidden />
    </div>
  );
}
