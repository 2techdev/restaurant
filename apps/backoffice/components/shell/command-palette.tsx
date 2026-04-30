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
  type LucideIcon,
} from "lucide-react";
import { useTenant } from "./tenant-context";
import { canManageHq } from "@/lib/roles";
import { NAV_CONFIG, type NavEntry } from "@/lib/nav-config";

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

/**
 * Singleton command palette mounted once at the dashboard layout. Bound to
 * ⌘K / Ctrl+K globally; topbar search box opens the same dialog via
 * usePalette().
 */
export function CommandPaletteProvider({
  locale,
  children,
}: {
  locale: string;
  children: React.ReactNode;
}) {
  const t = useTranslations("nav");
  const router = useRouter();
  const tenant = useTenant();
  const isHq = canManageHq(tenant.user.role);

  const [open, setOpen] = React.useState(false);

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
          label: t(entry.labelKey),
          href: entry.href(locale),
          icon: Icon,
        });
      } else {
        for (const sub of entry.items) {
          items.push({
            key: `${entry.id}:${sub.labelKey}`,
            label: `${t(entry.labelKey)} → ${t(sub.labelKey)}`,
            href: sub.href(locale),
            icon: Icon,
          });
        }
      }
    }
    return items;
  }, [t, locale, isHq]);

  return (
    <PaletteCtx.Provider value={ctxValue}>
      {children}
      <CommandDialog open={open} onOpenChange={setOpen}>
        <CommandInput placeholder="Sayfa, eylem veya restoran ara…" />
        <CommandList>
          <CommandEmpty>Sonuç bulunamadı</CommandEmpty>

          <CommandGroup heading="Hızlı eylemler">
            <CommandItem onSelect={() => go(`/${locale}/orders/new`)}>
              <Plus />
              <span>Yeni Sipariş</span>
              <CommandShortcut>N O</CommandShortcut>
            </CommandItem>
            <CommandItem
              onSelect={() => go(`/${locale}/menu/publish-history`)}
            >
              <Send />
              <span>Menü Yayınla</span>
              <CommandShortcut>P M</CommandShortcut>
            </CommandItem>
            <CommandItem onSelect={() => go(`/${locale}/reports/mwst`)}>
              <Receipt />
              <span>Vergi Raporu Çıkar (MWST)</span>
            </CommandItem>
          </CommandGroup>

          <CommandSeparator />

          <CommandGroup heading="Sayfalara git">
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

          {tenant.tenants.length > 0 && (
            <>
              <CommandSeparator />
              <CommandGroup heading="Restoran değiştir">
                {tenant.tenants.map((x) => (
                  <CommandItem
                    key={x.id}
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
