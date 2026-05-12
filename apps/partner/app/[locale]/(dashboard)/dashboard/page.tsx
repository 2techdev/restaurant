import { setRequestLocale, getTranslations } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";

interface DashboardData {
  brand_count: number;
  store_count: number;
  edition_count: number;
  employee_count: number;
  active_stores: number;
  mrr_chf: number;
}

async function fetchDashboard(token: string): Promise<DashboardData | null> {
  try {
    return await apiGet<DashboardData>("/partner/dashboard", { token });
  } catch {
    return null;
  }
}

export default async function PartnerDashboardPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  const t = await getTranslations({ locale, namespace: "dashboard" });
  const data = session ? await fetchDashboard(session.token) : null;

  const cards: { label: string; value: string | number }[] = [
    { label: t("brands"), value: data?.brand_count ?? "—" },
    { label: t("stores"), value: data?.store_count ?? "—" },
    { label: t("activeStores"), value: data?.active_stores ?? "—" },
    { label: t("editions"), value: data?.edition_count ?? "—" },
    { label: t("employees"), value: data?.employee_count ?? "—" },
    { label: t("mrr"), value: data ? `CHF ${data.mrr_chf.toFixed(2)}` : "—" },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
        {cards.map((c) => (
          <div
            key={c.label}
            className="rounded-lg border border-border bg-card p-4"
          >
            <div className="text-xs uppercase tracking-wider text-muted-foreground">
              {c.label}
            </div>
            <div className="mt-1.5 text-2xl font-semibold tabular-nums text-foreground">
              {c.value}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
