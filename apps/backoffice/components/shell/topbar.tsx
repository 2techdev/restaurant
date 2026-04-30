"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { LogOut, Search } from "lucide-react";
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
import { usePalette } from "@/components/shell/command-palette";
import type { AdminUser } from "@/lib/api-types";

export function Topbar({ locale, user }: { locale: string; user: AdminUser }) {
  const tAuth = useTranslations("auth");
  const router = useRouter();
  const palette = usePalette();
  const [isMac, setIsMac] = React.useState(false);

  React.useEffect(() => {
    setIsMac(/Mac/i.test(navigator.platform));
  }, []);

  const onLogout = async () => {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push(`/${locale}/login`);
    router.refresh();
  };

  return (
    <header className="flex h-14 items-center justify-between border-b border-border bg-card/30 backdrop-blur-sm px-4">
      <div className="flex items-center gap-3">
        <TenantSwitcher />
      </div>

      {/* Center: Command palette trigger (display only — opens palette on click). */}
      <button
        type="button"
        onClick={palette.open}
        className="hidden md:flex items-center gap-2 rounded-md border border-border bg-background/50 px-3 h-8 min-w-[260px] text-[12.5px] text-muted-foreground hover:bg-accent/40 transition-colors"
        aria-label="Komut paletini aç"
      >
        <Search className="h-3.5 w-3.5" />
        <span className="flex-1 text-left">Sayfa, eylem ara…</span>
        <kbd className="font-mono text-[10px] px-1.5 py-0.5 rounded border border-border bg-muted/50 text-muted-foreground tracking-wider">
          {isMac ? "⌘" : "Ctrl"} K
        </kbd>
      </button>

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
