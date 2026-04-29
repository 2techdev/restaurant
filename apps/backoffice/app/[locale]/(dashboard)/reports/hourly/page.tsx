import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { PlaceholderPage } from "@/components/shared/placeholder-page";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const tNav = await getTranslations({ locale, namespace: "nav" });
  return (
    <PlaceholderPage
      title={tNav("reportsHourly")}
      hint={tNav("comingSoon")}
      bodyMessage={tNav("comingSoonHint")}
    />
  );
}
