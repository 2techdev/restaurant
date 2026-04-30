"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, AlertTriangle, Edit, Trash2 } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatDate } from "@/lib/utils";

interface InventoryItem {
  id: string;
  sku: string;
  name: string;
  unit: string;
  current_stock: number;
  threshold: number;
  supplier_id?: string | null;
  supplier_name?: string | null;
  updated_at?: string;
}

const itemSchema = z.object({
  sku: z.string().min(1),
  name: z.string().min(1),
  unit: z.string().min(1),
  current_stock: z.coerce.number().min(0),
  threshold: z.coerce.number().min(0),
  supplier_id: z.string().optional(),
});
type ItemForm = z.infer<typeof itemSchema>;

export function InventoryClient() {
  const t = useTranslations("inventory");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<InventoryItem | null>(null);

  const query = useQuery<InventoryItem[]>({
    queryKey: ["inventory"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ items?: InventoryItem[] } | InventoryItem[]>({
          path: "/inventory",
        });
        if (Array.isArray(data)) return data;
        return data.items ?? [];
      } catch {
        return [];
      }
    },
  });
  const items = query.data ?? [];

  const form = useForm<ItemForm>({ resolver: zodResolver(itemSchema) });

  const save = useMutation({
    mutationFn: async (values: ItemForm) =>
      clientFetch({
        path: editing ? `/inventory/${editing.id}` : "/inventory",
        method: editing ? "PUT" : "POST",
        body: values,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["inventory"] });
      toast({ title: tCommon("success") });
      setOpen(false);
      setEditing(null);
      form.reset();
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/inventory/${id}`, method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["inventory"] }),
  });

  function openCreate() {
    setEditing(null);
    form.reset({ sku: "", name: "", unit: "", current_stock: 0, threshold: 0 });
    setOpen(true);
  }
  function openEdit(it: InventoryItem) {
    setEditing(it);
    form.reset({
      sku: it.sku,
      name: it.name,
      unit: it.unit,
      current_stock: it.current_stock,
      threshold: it.threshold,
      supplier_id: it.supplier_id ?? "",
    });
    setOpen(true);
  }

  const lowStockCount = items.filter((it) => it.current_stock <= it.threshold).length;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        {lowStockCount > 0 && (
          <Badge variant="destructive" className="gap-1">
            <AlertTriangle className="h-3 w-3" />
            {t("lowStockCount", { count: lowStockCount })}
          </Badge>
        )}
        <Button onClick={openCreate} className="ml-auto">
          <Plus className="mr-2 h-4 w-4" />
          {t("newItem")}
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : items.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">{tCommon("noData")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("colSku")}</TableHead>
                  <TableHead>{t("colName")}</TableHead>
                  <TableHead>{t("colUnit")}</TableHead>
                  <TableHead className="text-right">{t("colStock")}</TableHead>
                  <TableHead className="text-right">{t("colThreshold")}</TableHead>
                  <TableHead>{t("colSupplier")}</TableHead>
                  <TableHead>{t("colUpdated")}</TableHead>
                  <TableHead className="w-[100px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((it) => {
                  const low = it.current_stock <= it.threshold;
                  return (
                    <TableRow key={it.id} className={low ? "bg-destructive/5" : undefined}>
                      <TableCell className="font-mono text-xs">{it.sku}</TableCell>
                      <TableCell className="font-medium">{it.name}</TableCell>
                      <TableCell className="text-muted-foreground">{it.unit}</TableCell>
                      <TableCell
                        className={`text-right tabular-nums ${low ? "font-semibold text-destructive" : ""}`}
                      >
                        {it.current_stock}
                      </TableCell>
                      <TableCell className="text-right tabular-nums text-muted-foreground">
                        {it.threshold}
                      </TableCell>
                      <TableCell className="text-muted-foreground">{it.supplier_name || "—"}</TableCell>
                      <TableCell className="text-muted-foreground">
                        {it.updated_at ? formatDate(it.updated_at) : "—"}
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          <Button size="icon" variant="ghost" onClick={() => openEdit(it)}>
                            <Edit className="h-4 w-4" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            onClick={() => {
                              if (confirm(t("confirmDelete", { name: it.name }))) remove.mutate(it.id);
                            }}
                          >
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <form
            onSubmit={form.handleSubmit((v) => save.mutate(v))}
            className="space-y-4"
          >
            <DialogHeader>
              <DialogTitle>{editing ? t("editItem") : t("newItem")}</DialogTitle>
            </DialogHeader>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label htmlFor="inv-sku">{t("colSku")}</Label>
                <Input id="inv-sku" {...form.register("sku")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="inv-unit">{t("colUnit")}</Label>
                <Input id="inv-unit" placeholder="kg, l, adet" {...form.register("unit")} />
              </div>
              <div className="col-span-2 space-y-1">
                <Label htmlFor="inv-name">{t("colName")}</Label>
                <Input id="inv-name" {...form.register("name")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="inv-stock">{t("colStock")}</Label>
                <Input id="inv-stock" type="number" {...form.register("current_stock")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="inv-th">{t("colThreshold")}</Label>
                <Input id="inv-th" type="number" {...form.register("threshold")} />
              </div>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                {tCommon("cancel")}
              </Button>
              <Button type="submit" disabled={save.isPending}>
                {save.isPending ? tCommon("loading") : tCommon("save")}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
