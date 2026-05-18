"use client";

/**
 * Staff Performance — client island.
 *
 * Pulls /api/v1/reports/staff-performance once per period selection.
 * Renders a sortable table; clicking a row opens a side-sheet with that
 * user's hourly + daily breakdown (re-uses /reports/sales-summary +
 * /sales-hourly scoped server-side once the brief's drill-down endpoint
 * lands — for the MVP we show the basics from the same envelope).
 */

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { ArrowUpDown, Download } from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatChf } from "@/lib/utils";

type Period = "today" | "this_week" | "this_month" | "last_month";

interface StaffRow {
  user_id: string;
  user_name: string;
  role: string;
  order_count: number;
  gross_cents: number;
  avg_ticket_cents: number;
  tip_total_cents: number;
  void_count: number;
  refund_count: number;
  shift_minutes: number;
  shifts_opened: number;
  gross_per_hour_cents: number;
  orders_per_hour: number;
}

type SortKey =
  | "gross_cents"
  | "order_count"
  | "avg_ticket_cents"
  | "tip_total_cents"
  | "shift_minutes";

export function StaffPerformanceClient() {
  const t = useTranslations("reports.staffPerformance");
  const tc = useTranslations("common");
  const tReports = useTranslations("reports");
  const [period, setPeriod] = React.useState<Period>("this_week");
  const [sort, setSort] = React.useState<SortKey>("gross_cents");

  const query = useQuery({
    queryKey: ["reports", "staff-performance", period],
    queryFn: () =>
      clientFetch<{ period: string; from: string; to: string; staff: StaffRow[] }>({
        path: `/reports/staff-performance?period=${period}`,
      }),
    refetchInterval: 60_000,
  });

  const rows = React.useMemo(() => {
    const all = query.data?.staff ?? [];
    return [...all].sort((a, b) => (b[sort] ?? 0) - (a[sort] ?? 0));
  }, [query.data, sort]);

  const exportHref = query.data
    ? `/api/proxy/reports/export?type=staff&from=${encodeURIComponent(query.data.from.slice(0, 10))}&to=${encodeURIComponent(query.data.to.slice(0, 10))}`
    : undefined;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <Select value={period} onValueChange={(v) => setPeriod(v as Period)}>
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="today">{tc("today")}</SelectItem>
            <SelectItem value="this_week">{tc("thisWeek")}</SelectItem>
            <SelectItem value="this_month">{tc("thisMonth")}</SelectItem>
            <SelectItem value="last_month">{tReports("period.lastMonth")}</SelectItem>
          </SelectContent>
        </Select>
        <Select value={sort} onValueChange={(v) => setSort(v as SortKey)}>
          <SelectTrigger className="w-56">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="gross_cents">{t("sort.revenue")}</SelectItem>
            <SelectItem value="order_count">{t("sort.orderCount")}</SelectItem>
            <SelectItem value="avg_ticket_cents">{t("sort.avgTicket")}</SelectItem>
            <SelectItem value="tip_total_cents">{t("sort.tip")}</SelectItem>
            <SelectItem value="shift_minutes">{t("sort.shift")}</SelectItem>
          </SelectContent>
        </Select>
        {exportHref && (
          <Button asChild variant="outline">
            <a href={exportHref} download>
              <Download className="h-4 w-4" />
              {tReports("downloadExport")}
            </a>
          </Button>
        )}
      </div>

      <Card className="overflow-hidden">
        {query.isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {tc("loading")}
          </div>
        ) : query.error ? (
          <div className="p-12 text-center text-sm text-error">
            {(query.error as Error).message}
          </div>
        ) : rows.length === 0 ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {tc("noData")}
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.role")}</TableHead>
                <TableHead className="text-right">{t("col.orderCount")}</TableHead>
                <TableHead className="text-right">
                  <button
                    className="inline-flex items-center gap-1 hover:underline"
                    onClick={() => setSort("gross_cents")}
                  >
                    {t("col.gross")}
                    <ArrowUpDown className="h-3 w-3" />
                  </button>
                </TableHead>
                <TableHead className="text-right">{t("col.avgTicket")}</TableHead>
                <TableHead className="text-right">{t("col.tip")}</TableHead>
                <TableHead className="text-right">{t("col.shiftHours")}</TableHead>
                <TableHead className="text-right">{t("col.grossPerHour")}</TableHead>
                <TableHead className="text-right">{t("col.voids")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => (
                <TableRow key={r.user_id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{r.user_name}</TableCell>
                  <TableCell className="text-xs uppercase tracking-wider text-muted-foreground">
                    {r.role}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{r.order_count}</TableCell>
                  <TableCell className="text-right tabular-nums font-mono">
                    {formatChf(r.gross_cents / 100)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums font-mono">
                    {formatChf(r.avg_ticket_cents / 100)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums font-mono">
                    {formatChf(r.tip_total_cents / 100)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {(r.shift_minutes / 60).toFixed(1)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums font-mono">
                    {formatChf(r.gross_per_hour_cents / 100)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums text-rose-600">
                    {r.void_count}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>
    </div>
  );
}
