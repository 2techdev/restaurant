"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Lock } from "lucide-react";
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
        {canEdit && (
          <Button size="sm" onClick={() => { setEditing(null); setOpen(true); }}>
            <Plus className="h-4 w-4" /> {t("addProduct")}
          </Button>
        )}
      </div>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("name")}</TableHead>
              <TableHead>{t("category")}</TableHead>
              <TableHead className="text-right">{t("priceStandard")}</TableHead>
              <TableHead className="text-right">{t("priceTakeaway")}</TableHead>
              <TableHead>{tCommon("active")}</TableHead>
              <TableHead className="w-24"></TableHead>
              {canEdit && <TableHead className="w-24"></TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 && (
              <TableRow>
                <TableCell colSpan={canEdit ? 7 : 6} className="text-center text-muted-foreground py-8">
                  {tCommon("noData")}
                </TableCell>
              </TableRow>
            )}
            {filtered.map((p) => {
              const cat = categories.find((c) => c.id === p.category_id);
              return (
                <TableRow key={p.id}>
                  <TableCell className="font-medium">{p.name}</TableCell>
                  <TableCell className="text-muted-foreground">{cat?.name ?? "—"}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatChf(p.price)}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatChf(p.price_takeaway ?? p.price)}</TableCell>
                  <TableCell>
                    {p.is_active ? <Badge variant="success">{tCommon("active")}</Badge> : <Badge variant="secondary">{tCommon("inactive")}</Badge>}
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
