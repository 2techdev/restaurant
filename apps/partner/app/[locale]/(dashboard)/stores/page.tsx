import { setRequestLocale, getTranslations } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";
import { StoresClient, type Store } from "@/components/stores/stores-client";
import type { Brand } from "@/components/brands/brands-client";
import type { Edition } from "@/components/editions/editions-client";

async function fetchAll(token: string) {
  const safe = async <T,>(p: Promise<T>): Promise<T | null> => p.catch(() => null);
  const stores = (await safe(apiGet<{ data: Store[] }>("/partner/stores", { token })))?.data ?? [];
  const brands = (await safe(apiGet<{ data: Brand[] }>("/partner/brands", { token })))?.data ?? [];
  const editions = (await safe(apiGet<{ data: Edition[] }>("/partner/editions", { token })))?.data ?? [];
  return { stores, brands, editions };
}

export default async function StoresPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  const t = await getTranslations({ locale, namespace: "stores" });
  const data = session ? await fetchAll(session.token) : { stores: [], brands: [], editions: [] };
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <StoresClient
        initialStores={data.stores}
        brands={data.brands}
        editions={data.editions}
        canWrite={session?.user.role !== "EMPLOYEE"}
      />
    </div>
  );
}
