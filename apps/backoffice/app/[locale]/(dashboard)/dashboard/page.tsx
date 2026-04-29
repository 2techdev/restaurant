import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import {
  fetchDashboardStats,
  fetchRevenue7d,
  fetchTopSellers,
} from "@/lib/server-data";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatChf } from "@/lib/utils";
import { RevenueChart } from "@/components/dashboard/revenue-chart";
import { TopSellersTable } from "@/components/dashboard/top-sellers-table";
import { ShoppingBag, TrendingUp, Receipt, Activity } from "lucide-react";

export default async function DashboardPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "dashboard" });

  const [stats, revenue, topSellers] = await Promise.all([
    fetchDashboardStats(session),
    fetchRevenue7d(session),
    fetchTopSellers(session),
  ]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("revenueChart")}</h1>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <KpiCard
          title={t("todayRevenue")}
          value={formatChf(stats?.today_revenue ?? 0)}
          icon={<TrendingUp className="h-4 w-4" />}
        />
        <KpiCard
          title={t("orderCount")}
          value={String(stats?.order_count ?? 0)}
          icon={<ShoppingBag className="h-4 w-4" />}
        />
        <KpiCard
          title={t("avgTicket")}
          value={formatChf(stats?.avg_ticket ?? 0)}
          icon={<Receipt className="h-4 w-4" />}
        />
        <KpiCard
          title={t("activeOrders")}
          value={String(stats?.active_orders ?? 0)}
          icon={<Activity className="h-4 w-4" />}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>{t("revenueChart")}</CardTitle>
            <CardDescription>{t("last7Days")}</CardDescription>
          </CardHeader>
          <CardContent>
            <RevenueChart data={revenue} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>{t("topSellers")}</CardTitle>
          </CardHeader>
          <CardContent>
            <TopSellersTable items={topSellers} />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

function KpiCard({
  title,
  value,
  icon,
}: {
  title: string;
  value: string;
  icon: React.ReactNode;
}) {
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-xs font-medium text-muted-foreground">{title}</CardTitle>
        <span className="text-muted-foreground">{icon}</span>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold">{value}</div>
      </CardContent>
    </Card>
  );
}
