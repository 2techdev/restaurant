/**
 * Hourly Sales dashboard — 7×24 heatmap + daily breakdown.
 */
import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { getSession } from "@/lib/auth";
import { SalesHourlyClient } from "./sales-hourly-client";

interface Props {
  params: Promise<{ locale: string }>;
}

export default async function SalesHourlyPage({ params }: Props) {
  const { locale } = await params;
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations("reports");

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold">{t("salesHourly.title")}</h1>
        <p className="text-sm text-muted-foreground">
          {t("salesHourly.subtitle")}
        </p>
      </header>
      <SalesHourlyClient />
    </div>
  );
}
