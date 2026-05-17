/**
 * Super admin → Tenants list page (F1).
 * /[locale]/admin/tenants
 *
 * Server component: reads session, redirects non-super-admins, fetches the
 * tenant list from the Go server via the backoffice proxy. Client component
 * handles the impersonation buttons + countdown.
 */

import { redirect } from "next/navigation";
import { setRequestLocale, getTranslations } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";
import type { TenantInfo } from "@/lib/api-types";
import { TenantsClient } from "./tenants-client";

export const dynamic = "force-dynamic";

export default async function TenantsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);

  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!session.user.is_super_admin) {
    // Non-super admins shouldn't have a link to this page in the sidebar,
    // but defense-in-depth — bounce them back to dashboard.
    redirect(`/${locale}/dashboard`);
  }

  const t = await getTranslations({ locale, namespace: "admin.tenants" });

  let tenants: TenantInfo[] = [];
  let loadError: string | null = null;
  try {
    const data = await apiGet<{ tenants: TenantInfo[] }>("/admin/tenants", { token: session.token });
    tenants = data.tenants ?? [];
  } catch (e) {
    const err = e as { message?: string };
    loadError = err.message ?? "Failed to load tenants";
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
          <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
        </div>
      </div>
      {loadError ? (
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          {loadError}
        </div>
      ) : (
        <TenantsClient initial={tenants} locale={locale} />
      )}
    </div>
  );
}
