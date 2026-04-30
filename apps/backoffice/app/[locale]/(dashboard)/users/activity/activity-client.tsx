"use client";

/**
 * Audit log viewer (Agent A backend — GET /api/v1/audit-log).
 * Read-only. Filters: date range + action + entity_type + free-text search.
 * Server-side pagination via `cursor` (last row id).
 */

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { Loader2, Search, ChevronLeft, ChevronRight, Activity, ChevronDown, ChevronUp } from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDateTime } from "@/lib/utils";

interface AuditEntry {
  id: string;
  timestamp: string;
  user_id?: string | null;
  user_email?: string | null;
  action: string;
  entity_type?: string | null;
  entity_id?: string | null;
  changes?: Record<string, unknown> | null;
  ip_address?: string | null;
}

const PAGE_SIZE = 50;

const ACTION_VARIANT: Record<string, "success" | "warning" | "error" | "info" | "neutral"> = {
  create: "success",
  update: "info",
  delete: "error",
  login: "neutral",
  publish: "success",
  revoke: "error",
};

interface FilterState {
  from: string;
  to: string;
  user: string;
  action: string;
  entityType: string;
}
const EMPTY: FilterState = { from: "", to: "", user: "", action: "all", entityType: "all" };

export function ActivityClient() {
  const t = useTranslations("users.activity");
  const tCommon = useTranslations("common");

  const [filter, setFilter] = React.useState<FilterState>(EMPTY);
  const [applied, setApplied] = React.useState<FilterState>(EMPTY);
  const [cursor, setCursor] = React.useState<string | null>(null);
  const [stack, setStack] = React.useState<string[]>([]);
  const [expanded, setExpanded] = React.useState<Set<string>>(new Set());

  const list = useQuery({
    queryKey: ["audit-log", applied, cursor],
    queryFn: async () => {
      const params = new URLSearchParams();
      if (applied.from) params.set("from", applied.from);
      if (applied.to) params.set("to", applied.to);
      if (applied.user) params.set("user_id", applied.user);
      if (applied.action !== "all") params.set("action", applied.action);
      if (applied.entityType !== "all") params.set("entity_type", applied.entityType);
      params.set("limit", String(PAGE_SIZE));
      if (cursor) params.set("cursor", cursor);
      const data = await clientFetch<
        { entries?: AuditEntry[]; data?: AuditEntry[]; logs?: AuditEntry[] } | AuditEntry[]
      >({ path: `/audit-log?${params.toString()}` });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (Array.isArray(raw)
        ? raw
        : raw?.entries ?? raw?.logs ?? raw?.data ?? []) as AuditEntry[];
    },
  });

  const apply = () => {
    setApplied(filter);
    setCursor(null);
    setStack([]);
  };
  const reset = () => {
    setFilter(EMPTY);
    setApplied(EMPTY);
    setCursor(null);
    setStack([]);
  };

  const items = list.data ?? [];

  const toggleExpand = (id: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const next = () => {
    const last = items[items.length - 1];
    if (!last) return;
    setStack((prev) => [...prev, cursor ?? ""]);
    setCursor(last.id);
  };
  const prev = () => {
    setStack((prev) => {
      const popped = [...prev];
      const c = popped.pop() ?? "";
      setCursor(c || null);
      return popped;
    });
  };

  // Derive action options from current page (best-effort — server lookup
  // for the full vocab isn't wired yet).
  const actionOptions = React.useMemo(() => {
    const set = new Set<string>();
    items.forEach((e) => set.add(e.action));
    return Array.from(set).sort();
  }, [items]);

  return (
    <div className="space-y-4">
      <Card className="p-4 sticky top-0 z-10 bg-card/95 backdrop-blur">
        <div className="flex flex-wrap gap-3 items-end">
          <div className="space-y-1">
            <Label className="text-xs">{tCommon("from")}</Label>
            <Input
              type="date"
              value={filter.from}
              onChange={(e) => setFilter((f) => ({ ...f, from: e.target.value }))}
              className="w-40"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">{tCommon("to")}</Label>
            <Input
              type="date"
              value={filter.to}
              onChange={(e) => setFilter((f) => ({ ...f, to: e.target.value }))}
              className="w-40"
            />
          </div>
          <div className="space-y-1 min-w-[160px]">
            <Label className="text-xs">{t("filter.action")}</Label>
            <Select
              value={filter.action}
              onValueChange={(v) => setFilter((f) => ({ ...f, action: v }))}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{tCommon("all")}</SelectItem>
                {actionOptions.map((a) => (
                  <SelectItem key={a} value={a}>
                    {a}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1 flex-1 min-w-[160px]">
            <Label className="text-xs">{t("filter.user")}</Label>
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder={t("filter.userPlaceholder")}
                value={filter.user}
                onChange={(e) => setFilter((f) => ({ ...f, user: e.target.value }))}
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
            {t("listHeader", { count: items.length })}
          </span>
          {list.isFetching && (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
        </div>

        {list.isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {tCommon("loading")}
          </div>
        ) : list.error ? (
          <div className="p-12 text-center text-sm text-error">
            {(list.error as Error).message}
          </div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Activity className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
          </div>
        ) : (
          <>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-8"></TableHead>
                  <TableHead>{t("col.timestamp")}</TableHead>
                  <TableHead>{t("col.user")}</TableHead>
                  <TableHead>{t("col.action")}</TableHead>
                  <TableHead>{t("col.entity")}</TableHead>
                  <TableHead>{t("col.ip")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((e) => {
                  const isOpen = expanded.has(e.id);
                  return (
                    <React.Fragment key={e.id}>
                      <TableRow
                        className="hover:bg-muted/30 cursor-pointer"
                        onClick={() => toggleExpand(e.id)}
                      >
                        <TableCell>
                          {isOpen ? (
                            <ChevronUp className="h-4 w-4 text-muted-foreground" />
                          ) : (
                            <ChevronDown className="h-4 w-4 text-muted-foreground" />
                          )}
                        </TableCell>
                        <TableCell className="font-mono text-[11px] text-muted-foreground">
                          {formatDateTime(e.timestamp)}
                        </TableCell>
                        <TableCell className="text-sm">
                          {e.user_email ?? (e.user_id ? e.user_id.slice(0, 8) + "…" : "—")}
                        </TableCell>
                        <TableCell>
                          <StatusBadge variant={ACTION_VARIANT[e.action] ?? "neutral"}>
                            {e.action}
                          </StatusBadge>
                        </TableCell>
                        <TableCell className="font-mono text-[11px]">
                          {e.entity_type ? (
                            <>
                              {e.entity_type}
                              {e.entity_id && (
                                <span className="text-muted-foreground">
                                  {" · "}
                                  {e.entity_id.slice(0, 8)}…
                                </span>
                              )}
                            </>
                          ) : (
                            "—"
                          )}
                        </TableCell>
                        <TableCell className="font-mono text-[11px] text-muted-foreground">
                          {e.ip_address ?? "—"}
                        </TableCell>
                      </TableRow>
                      {isOpen && e.changes && (
                        <TableRow className="bg-muted/20">
                          <TableCell></TableCell>
                          <TableCell colSpan={5}>
                            <div className="text-xs">
                              <Label className="text-[10px] uppercase tracking-wider text-muted-foreground">
                                {t("changes")}
                              </Label>
                              <pre className="mt-1 p-2 bg-muted rounded text-[11px] font-mono overflow-x-auto">
                                {JSON.stringify(e.changes, null, 2)}
                              </pre>
                            </div>
                          </TableCell>
                        </TableRow>
                      )}
                    </React.Fragment>
                  );
                })}
              </TableBody>
            </Table>

            <div className="border-t px-4 py-3 flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {t("pagination.showing", { count: items.length })}
              </span>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={stack.length === 0}
                  onClick={prev}
                >
                  <ChevronLeft className="h-4 w-4" />
                  {t("pagination.prev")}
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={items.length < PAGE_SIZE}
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
    </div>
  );
}
