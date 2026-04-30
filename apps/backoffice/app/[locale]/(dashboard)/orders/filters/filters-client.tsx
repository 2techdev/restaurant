"use client";

/**
 * Saved filter list — localStorage-backed. The Active Orders page reads from
 * the same `bo.orders.savedFilters.v1` key via `loadSavedFilters()` so adding
 * one here makes it pick-able from the toolbar there.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { z } from "zod";
import { Plus, Trash2, Bookmark, ExternalLink } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";

const STORAGE_KEY = "bo.orders.savedFilters.v1";

const SavedFilterSchema = z.object({
  id: z.string(),
  name: z.string().min(1),
  criteria: z.object({
    status: z.string().optional(),
    table: z.string().optional(),
    date_from: z.string().optional(),
    date_to: z.string().optional(),
    min_total_chf: z.number().optional(),
  }),
});
export type SavedFilter = z.infer<typeof SavedFilterSchema>;

export function loadSavedFilters(): SavedFilter[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((x): x is SavedFilter => SavedFilterSchema.safeParse(x).success);
  } catch {
    return [];
  }
}
export function saveSavedFilters(items: SavedFilter[]) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch {
    // ignore quota / private mode
  }
}

export function FiltersClient({ locale }: { locale: string }) {
  const t = useTranslations("orders.filters");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [items, setItems] = React.useState<SavedFilter[]>([]);
  const [open, setOpen] = React.useState(false);

  const [name, setName] = React.useState("");
  const [status, setStatus] = React.useState("");
  const [table, setTable] = React.useState("");
  const [dateFrom, setDateFrom] = React.useState("");
  const [dateTo, setDateTo] = React.useState("");

  React.useEffect(() => {
    setItems(loadSavedFilters());
  }, []);

  const persist = (next: SavedFilter[]) => {
    setItems(next);
    saveSavedFilters(next);
  };

  const onCreate = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    const f: SavedFilter = {
      id: crypto.randomUUID(),
      name: name.trim(),
      criteria: {
        status: status.trim() || undefined,
        table: table.trim() || undefined,
        date_from: dateFrom || undefined,
        date_to: dateTo || undefined,
      },
    };
    persist([...items, f]);
    setOpen(false);
    setName("");
    setStatus("");
    setTable("");
    setDateFrom("");
    setDateTo("");
    toast({ title: t("createdToast") });
  };

  const onRemove = (id: string) => {
    persist(items.filter((x) => x.id !== id));
  };

  const buildLink = (f: SavedFilter): string => {
    const params = new URLSearchParams();
    Object.entries(f.criteria).forEach(([k, v]) => {
      if (v !== undefined && v !== "") params.set(k, String(v));
    });
    const qs = params.toString();
    return `/${locale}/orders${qs ? `?${qs}` : ""}`;
  };

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" />
          {t("newFilter")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 text-sm font-medium">
          {t("listHeader", { count: items.length })}
        </div>
        {items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Bookmark className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
          </div>
        ) : (
          <ul className="divide-y">
            {items.map((f) => (
              <li
                key={f.id}
                className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-muted/30"
              >
                <div className="min-w-0 flex-1">
                  <div className="font-medium truncate">{f.name}</div>
                  <div className="flex flex-wrap gap-x-3 gap-y-0.5 mt-0.5 text-xs text-muted-foreground">
                    {f.criteria.status && (
                      <span>
                        <strong className="font-mono">status</strong>={f.criteria.status}
                      </span>
                    )}
                    {f.criteria.table && (
                      <span>
                        <strong className="font-mono">table</strong>={f.criteria.table}
                      </span>
                    )}
                    {f.criteria.date_from && (
                      <span>
                        <strong className="font-mono">from</strong>={f.criteria.date_from}
                      </span>
                    )}
                    {f.criteria.date_to && (
                      <span>
                        <strong className="font-mono">to</strong>={f.criteria.date_to}
                      </span>
                    )}
                  </div>
                </div>
                <Link href={buildLink(f)} target="_blank">
                  <Button variant="outline" size="sm">
                    <ExternalLink className="h-3.5 w-3.5" />
                    {t("apply")}
                  </Button>
                </Link>
                <Button
                  variant="ghost"
                  size="icon"
                  className="text-error h-8 w-8"
                  onClick={() => onRemove(f.id)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("newFilter")}</DialogTitle>
            <DialogDescription>{t("formHint")}</DialogDescription>
          </DialogHeader>
          <form onSubmit={onCreate} className="space-y-3 pt-2">
            <div className="space-y-1">
              <Label>{t("col.name")}</Label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder={t("namePlaceholder")}
                required
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>{t("col.status")}</Label>
                <Input
                  value={status}
                  onChange={(e) => setStatus(e.target.value)}
                  placeholder="paid|open|preparing"
                />
              </div>
              <div className="space-y-1">
                <Label>{t("col.table")}</Label>
                <Input
                  value={table}
                  onChange={(e) => setTable(e.target.value)}
                  placeholder="M07"
                />
              </div>
              <div className="space-y-1">
                <Label>{tCommon("from")}</Label>
                <Input
                  type="date"
                  value={dateFrom}
                  onChange={(e) => setDateFrom(e.target.value)}
                />
              </div>
              <div className="space-y-1">
                <Label>{tCommon("to")}</Label>
                <Input
                  type="date"
                  value={dateTo}
                  onChange={(e) => setDateTo(e.target.value)}
                />
              </div>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                {tCommon("cancel")}
              </Button>
              <Button type="submit">{tCommon("save")}</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
