"use client";

import { useRouter } from "next/navigation";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useTranslations } from "next-intl";
import type { PartnerUser } from "@/lib/auth";

export function Topbar({ locale, user }: { locale: string; user: PartnerUser }) {
  const t = useTranslations("auth");
  const router = useRouter();
  const onLogout = async () => {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push(`/${locale}/login`);
    router.refresh();
  };
  return (
    <header className="flex h-14 items-center justify-between border-b border-border px-4">
      <div className="flex items-center gap-3">
        <span className="text-xs font-mono text-muted-foreground">
          {user.role}
        </span>
        <span className="text-sm text-foreground">{user.name}</span>
        <span className="text-xs text-muted-foreground">·</span>
        <span className="text-xs text-muted-foreground">{user.email}</span>
      </div>
      <Button variant="ghost" size="sm" onClick={onLogout} className="gap-2">
        <LogOut className="h-4 w-4" />
        {t("logout")}
      </Button>
    </header>
  );
}
