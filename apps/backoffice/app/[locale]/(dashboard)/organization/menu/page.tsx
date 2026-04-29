import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { fetchCategories, fetchProducts, fetchModifierGroups, fetchPublishHistory } from "@/lib/server-data";
import { MenuTabs } from "@/components/menu/menu-tabs";
import { MenuPublishButton } from "@/components/menu/menu-publish-button";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Building2 } from "lucide-react";

/**
 * HQ Master Menu — organization-level menü.
 *
 * Pilot v1: backend'in /api/v1/admin/menu/* endpoint'leri henüz yok; mevcut tenant
 * menüsünü gösteriyoruz, lock policy badge'leri UI'da renderlanıyor. Backend'de
 * organization_memberships ve menu_policies tabloları eklendiğinde bu sayfa aggregate
 * master menüye geçer.
 */
export default async function MasterMenuPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "menu" });
  const tHq = await getTranslations({ locale, namespace: "hq" });

  const [categories, products, modifierGroups, history] = await Promise.all([
    fetchCategories(session),
    fetchProducts(session),
    fetchModifierGroups(session),
    fetchPublishHistory(session),
  ]);

  return (
    <div className="space-y-6">
      <Alert>
        <Building2 className="h-4 w-4" />
        <AlertTitle>{tHq("masterMenu")}</AlertTitle>
        <AlertDescription>
          Bu menü organizasyonun tüm restoranlarına yayınlanır. Kilit politikalarını ürün bazında
          ayarlayın — kilitli ürünler restoran yöneticileri tarafından düzenlenemez.
        </AlertDescription>
      </Alert>

      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold tracking-tight">{tHq("masterMenu")}</h1>
        <MenuPublishButton history={history} />
      </div>

      <MenuTabs
        initialCategories={categories}
        initialProducts={products}
        initialModifierGroups={modifierGroups}
        userRole={session.user.role}
      />
    </div>
  );
}
