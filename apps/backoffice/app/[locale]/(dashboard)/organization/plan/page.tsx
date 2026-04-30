import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Check, Sparkles, Building2, Crown } from "lucide-react";

const TIERS = [
  {
    id: "basic",
    icon: Sparkles,
    nameKey: "tierBasicName",
    priceKey: "tierBasicPrice",
    descKey: "tierBasicDesc",
    featuresKeys: ["tierBasicF1", "tierBasicF2", "tierBasicF3"],
    accent: false,
  },
  {
    id: "pro",
    icon: Building2,
    nameKey: "tierProName",
    priceKey: "tierProPrice",
    descKey: "tierProDesc",
    featuresKeys: ["tierProF1", "tierProF2", "tierProF3", "tierProF4"],
    accent: true,
    currentKey: "currentPilot",
  },
  {
    id: "enterprise",
    icon: Crown,
    nameKey: "tierEntName",
    priceKey: "tierEntPrice",
    descKey: "tierEntDesc",
    featuresKeys: ["tierEntF1", "tierEntF2", "tierEntF3", "tierEntF4", "tierEntF5"],
    accent: false,
  },
] as const;

const ADDONS = [
  { id: "tisch", nameKey: "addonTischName", descKey: "addonTischDesc" },
  { id: "hq", nameKey: "addonHqName", descKey: "addonHqDesc" },
  { id: "branding", nameKey: "addonBrandingName", descKey: "addonBrandingDesc" },
] as const;

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!canManageHq(session.user.org_role)) redirect(`/${locale}/dashboard`);
  const t = await getTranslations({ locale, namespace: "orgPlan" });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {TIERS.map((tier) => {
          const Icon = tier.icon;
          const isCurrent = "currentKey" in tier;
          return (
            <Card
              key={tier.id}
              className={tier.accent ? "ring-2 ring-primary" : undefined}
            >
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base flex items-center gap-2">
                    <Icon className="h-5 w-5" /> {t(tier.nameKey)}
                  </CardTitle>
                  {isCurrent ? <Badge>{t("currentPilot")}</Badge> : null}
                </div>
                <CardDescription>{t(tier.descKey)}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <span className="text-3xl font-bold tabular-nums">{t(tier.priceKey)}</span>
                  <span className="text-sm text-muted-foreground ml-1">{t("perMonth")}</span>
                </div>
                <ul className="space-y-2 text-sm">
                  {tier.featuresKeys.map((fk) => (
                    <li key={fk} className="flex items-start gap-2">
                      <Check className="h-4 w-4 text-emerald-500 mt-0.5 shrink-0" />
                      <span>{t(fk)}</span>
                    </li>
                  ))}
                </ul>
                <Button
                  variant={tier.accent ? "default" : "outline"}
                  className="w-full"
                  disabled={isCurrent}
                >
                  {isCurrent ? t("currentPlan") : t("contactSales")}
                </Button>
              </CardContent>
            </Card>
          );
        })}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("addonsTitle")}</CardTitle>
          <CardDescription>{t("addonsSubtitle")}</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            {ADDONS.map((addon) => (
              <div key={addon.id} className="rounded border p-3">
                <div className="font-medium text-sm">{t(addon.nameKey)}</div>
                <div className="text-xs text-muted-foreground mt-1">{t(addon.descKey)}</div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
