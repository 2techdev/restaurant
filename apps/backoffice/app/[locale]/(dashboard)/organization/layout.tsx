import { redirect } from "next/navigation";
import { getSession, canManageHq } from "@/lib/auth";

export default async function OrganizationLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!canManageHq(session.user.org_role)) redirect(`/${locale}/dashboard`);
  return <div className="space-y-6">{children}</div>;
}
