"use client";

import { useTranslations } from "next-intl";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { CategoriesPanel } from "./categories-panel";
import { ProductsPanel } from "./products-panel";
import { ModifiersPanel } from "./modifiers-panel";
import type { MenuCategory, MenuProduct, ModifierGroup, UserRole } from "@/lib/api-types";

export function MenuTabs({
  initialCategories,
  initialProducts,
  initialModifierGroups,
  userRole,
}: {
  initialCategories: MenuCategory[];
  initialProducts: MenuProduct[];
  initialModifierGroups: ModifierGroup[];
  userRole: UserRole | string;
}) {
  const t = useTranslations("menu.tab");
  return (
    <Tabs defaultValue="categories" className="w-full">
      <TabsList>
        <TabsTrigger value="categories">{t("categories")}</TabsTrigger>
        <TabsTrigger value="products">{t("products")}</TabsTrigger>
        <TabsTrigger value="modifiers">{t("modifiers")}</TabsTrigger>
      </TabsList>
      <TabsContent value="categories">
        <CategoriesPanel initial={initialCategories} userRole={userRole} />
      </TabsContent>
      <TabsContent value="products">
        <ProductsPanel
          initial={initialProducts}
          categories={initialCategories}
          modifierGroups={initialModifierGroups}
          userRole={userRole}
        />
      </TabsContent>
      <TabsContent value="modifiers">
        <ModifiersPanel initial={initialModifierGroups} userRole={userRole} />
      </TabsContent>
    </Tabs>
  );
}
