"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
  Legend,
} from "recharts";

interface HourlyPoint {
  hour: number; // 0-23
  order_count: number;
  revenue: number; // cents
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

export function HourlyClient() {
  const t = useTranslations("reports");
  const tCommon = useTranslations("common");
  const [date, setDate] = React.useState<string>(todayIso());

  const query = useQuery<HourlyPoint[]>({
    queryKey: ["hourly", date],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ points?: HourlyPoint[] } | HourlyPoint[]>({
          path: `/reports/hourly?date=${date}`,
        });
        if (Array.isArray(data)) return data;
        return data.points ?? [];
      } catch {
        return [];
      }
    },
  });

  const points = query.data ?? [];
  const fullSeries = Array.from({ length: 24 }, (_, h) => {
    const found = points.find((p) => p.hour === h);
    return {
      hour: `${String(h).padStart(2, "0")}:00`,
      orders: found?.order_count ?? 0,
      revenue: (found?.revenue ?? 0) / 100,
    };
  });
  const totalOrders = points.reduce((s, p) => s + (p.order_count ?? 0), 0);
  const totalRevenue = points.reduce((s, p) => s + (p.revenue ?? 0), 0);
  const peak = points.length
    ? points.reduce((a, b) => ((a.order_count ?? 0) > (b.order_count ?? 0) ? a : b)).hour
    : null;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-2">
          <Label htmlFor="hourly-date">{t("dateFilter")}</Label>
          <Input
            id="hourly-date"
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="w-[200px]"
          />
        </div>
        <div className="ml-auto flex items-center gap-4 text-sm text-muted-foreground">
          <span>
            {t("totalOrders")}: <span className="font-medium tabular-nums text-foreground">{totalOrders}</span>
          </span>
          <span>
            {t("totalRevenue")}:{" "}
            <span className="font-medium tabular-nums text-foreground">{formatChf(totalRevenue)}</span>
          </span>
          {peak !== null ? (
            <span>
              {t("peakHour")}:{" "}
              <span className="font-medium tabular-nums text-foreground">
                {String(peak).padStart(2, "0")}:00
              </span>
            </span>
          ) : null}
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("hourlyDistribution")}</CardTitle>
        </CardHeader>
        <CardContent className="h-[320px]">
          {query.isLoading ? (
            <div className="h-full flex items-center justify-center text-sm text-muted-foreground">
              {tCommon("loading")}
            </div>
          ) : points.length === 0 ? (
            <div className="h-full flex items-center justify-center text-sm text-muted-foreground">
              {tCommon("noData")}
            </div>
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={fullSeries}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis dataKey="hour" tick={{ fontSize: 10 }} />
                <YAxis yAxisId="left" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
                <Tooltip
                  formatter={(v: number, n: string) =>
                    n === t("revenue") ? `CHF ${v.toFixed(2)}` : `${v}`
                  }
                />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar
                  yAxisId="left"
                  dataKey="orders"
                  name={t("ordersAxis")}
                  fill="hsl(var(--primary))"
                  radius={[4, 4, 0, 0]}
                />
                <Bar
                  yAxisId="right"
                  dataKey="revenue"
                  name={t("revenue")}
                  fill="hsl(var(--muted-foreground))"
                  radius={[4, 4, 0, 0]}
                />
              </BarChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
