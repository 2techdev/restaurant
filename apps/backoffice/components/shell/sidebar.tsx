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
  Plus,
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
  type NavIndicator,
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

const INDICATOR_CLASS: Record<NavIndicator, string> = {
  success: "bg-success",
  warning: "bg-warning",
  error: "bg-error",
  info: "bg-info",
};

function pathOf(href: string): string {
  const q = href.indexOf("?");
  return q >= 0 ? href.slice(0, q) : href;
}

function isItemActive(itemHref: string, pathname: string): boolean {
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
      // ignore
    }
    setHydrated(true);
  }, []);

  React.useEffect(() => {
    if (!hydrated) return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(expanded));
    } catch {
      // ignore quota
    }
  }, [expanded, hydrated]);

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
    <aside
      data-sidebar="true"
      className={cn(
        // 232px = w-58 (custom). Always-dark via [data-sidebar=true] CSS scope.
        "flex w-58 flex-col border-r border-border",
        "bg-background text-foreground"
      )}
    >
      <div className="flex h-14 items-center px-4 border-b border-border">
        <span className="text-[15px] font-semibold tracking-tight text-white">
          GastroCore
        </span>
      </div>
      <nav className="flex-1 overflow-y-auto px-2 py-3 space-y-px">
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
      <div className="px-3 py-2 text-[10px] font-mono text-muted-foreground border-t border-border tabular-nums">
        v0.2 · pilot
      </div>
    </aside>
  );
}

function entryKey(e: NavEntry): string {
  if (e.kind === "leaf") return "leaf:" + e.labelKey;
  return "group:" + e.id;
}

function IndicatorDot({ kind }: { kind: NavIndicator }) {
  return (
    <span
      aria-hidden
      className={cn("h-1.5 w-1.5 rounded-full shrink-0", INDICATOR_CLASS[kind])}
    />
  );
}

function CountBadge({ value }: { value: number | string }) {
  return (
    <span className="ml-auto text-[10px] font-mono text-muted-foreground tabular-nums">
      {value}
    </span>
  );
}

function Kbd({ value }: { value: string }) {
  return (
    <kbd className="ml-auto font-mono text-[9px] px-1.5 py-0.5 rounded border border-border bg-accent/40 text-muted-foreground tracking-wider">
      {value}
    </kbd>
  );
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
            // 26px row height
            "group flex h-6.5 items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors",
            active
              ? "bg-accent text-accent-foreground font-medium"
              : "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
          )}
        >
          <Icon className={cn("h-4 w-4 shrink-0", active && "text-primary")} />
          <span className="truncate flex-1">{t(entry.labelKey)}</span>
          {entry.indicator && <IndicatorDot kind={entry.indicator} />}
          {entry.badge != null && <CountBadge value={entry.badge} />}
          {entry.kbd && !entry.badge && <Kbd value={entry.kbd} />}
        </Link>
      </>
    );
  }

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
          "group w-full flex h-6.5 items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors",
          groupActive
            ? "text-foreground font-medium"
            : "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
        )}
      >
        <Icon
          className={cn(
            "h-4 w-4 shrink-0",
            groupActive && "text-primary"
          )}
        />
        <span className="truncate flex-1 text-left">
          {t(entry.labelKey)}
        </span>
        {entry.count != null && <CountBadge value={entry.count} />}
        <ChevronRight
          className={cn(
            "h-3.5 w-3.5 shrink-0 text-muted-foreground/60 transition-transform duration-200",
            isOpen && "rotate-90",
            entry.count != null && "ml-1"
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
          <ul className="ml-4 mt-px mb-1 border-l border-border/70 space-y-px">
            {entry.items.map((it) => {
              const href = it.href(locale);
              const active = isItemActive(pathOf(href), pathname);
              return (
                <li key={it.labelKey}>
                  <Link
                    href={href}
                    className={cn(
                      // 26px row, indented, left-border accent on active
                      "flex h-6.5 items-center gap-2 rounded-r-md pr-2 pl-3 text-[12.5px] transition-colors -ml-px border-l-2",
                      active
                        ? "border-primary bg-primary/10 text-foreground font-medium"
                        : "border-transparent text-muted-foreground hover:text-foreground hover:bg-accent/40"
                    )}
                  >
                    {it.indicator && <IndicatorDot kind={it.indicator} />}
                    <span className="truncate flex-1">{t(it.labelKey)}</span>
                    {it.placeholder && (
                      <span className="text-[9px] uppercase font-mono text-muted-foreground/60 tracking-wider">
                        SOON
                      </span>
                    )}
                    {it.badge != null && <CountBadge value={it.badge} />}
                    {it.kbd && !it.badge && !it.placeholder && (
                      <Kbd value={it.kbd} />
                    )}
                  </Link>
                </li>
              );
            })}
            {entry.action && (
              <li>
                <Link
                  href={entry.action.href(locale)}
                  className="flex h-6.5 items-center gap-2 rounded-r-md pr-2 pl-3 text-[12px] -ml-px border-l-2 border-transparent text-muted-foreground/70 hover:text-foreground hover:bg-accent/40"
                >
                  <Plus className="h-3 w-3" />
                  {t(entry.action.labelKey)}
                </Link>
              </li>
            )}
          </ul>
        </div>
      </div>
    </>
  );
}

function HqSectionHeader() {
  const t = useTranslations("nav");
  return (
    <div className="mt-4 mb-1 px-2 pt-1 text-[10px] font-semibold text-muted-foreground/70 uppercase tracking-wider">
      {t("headquarters")}
    </div>
  );
}
