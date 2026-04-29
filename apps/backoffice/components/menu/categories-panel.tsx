"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { CategoryForm, type CategoryInput } from "./category-form";
import { clientFetch } from "@/lib/api-client";
import { useToast } from "@/components/ui/use-toast";
import type { MenuCategory, UserRole } from "@/lib/api-types";
import { canManageMenu } from "@/lib/roles";

const QK = ["menu", "categories"];

export function CategoriesPanel({
  initial,
  userRole,
}: {
  initial: MenuCategory[];
  userRole: UserRole | string;
}) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const canEdit = canManageMenu(userRole);

  const { data: categories = initial } = useQuery({
    queryKey: QK,
    queryFn: () => clientFetch<MenuCategory[] | { categories: MenuCategory[] }>({ path: "/menu/categories" })
      .then((d) => (Array.isArray(d) ? d : d.categories ?? [])),
    initialData: initial,
  });

  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<MenuCategory | null>(null);

  const create = useMutation({
    mutationFn: (input: CategoryInput) =>
      clientFetch<MenuCategory>({ path: "/menu/categories", method: "POST", body: input }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
      setOpen(false);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const update = useMutation({
    mutationFn: ({ id, input }: { id: string; input: CategoryInput }) =>
      clientFetch<MenuCategory>({ path: `/menu/categories/${id}`, method: "PUT", body: input }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
      setOpen(false);
      setEditing(null);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const remove = useMutation({
    mutationFn: (id: string) => clientFetch<void>({ path: `/menu/categories/${id}`, method: "DELETE" }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        {canEdit && (
          <Button onClick={() => { setEditing(null); setOpen(true); }} size="sm">
            <Plus className="h-4 w-4" /> {t("addCategory")}
          </Button>
        )}
      </div>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-12">{t("icon")}</TableHead>
              <TableHead>{t("name")}</TableHead>
              <TableHead className="w-16">{t("color")}</TableHead>
              <TableHead className="w-20 text-right">{t("displayOrder")}</TableHead>
              <TableHead className="w-24">{tCommon("active")}</TableHead>
              {canEdit && <TableHead className="w-24"></TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {categories.length === 0 && (
              <TableRow>
                <TableCell colSpan={canEdit ? 6 : 5} className="text-center text-muted-foreground py-8">
                  {tCommon("noData")}
                </TableCell>
              </TableRow>
            )}
            {categories.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="text-xl">{c.icon ?? "·"}</TableCell>
                <TableCell className="font-medium">{c.name}</TableCell>
                <TableCell>
                  {c.color ? (
                    <div
                      className="h-5 w-5 rounded border border-border/40"
                      style={{ backgroundColor: c.color }}
                    />
                  ) : (
                    "—"
                  )}
                </TableCell>
                <TableCell className="text-right tabular-nums">{c.display_order}</TableCell>
                <TableCell>
                  {c.is_active ? (
                    <Badge variant="success">{tCommon("active")}</Badge>
                  ) : (
                    <Badge variant="secondary">{tCommon("inactive")}</Badge>
                  )}
                </TableCell>
                {canEdit && (
                  <TableCell className="text-right">
                    <Button variant="ghost" size="icon" onClick={() => { setEditing(c); setOpen(true); }}>
                      <Pencil className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => {
                        if (confirm(`${tCommon("delete")}: ${c.name}?`)) remove.mutate(c.id);
                      }}
                    >
                      <Trash2 className="h-3.5 w-3.5 text-destructive" />
                    </Button>
                  </TableCell>
                )}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{editing ? t("editCategory") : t("addCategory")}</DialogTitle>
          </DialogHeader>
          <CategoryForm
            initial={editing ?? undefined}
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
