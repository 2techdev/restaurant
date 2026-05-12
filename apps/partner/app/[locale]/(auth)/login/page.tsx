import { redirect } from "next/navigation";
import { setRequestLocale, getTranslations } from "next-intl/server";
import { LoginForm } from "@/components/auth/login-form";
import { getSession } from "@/lib/auth";

export default async function LoginPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (session) redirect(`/${locale}/dashboard`);
  const t = await getTranslations({ locale, namespace: "auth" });
  return (
    <div className="space-y-6 rounded-xl border border-border bg-card p-8 shadow-lg">
      <div className="space-y-1.5 text-center">
        <h1 className="text-xl font-semibold tracking-tight text-foreground">
          GastroCore Partner
        </h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <LoginForm />
    </div>
  );
}
