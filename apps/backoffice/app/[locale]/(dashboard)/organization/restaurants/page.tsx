import { setRequestLocale, getTranslations } from "next-intl/server";
import { getSession } from "@/lib/auth";
import { redirect } from "next/navigation";
import { fetchRestaurants } from "@/lib/server-data";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Plus, Building2 } from "lucide-react";
import { formatDate } from "@/lib/utils";

export default async function RestaurantsListPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  setRequestLocale(locale);
  const session = await getSession();
  if (!session) redirect(`/${locale}/login`);
  const t = await getTranslations({ locale, namespace: "hq" });
  const tCommon = await getTranslations({ locale, namespace: "common" });
  const restaurants = await fetchRestaurants(session);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <Building2 className="h-5 w-5" /> {t("restaurantList")}
          </h1>
          <p className="text-sm text-muted-foreground mt-1">
            Organizasyonunuza bağlı tüm restoranlar
          </p>
        </div>
        <Button size="sm">
          <Plus className="h-4 w-4" /> {t("addRestaurant")}
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Tüm restoranlar ({restaurants.length})</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>İsim</TableHead>
                <TableHead>Adres</TableHead>
                <TableHead>Aktif</TableHead>
                <TableHead>Eklenme</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {restaurants.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4} className="text-center text-muted-foreground py-8">
                    {tCommon("noData")}
                  </TableCell>
                </TableRow>
              )}
              {restaurants.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.name}</TableCell>
                  <TableCell className="text-muted-foreground text-xs">{r.address ?? "—"}</TableCell>
                  <TableCell>
                    {r.is_active ? (
                      <Badge variant="success">{tCommon("active")}</Badge>
                    ) : (
                      <Badge variant="secondary">{tCommon("inactive")}</Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-xs">{formatDate(r.created_at)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
