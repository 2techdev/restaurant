"use client";

/**
 * Sales Summary — client island.
 *
 * One round-trip to `/api/v1/reports/sales-summary?period=...&start=&end=`
 * pulls every aggregate this page renders:
 *   • KPI cards (gross / net / avg ticket / order count) + % delta
 *     against the equivalent previous period
 *   • daily series line chart (30-day default; window follows the period
 *     selector)
 *   • payment method donut
 *   • order type bar
 *   • top-10 products bar
 *   • top-5 categories bar
 *
 * Uses recharts (already installed, v2.13.3). CSV export is a direct
 * link to the existing `/api/v1/reports/export` endpoint scoped by the
 * same period.
 */

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { TrendingUp, TrendingDown, Download, Users, Receipt } from "lucide-react";

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
import { formatChf } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Types — mirror the Go envelope shape from dashboard_handlers.go
// ---------------------------------------------------------------------------

type Period =
  | "today"
  | "yesterday"
  | "this_week"
  | "last_week"
  | "this_month"
  | "last_month";

interface KpiSet {
  gross_cents: number;
  net_cents: number;
  tax_cents: number;
  discount_cents: number;
  order_count: number;
  avg_ticket_cents: number;
  guest_count: number;
}

interface SalesSummary {
  period: Period;
  from: string;
  to: string;
  kpi: {
    current: KpiSet;
    previous: KpiSet;
    gross_delta_pct: number;
    count_delta_pct: number;
  };
  daily: Array<{ date: string; gross_cents: number; order_count: number }>;
  payment: Array<{ key: string; label: string; value_cents: number; count: number }>;
  order_type: Array<{ key: string; label: string; value_cents: number; count: number }>;
  top_products: Array<{
    product_id: string;
    name: string;
    quantity: number;
    revenue_cents: number;
    order_count: number;
  }>;
  top_categories: Array<{
    category_id: string;
    name: string;
    revenue_cents: number;
    quantity: number;
  }>;
}

