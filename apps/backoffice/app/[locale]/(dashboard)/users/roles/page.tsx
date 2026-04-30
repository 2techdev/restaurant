import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Check, X } from "lucide-react";

const ROLES = ["HQ_ADMIN", "HQ_MANAGER", "RESTAURANT_MANAGER", "STAFF", "POS_OPERATOR"] as const;
const PERMISSIONS = [
  { key: "manageOrgUsers", roles: ["HQ_ADMIN"] },
  { key: "manageOrg", roles: ["HQ_ADMIN", "HQ_MANAGER"] },
  { key: "viewAllRestaurants", roles: ["HQ_ADMIN", "HQ_MANAGER"] },
  { key: "manageMasterMenu", roles: ["HQ_ADMIN", "HQ_MANAGER"] },
  { key: "manageRestaurantMenu", roles: ["HQ_ADMIN", "HQ_MANAGER", "RESTAURANT_MANAGER"] },
  { key: "viewReports", roles: ["HQ_ADMIN", "HQ_MANAGER", "RESTAURANT_MANAGER"] },
  { key: "manageOrders", roles: ["HQ_ADMIN", "HQ_MANAGER", "RESTAURANT_MANAGER", "STAFF"] },
  { key: "operatePos", roles: ["RESTAURANT_MANAGER", "STAFF", "POS_OPERATOR"] },
] as const;

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!canManageHq(session.user.org_role)) redirect(`/${locale}/dashboard`);
  const t = await getTranslations({ locale, namespace: "rolesPage" });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
        {ROLES.map((r) => (
          <Card key={r}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <CardTitle className="text-base">{t(`role_${r}`)}</CardTitle>
                <Badge variant="secondary" className="font-mono text-xs">
                  {r}
                </Badge>
              </div>
              <CardDescription>{t(`role_${r}_desc`)}</CardDescription>
            </CardHeader>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("matrixTitle")}</CardTitle>
          <CardDescription>{t("matrixSubtitle")}</CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("permission")}</TableHead>
                {ROLES.map((r) => (
                  <TableHead key={r} className="text-center text-xs font-mono">
                    {r.replace(/_/g, " ")}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {PERMISSIONS.map((p) => (
                <TableRow key={p.key}>
                  <TableCell className="font-medium">{t(`perm_${p.key}`)}</TableCell>
                  {ROLES.map((r) => (
                    <TableCell key={r} className="text-center">
                      {(p.roles as readonly string[]).includes(r) ? (
                        <Check className="h-4 w-4 text-emerald-500 inline" />
                      ) : (
                        <X className="h-4 w-4 text-muted-foreground/30 inline" />
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
