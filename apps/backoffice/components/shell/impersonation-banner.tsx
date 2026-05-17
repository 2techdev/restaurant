"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { useTranslations } from "next-intl";

/**
 * Sticky top banner shown while a super admin is impersonating a tenant
 * admin. Click "Exit" → POST /api/admin/impersonate/exit → cookies restored
 * → redirect to /admin/tenants.
 *
 * Renders only when targetEmail + superAdminEmail are present (the parent
 * layout checks user.impersonated_by_email before mounting).
 */
export function ImpersonationBanner({
  targetEmail,
  superAdminEmail,
  locale,
}: {
  targetEmail: string;
  superAdminEmail: string;
  locale: string;
}) {
  const t = useTranslations("impersonation");
  const router = useRouter();
  const [exiting, setExiting] = useState(false);

  async function exit() {
    setExiting(true);
    try {
      await fetch("/api/admin/impersonate/exit", { method: "POST" });
    } catch {
      /* ignore — cookies still rotated server-side on success */
    }
    router.push(`/${locale}/admin/tenants`);
    router.refresh();
  }

  return (
    <div className="sticky top-0 z-50 flex items-center justify-between gap-3 bg-yellow-500 px-4 py-2 text-sm font-medium text-yellow-950 shadow-sm">
      <div className="flex items-center gap-2">
        <span aria-hidden className="text-base">⚠</span>
        <span>
          {t.rich("activeAs", {
            target: (chunks) => <strong className="font-bold">{chunks}</strong>,
            super: (chunks) => <strong className="font-bold">{chunks}</strong>,
            targetEmail,
            superAdminEmail,
          })}
        </span>
      </div>
      <button
        type="button"
        disabled={exiting}
        onClick={exit}
        className="inline-flex items-center gap-1 rounded-md bg-yellow-950 px-3 py-1 text-xs font-semibold text-yellow-50 hover:bg-yellow-900 disabled:opacity-60"
      >
        {exiting ? t("exiting") : t("exitButton")}
      </button>
    </div>
  );
}
