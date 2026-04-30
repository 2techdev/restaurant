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
import type { TopSeller } from "@/lib/api-types";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

const PERIOD_OPTIONS = [
  { value: "7", labelKey: "period7d" },
  { value: "30", labelKey: "period30d" },
  { value: "90", labelKey: "period90d" },
  { value: "365", labelKey: "period365d" },
] as const;

export function TopSellersClient({ initial }: { initial: TopSeller[] }) {
  const t = useTranslations("reports");
  const tCommon = useTranslations("common");
  const [period, setPeriod] = React.useState<string>("30");

  const query = useQuery<TopSeller[]>({
    queryKey: ["top-sellers", period],
    queryFn: async () => {
      const data = await clientFetch<{ items?: TopSeller[] } | TopSeller[]>({
        path: `/reports/products?days=${period}&limit=50`,
      });
      if (Array.isArray(data)) return data;
      return data.items ?? [];
    },
    initialData: period === "30" ? initial : undefined,
    staleTime: 30_000,
  });

  const items = query.data ?? [];
  const totalQty = items.reduce((s, it) => s + (it.quantity ?? 0), 0);
  const totalRev = items.reduce((s, it) => s + (it.revenue ?? 0), 0);

  const chartData = items.slice(0, 10).map((it) => ({
    name: it.product_name.length > 14 ? it.product_name.slice(0, 13) + "…" : it.product_name,
    revenue: (it.revenue ?? 0) / 100,
    qty: it.quantity ?? 0,
  }));

  function exportCsv() {
    const header = [
      t("colRank"),
      t("colProduct"),
      t("colQty"),
      t("colRevenue"),
      t("colAvgPrice"),
    ].join(",");
    const lines = items.map((it, idx) => {
      const avg = (it.quantity ?? 0) > 0 ? (it.revenue ?? 0) / (it.quantity ?? 1) : 0;
      return [
        idx + 1,
        `"${it.product_name.replace(/"/g, '""')}"`,
        it.quantity ?? 0,
        ((it.revenue ?? 0) / 100).toFixed(2),
        (avg / 100).toFixed(2),
      ].join(",");
    });
    const blob = new Blob([[header, ...lines].join("\n")], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `top-sellers-${period}d-${new Date().toISOString().slice(0, 10)}.csv`;
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
            {PERIOD_OPTIONS.map((p) => (
              <SelectItem key={p.value} value={p.value}>
                {t(p.labelKey)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <div className="ml-auto flex items-center gap-3 text-sm text-muted-foreground">
          <span>
            {t("totalQty")}: <span className="font-medium tabular-nums text-foreground">{totalQty}</span>
          </span>
          <span>
            {t("totalRevenue")}:{" "}
            <span className="font-medium tabular-nums text-foreground">{formatChf(totalRev)}</span>
          </span>
          <Button size="sm" variant="outline" onClick={exportCsv} disabled={!items.length}>
            <Download className="mr-2 h-4 w-4" />
            {t("exportCsv")}
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("top10Chart")}</CardTitle>
        </CardHeader>
        <CardContent className="h-[280px]">
          {chartData.length ? (
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis dataKey="name" tick={{ fontSize: 11 }} interval={0} angle={-30} textAnchor="end" height={60} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip
                  formatter={(v: number, n: string) =>
                    n === "revenue" ? `CHF ${v.toFixed(2)}` : `${v}`
                  }
                />
                <Bar dataKey="revenue" name={t("revenue")} fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <div className="h-full flex items-center justify-center text-sm text-muted-foreground">
              {tCommon("noData")}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : items.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">{tCommon("noData")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[50px]">#</TableHead>
                  <TableHead>{t("colProduct")}</TableHead>
                  <TableHead className="text-right">{t("colQty")}</TableHead>
                  <TableHead className="text-right">{t("colRevenue")}</TableHead>
                  <TableHead className="text-right">{t("colAvgPrice")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((it, idx) => {
                  const avg = (it.quantity ?? 0) > 0 ? (it.revenue ?? 0) / (it.quantity ?? 1) : 0;
                  return (
                    <TableRow key={it.product_id}>
                      <TableCell className="tabular-nums text-muted-foreground">{idx + 1}</TableCell>
                      <TableCell className="font-medium">{it.product_name}</TableCell>
                      <TableCell className="text-right tabular-nums">{it.quantity}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatChf(it.revenue)}</TableCell>
                      <TableCell className="text-right tabular-nums text-muted-foreground">
                        {formatChf(avg)}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
