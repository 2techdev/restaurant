"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Check, ChevronsUpDown, Building2 } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useTenant } from "./tenant-context";
import { canManageHq } from "@/lib/roles";
import { cn } from "@/lib/utils";

/**
 * Cherry-picked from designer canvas:
 *  - 26×26 gradient avatar (indigo for restaurant, amber for HQ)
 *  - 2-line trigger: name (12px white 500) + sub-info (10px mono mute)
 *  - Sub-info shows tenant kind + identifier (e.g. CHE-145.892.012)
 */
export function TenantSwitcher() {
  const t = useTranslations("tenant");
  const router = useRouter();
  const { user, tenants, activeTenantId, setActive } = useTenant();
  const isHq = canManageHq(user.role);

  const activeTenant = tenants.find((x) => x.id === activeTenantId);
  const aggregate = activeTenantId === "all";
  const label = aggregate ? t("all") : activeTenant?.name ?? t("switcher");

  // Sub-info line (10px mono, muted). Tenant doesn't (yet) carry a fiscal id;
  // fall back to short tenant.id for now — when CHE-XXX gets wired up the
  // backend will populate `Tenant.uid` and we just point to it here.
  const tenantUid = (activeTenant as { uid?: string } | undefined)?.uid;
  const tenantShort = activeTenant?.id ? activeTenant.id.slice(0, 8) : "—";
  const subInfo = aggregate
    ? `${tenants.length} lokasyon`
    : `Tek Restoran · ${tenantUid ?? tenantShort}`;

  const onSelect = (id: string) => {
    setActive(id);
    router.refresh();
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          className={cn(
            "flex items-center gap-2.5 rounded-md px-2 py-1.5 transition-colors",
            "hover:bg-accent/50 focus-visible:bg-accent focus-visible:outline-none"
          )}
        >
          <Avatar aggregate={aggregate} initial={label[0] ?? "?"} />
          <div className="flex flex-col items-start leading-tight min-w-0">
            <span className="text-[12px] font-medium text-foreground truncate max-w-[180px]">
              {label}
            </span>
            <span className="text-[10px] font-mono text-muted-foreground truncate max-w-[180px]">
              {subInfo}
            </span>
          </div>
          <ChevronsUpDown className="h-3.5 w-3.5 opacity-50 ml-1" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[260px]">
        <DropdownMenuLabel>{t("switcher")}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {isHq && (
          <DropdownMenuItem onSelect={() => onSelect("all")} className="gap-2">
            <Avatar aggregate initial="∑" />
            <span className="flex-1">{t("all")}</span>
            {aggregate && <Check className="ml-auto h-4 w-4" />}
          </DropdownMenuItem>
        )}
        {tenants.map((x) => (
          <DropdownMenuItem
            key={x.id}
            onSelect={() => onSelect(x.id)}
            className="gap-2"
          >
            <Avatar initial={x.name[0] ?? "?"} />
            <span className="truncate flex-1">{x.name}</span>
            {activeTenantId === x.id && <Check className="ml-auto h-4 w-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function Avatar({ aggregate, initial }: { aggregate?: boolean; initial: string }) {
  return (
    <div
      className={cn(
        "flex h-6.5 w-6.5 shrink-0 items-center justify-center rounded-md text-[11px] font-semibold text-white",
        aggregate
          ? "bg-gradient-to-br from-amber-400 to-amber-600"
          : "bg-gradient-to-br from-indigo-500 to-indigo-700"
      )}
    >
      {aggregate ? (
        <Building2 className="h-3.5 w-3.5" />
      ) : (
        <span>{initial.toUpperCase()}</span>
      )}
    </div>
  );
}

