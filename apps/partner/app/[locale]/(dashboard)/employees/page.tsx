import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";
import { EmployeesClient, type Employee } from "@/components/employees/employees-client";

async function fetchEmployees(token: string): Promise<Employee[]> {
  try {
    const r = await apiGet<{ data: Employee[] }>("/partner/employees", { token });
    return r?.data ?? [];
  } catch {
    return [];
  }
}

export default async function EmployeesPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  // Employees list is MANAGER+; the page itself is OPERATOR-only per sidebar
  // gating, but keep a defence-in-depth guard here too.
  if (session.user.role === "EMPLOYEE") redirect(`/${locale}/dashboard`);
  const t = await getTranslations({ locale, namespace: "employees" });
  const initial = await fetchEmployees(session.token);
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>
      <EmployeesClient
        initial={initial}
        currentUserId={session.user.id}
        canWrite={session.user.role === "OPERATOR"}
      />
    </div>
  );
}
