import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Tag, Info } from "lucide-react";

export default async function PromotionsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const tNav = await getTranslations({ locale, namespace: "nav" });
  const t = await getTranslations({ locale, namespace: "settings" });

  return (
    <div className="space-y-6 max-w-3xl">
      <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
        <Tag className="h-6 w-6" /> {tNav("promotions")}
      </h1>
      <Card>
        <CardHeader>
          <CardTitle>Happy Hour, Discounts, Bundles</CardTitle>
          <CardDescription>{t("comingSoon")}</CardDescription>
        </CardHeader>
        <CardContent>
          <Alert>
            <Info className="h-4 w-4" />
            <AlertDescription>{t("comingSoon")}</AlertDescription>
          </Alert>
        </CardContent>
      </Card>
    </div>
  );
}
