"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Edit, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

export interface Brand {
  id: string;
  name: string;
  dealer_id?: string | null;
  store_count: number;
  created_at: string;
}

export function BrandsClient({
  initial,
  canWrite,
}: {
  initial: Brand[];
  canWrite: boolean;
}) {
  const t = useTranslations("brands");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Brand | null>(null);

  const { data = initial } = useQuery({
    queryKey: ["partner-brands"],
    queryFn: async () => {
      const r = await clientFetch<{ data: Brand[] }>({ path: "/brands" });
      return r?.data ?? [];
    },
    initialData: initial,
  });

  const refresh = () => qc.invalidateQueries({ queryKey: ["partner-brands"] });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/brands/${id}`, method: "DELETE" }),
    onSuccess: () => {
      toast({ title: t("deleteSuccess") });
      refresh();
    },
    onError: (e: Error) =>
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      {canWrite && (
        <div className="flex justify-end">
          <Button onClick={() => { setEditing(null); setFormOpen(true); }} className="gap-2">
            <Plus className="h-4 w-4" />
            {t("addBrand")}
          </Button>
        </div>
      )}
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colName")}</TableHead>
              <TableHead>{t("colStoreCount")}</TableHead>
              <TableHead>{t("colCreatedAt")}</TableHead>
              {canWrite && <TableHead className="text-right">{t("colActions")}</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.length === 0 && (
              <TableRow>
                <TableCell colSpan={canWrite ? 4 : 3} className="text-center text-muted-foreground py-8">
                  {t("emptyState")}
                </TableCell>
              </TableRow>
            )}
            {data.map((b) => (
              <TableRow key={b.id}>
                <TableCell className="font-medium">{b.name}</TableCell>
                <TableCell>{b.store_count}</TableCell>
                <TableCell className="text-sm text-muted-foreground">
                  {new Date(b.created_at).toLocaleDateString()}
                </TableCell>
                {canWrite && (
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button size="icon" variant="ghost"
                        onClick={() => { setEditing(b); setFormOpen(true); }}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button size="icon" variant="ghost"
                        onClick={() => {
                          if (confirm(t("deleteConfirmBody", { name: b.name }))) {
                            deleteMut.mutate(b.id);
                          }
                        }}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </TableCell>
                )}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <BrandFormDialog
        open={formOpen}
        initial={editing}
        onOpenChange={setFormOpen}
        onSaved={() => { setFormOpen(false); refresh(); }}
      />
    </div>
  );
}

function BrandFormDialog({
  open, initial, onOpenChange, onSaved,
}: {
  open: boolean;
  initial: Brand | null;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const t = useTranslations("brands");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [name, setName] = React.useState("");
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (open) setName(initial?.name ?? "");
  }, [open, initial]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      if (initial) {
        await clientFetch({ path: `/brands/${initial.id}`, method: "PUT", body: { name } });
        toast({ title: t("updateSuccess") });
      } else {
        await clientFetch({ path: "/brands", method: "POST", body: { name } });
        toast({ title: t("createSuccess") });
      }
      onSaved();
    } catch (err) {
      toast({
        title: t("saveError"),
        description: (err as Error).message,
        variant: "destructive",
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{initial ? t("editBrand") : t("addBrand")}</DialogTitle>
            <DialogDescription>
              {initial ? t("editSubtitle") : t("addSubtitle")}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-3">
            <div className="space-y-1">
              <Label htmlFor="brand-name">{t("colName")}</Label>
              <Input
                id="brand-name"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={submitting}>
              {submitting ? tCommon("loading") : tCommon("save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
