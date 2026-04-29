"use client";

import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatChf } from "@/lib/utils";
import type { RevenuePoint } from "@/lib/api-types";

export function RevenueChart({ data }: { data: RevenuePoint[] }) {
  if (!data.length) {
    return <div className="h-72 flex items-center justify-center text-muted-foreground text-sm">—</div>;
  }
  const formatted = data.map((p) => ({
    date: p.date,
    revenue: p.revenue / 100,
    order_count: p.order_count,
  }));

  return (
    <div className="h-72 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={formatted} margin={{ top: 12, right: 16, left: 0, bottom: 0 }}>
          <defs>
            <linearGradient id="revFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="hsl(var(--primary))" stopOpacity={0.6} />
              <stop offset="95%" stopColor="hsl(var(--primary))" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
          <XAxis dataKey="date" stroke="currentColor" fontSize={11} />
          <YAxis stroke="currentColor" fontSize={11} tickFormatter={(v) => `${v}`} />
          <Tooltip
            contentStyle={{
              background: "hsl(var(--popover))",
              border: "1px solid hsl(var(--border))",
              borderRadius: 6,
              fontSize: 12,
            }}
            formatter={(value: number) => formatChf(value * 100)}
          />
          <Area
            type="monotone"
            dataKey="revenue"
            stroke="hsl(var(--primary))"
            fill="url(#revFill)"
            strokeWidth={2}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
