"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { ModifierGroupForm, type GroupSubmitPayload } from "./modifier-group-form";
import { clientFetch } from "@/lib/api-client";
import { useToast } from "@/components/ui/use-toast";
import type { ModifierGroup, UserRole } from "@/lib/api-types";
import { canManageMenu } from "@/lib/roles";

const QK = ["menu", "modifiers"];

export function ModifiersPanel({
  initial,
  userRole,
}: {
  initial: ModifierGroup[];
  userRole: UserRole | string;
}) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const canEdit = canManageMenu(userRole);

  const { data: groups = initial } = useQuery({
    queryKey: QK,
    queryFn: () =>
      clientFetch<ModifierGroup[] | { groups: ModifierGroup[] }>({ path: "/menu/modifiers" }).then((d) =>
        Array.isArray(d) ? d : d.groups ?? []
      ),
    initialData: initial,
  });

  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<ModifierGroup | null>(null);

  const create = useMutation({
    mutationFn: (input: GroupSubmitPayload) =>
      clientFetch<ModifierGroup>({ path: "/menu/modifiers", method: "POST", body: input }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
      setOpen(false);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const update = useMutation({
    mutationFn: ({ id, input }: { id: string; input: GroupSubmitPayload }) =>
      clientFetch<ModifierGroup>({ path: `/menu/modifiers/${id}`, method: "PUT", body: input }),
    onSuccess: () => {
      toast({ title: tCommon("success") });
      qc.invalidateQueries({ queryKey: QK });
      setOpen(false);
      setEditing(null);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const remove = useMutation({
    mutationFn: (id: string) => clientFetch<void>({ path: `/menu/modifiers/${id}`, method: "DELETE" }),
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
          <Button size="sm" onClick={() => { setEditing(null); setOpen(true); }}>
            <Plus className="h-4 w-4" /> {t("addModifierGroup")}
          </Button>
        )}
      </div>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("name")}</TableHead>
              <TableHead>{t("selectionType")}</TableHead>
              <TableHead className="text-right">Min</TableHead>
              <TableHead className="text-right">Max</TableHead>
              <TableHead>{t("isRequired")}</TableHead>
              <TableHead className="text-right">{t("modifiers")}</TableHead>
              {canEdit && <TableHead className="w-24"></TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {groups.length === 0 && (
              <TableRow>
                <TableCell colSpan={canEdit ? 7 : 6} className="text-center text-muted-foreground py-8">
                  {tCommon("noData")}
                </TableCell>
              </TableRow>
            )}
            {groups.map((g) => (
              <TableRow key={g.id}>
                <TableCell className="font-medium">{g.name}</TableCell>
                <TableCell>{g.selection_type === "single" ? t("single") : t("multiple")}</TableCell>
                <TableCell className="text-right tabular-nums">{g.min_selections}</TableCell>
                <TableCell className="text-right tabular-nums">{g.max_selections}</TableCell>
                <TableCell>
                  {g.is_required ? <Badge variant="warning">{tCommon("yes")}</Badge> : <Badge variant="secondary">{tCommon("no")}</Badge>}
                </TableCell>
                <TableCell className="text-right tabular-nums">{g.modifiers?.length ?? 0}</TableCell>
                {canEdit && (
                  <TableCell className="text-right">
                    <Button variant="ghost" size="icon" onClick={() => { setEditing(g); setOpen(true); }}>
                      <Pencil className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => {
                        if (confirm(`${tCommon("delete")}: ${g.name}?`)) remove.mutate(g.id);
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
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>{editing ? tCommon("edit") : t("addModifierGroup")}</DialogTitle>
          </DialogHeader>
          <ModifierGroupForm
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
