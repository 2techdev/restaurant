import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { AutomationClient } from "@/components/reporting/automation-client";
import { fetchScheduledReports, fetchReportLogs } from "@/lib/server-data";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const orgRole = session.user.org_role;
  if (!canManageHq(orgRole) && orgRole !== "RESTAURANT_MANAGER") {
    redirect(`/${locale}/dashboard`);
  }

  const t = await getTranslations({ locale, namespace: "automation" });
  const [reports, logs] = await Promise.all([
    fetchScheduledReports(session),
    fetchReportLogs(session, 50),
  ]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <AutomationClient
        initialReports={reports}
        initialLogs={logs}
        locale={locale}
        defaultRecipient={session.user.email ?? ""}
      />
    </div>
  );
}
