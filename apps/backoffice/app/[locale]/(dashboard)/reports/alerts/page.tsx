import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { AlertsClient } from "@/components/reporting/alerts-client";
import { fetchThresholdAlerts, fetchAlertLogs } from "@/lib/server-data";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const orgRole = session.user.org_role;
  if (!canManageHq(orgRole) && orgRole !== "RESTAURANT_MANAGER") {
    redirect(`/${locale}/dashboard`);
  }

  const t = await getTranslations({ locale, namespace: "alerts" });
  const [alerts, logs] = await Promise.all([
    fetchThresholdAlerts(session),
    fetchAlertLogs(session, 50),
  ]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <AlertsClient
        initialAlerts={alerts}
        initialLogs={logs}
        defaultRecipient={session.user.email ?? ""}
      />
    </div>
  );
}
