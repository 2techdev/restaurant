import { setRequestLocale, getTranslations } from "next-intl/server";
import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";
import { canManageHq } from "@/lib/roles";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { CreditCard, Download, Info } from "lucide-react";

export default async function Page({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  if (!canManageHq(session.user.org_role)) redirect(`/${locale}/dashboard`);
  const t = await getTranslations({ locale, namespace: "orgBilling" });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
        <p className="text-sm text-muted-foreground">{t("subtitle")}</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Card className="lg:col-span-2">
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle className="text-base">{t("currentPlan")}</CardTitle>
              <Badge>{t("planPilot")}</Badge>
            </div>
            <CardDescription>{t("planPilotDesc")}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-3 gap-4">
              <div>
                <div className="text-xs text-muted-foreground">{t("limitRestaurants")}</div>
                <div className="text-xl font-semibold tabular-nums">3</div>
                <div className="text-xs text-muted-foreground">{t("currentUsage", { current: 1 })}</div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground">{t("limitUsers")}</div>
                <div className="text-xl font-semibold tabular-nums">10</div>
                <div className="text-xs text-muted-foreground">{t("currentUsage", { current: 2 })}</div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground">{t("limitOrdersMonth")}</div>
                <div className="text-xl font-semibold tabular-nums">∞</div>
                <div className="text-xs text-muted-foreground">{t("unlimited")}</div>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">{t("nextInvoice")}</CardTitle>
            <CardDescription>{t("nextInvoiceDesc")}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2">
            <div className="text-2xl font-bold tabular-nums">CHF 0.00</div>
            <div className="text-xs text-muted-foreground">{t("pilotFree")}</div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="text-base flex items-center gap-2">
              <CreditCard className="h-4 w-4" /> {t("paymentMethod")}
            </CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          <Alert>
            <Info className="h-4 w-4" />
            <AlertDescription>{t("stripeComing")}</AlertDescription>
          </Alert>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("invoiceHistory")}</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("colInvoiceNumber")}</TableHead>
                <TableHead>{t("colPeriod")}</TableHead>
                <TableHead>{t("colStatus")}</TableHead>
                <TableHead className="text-right">{t("colAmount")}</TableHead>
                <TableHead className="w-[100px]" />
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow>
                <TableCell colSpan={5} className="text-center text-sm text-muted-foreground py-8">
                  {t("noInvoicesYet")}
                </TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
