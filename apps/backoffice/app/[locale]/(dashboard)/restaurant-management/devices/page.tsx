import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { DevicesPageClient } from "./devices-client";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);

  // RM'ler kendi tenant'ları için cihaz görür; HQ rolleri ise active tenant
  // (topbar tenant switcher) bazlı listeler. "all" modunda boş liste + uyarı.
  const tNav = await getTranslations({ locale, namespace: "nav" });
  return <DevicesPageClient locale={locale} title={tNav("rmDevices")} />;
}
