"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatChf } from "@/lib/utils";
import type { AggregateStats } from "@/lib/api-types";

export function LocationCompareChart({
  data,
}: {
  data: AggregateStats["per_restaurant"];
}) {
  if (!data?.length) {
    return <div className="h-72 flex items-center justify-center text-muted-foreground text-sm">—</div>;
  }
  const formatted = data.map((p) => ({
    name: p.restaurant_name,
    revenue: p.revenue / 100,
    orders: p.order_count,
  }));
  return (
    <div className="h-80 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={formatted} margin={{ top: 12, right: 16, left: 0, bottom: 24 }}>
          <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
          <XAxis dataKey="name" stroke="currentColor" fontSize={11} angle={-25} textAnchor="end" height={60} />
          <YAxis stroke="currentColor" fontSize={11} />
          <Tooltip
            contentStyle={{
              background: "hsl(var(--popover))",
              border: "1px solid hsl(var(--border))",
              borderRadius: 6,
              fontSize: 12,
            }}
            formatter={(v: number) => formatChf(v * 100)}
          />
          <Bar dataKey="revenue" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
