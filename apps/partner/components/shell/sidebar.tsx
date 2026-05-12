"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  LayoutDashboard,
  Building2,
  Store,
  CreditCard,
  Users,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { PartnerUser } from "@/lib/auth";

interface NavItem {
  href: (l: string) => string;
  labelKey: string;
  icon: LucideIcon;
  minRole?: PartnerUser["role"];
}

const NAV: NavItem[] = [
  { href: (l) => `/${l}/dashboard`, labelKey: "dashboard", icon: LayoutDashboard },
  { href: (l) => `/${l}/brands`,    labelKey: "brands",    icon: Building2 },
  { href: (l) => `/${l}/stores`,    labelKey: "stores",    icon: Store },
  { href: (l) => `/${l}/editions`,  labelKey: "editions",  icon: CreditCard, minRole: "MANAGER" },
  { href: (l) => `/${l}/employees`, labelKey: "employees", icon: Users,      minRole: "OPERATOR" },
];

const RANK = { EMPLOYEE: 1, MANAGER: 2, BD: 3, OPERATOR: 4 } as const;

export function Sidebar({ locale, role }: { locale: string; role: PartnerUser["role"] }) {
  const t = useTranslations("nav");
  const pathname = usePathname();
  const visible = NAV.filter((n) => !n.minRole || RANK[role] >= RANK[n.minRole]);

  return (
    <aside className="flex w-58 flex-col border-r border-border bg-background text-foreground">
      <div className="flex h-14 items-center px-4 border-b border-border">
        <span className="text-[15px] font-semibold tracking-tight text-white">
          GastroCore Partner
        </span>
      </div>
      <nav className="flex-1 overflow-y-auto px-2 py-3 space-y-px">
        {visible.map((item) => {
          const href = item.href(locale);
          const active = pathname === href || pathname.startsWith(href + "/");
          const Icon = item.icon;
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex h-9 items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors",
                active
                  ? "bg-accent text-accent-foreground font-medium"
                  : "text-muted-foreground hover:bg-accent/50 hover:text-foreground",
              )}
            >
              <Icon className={cn("h-4 w-4 shrink-0", active && "text-primary")} />
              <span className="truncate">{t(item.labelKey)}</span>
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
