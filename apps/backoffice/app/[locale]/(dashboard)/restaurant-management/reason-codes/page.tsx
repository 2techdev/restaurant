import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageMenu } from "@/lib/roles";
import { apiGet } from "@/lib/api";
import { ReasonCodesClient, type Reason } from "@/components/reasons/reason-codes-client";

async function fetchReasons(token: string, tenantId: string, kind: "void" | "discount"): Promise<Reason[]> {
  try {
    const r = await apiGet<{ data: Reason[] }>(`/admin/reasons/${kind}`, {
      token, tenantId,
    });
    return r?.data ?? [];
  } catch {
    return [];
  }
}

export default async function ReasonCodesPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!canManageMenu(session.user.org_role ?? session.user.role)) {
    redirect(`/${locale}/dashboard`);
  }

  const t = await getTranslations({ locale, namespace: "reasonCodes" });
  const [voidReasons, discountReasons] = await Promise.all([
    fetchReasons(session.token, session.tenantId, "void"),
    fetchReasons(session.token, session.tenantId, "discount"),
  ]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <ReasonCodesClient
        initialVoid={voidReasons}
        initialDiscount={discountReasons}
      />
    </div>
  );
}
