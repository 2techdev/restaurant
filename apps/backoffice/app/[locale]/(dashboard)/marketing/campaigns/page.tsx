import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { CampaignsClient } from "@/components/marketing/campaigns-client";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "marketing" });
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("campaigns.title")}</h1>
        <p className="text-sm text-muted-foreground">{t("campaigns.subtitle")}</p>
      </div>
      <CampaignsClient />
    </div>
  );
}
