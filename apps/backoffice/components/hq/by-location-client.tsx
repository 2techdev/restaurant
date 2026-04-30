"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { MapPin, Building2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";

interface RestaurantStat {
  restaurant_id: string;
  restaurant_name: string;
  city?: string | null;
  revenue: number;
  order_count: number;
  top_product_name?: string | null;
}

interface ByRestaurantResp {
  total_revenue: number;
  per_restaurant: RestaurantStat[];
}

interface CityGroup {
  city: string;
  restaurants: RestaurantStat[];
  totalRevenue: number;
  totalOrders: number;
  topProduct: string | null;
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}
function thirtyAgo() {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d.toISOString().slice(0, 10);
}

export function ByLocationClient({ orgId }: { orgId: string }) {
  const t = useTranslations("byLocationReport");
  const tCommon = useTranslations("common");

  const query = useQuery<ByRestaurantResp | null>({
    queryKey: ["org-by-restaurant-location", orgId],
    queryFn: async () => {
      try {
        return await clientFetch<ByRestaurantResp>({
          path: `/org/${orgId}/reports/by-restaurant?from=${thirtyAgo()}&to=${todayIso()}`,
        });
      } catch {
        return null;
      }
    },
  });

  const restaurants = query.data?.per_restaurant ?? [];

  const groups: CityGroup[] = React.useMemo(() => {
    const map = new Map<string, RestaurantStat[]>();
    for (const r of restaurants) {
      const key = r.city || t("unknownCity");
      const list = map.get(key) ?? [];
      list.push(r);
      map.set(key, list);
    }
    const out: CityGroup[] = [];
    for (const [city, list] of map.entries()) {
      const totalRevenue = list.reduce((s, r) => s + (r.revenue ?? 0), 0);
      const totalOrders = list.reduce((s, r) => s + (r.order_count ?? 0), 0);
      // Pick the first non-empty top_product_name as the city's representative
      // (Agent E's chained reduce had a TS strict-null narrowing issue in
      // production build; simplified here without changing the visible output).
      const topProduct: string | null =
        list.find((r) => r.top_product_name)?.top_product_name ?? null;
      out.push({ city, restaurants: list, totalRevenue, totalOrders, topProduct });
    }
    return out.sort((a, b) => b.totalRevenue - a.totalRevenue);
  }, [restaurants, t]);

  return (
    <div className="space-y-4">
      {query.isLoading ? (
        <Card>
          <CardContent className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</CardContent>
        </Card>
      ) : groups.length === 0 ? (
        <Card>
          <CardContent className="p-6 text-sm text-muted-foreground text-center">
            {tCommon("noData")}
            <div className="text-xs mt-2 italic">{t("emptyHint")}</div>
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-4">
          {groups.map((g) => (
            <Card key={g.city}>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base flex items-center gap-2">
                    <MapPin className="h-4 w-4 text-muted-foreground" />
                    {g.city}
                  </CardTitle>
                  <Badge variant="outline" className="font-mono text-xs">
                    {g.restaurants.length} {t("restaurants")}
                  </Badge>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <div className="text-xs text-muted-foreground">{t("totalRevenue")}</div>
                    <div className="font-semibold tabular-nums">{formatChf(g.totalRevenue)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-muted-foreground">{t("totalOrders")}</div>
                    <div className="font-semibold tabular-nums">{g.totalOrders}</div>
                  </div>
                </div>
                {g.topProduct ? (
                  <div className="border-t pt-2">
                    <div className="text-xs text-muted-foreground">{t("topProduct")}</div>
                    <div className="text-sm font-medium">{g.topProduct}</div>
                  </div>
                ) : null}
                <div className="border-t pt-2 space-y-1">
                  {g.restaurants.map((r) => (
                    <div key={r.restaurant_id} className="flex items-center justify-between text-xs">
                      <span className="flex items-center gap-1 text-muted-foreground">
                        <Building2 className="h-3 w-3" />
                        {r.restaurant_name}
                      </span>
                      <span className="tabular-nums">{formatChf(r.revenue)}</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
