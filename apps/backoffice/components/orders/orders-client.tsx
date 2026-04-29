"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { formatChf, formatDateTime } from "@/lib/utils";
import { clientFetch } from "@/lib/api-client";
import type { Order, OrderStatus } from "@/lib/api-types";

const POLL_MS = 10_000;

export function OrdersClient({ initial }: { initial: Order[] }) {
  const t = useTranslations("orders");
  const tCommon = useTranslations("common");
  const [from, setFrom] = React.useState("");
  const [to, setTo] = React.useState("");
  const [status, setStatus] = React.useState<OrderStatus | "all">("all");
  const [selected, setSelected] = React.useState<Order | null>(null);

  const params = new URLSearchParams();
  if (from) params.set("from", from);
  if (to) params.set("to", to);
  if (status !== "all") params.set("status", status);
  const qs = params.toString();
  const path = `/orders${qs ? `?${qs}` : ""}`;

  const { data: orders = initial } = useQuery({
    queryKey: ["orders", path],
    queryFn: () =>
      clientFetch<Order[] | { orders: Order[] }>({ path }).then((d) =>
        Array.isArray(d) ? d : d.orders ?? []
      ),
    initialData: initial,
    refetchInterval: POLL_MS,
  });

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2 items-end">
        <div className="space-y-1">
          <label className="text-xs text-muted-foreground">{tCommon("from")}</label>
          <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-44" />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-muted-foreground">{tCommon("to")}</label>
          <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-44" />
        </div>
        <div className="space-y-1">
          <label className="text-xs text-muted-foreground">{t("filterByStatus")}</label>
          <Select value={status} onValueChange={(v) => setStatus(v as OrderStatus | "all")}>
            <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">{tCommon("all")}</SelectItem>
              <SelectItem value="open">{t("open")}</SelectItem>
              <SelectItem value="preparing">{t("preparing")}</SelectItem>
              <SelectItem value="paid">{t("paid")}</SelectItem>
              <SelectItem value="closed">{t("closed")}</SelectItem>
              <SelectItem value="cancelled">{t("cancelled")}</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <Button variant="outline" size="sm" onClick={() => exportCsv(orders)}>
          {t("exportCsv")}
        </Button>
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("orderNumber", { number: "" })}</TableHead>
              <TableHead>{t("date")}</TableHead>
              <TableHead>{t("channel")}</TableHead>
              <TableHead>{t("status")}</TableHead>
              <TableHead className="text-right">{t("total")}</TableHead>
              <TableHead className="w-24"></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {orders.length === 0 && (
              <TableRow><TableCell colSpan={6} className="text-center text-muted-foreground py-8">{tCommon("noData")}</TableCell></TableRow>
            )}
            {orders.map((o) => (
              <TableRow key={o.id} onClick={() => setSelected(o)} className="cursor-pointer">
                <TableCell className="font-medium">#{o.number}</TableCell>
                <TableCell>{formatDateTime(o.created_at)}</TableCell>
                <TableCell>
                  <Badge variant="outline">{channelLabel(o.channel, t)}</Badge>
                </TableCell>
                <TableCell>{statusBadge(o.status, t)}</TableCell>
                <TableCell className="text-right tabular-nums">{formatChf(o.total)}</TableCell>
                <TableCell className="text-right">
                  <Button variant="ghost" size="sm">{tCommon("edit")}</Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>{t("detail")} · #{selected?.number}</DialogTitle>
          </DialogHeader>
          {selected && (
            <div className="space-y-3 text-sm">
              <div className="grid grid-cols-2 gap-2 text-xs">
                <div><span className="text-muted-foreground">{t("date")}:</span> {formatDateTime(selected.created_at)}</div>
                <div><span className="text-muted-foreground">{t("status")}:</span> {selected.status}</div>
                <div><span className="text-muted-foreground">{t("channel")}:</span> {channelLabel(selected.channel, t)}</div>
                <div><span className="text-muted-foreground">{t("total")}:</span> {formatChf(selected.total)}</div>
              </div>
              <div className="border-t pt-3">
                <div className="text-xs text-muted-foreground mb-2">{t("items")}</div>
                <div className="space-y-1.5">
                  {(selected.items ?? []).map((it) => (
                    <div key={it.id} className="flex justify-between">
                      <span>{it.quantity}× {it.product_name}</span>
                      <span className="tabular-nums">{formatChf(it.total)}</span>
                    </div>
                  ))}
                  {!selected.items?.length && <p className="text-xs text-muted-foreground">{tCommon("noData")}</p>}
                </div>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}

type Translator = (key: string, values?: Record<string, string | number>) => string;

function statusBadge(s: OrderStatus, t: Translator) {
  const map: Record<OrderStatus, "default" | "secondary" | "success" | "warning" | "destructive"> = {
    open: "warning",
    preparing: "warning",
    paid: "success",
    closed: "secondary",
    cancelled: "destructive",
  };
  return <Badge variant={map[s] ?? "default"}>{t(s)}</Badge>;
}

function channelLabel(c: string, t: Translator) {
  if (c === "dine_in") return t("dineIn");
  if (c === "takeaway") return t("takeaway");
  if (c === "delivery") return t("delivery");
  return c;
}

function exportCsv(orders: Order[]) {
  const headers = ["number", "status", "channel", "total_chf", "created_at"];
  const rows = orders.map((o) => [
    String(o.number),
    o.status,
    o.channel,
    (o.total / 100).toFixed(2),
    o.created_at,
  ]);
  const csv = [headers.join(","), ...rows.map((r) => r.map(csvCell).join(","))].join("\n");
  const blob = new Blob([csv], { type: "text/csv" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `orders-${Date.now()}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

function csvCell(v: string) {
  if (/[",\n]/.test(v)) return `"${v.replace(/"/g, '""')}"`;
  return v;
}
