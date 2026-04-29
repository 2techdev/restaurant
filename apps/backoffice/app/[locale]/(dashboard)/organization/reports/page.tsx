import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { fetchAggregateStats } from "@/lib/server-data";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { LocationCompareChart } from "@/components/hq/location-compare-chart";
import { formatChf } from "@/lib/utils";
import { Building2, TrendingUp, ShoppingBag } from "lucide-react";

export default async function AggregateReportsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "hq" });
  const tDash = await getTranslations({ locale, namespace: "dashboard" });
  const stats = await fetchAggregateStats(session);

  const top = stats?.per_restaurant
    ? [...stats.per_restaurant].sort((a, b) => b.revenue - a.revenue)[0]
    : null;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
        <Building2 className="h-5 w-5" /> {t("aggregateRevenue")}
      </h1>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">{t("aggregateRevenue")}</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatChf(stats?.total_revenue ?? 0)}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">{tDash("orderCount")}</CardTitle>
            <ShoppingBag className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats?.total_orders ?? 0}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-xs font-medium text-muted-foreground">{tDash("topRestaurant")}</CardTitle>
            <Building2 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-lg font-semibold truncate">{top?.restaurant_name ?? "—"}</div>
            <div className="text-xs text-muted-foreground">{top ? formatChf(top.revenue) : ""}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{tDash("compareLocations")}</CardTitle>
        </CardHeader>
        <CardContent>
          <LocationCompareChart data={stats?.per_restaurant ?? []} />
        </CardContent>
      </Card>
    </div>
  );
}
