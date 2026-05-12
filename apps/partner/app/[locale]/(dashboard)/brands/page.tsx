import { setRequestLocale, getTranslations } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";
import { BrandsClient, type Brand } from "@/components/brands/brands-client";

async function fetchBrands(token: string): Promise<Brand[]> {
  try {
    const r = await apiGet<{ data: Brand[] }>("/partner/brands", { token });
    return r?.data ?? [];
  } catch {
    return [];
  }
}

export default async function BrandsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  const t = await getTranslations({ locale, namespace: "brands" });
  const initial = session ? await fetchBrands(session.token) : [];
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <BrandsClient initial={initial} canWrite={session?.user.role !== "EMPLOYEE"} />
    </div>
  );
}
