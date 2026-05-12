import { setRequestLocale, getTranslations } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";
import { EditionsClient, type Edition } from "@/components/editions/editions-client";

async function fetchEditions(token: string): Promise<Edition[]> {
  try {
    const r = await apiGet<{ data: Edition[] }>("/partner/editions", { token });
    return r?.data ?? [];
  } catch {
    return [];
  }
}

export default async function EditionsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  const t = await getTranslations({ locale, namespace: "editions" });
  const initial = session ? await fetchEditions(session.token) : [];
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <EditionsClient initial={initial} canWrite={session?.user.role === "OPERATOR"} />
    </div>
  );
}
