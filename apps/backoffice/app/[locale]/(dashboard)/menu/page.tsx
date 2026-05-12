import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import Link from "next/link";
import { getSession } from "@/lib/auth";
import { fetchCategories, fetchPublishHistory } from "@/lib/server-data";
import { CategoriesPanel } from "@/components/menu/categories-panel";
import { MenuPublishButton } from "@/components/menu/menu-publish-button";

export default async function MenuPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "menu" });

  const [categories, history] = await Promise.all([
    fetchCategories(session),
    fetchPublishHistory(session),
  ]);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3">
        <h1 className="text-2xl font-bold tracking-tight">{t("categories")}</h1>
        <div className="flex items-center gap-2">
          <Link
            href={`/${locale}/menu/connect-gastrohub`}
            className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-3 py-1.5 text-sm font-medium hover:bg-accent hover:text-accent-foreground transition"
          >
            <span aria-hidden>🔗</span> {t("import.headerButton")}
          </Link>
          <MenuPublishButton history={history} />
        </div>
      </div>
      <CategoriesPanel initial={categories} userRole={session.user.role} />
    </div>
  );
}
