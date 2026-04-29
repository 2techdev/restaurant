import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { fetchRevenue7d, fetchTopSellers } from "@/lib/server-data";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { RevenueChart } from "@/components/dashboard/revenue-chart";
import { TopSellersTable } from "@/components/dashboard/top-sellers-table";
import { Info } from "lucide-react";

export default async function ReportsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "reports" });

  const [revenue, top] = await Promise.all([
    fetchRevenue7d(session),
    fetchTopSellers(session, 30),
  ]);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>

      <Tabs defaultValue="revenue">
        <TabsList>
          <TabsTrigger value="revenue">{t("revenue")}</TabsTrigger>
          <TabsTrigger value="top">{t("topSellers")}</TabsTrigger>
          <TabsTrigger value="timeline">{t("salesTimeline")}</TabsTrigger>
          <TabsTrigger value="mwst">{t("mwst")}</TabsTrigger>
        </TabsList>

        <TabsContent value="revenue">
          <Card>
            <CardHeader>
              <CardTitle>{t("revenue")}</CardTitle>
              <CardDescription>Son 7 gün</CardDescription>
            </CardHeader>
            <CardContent>
              <RevenueChart data={revenue} />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="top">
          <Card>
            <CardHeader>
              <CardTitle>{t("topSellers")}</CardTitle>
              <CardDescription>Son 30 gün</CardDescription>
            </CardHeader>
            <CardContent>
              <TopSellersTable items={top} />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="timeline">
          <Card>
            <CardHeader>
              <CardTitle>{t("salesTimeline")}</CardTitle>
            </CardHeader>
            <CardContent>
              <RevenueChart data={revenue} />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="mwst">
          <Alert>
            <Info className="h-4 w-4" />
            <AlertTitle>{t("mwst")}</AlertTitle>
            <AlertDescription>{t("placeholder")}</AlertDescription>
          </Alert>
        </TabsContent>
      </Tabs>
    </div>
  );
}
