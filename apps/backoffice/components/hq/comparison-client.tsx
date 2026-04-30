"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
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

interface RestaurantStat {
  restaurant_id: string;
  restaurant_name: string;
  city?: string | null;
  revenue: number;
  order_count: number;
  avg_ticket?: number;
}

interface AggregateResp {
  total_revenue: number;
  total_orders: number;
  per_restaurant: RestaurantStat[];
}

const PERIODS = [
  { value: "week", labelKey: "periodWeek" },
  { value: "month", labelKey: "periodMonth" },
  { value: "quarter", labelKey: "periodQuarter" },
] as const;

function periodRange(period: string): { from: string; to: string } {
  const to = new Date();
  const from = new Date();
  if (period === "week") from.setDate(from.getDate() - 7);
  else if (period === "month") from.setDate(from.getDate() - 30);
  else from.setDate(from.getDate() - 90);
  return {
    from: from.toISOString().slice(0, 10),
    to: to.toISOString().slice(0, 10),
  };
}

export function ComparisonClient({ orgId }: { orgId: string }) {
  const t = useTranslations("comparisonReport");
  const tCommon = useTranslations("common");
  const [period, setPeriod] = React.useState<string>("month");
  const range = periodRange(period);

  const query = useQuery<AggregateResp | null>({
    queryKey: ["org-by-restaurant", orgId, period],
    queryFn: async () => {
      try {
        return await clientFetch<AggregateResp>({
          path: `/org/${orgId}/reports/by-restaurant?from=${range.from}&to=${range.to}`,
        });
      } catch {
        return null;
      }
    },
  });

  const stats = (query.data?.per_restaurant ?? [])
    .map((r) => ({
      ...r,
      avg_ticket: r.avg_ticket ?? (r.order_count > 0 ? r.revenue / r.order_count : 0),
    }))
    .sort((a, b) => b.revenue - a.revenue);

  const chartData = stats.map((r) => ({
    name: r.restaurant_name.length > 14 ? r.restaurant_name.slice(0, 13) + "…" : r.restaurant_name,
    revenue: r.revenue / 100,
    orders: r.order_count,
    avg: r.avg_ticket / 100,
  }));

  const totalRevenue = query.data?.total_revenue ?? 0;
  const totalOrders = query.data?.total_orders ?? 0;

  function exportCsv() {
    const header = [
      t("colRank"),
      t("colRestaurant"),
      t("colRevenue"),
      t("colOrders"),
      t("colAvgTicket"),
    ].join(",");
    const lines = stats.map((r, i) =>
      [
        i + 1,
        `"${r.restaurant_name.replace(/"/g, '""')}"`,
        (r.revenue / 100).toFixed(2),
        r.order_count,
        (r.avg_ticket / 100).toFixed(2),
      ].join(",")
    );
    const blob = new Blob([[header, ...lines].join("\n")], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `comparison-${period}-${range.to}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select value={period} onValueChange={setPeriod}>
          <SelectTrigger className="w-[180px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {PERIODS.map((p) => (
              <SelectItem key={p.value} value={p.value}>
                {t(p.labelKey)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <div className="ml-auto flex items-center gap-3 text-sm text-muted-foreground">
          <span>
            {t("totalRevenue")}:{" "}
            <span className="font-medium tabular-nums text-foreground">{formatChf(totalRevenue)}</span>
          </span>
          <span>
            {t("totalOrders")}:{" "}
            <span className="font-medium tabular-nums text-foreground">{totalOrders}</span>
          </span>
          <Button size="sm" variant="outline" onClick={exportCsv} disabled={!stats.length}>
            <Download className="mr-2 h-4 w-4" />
            {t("exportCsv")}
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("chartTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="h-[320px]">
          {query.isLoading ? (
            <div className="h-full flex items-center justify-center text-sm text-muted-foreground">
              {tCommon("loading")}
            </div>
          ) : !chartData.length ? (
            <div className="h-full flex items-center justify-center text-sm text-muted-foreground">
              {tCommon("noData")}
            </div>
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis dataKey="name" tick={{ fontSize: 11 }} interval={0} angle={-30} textAnchor="end" height={70} />
                <YAxis yAxisId="left" tick={{ fontSize: 11 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 11 }} />
                <Tooltip
                  formatter={(v: number, n: string) => (n === t("orders") ? `${v}` : `CHF ${v.toFixed(2)}`)}
                />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar yAxisId="left" dataKey="revenue" name={t("revenue")} fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
                <Bar yAxisId="right" dataKey="orders" name={t("orders")} fill="hsl(var(--muted-foreground))" radius={[4, 4, 0, 0]} />
                <Bar yAxisId="left" dataKey="avg" name={t("avgTicket")} fill="hsl(var(--accent))" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("rankingTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {stats.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">{tCommon("noData")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[60px]">{t("colRank")}</TableHead>
                  <TableHead>{t("colRestaurant")}</TableHead>
                  <TableHead className="text-right">{t("colRevenue")}</TableHead>
                  <TableHead className="text-right">{t("colOrders")}</TableHead>
                  <TableHead className="text-right">{t("colAvgTicket")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {stats.map((r, i) => (
                  <TableRow key={r.restaurant_id}>
                    <TableCell className="tabular-nums text-muted-foreground">{i + 1}</TableCell>
                    <TableCell className="font-medium">{r.restaurant_name}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(r.revenue)}</TableCell>
                    <TableCell className="text-right tabular-nums">{r.order_count}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {formatChf(r.avg_ticket)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
