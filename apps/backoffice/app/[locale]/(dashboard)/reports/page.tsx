import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { fetchRevenue7d } from "@/lib/server-data";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { RevenueChart } from "@/components/dashboard/revenue-chart";

export default async function ReportsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "reports" });

  const revenue = await fetchRevenue7d(session);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">{t("revenue")}</h1>

      <Card>
        <CardHeader>
          <CardTitle>{t("revenue")}</CardTitle>
          <CardDescription>Son 7 gün</CardDescription>
        </CardHeader>
        <CardContent>
          <RevenueChart data={revenue} />
        </CardContent>
      </Card>
    </div>
  );
}
