"use client";

import * as React from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import {
  ChevronDown,
  CheckCircle2,
  Circle,
  X as XIcon,
  Sparkles,
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { Progress } from "@/components/ui/progress";
import { cn } from "@/lib/utils";
import { clientFetch } from "@/lib/api-client";

/**
 * Setup Progress Tracker pill — lives in the topbar between the tenant
 * switcher and the command-palette trigger. Shows a per-tenant onboarding
 * checklist (10–11 items) so a fresh restaurant has a visible "you're 63%
 * configured" indicator instead of nine half-filled pages with no signpost.
 *
 * Data: GET /api/v1/admin/setup-progress (Go server, internal/setup).
 * Hides automatically when the user has dismissed it (localStorage flag) or
 * when every required step is done. The dismiss state is per-tenant so
 * dismissing it on Pizzeria doesn't hide it for Burger House.
 */

interface Step {
  key: string;
  done: boolean;
  nav_href: string;
  required: boolean;
}
interface ProgressResponse {
  tenant_id: string;
  percent: number;
  done: number;
  total: number;
  steps: Step[];
  completed: boolean;
}

const DISMISS_KEY_PREFIX = "bo_setup_dismissed.";

export function SetupProgressPill({ locale }: { locale: string }) {
  const t = useTranslations("setupProgress");
  const [dismissed, setDismissed] = React.useState<boolean>(false);
  const [open, setOpen] = React.useState(false);

  const { data } = useQuery({
    queryKey: ["setup-progress"],
    queryFn: () =>
      clientFetch<ProgressResponse>({ path: "/admin/setup-progress" }),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
  });

  // Per-tenant dismiss flag. Reads on mount + whenever the active tenant
  // (carried as data.tenant_id) changes.
  React.useEffect(() => {
    if (!data?.tenant_id) return;
    try {
      const flag = window.localStorage.getItem(
        DISMISS_KEY_PREFIX + data.tenant_id,
      );
      setDismissed(flag === "1");
    } catch {
      // ignore
    }
  }, [data?.tenant_id]);

  if (!data) return null;
  if (data.completed) {
    // All required steps done → render a compact "✓ Setup tamam" badge
    // that's muted but still tappable in case the user wants to confirm
    // optional steps. Auto-disappears once the user dismisses it.
    if (dismissed) return null;
    return (
      <button
        type="button"
        onClick={() => {
          if (!data.tenant_id) return;
          window.localStorage.setItem(DISMISS_KEY_PREFIX + data.tenant_id, "1");
          setDismissed(true);
        }}
        className="hidden md:inline-flex items-center gap-1.5 rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2.5 py-1 text-[11.5px] font-medium text-emerald-700 hover:bg-emerald-500/15 transition"
        title={t("dismiss")}
      >
        <CheckCircle2 className="h-3.5 w-3.5" />
        {t("complete")}
      </button>
    );
  }
  if (dismissed) return null;

  return (
    <DropdownMenu open={open} onOpenChange={setOpen}>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          className={cn(
            "hidden md:inline-flex items-center gap-2 rounded-full border px-3 py-1 text-[12px] font-medium transition",
            data.percent >= 80
              ? "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 hover:bg-emerald-500/15"
              : data.percent >= 40
              ? "border-amber-500/30 bg-amber-500/10 text-amber-700 hover:bg-amber-500/15"
              : "border-rose-500/30 bg-rose-500/10 text-rose-700 hover:bg-rose-500/15",
          )}
        >
          <Sparkles className="h-3.5 w-3.5" />
          <span>{t("pill", { percent: data.percent })}</span>
          <ChevronDown className="h-3 w-3 opacity-70" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="center" className="w-80">
        <DropdownMenuLabel className="flex items-center justify-between">
          <span>{t("title")}</span>
          <button
            type="button"
            onClick={(e) => {
              e.preventDefault();
              if (!data.tenant_id) return;
              window.localStorage.setItem(
                DISMISS_KEY_PREFIX + data.tenant_id,
                "1",
              );
              setDismissed(true);
              setOpen(false);
            }}
            className="rounded p-1 text-muted-foreground hover:bg-accent/50"
            aria-label={t("dismiss")}
            title={t("dismiss")}
          >
            <XIcon className="h-3.5 w-3.5" />
          </button>
        </DropdownMenuLabel>
        <div className="px-2 pb-2">
          <Progress value={data.percent} className="h-1.5" />
          <p className="mt-1.5 text-[11px] text-muted-foreground">
            {t("subtitle", { done: data.done, total: data.total })}
          </p>
        </div>
        <DropdownMenuSeparator />
        <ul className="max-h-[360px] overflow-y-auto py-1">
          {data.steps.map((s) => (
            <li key={s.key}>
              <Link
                href={`/${locale}${s.nav_href}`}
                onClick={() => setOpen(false)}
                className={cn(
                  "flex items-start gap-2 px-3 py-1.5 text-[12.5px] transition",
                  s.done
                    ? "text-muted-foreground hover:bg-accent/30"
                    : "text-foreground hover:bg-accent/50",
                )}
              >
                {s.done ? (
                  <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
                ) : (
                  <Circle className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground/60" />
                )}
                <span className="flex-1">
                  {t(`steps.${s.key}` as never)}
                  {!s.required && (
                    <span className="ml-1.5 text-[10px] uppercase tracking-wider text-muted-foreground/70">
                      {t("optional")}
                    </span>
                  )}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
