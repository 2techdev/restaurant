/**
 * Sales Summary dashboard — top-level page (RSC).
 *
 * Mirrors the rest of `/reports/*`: server component checks the session
 * + redirects if unauthenticated, then renders the client island that
 * owns the period selector + TanStack Query data fetches.
 */
import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { getSession } from "@/lib/auth";
import { SalesSummaryClient } from "./sales-summary-client";

interface Props {
  params: Promise<{ locale: string }>;
}

export default async function SalesSummaryPage({ params }: Props) {
  const { locale } = await params;
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations("reports");

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold">{t("salesSummary.title")}</h1>
        <p className="text-sm text-muted-foreground">
          {t("salesSummary.subtitle")}
        </p>
      </header>
      <SalesSummaryClient />
    </div>
  );
}
