import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { UsersClient } from "@/components/users/users-client";
import { fetchAdminUsers, fetchAppUsers } from "@/lib/server-data";

export default async function UsersPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const orgRole = session.user.org_role;
  if (!canManageHq(orgRole)) redirect(`/${locale}/dashboard`);

  const t = await getTranslations({ locale, namespace: "users" });
  const [admins, staff] = await Promise.all([
    fetchAdminUsers(session),
    fetchAppUsers(session),
  ]);
  const isHqAdmin = orgRole === "HQ_ADMIN";

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
          <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
        </div>
      </div>
      <UsersClient
        initialAdmins={admins}
        initialStaff={staff}
        canWrite={isHqAdmin}
        currentUserId={session.user.id}
      />
    </div>
  );
}
