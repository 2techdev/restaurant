"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import {
  flexRender,
  getCoreRowModel,
  useReactTable,
  type ColumnDef,
} from "@tanstack/react-table";
import { Loader2, Search, ChevronLeft, ChevronRight, Receipt } from "lucide-react";
import { clientFetch } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { StatusBadge } from "@/components/ui/status-badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { Order, OrderStatus } from "@/lib/api-types";
import { formatChf, formatDateTime } from "@/lib/utils";

const PAGE_SIZE = 50;

const STATUSES: OrderStatus[] = [
  "open",
  "preparing",
  "paid",
  "closed",
  "cancelled",
];

const STATUS_VARIANT: Record<string, "success" | "warning" | "info" | "neutral" | "error"> = {
  paid: "success",
  closed: "success",
  open: "info",
  preparing: "warning",
  cancelled: "error",
};

interface FilterState {
  from: string;
  to: string;
  status: string;
  table: string;
}

const EMPTY_FILTER: FilterState = { from: "", to: "", status: "all", table: "" };

export function OrdersHistoryClient() {
  const t = useTranslations("orders.history");
  const tStatus = useTranslations("orders.status");
  const tCommon = useTranslations("common");

  const [filter, setFilter] = React.useState<FilterState>(EMPTY_FILTER);
  const [applied, setApplied] = React.useState<FilterState>(EMPTY_FILTER);
  const [cursor, setCursor] = React.useState<string | null>(null);
  const [cursorStack, setCursorStack] = React.useState<string[]>([]);
  const [selected, setSelected] = React.useState<Order | null>(null);

  const queryKey = ["orders-history", applied, cursor];

  const list = useQuery({
    queryKey,
    queryFn: async () => {
      const params = new URLSearchParams();
      if (applied.from) params.set("date_from", applied.from);
      if (applied.to) params.set("date_to", applied.to);
      if (applied.status !== "all") params.set("status", applied.status);
      params.set("limit", String(PAGE_SIZE));
      if (cursor) params.set("cursor", cursor);
      const data = await clientFetch<Order[] | { orders?: Order[]; data?: Order[] }>({
        path: `/orders?${params.toString()}`,
      });
      // Backend can return either an array, {orders:[]}, or {data:[]}
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      const arr: Order[] = Array.isArray(raw)
        ? raw
        : raw?.orders ?? raw?.data ?? [];
      // Client-side table filter (backend doesn't support yet)
      const table = applied.table.trim().toLowerCase();
      return table
        ? arr.filter((o) =>
            (o.table_id ?? "").toLowerCase().includes(table) ||
            String(o.number ?? "").toLowerCase().includes(table)
          )
        : arr;
    },
  });

  const apply = () => {
    setApplied(filter);
    setCursor(null);
    setCursorStack([]);
  };

  const reset = () => {
    setFilter(EMPTY_FILTER);
    setApplied(EMPTY_FILTER);
    setCursor(null);
    setCursorStack([]);
  };

  const orders = list.data ?? [];

  const columns = React.useMemo<ColumnDef<Order>[]>(
    () => [
      {
        id: "id",
        header: t("col.id"),
        cell: ({ row }) => (
          <span className="font-mono text-[12px]">
            #{String(row.original.number ?? row.original.id.slice(0, 8))}
          </span>
        ),
      },
      {
        id: "date",
        header: t("col.date"),
        cell: ({ row }) => (
          <span className="text-muted-foreground">
            {formatDateTime(row.original.created_at)}
          </span>
        ),
      },
      {
        id: "table",
        header: t("col.table"),
        cell: ({ row }) => row.original.table_id ?? "—",
      },
      {
        id: "items",
        header: t("col.items"),
        cell: ({ row }) => (
          <span className="tabular-nums">
            {row.original.items?.length ?? 0}
          </span>
        ),
      },
      {
        id: "total",
        header: t("col.total"),
        cell: ({ row }) => (
          <span className="font-mono tabular-nums">
            {formatChf((row.original.total ?? 0) / 100)}
          </span>
        ),
      },
      {
        id: "status",
        header: t("col.status"),
        cell: ({ row }) => {
          const s = row.original.status;
          return (
            <StatusBadge variant={STATUS_VARIANT[s] ?? "neutral"} withDot>
              {tStatus(s)}
            </StatusBadge>
          );
        },
      },
    ],
    [t, tStatus]
  );

  const table = useReactTable({
    data: orders,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  const next = () => {
    const last = orders[orders.length - 1];
    if (!last) return;
    setCursorStack((prev) => [...prev, cursor ?? ""]);
    setCursor(last.id);
  };
  const prev = () => {
    setCursorStack((prev) => {
      const popped = [...prev];
      const c = popped.pop() ?? "";
      setCursor(c || null);
      return popped;
    });
  };

  return (
    <div className="space-y-4">
      <Card className="p-4 space-y-3 sticky top-0 z-10 bg-card/95 backdrop-blur">
        <div className="flex flex-wrap gap-3 items-end">
          <div className="space-y-1">
            <label className="text-xs text-muted-foreground">{tCommon("from")}</label>
            <Input
              type="date"
              value={filter.from}
              onChange={(e) => setFilter((f) => ({ ...f, from: e.target.value }))}
              className="w-40"
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs text-muted-foreground">{tCommon("to")}</label>
            <Input
              type="date"
              value={filter.to}
              onChange={(e) => setFilter((f) => ({ ...f, to: e.target.value }))}
              className="w-40"
            />
          </div>
          <div className="space-y-1 min-w-[160px]">
            <label className="text-xs text-muted-foreground">{t("col.status")}</label>
            <Select
              value={filter.status}
              onValueChange={(v) => setFilter((f) => ({ ...f, status: v }))}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{tCommon("all")}</SelectItem>
                {STATUSES.map((s) => (
                  <SelectItem key={s} value={s}>
                    {tStatus(s)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1 flex-1 min-w-[160px]">
            <label className="text-xs text-muted-foreground">
              {t("filter.tableSearch")}
            </label>
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder={t("filter.tablePlaceholder")}
                value={filter.table}
                onChange={(e) => setFilter((f) => ({ ...f, table: e.target.value }))}
                className="pl-8"
              />
            </div>
          </div>
          <div className="flex gap-2">
            <Button onClick={apply}>{tCommon("apply")}</Button>
            <Button variant="outline" onClick={reset}>
              {t("filter.reset")}
            </Button>
          </div>
        </div>
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 flex items-center justify-between">
          <span className="text-sm font-medium">
            {t("listHeader", { count: orders.length })}
          </span>
          {list.isFetching && (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
        </div>

        {list.isLoading ? (
          <SkeletonTable />
        ) : list.error ? (
          <ErrorState message={(list.error as Error).message} onRetry={() => list.refetch()} />
        ) : orders.length === 0 ? (
          <EmptyState
            title={t("empty.title")}
            body={t("empty.body")}
          />
        ) : (
          <>
            <div className="hidden md:block">
              <Table>
                <TableHeader>
                  {table.getHeaderGroups().map((hg) => (
                    <TableRow key={hg.id}>
                      {hg.headers.map((h) => (
                        <TableHead key={h.id}>
                          {flexRender(h.column.columnDef.header, h.getContext())}
                        </TableHead>
                      ))}
                    </TableRow>
                  ))}
                </TableHeader>
                <TableBody>
                  {table.getRowModel().rows.map((row) => (
                    <TableRow
                      key={row.id}
                      className="cursor-pointer hover:bg-muted/40"
                      onClick={() => setSelected(row.original)}
                    >
                      {row.getVisibleCells().map((cell) => (
                        <TableCell key={cell.id}>
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </TableCell>
                      ))}
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
            <div className="md:hidden divide-y">
              {orders.map((o) => (
                <button
                  key={o.id}
                  onClick={() => setSelected(o)}
                  className="w-full text-left p-4 hover:bg-muted/40"
                >
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-[13px] font-semibold">
                      #{String(o.number ?? o.id.slice(0, 8))}
                    </span>
                    <StatusBadge variant={STATUS_VARIANT[o.status] ?? "neutral"} withDot>
                      {tStatus(o.status)}
                    </StatusBadge>
                  </div>
                  <div className="flex items-center justify-between mt-1 text-sm text-muted-foreground">
                    <span>{formatDateTime(o.created_at)}</span>
                    <span className="font-mono tabular-nums text-foreground">
                      {formatChf((o.total ?? 0) / 100)}
                    </span>
                  </div>
                  <div className="mt-1 text-xs text-muted-foreground">
                    {o.table_id ?? "—"} · {o.items?.length ?? 0} {t("col.items").toLowerCase()}
                  </div>
                </button>
              ))}
            </div>

            <div className="border-t px-4 py-3 flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {t("pagination.showing", { count: orders.length })}
              </span>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={cursorStack.length === 0}
                  onClick={prev}
                >
                  <ChevronLeft className="h-4 w-4" />
                  {t("pagination.prev")}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={orders.length < PAGE_SIZE}
                  onClick={next}
                >
                  {t("pagination.next")}
                  <ChevronRight className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </>
        )}
      </Card>

      <OrderDetailDialog
        order={selected}
        onClose={() => setSelected(null)}
      />
    </div>
  );
}

function SkeletonTable() {
  return (
    <div className="p-4 space-y-2">
      {Array.from({ length: 8 }).map((_, i) => (
        <div key={i} className="h-10 rounded bg-muted/40 animate-pulse" />
      ))}
    </div>
  );
}

function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  const tCommon = useTranslations("common");
  return (
    <div className="p-12 text-center space-y-3">
      <p className="text-sm text-error">{message}</p>
      <Button variant="outline" onClick={onRetry}>
        {tCommon("retry")}
      </Button>
    </div>
  );
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="p-12 text-center space-y-3">
      <Receipt className="h-12 w-12 mx-auto text-muted-foreground/50" />
      <div>
        <p className="font-medium">{title}</p>
        <p className="text-sm text-muted-foreground mt-1">{body}</p>
      </div>
    </div>
  );
}

function OrderDetailDialog({
  order,
  onClose,
}: {
  order: Order | null;
  onClose: () => void;
}) {
  const t = useTranslations("orders");
  if (!order) return null;
  return (
    <Dialog open={true} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>
            {t("detail")} #{String(order.number ?? order.id.slice(0, 8))}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-3 text-sm">
          <Row label={t("status")} value={order.status} />
          <Row label={t("date")} value={formatDateTime(order.created_at)} />
          <Row label={t("channel")} value={order.channel} />
          <Row label={t("total")} value={formatChf((order.total ?? 0) / 100)} />
          {order.customer_name && (
            <Row label={t("customer")} value={order.customer_name} />
          )}
          {order.table_id && (
            <Row label={t("history.col.table")} value={order.table_id} />
          )}
          {order.items && order.items.length > 0 && (
            <div className="border-t pt-3">
              <p className="font-medium mb-2">{t("items")}</p>
              <ul className="space-y-1 text-muted-foreground">
                {order.items.map((it, i) => (
                  <li key={i} className="flex justify-between">
                    <span>
                      {(it as { quantity?: number; qty?: number }).quantity ??
                        (it as { qty?: number }).qty ??
                        1}
                      × {(it as { name?: string }).name ?? "?"}
                    </span>
                    <span className="font-mono tabular-nums">
                      {formatChf(
                        ((it as { price?: number; total?: number }).price ??
                          (it as { total?: number }).total ??
                          0) / 100
                      )}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between border-b border-border/50 pb-2">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
