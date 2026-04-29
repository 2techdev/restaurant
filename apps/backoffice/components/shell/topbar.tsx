"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { ThemeToggle } from "@/components/theme/theme-toggle";
import { LocaleSwitcher } from "@/components/shell/locale-switcher";
import { TenantSwitcher } from "@/components/shell/tenant-switcher";
import type { AdminUser } from "@/lib/api-types";

export function Topbar({ locale, user }: { locale: string; user: AdminUser }) {
  const tAuth = useTranslations("auth");
  const router = useRouter();

  const onLogout = async () => {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push(`/${locale}/login`);
    router.refresh();
  };

  return (
    <header className="flex h-16 items-center justify-between border-b bg-card/30 backdrop-blur-sm px-6">
      <div className="flex items-center gap-3">
        <TenantSwitcher />
      </div>
      <div className="flex items-center gap-2">
        <LocaleSwitcher locale={locale} variant="dropdown" />
        <ThemeToggle />
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="sm" className="gap-2">
              <span className="hidden sm:inline">{user.name}</span>
              <span className="text-xs text-muted-foreground">{user.role}</span>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-60">
            <DropdownMenuLabel>{tAuth("loggedInAs", { name: user.name })}</DropdownMenuLabel>
            <DropdownMenuLabel className="text-xs text-muted-foreground font-normal">
              {user.email}
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={onLogout}>
              <LogOut className="h-4 w-4" />
              {tAuth("logout")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
