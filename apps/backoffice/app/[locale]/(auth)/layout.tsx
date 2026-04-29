import { setRequestLocale } from "next-intl/server";
import { LocaleSwitcher } from "@/components/shell/locale-switcher";

export default async function AuthLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  return (
    <div className="min-h-screen flex items-center justify-center bg-background px-4">
      <div className="w-full max-w-md space-y-3">
        <div className="flex justify-end">
          <LocaleSwitcher locale={locale} variant="flags" size="md" />
        </div>
        {children}
      </div>
    </div>
  );
}
