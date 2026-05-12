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
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

export interface Edition {
  id: string;
  code: string;
  name: string;
  features: Record<string, unknown>;
  max_stores?: number | null;
  max_devices?: number | null;
  price_chf_month: number;
  is_active: boolean;
  created_at: string;
}

export function EditionsClient({
  initial,
  canWrite,
}: {
  initial: Edition[];
  canWrite: boolean;
}) {
  const t = useTranslations("editions");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Edition | null>(null);

  const { data = initial } = useQuery({
    queryKey: ["partner-editions"],
    queryFn: async () => {
      const r = await clientFetch<{ data: Edition[] }>({ path: "/editions" });
      return r?.data ?? [];
    },
    initialData: initial,
  });
  const refresh = () => qc.invalidateQueries({ queryKey: ["partner-editions"] });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/editions/${id}`, method: "DELETE" }),
    onSuccess: () => { toast({ title: t("deleteSuccess") }); refresh(); },
    onError: (e: Error) =>
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      {canWrite && (
        <div className="flex justify-end">
          <Button onClick={() => { setEditing(null); setFormOpen(true); }} className="gap-2">
            <Plus className="h-4 w-4" />
            {t("addEdition")}
          </Button>
        </div>
      )}
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colCode")}</TableHead>
              <TableHead>{t("colName")}</TableHead>
              <TableHead>{t("colPrice")}</TableHead>
              <TableHead>{t("colMaxStores")}</TableHead>
              <TableHead>{t("colStatus")}</TableHead>
              {canWrite && <TableHead className="text-right">{t("colActions")}</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((e) => (
              <TableRow key={e.id}>
                <TableCell className="font-mono text-sm">{e.code}</TableCell>
                <TableCell className="font-medium">{e.name}</TableCell>
                <TableCell>CHF {e.price_chf_month.toFixed(2)}</TableCell>
                <TableCell>{e.max_stores ?? "∞"}</TableCell>
                <TableCell>
                  <Badge variant={e.is_active ? "default" : "secondary"}>
                    {e.is_active ? t("statusActive") : t("statusInactive")}
                  </Badge>
                </TableCell>
                {canWrite && (
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button size="icon" variant="ghost"
                        onClick={() => { setEditing(e); setFormOpen(true); }}>
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button size="icon" variant="ghost"
                        onClick={() => {
                          if (confirm(t("deleteConfirmBody", { name: e.name }))) {
                            deleteMut.mutate(e.id);
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
      <EditionFormDialog
        open={formOpen}
        initial={editing}
        onOpenChange={setFormOpen}
        onSaved={() => { setFormOpen(false); refresh(); }}
      />
    </div>
  );
}

function EditionFormDialog({
  open, initial, onOpenChange, onSaved,
}: {
  open: boolean;
  initial: Edition | null;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const t = useTranslations("editions");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [code, setCode] = React.useState("");
  const [name, setName] = React.useState("");
  const [features, setFeatures] = React.useState("{}");
  const [maxStores, setMaxStores] = React.useState("");
  const [maxDevices, setMaxDevices] = React.useState("");
  const [price, setPrice] = React.useState("0");
  const [isActive, setIsActive] = React.useState(true);
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (!open) return;
    if (initial) {
      setCode(initial.code);
      setName(initial.name);
      setFeatures(JSON.stringify(initial.features, null, 2));
      setMaxStores(initial.max_stores != null ? String(initial.max_stores) : "");
      setMaxDevices(initial.max_devices != null ? String(initial.max_devices) : "");
      setPrice(String(initial.price_chf_month));
      setIsActive(initial.is_active);
    } else {
      setCode("");
      setName("");
      setFeatures("{}");
      setMaxStores("");
      setMaxDevices("");
      setPrice("0");
      setIsActive(true);
    }
  }, [open, initial]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      let parsedFeatures: unknown = {};
      try { parsedFeatures = JSON.parse(features); }
      catch { toast({ title: t("invalidJson"), variant: "destructive" }); setSubmitting(false); return; }
      const body: Record<string, unknown> = {
        code, name,
        features: parsedFeatures,
        max_stores: maxStores ? parseInt(maxStores, 10) : null,
        max_devices: maxDevices ? parseInt(maxDevices, 10) : null,
        price_chf_month: parseFloat(price),
        is_active: isActive,
      };
      if (initial) {
        await clientFetch({ path: `/editions/${initial.id}`, method: "PUT", body });
        toast({ title: t("updateSuccess") });
      } else {
        await clientFetch({ path: "/editions", method: "POST", body });
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
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{initial ? t("editEdition") : t("addEdition")}</DialogTitle>
            <DialogDescription>{t("formHint")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>{t("colCode")}</Label>
                <Input required value={code} onChange={(e) => setCode(e.target.value)} disabled={!!initial} />
              </div>
              <div className="space-y-1">
                <Label>{t("colName")}</Label>
                <Input required value={name} onChange={(e) => setName(e.target.value)} />
              </div>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-1">
                <Label>{t("colPrice")} (CHF)</Label>
                <Input type="number" step="0.01" min="0"
                  value={price} onChange={(e) => setPrice(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("colMaxStores")}</Label>
                <Input type="number" min="0" value={maxStores}
                  onChange={(e) => setMaxStores(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("colMaxDevices")}</Label>
                <Input type="number" min="0" value={maxDevices}
                  onChange={(e) => setMaxDevices(e.target.value)} />
              </div>
            </div>
            <div className="space-y-1">
              <Label>{t("featuresJson")}</Label>
              <textarea
                className="w-full h-32 rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                value={features}
                onChange={(e) => setFeatures(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">{t("featuresHint")}</p>
            </div>
            <div className="flex items-center gap-2">
              <input id="is-active" type="checkbox" className="h-4 w-4"
                checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
              <Label htmlFor="is-active" className="font-normal cursor-pointer">
                {t("statusActive")}
              </Label>
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
