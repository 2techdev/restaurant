/**
 * Staff Performance dashboard — per-user revenue / orders / tips / shift.
 */
import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { getSession } from "@/lib/auth";
import { StaffPerformanceClient } from "./staff-performance-client";

interface Props {
  params: Promise<{ locale: string }>;
}

export default async function StaffPerformancePage({ params }: Props) {
  const { locale } = await params;
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations("reports");

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-bold">{t("staffPerformance.title")}</h1>
        <p className="text-sm text-muted-foreground">
          {t("staffPerformance.subtitle")}
        </p>
      </header>
      <StaffPerformanceClient />
    </div>
  );
}
