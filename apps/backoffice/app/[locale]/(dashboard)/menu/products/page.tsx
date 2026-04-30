import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { fetchProducts, fetchCategories } from "@/lib/server-data";
import { ProductsClient } from "./products-client";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "menu.productsPage" });

  const [products, categories] = await Promise.all([
    fetchProducts(session).catch(() => []),
    fetchCategories(session).catch(() => []),
  ]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground mt-1">{t("subtitle")}</p>
      </div>
      <ProductsClient initialProducts={products} initialCategories={categories} />
    </div>
  );
}