// Recharts colour palette — picked for legibility on white + dark cards.
const PALETTE = [
  "#3b82f6",
  "#10b981",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#ec4899",
  "#14b8a6",
];

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function SalesSummaryClient() {
  const t = useTranslations("reports.salesSummary");
  const tCommon = useTranslations("common");
  const [period, setPeriod] = React.useState<Period>("today");

  const query = useQuery({
    queryKey: ["reports", "sales-summary", period],
    queryFn: async () => {
      return clientFetch<SalesSummary>({ path: `/reports/sales-summary?period=${period}` });
    },
    refetchInterval: 60_000, // gentle auto-refresh; WS upgrade later
  });

  const data = query.data;

  return (
    <div className="space-y-6">
      <Toolbar period={period} onPeriod={setPeriod} fromTo={data ? { from: data.from, to: data.to } : null} />

      {query.isLoading ? (
        <div className="p-12 text-center text-sm text-muted-foreground">
          {tCommon("loading")}
        </div>
      ) : query.error ? (
        <div className="p-12 text-center text-sm text-error">
          {(query.error as Error).message}
        </div>
      ) : !data ? null : (
        <>
          {/* KPI cards */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <KpiCard
              label={t("kpi.gross")}
              valueChf={data.kpi.current.gross_cents / 100}
              deltaPct={data.kpi.gross_delta_pct}
              icon={<Receipt className="h-4 w-4" />}
            />
            <KpiCard
              label={t("kpi.net")}
              valueChf={data.kpi.current.net_cents / 100}
            />
            <KpiCard
              label={t("kpi.avgTicket")}
              valueChf={data.kpi.current.avg_ticket_cents / 100}
            />
            <KpiCard
              label={t("kpi.orderCount")}
              valueChf={null}
              valueRaw={data.kpi.current.order_count}
              deltaPct={data.kpi.count_delta_pct}
              icon={<Users className="h-4 w-4" />}
            />
          </div>

          {/* Daily line chart */}
          <Card className="p-4">
            <h2 className="text-sm font-semibold mb-3">{t("dailyChart")}</h2>
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={data.daily}>
                  <defs>
                    <linearGradient id="grad-gross" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.4} />
                      <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.06)" />
                  <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                  <YAxis
                    tick={{ fontSize: 11 }}
                    tickFormatter={(v) => `${Math.round(v / 100)}`}
                  />
                  <Tooltip
                    formatter={(v: number) => formatChf(v / 100)}
                    labelFormatter={(l) => l}
                  />
                  <Area
                    type="monotone"
                    dataKey="gross_cents"
                    stroke="#3b82f6"
                    fill="url(#grad-gross)"
                    name={t("kpi.gross")}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </Card>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* Payment method donut */}
            <Card className="p-4">
              <h2 className="text-sm font-semibold mb-3">{t("paymentBreakdown")}</h2>
              <div className="h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={data.payment}
                      dataKey="value_cents"
                      nameKey="label"
                      cx="50%"
                      cy="50%"
                      outerRadius={80}
                      innerRadius={50}
                      label={({ label }) => label}
                    >
                      {data.payment.map((_, i) => (
                        <Cell key={i} fill={PALETTE[i % PALETTE.length]} />
                      ))}
                    </Pie>
                    <Tooltip formatter={(v: number) => formatChf(v / 100)} />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </Card>

            {/* Order type bar */}
            <Card className="p-4">
              <h2 className="text-sm font-semibold mb-3">{t("orderTypeBreakdown")}</h2>
              <div className="h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={data.order_type}>
                    <CartesianGrid strokeDasharray="3 3" stroke="rgba(0,0,0,0.06)" />
                    <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                    <YAxis
                      tick={{ fontSize: 11 }}
                      tickFormatter={(v) => `${Math.round(v / 100)}`}
                    />
                    <Tooltip formatter={(v: number) => formatChf(v / 100)} />
                    <Bar dataKey="value_cents" fill="#10b981" />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </Card>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card className="p-4">
              <h2 className="text-sm font-semibold mb-3">{t("topProducts")}</h2>
              <Ranking
                rows={data.top_products.map((p) => ({
                  label: p.name,
                  value: p.revenue_cents,
                  meta: `${p.quantity}× · ${p.order_count} ${t("orders")}`,
                }))}
              />
            </Card>
            <Card className="p-4">
              <h2 className="text-sm font-semibold mb-3">{t("topCategories")}</h2>
              <Ranking
                rows={data.top_categories.map((c) => ({
                  label: c.name,
                  value: c.revenue_cents,
                  meta: `${c.quantity}×`,
                }))}
              />
            </Card>
          </div>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Internal widgets
// ---------------------------------------------------------------------------

function Toolbar({
  period,
  onPeriod,
  fromTo,
}: {
  period: Period;
  onPeriod: (p: Period) => void;
  fromTo: { from: string; to: string } | null;
}) {
  const t = useTranslations("reports");
  const tc = useTranslations("common");

  const exportHref = fromTo
    ? `/api/proxy/reports/export?type=orders&from=${encodeURIComponent(fromTo.from.slice(0, 10))}&to=${encodeURIComponent(fromTo.to.slice(0, 10))}`
    : undefined;

  return (
    <div className="flex items-center gap-3 flex-wrap">
      <Select value={period} onValueChange={(v) => onPeriod(v as Period)}>
        <SelectTrigger className="w-48">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="today">{tc("today")}</SelectItem>
          <SelectItem value="yesterday">{tc("yesterday")}</SelectItem>
          <SelectItem value="this_week">{tc("thisWeek")}</SelectItem>
          <SelectItem value="last_week">{t("period.lastWeek")}</SelectItem>
          <SelectItem value="this_month">{tc("thisMonth")}</SelectItem>
          <SelectItem value="last_month">{t("period.lastMonth")}</SelectItem>
        </SelectContent>
      </Select>
      {exportHref && (
        <Button asChild variant="outline">
          <a href={exportHref} download>
            <Download className="h-4 w-4" />
            {t("downloadExport")}
          </a>
        </Button>
      )}
    </div>
  );
}

function KpiCard({
  label,
  valueChf,
  valueRaw,
  deltaPct,
  icon,
}: {
  label: string;
  valueChf: number | null;
  valueRaw?: number;
  deltaPct?: number;
  icon?: React.ReactNode;
}) {
  const positive = (deltaPct ?? 0) >= 0;
  return (
    <Card className="p-4">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wider text-muted-foreground">
          {label}
        </span>
        {icon ?? null}
      </div>
      <div className="text-2xl font-bold tabular-nums mt-2">
        {valueChf !== null ? formatChf(valueChf) : valueRaw}
      </div>
      {deltaPct !== undefined && (
        <div
          className={`text-xs mt-1 flex items-center gap-1 ${
            positive ? "text-emerald-600" : "text-rose-600"
          }`}
        >
          {positive ? (
            <TrendingUp className="h-3 w-3" />
          ) : (
            <TrendingDown className="h-3 w-3" />
          )}
          {deltaPct.toFixed(1)}%
        </div>
      )}
    </Card>
  );
}

function Ranking({
  rows,
}: {
  rows: Array<{ label: string; value: number; meta?: string }>;
}) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <div className="space-y-2">
      {rows.length === 0 && (
        <div className="text-sm text-muted-foreground p-4 text-center">—</div>
      )}
      {rows.map((r, i) => (
        <div key={i} className="space-y-1">
          <div className="flex items-baseline justify-between text-sm">
            <span className="font-medium truncate pr-2">{r.label}</span>
            <span className="font-mono tabular-nums text-xs">
              {formatChf(r.value / 100)}
            </span>
          </div>
          <div className="h-1.5 rounded bg-muted overflow-hidden">
            <div
              className="h-full bg-primary"
              style={{ width: `${Math.round((r.value / max) * 100)}%` }}
            />
          </div>
          {r.meta && (
            <div className="text-[11px] text-muted-foreground">{r.meta}</div>
          )}
        </div>
      ))}
    </div>
  );
}
