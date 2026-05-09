import { redirect } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { Sidebar } from "@/components/shell/sidebar";
import { Topbar } from "@/components/shell/topbar";
import { TenantContextProvider } from "@/components/shell/tenant-context";
import { CommandPaletteProvider } from "@/components/shell/command-palette";
import { ImpersonationBanner } from "@/components/shell/impersonation-banner";
import { fetchTenantsForUser } from "@/lib/server-data";

export default async function DashboardLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);

  const tenants = await fetchTenantsForUser(session).catch(() => []);
  const impersonatingFor = session.user.impersonated_by_email;

  return (
    <TenantContextProvider
      user={session.user}
      tenants={tenants}
      activeTenantId={session.tenantId}
    >
      <CommandPaletteProvider locale={locale}>
        <div className="flex min-h-screen flex-col bg-background">
          {impersonatingFor ? (
            <ImpersonationBanner
              targetEmail={session.user.email}
              superAdminEmail={impersonatingFor}
              locale={locale}
            />
          ) : null}
          <div className="flex flex-1">
            <Sidebar
              locale={locale}
              role={session.user.org_role ?? session.user.role}
              isSuperAdmin={!!session.user.is_super_admin}
            />
            <div className="flex flex-1 flex-col">
              <Topbar locale={locale} user={session.user} />
              <main className="flex-1 overflow-y-auto p-6">{children}</main>
            </div>
          </div>
        </div>
      </CommandPaletteProvider>
    </TenantContextProvider>
  );
}
