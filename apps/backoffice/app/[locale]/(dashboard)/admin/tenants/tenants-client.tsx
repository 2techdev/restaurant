"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import type { TenantInfo, ImpersonateResponse } from "@/lib/api-types";

export function TenantsClient({
  initial,
  locale,
}: {
  initial: TenantInfo[];
  locale: string;
}) {
  const t = useTranslations("admin.tenants");
  const router = useRouter();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function impersonate(tenant: TenantInfo) {
    if (!tenant.owner_user_id) {
      setError(t("noOwnerError", { tenant: tenant.organization_name }));
      return;
    }
    setBusyId(tenant.organization_id);
    setError(null);
    try {
      const res = await fetch("/api/admin/impersonate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          target_user_id: tenant.owner_user_id,
          reason: `Super admin ghost-login → ${tenant.organization_name}`,
        }),
      });
      const data: ImpersonateResponse & { code?: string; message?: string } = await res.json();
      if (!res.ok) {
        setError(data.message ?? t("genericError"));
        setBusyId(null);
        return;
      }
      // Cookies were rotated server-side — navigating triggers a fresh server
      // component render with the impersonation session active.
      router.push(`/${locale}/dashboard`);
      router.refresh();
    } catch {
      setError(t("genericError"));
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-3">
      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}
      <div className="overflow-hidden rounded-lg border bg-card">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left">
            <tr>
              <th className="px-4 py-2 font-medium">{t("col.tenant")}</th>
              <th className="px-4 py-2 font-medium">{t("col.owner")}</th>
              <th className="px-4 py-2 font-medium text-center">{t("col.adminCount")}</th>
              <th className="px-4 py-2 font-medium">{t("col.lastActive")}</th>
              <th className="px-4 py-2 font-medium text-right">{t("col.action")}</th>
            </tr>
          </thead>
          <tbody>
            {initial.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-6 text-center text-muted-foreground">
                  {t("empty")}
                </td>
              </tr>
            ) : (
              initial.map((tenant) => {
                const busy = busyId === tenant.organization_id;
                const lastActive = tenant.last_active_at
                  ? new Date(tenant.last_active_at).toLocaleDateString(locale)
                  : "—";
                return (
                  <tr key={tenant.organization_id} className="border-t">
                    <td className="px-4 py-3 font-medium">{tenant.organization_name}</td>
                    <td className="px-4 py-3 text-muted-foreground">
                      {tenant.owner_email ? (
                        <>
                          <div>{tenant.owner_email}</div>
                          {tenant.owner_name ? <div className="text-xs">{tenant.owner_name}</div> : null}
                        </>
                      ) : (
                        <span className="italic">{t("noOwner")}</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-center">{tenant.admin_user_count}</td>
                    <td className="px-4 py-3 text-muted-foreground">{lastActive}</td>
                    <td className="px-4 py-3 text-right">
                      <button
                        type="button"
                        disabled={busy || !tenant.owner_user_id}
                        onClick={() => impersonate(tenant)}
                        className="inline-flex items-center gap-1 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {busy ? t("loggingIn") : t("login")}
                      </button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-muted-foreground">{t("footer")}</p>
    </div>
  );
}
