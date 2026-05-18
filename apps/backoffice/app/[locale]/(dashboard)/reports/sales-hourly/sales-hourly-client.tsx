"use client";

/**
 * Hourly Sales — client island.
 *
 * /api/v1/reports/sales-hourly returns `cells[]` with one row per
 * (day-of-week, hour) bucket. We pivot client-side into a 7×24 matrix
 * for the heatmap, then collapse the rows to "today's hourly bars" and
 * the "average by day-of-week" view.
 *
 * Heatmap is CSS-grid (no recharts) — recharts doesn't ship a clean
 * matrix-style heatmap, and the operator value here is "peak slot at a
 * glance" which a colour-scaled grid does just as well.
 */

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { formatChf } from "@/lib/utils";

type Period = "this_week" | "last_week" | "this_month" | "last_month";

interface HourCell {
  day_of_week: number; // 0 Sun .. 6 Sat (Postgres EXTRACT(DOW))
  hour: number; // 0..23
  gross_cents: number;
  order_count: number;
}

interface HourlyEnvelope {
  period: Period;
  from: string;
  to: string;
  cells: HourCell[];
  previous: HourCell[];
}

// Localized day labels (Mon-first to match Swiss / EU convention).
const DOW_ORDER = [1, 2, 3, 4, 5, 6, 0] as const;

export function SalesHourlyClient() {
  const t = useTranslations("reports.salesHourly");
  const tc = useTranslations("common");
  const [period, setPeriod] = React.useState<Period>("this_week");

  const query = useQuery({
    queryKey: ["reports", "sales-hourly", period],
    queryFn: () =>
      clientFetch<HourlyEnvelope>({ path: `/reports/sales-hourly?period=${period}` }),
    refetchInterval: 60_000,
  });

  const data = query.data;
  const matrix = React.useMemo(() => pivot(data?.cells ?? []), [data]);
  const max = React.useMemo(
    () => Math.max(1, ...(data?.cells ?? []).map((c) => c.gross_cents)),
    [data],
  );

  const hourlyToday = React.useMemo(() => {
    if (!data) return [];
    // Sum across all DOW into a single hour-of-day series for the bar chart.
    const sum = Array.from({ length: 24 }, (_, h) => ({
      hour: h,
      label: `${h.toString().padStart(2, "0")}:00`,
      gross_cents: 0,
      order_count: 0,
    }));
    for (const c of data.cells) {
      sum[c.hour].gross_cents += c.gross_cents;
      sum[c.hour].order_count += c.order_count;
    }
    return sum;
  }, [data]);

  // Detect peak slot for the insight badge.
  const peak = React.useMemo(() => {
    if (!data || data.cells.length === 0) return null;
    return [...data.cells].sort((a, b) => b.gross_cents - a.gross_cents)[0];
  }, [data]);

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Select value={period} onValueChange={(v) => setPeriod(v as Period)}>
          <SelectTrigger className="w-48">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="this_week">{tc("thisWeek")}</SelectItem>
            <SelectItem value="last_week">{t("period.lastWeek")}</SelectItem>
            <SelectItem value="this_month">{tc("thisMonth")}</SelectItem>
            <SelectItem value="last_month">{t("period.lastMonth")}</SelectItem>
          </SelectContent>
        </Select>
      </div>

      {query.isLoading ? (
        <div className="p-12 text-center text-sm text-muted-foreground">
          {tc("loading")}
        </div>
      ) : query.error ? (
        <div className="p-12 text-center text-sm text-error">
          {(query.error as Error).message}
        </div>
      ) : !data ? null : (
        <>
          {peak && (
            <Card className="p-4 border-l-4 border-l-emerald-500 bg-emerald-50/40">
              <div className="text-xs uppercase tracking-wider text-emerald-700 font-semibold">
                {t("insight.peak")}
              </div>
              <div className="text-sm mt-1">
                {t("insight.peakLine", {
                  day: t(`day.${dowKey(peak.day_of_week)}`),
                  hour: `${peak.hour.toString().padStart(2, "0")}:00`,
                  amount: formatChf(peak.gross_cents / 100),
                })}
              </div>
            </Card>
          )}

          <Card className="p-4">
            <h2 className="text-sm font-semibold mb-3">{t("heatmap")}</h2>
            <div className="overflow-x-auto">
              <Heatmap matrix={matrix} max={max} dayLabel={(d) => t(`day.${dowKey(d)}`)} />
            </div>
          </Card>

          <Card className="p-4">
            <h2 className="text-sm font-semibold mb-3">{t("hourlyToday")}</h2>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={hourlyToday}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.06)" />
                  <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                  <YAxis
                    tick={{ fontSize: 11 }}
                    tickFormatter={(v) => `${Math.round(v / 100)}`}
                  />
                  <Tooltip formatter={(v: number) => formatChf(v / 100)} />
                  <Bar dataKey="gross_cents" fill="#3b82f6" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </Card>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Heatmap (CSS grid)
// ---------------------------------------------------------------------------

function Heatmap({
  matrix,
  max,
  dayLabel,
}: {
  matrix: Record<number, Record<number, HourCell>>;
  max: number;
  dayLabel: (dow: number) => string;
}) {
  return (
    <div className="inline-grid gap-[2px]" style={{ gridTemplateColumns: "auto repeat(24, 24px)" }}>
      {/* header row: hour labels */}
      <div />
      {Array.from({ length: 24 }, (_, h) => (
        <div
          key={`h-${h}`}
          className="text-[9px] text-muted-foreground font-mono text-center"
        >
          {h % 3 === 0 ? h.toString().padStart(2, "0") : ""}
        </div>
      ))}
      {/* rows */}
      {DOW_ORDER.map((dow) => (
        <React.Fragment key={dow}>
          <div className="text-[10px] uppercase tracking-wider text-muted-foreground pr-2 font-mono self-center">
            {dayLabel(dow)}
          </div>
          {Array.from({ length: 24 }, (_, h) => {
            const cell = matrix[dow]?.[h];
            const v = cell?.gross_cents ?? 0;
            const intensity = max > 0 ? v / max : 0;
            const bg = intensity === 0
              ? "rgba(0,0,0,0.04)"
              : `rgba(59, 130, 246, ${0.15 + intensity * 0.75})`;
            return (
              <div
                key={`c-${dow}-${h}`}
                title={cell
                  ? `${formatChf(cell.gross_cents / 100)} · ${cell.order_count}×`
                  : "—"}
                className="rounded-[2px] h-6"
                style={{ backgroundColor: bg }}
              />
            );
          })}
        </React.Fragment>
      ))}
    </div>
  );
}

function pivot(cells: HourCell[]) {
  const m: Record<number, Record<number, HourCell>> = {};
  for (const c of cells) {
    (m[c.day_of_week] ??= {})[c.hour] = c;
  }
  return m;
}

function dowKey(dow: number): string {
  // Map Postgres EXTRACT(DOW) → i18n keys (sun..sat).
  return ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][dow] ?? "sun";
}
