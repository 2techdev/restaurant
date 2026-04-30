import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { fetchTopSellers } from "@/lib/server-data";
import { TopSellersClient } from "@/components/reports/top-sellers-client";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "reports" });
  const initial = await fetchTopSellers(session, 30);
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("topSellers")}</h1>
        <p className="text-sm text-muted-foreground">{t("topSellersSubtitle")}</p>
      </div>
      <TopSellersClient initial={initial} />
    </div>
  );
}
