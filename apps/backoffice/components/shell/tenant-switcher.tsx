"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { Check, ChevronsUpDown, Building2, Store } from "lucide-react";
import { Button } from "@/components/ui/button";
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

export function TenantSwitcher() {
  const t = useTranslations("tenant");
  const router = useRouter();
  const { user, tenants, activeTenantId, setActive } = useTenant();
  const isHq = canManageHq(user.role);

  const activeTenant = tenants.find((x) => x.id === activeTenantId);
  const label =
    activeTenantId === "all" ? t("all") : activeTenant?.name ?? t("switcher");

  const onSelect = (id: string) => {
    setActive(id);
    router.refresh();
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="gap-2 min-w-[160px] justify-between">
          <span className="flex items-center gap-2 truncate">
            {activeTenantId === "all" ? <Building2 className="h-4 w-4" /> : <Store className="h-4 w-4" />}
            <span className="truncate">{label}</span>
          </span>
          <ChevronsUpDown className="h-3.5 w-3.5 opacity-50" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="min-w-[220px]">
        <DropdownMenuLabel>{t("switcher")}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {isHq && (
          <DropdownMenuItem onSelect={() => onSelect("all")}>
            <Building2 className="h-4 w-4" />
            {t("all")}
            {activeTenantId === "all" && <Check className="ml-auto h-4 w-4" />}
          </DropdownMenuItem>
        )}
        {tenants.map((x) => (
          <DropdownMenuItem key={x.id} onSelect={() => onSelect(x.id)}>
            <Store className="h-4 w-4" />
            <span className="truncate">{x.name}</span>
            {activeTenantId === x.id && <Check className="ml-auto h-4 w-4" />}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
