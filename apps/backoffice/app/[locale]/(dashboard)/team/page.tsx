/**
 * Tenant-level team / staff page.
 * /[locale]/team
 *
 * Lists POS staff (app_users) for the active tenant — waiter, kitchen,
 * manager, cashier, kiosk. HQ admins switch the active tenant via the
 * top-bar tenant switcher; the proxy then scopes /api/v1/users to that
 * tenant via X-Tenant-ID.
 *
 * Write permission: HQ_ADMIN, HQ_MANAGER, or in-tenant manager/owner.
 */

import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { TeamClient } from "@/components/team/team-client";
import { fetchTeamUsers } from "@/lib/server-data";

const MANAGER_ROLES = new Set([
  "HQ_ADMIN",
  "HQ_MANAGER",
  "RESTAURANT_MANAGER",
  "admin",
  "owner",
  "manager",
  "store_manager",
  "brand_manager",
]);

export default async function TeamPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);

  const t = await getTranslations({ locale, namespace: "team" });
  const initial = await fetchTeamUsers(session);
  const role = session.user.org_role ?? session.user.role ?? "";
  const canWrite = MANAGER_ROLES.has(role) || !!session.user.is_super_admin;
  const isHQ = role === "HQ_ADMIN" || role === "HQ_MANAGER" || !!session.user.is_super_admin;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
          <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
        </div>
      </div>
      <TeamClient
        initial={initial}
        canWrite={canWrite}
        currentUserId={session.user.id}
        isHQ={isHQ}
      />
    </div>
  );
}
