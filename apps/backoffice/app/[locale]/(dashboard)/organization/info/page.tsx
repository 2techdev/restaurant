import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { OrgInfoClient } from "@/components/organization/info-client";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!canManageHq(session.user.org_role)) redirect(`/${locale}/dashboard`);
  const t = await getTranslations({ locale, namespace: "orgInfo" });
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <OrgInfoClient />
    </div>
  );
}
