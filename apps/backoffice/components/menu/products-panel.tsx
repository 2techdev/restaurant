"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Lock, Ban, CheckCircle2, ChevronDown } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ProductForm, type ProductSubmitPayload } from "./product-form";
import { clientFetch } from "@/lib/api-client";
import { useToast } from "@/components/ui/use-toast";
import { formatChf } from "@/lib/utils";
import type { MenuCategory, MenuProduct, ModifierGroup, UserRole } from "@/lib/api-types";
import { canManageMenu } from "@/lib/roles";

const QK = ["menu", "products"];

export function ProductsPanel({
  initial,
  categories,
  modifierGroups,
  userRole,
}: {
  initial: MenuProduct[];
  categories: MenuCategory[];
  modifierGroups: ModifierGroup[];
  userRole: UserRole | string;
}) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const canEdit = canManageMenu(userRole);

  const { data: products = initial } = useQuery({
    queryKey: QK,
    queryFn: () =>
      clientFetch<MenuProduct[] | { products: MenuProduct[] }>({ path: "/menu/products" }).then((d) =>
        Array.isArray(d) ? d : d.products ?? []
      ),
    initialData: initial,
  });

  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<MenuProduct | null>(null);
  const [search, setSearch] = React.useState("");
  const [selected, setSelected] = React.useState<Set<string>>(new Set());

  const toggleSelected = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  // Snooze helpers — single + bulk. Single uses PATCH /menu/products/{id}/snooze;
  // bulk routes through POST /menu/products/snooze/bulk so one round-trip
  // updates an arbitrary set of rows.
  const snoozeOne = useMutation({
    mutationFn: ({ id, snoozed, until }: { id: string; snoozed: boolean; until?: string | null }) =>
      clientFetch({
        path: `/menu/products/${id}/snooze`,
        method: "PATCH",
        body: { snoozed, until: until ?? null },
      }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const snoozeBulk = useMutation({
    mutationFn: ({ ids, snoozed, until }: { ids: string[]; snoozed: boolean; until?: string | null }) =>
      clientFetch({
        path: "/menu/products/snooze/bulk",
        method: "POST",
        body: { product_ids: ids, snoozed, until: until ?? null },
      }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      setSelected(new Set());
      qc.invalidateQueries({ queryKey: QK });
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  /** Compute an ISO timestamp `offsetHours` from now, or "end of day" when
   *  `untilEod` is true. Used by the bulk-action dropdown items. */
  const isoFromNow = (offsetHours: number | "eod"): string => {
    const d = new Date();
    if (offsetHours === "eod") {
      d.setHours(23, 59, 0, 0);
    } else {
      d.setTime(d.getTime() + offsetHours * 3600 * 1000);
    }
    return d.toISOString();
  };

  const filtered = React.useMemo(
    () => products.filter((p) => p.name.toLowerCase().includes(search.toLowerCase())),
    [products, search]
  );

  const create = useMutation({
    mutationFn: (input: ProductSubmitPayload) =>
      clientFetch<MenuProduct>({ path: "/menu/products", method: "POST", body: input }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
      setOpen(false);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const update = useMutation({
    mutationFn: ({ id, input }: { id: string; input: ProductSubmitPayload }) =>
      clientFetch<MenuProduct>({ path: `/menu/products/${id}`, method: "PUT", body: input }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
      setOpen(false);
      setEditing(null);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const remove = useMutation({
    mutationFn: (id: string) => clientFetch<void>({ path: `/menu/products/${id}`, method: "DELETE" }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-2">
        <Input
          placeholder={tCommon("search")}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="max-w-sm"
        />
        <div className="flex items-center gap-2">
          {canEdit && selected.size > 0 && (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button size="sm" variant="outline" className="gap-1">
                  {t("snoozeBulk", { count: selected.size })}
                  <ChevronDown className="h-3.5 w-3.5" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-56">
                <DropdownMenuLabel>{t("snoozeFor")}</DropdownMenuLabel>
                <DropdownMenuItem onSelect={() =>
                  snoozeBulk.mutate({ ids: [...selected], snoozed: true, until: isoFromNow(1) })}
                >
                  {t("snooze1h")}
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={() =>
                  snoozeBulk.mutate({ ids: [...selected], snoozed: true, until: isoFromNow(2) })}
                >
                  {t("snooze2h")}
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={() =>
                  snoozeBulk.mutate({ ids: [...selected], snoozed: true, until: isoFromNow("eod") })}
                >
                  {t("snoozeEod")}
                </DropdownMenuItem>
                <DropdownMenuItem onSelect={() =>
                  snoozeBulk.mutate({ ids: [...selected], snoozed: true, until: null })}
                >
                  {t("snoozeManual")}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onSelect={() =>
                  snoozeBulk.mutate({ ids: [...selected], snoozed: false, until: null })}
                >
                  {t("snoozeClear")}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
          {canEdit && (
            <Button size="sm" onClick={() => { setEditing(null); setOpen(true); }}>
              <Plus className="h-4 w-4" /> {t("addProduct")}
            </Button>
          )}
        </div>
      </div>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              {canEdit && (
                <TableHead className="w-10">
                  <input
                    type="checkbox"
                    className="h-4 w-4"
                    aria-label={tCommon("all")}
                    checked={filtered.length > 0 && selected.size === filtered.length}
                    onChange={(e) => {
                      if (e.target.checked) setSelected(new Set(filtered.map((p) => p.id)));
                      else setSelected(new Set());
                    }}
                  />
                </TableHead>
              )}
              <TableHead>{t("name")}</TableHead>
              <TableHead>{t("category")}</TableHead>
              <TableHead className="text-right">{t("priceStandard")}</TableHead>
              <TableHead className="text-right">{t("priceTakeaway")}</TableHead>
              <TableHead>{tCommon("active")}</TableHead>
              <TableHead>{t("snoozeColumn")}</TableHead>
              <TableHead className="w-24"></TableHead>
              {canEdit && <TableHead className="w-24"></TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 && (
              <TableRow>
                <TableCell colSpan={canEdit ? 9 : 7} className="text-center text-muted-foreground py-8">
                  {tCommon("noData")}
                </TableCell>
              </TableRow>
            )}
            {filtered.map((p) => {
              const cat = categories.find((c) => c.id === p.category_id);
              const snoozed = !!p.is_snoozed;
              const snoozeUntilLabel = p.snooze_until
                ? new Date(p.snooze_until).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" })
                : null;
              return (
                <TableRow key={p.id} className={snoozed ? "bg-rose-500/5" : undefined}>
                  {canEdit && (
                    <TableCell>
                      <input
                        type="checkbox"
                        className="h-4 w-4"
                        aria-label={p.name}
                        checked={selected.has(p.id)}
                        onChange={() => toggleSelected(p.id)}
                      />
                    </TableCell>
                  )}
                  <TableCell className="font-medium">{p.name}</TableCell>
                  <TableCell className="text-muted-foreground">{cat?.name ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatChf(p.price)}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatChf(p.price_takeaway ?? p.price)}</TableCell>
                  <TableCell>
                    {p.is_active ? <Badge variant="success">{tCommon("active")}</Badge> : <Badge variant="secondary">{tCommon("inactive")}</Badge>}
                  </TableCell>
                  <TableCell>
                    {canEdit ? (
                      <button
                        type="button"
                        onClick={() => snoozeOne.mutate({ id: p.id, snoozed: !snoozed, until: null })}
                        disabled={snoozeOne.isPending}
                        className={
                          "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium transition " +
                          (snoozed
                            ? "border-rose-500/30 bg-rose-500/10 text-rose-700 hover:bg-rose-500/15"
                            : "border-emerald-500/30 bg-emerald-500/10 text-emerald-700 hover:bg-emerald-500/15")
                        }
                        title={snoozed && snoozeUntilLabel ? `${t("snoozedUntil")} ${snoozeUntilLabel}` : undefined}
                      >
                        {snoozed ? <Ban className="h-3 w-3" /> : <CheckCircle2 className="h-3 w-3" />}
                        {snoozed ? t("statusSnoozed") : t("statusAvailable")}
                      </button>
                    ) : (
                      <Badge variant={snoozed ? "secondary" : "success"}>
                        {snoozed ? t("statusSnoozed") : t("statusAvailable")}
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell>
                    {p.policy_lock === "FULLY_LOCKED" || p.policy_lock === "PRICE_LOCKED" ? (
                      <Badge variant="warning"><Lock className="h-3 w-3" /> {t("lockedBadge")}</Badge>
                    ) : p.is_local ? (
                      <Badge variant="outline">{t("localBadge")}</Badge>
                    ) : null}
                  </TableCell>
                  {canEdit && (
                    <TableCell className="text-right">
                      <Button variant="ghost" size="icon" onClick={() => { setEditing(p); setOpen(true); }}>
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        disabled={p.policy_lock === "FULLY_LOCKED"}
                        onClick={() => {
                          if (confirm(`${tCommon("delete")}: ${p.name}?`)) remove.mutate(p.id);
                        }}
                      >
                        <Trash2 className="h-3.5 w-3.5 text-destructive" />
                      </Button>
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>{editing ? t("editProduct") : t("addProduct")}</DialogTitle>
          </DialogHeader>
          <ProductForm
            initial={editing ?? undefined}
            categories={categories}
            modifierGroups={modifierGroups}
            onCancel={() => { setOpen(false); setEditing(null); }}
            onSubmit={async (data) => {
              if (editing) await update.mutateAsync({ id: editing.id, input: data });
              else await create.mutateAsync(data);
            }}
          />
        </DialogContent>
      </Dialog>
    </div>
  );
}
