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
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

export interface Reason {
  id: string;
  code: string;
  labels: Record<string, string>;
  requires_approval: boolean;
  max_discount_percent?: number | null;
  display_order: number;
  is_active: boolean;
}

type Kind = "void" | "discount";

const LOCALES = ["tr", "de", "en", "fr", "it"] as const;

export function ReasonCodesClient({
  initialVoid,
  initialDiscount,
}: {
  initialVoid: Reason[];
  initialDiscount: Reason[];
}) {
  const t = useTranslations("reasonCodes");
  const [tab, setTab] = React.useState<Kind>("void");

  return (
    <Tabs value={tab} onValueChange={(v) => setTab(v as Kind)}>
      <TabsList>
        <TabsTrigger value="void">{t("tabVoid")}</TabsTrigger>
        <TabsTrigger value="discount">{t("tabDiscount")}</TabsTrigger>
      </TabsList>
      <TabsContent value="void" className="mt-4">
        <ReasonTable kind="void" initial={initialVoid} />
      </TabsContent>
      <TabsContent value="discount" className="mt-4">
        <ReasonTable kind="discount" initial={initialDiscount} />
      </TabsContent>
    </Tabs>
  );
}

function ReasonTable({ kind, initial }: { kind: Kind; initial: Reason[] }) {
  const t = useTranslations("reasonCodes");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Reason | null>(null);

  const queryKey = ["reasons", kind] as const;
  const { data = initial } = useQuery({
    queryKey,
    queryFn: async () => {
      const r = await clientFetch<{ data: Reason[] }>({ path: `/admin/reasons/${kind}` });
      return r?.data ?? [];
    },
    initialData: initial,
  });
  const refresh = () => qc.invalidateQueries({ queryKey });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/admin/reasons/${kind}/${id}`, method: "DELETE" }),
    onSuccess: () => { toast({ title: t("deleteSuccess") }); refresh(); },
    onError: (e: Error) =>
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={() => { setEditing(null); setFormOpen(true); }} className="gap-2">
          <Plus className="h-4 w-4" />
          {t("addReason")}
        </Button>
      </div>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colCode")}</TableHead>
              <TableHead>{t("colLabelTr")}</TableHead>
              <TableHead>{t("colOrder")}</TableHead>
              <TableHead>{t("colApproval")}</TableHead>
              {kind === "discount" && <TableHead>{t("colMaxPercent")}</TableHead>}
              <TableHead>{t("colStatus")}</TableHead>
              <TableHead className="text-right">{t("colActions")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.length === 0 && (
              <TableRow>
                <TableCell colSpan={kind === "discount" ? 7 : 6} className="text-center text-muted-foreground py-8">
                  {t("emptyState")}
                </TableCell>
              </TableRow>
            )}
            {data.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="font-mono text-xs">{r.code}</TableCell>
                <TableCell>{r.labels?.tr ?? "—"}</TableCell>
                <TableCell>{r.display_order}</TableCell>
                <TableCell>
                  {r.requires_approval ? <Badge variant="default">{t("yesApproval")}</Badge> : <Badge variant="outline">{t("noApproval")}</Badge>}
                </TableCell>
                {kind === "discount" && (
                  <TableCell>
                    {r.max_discount_percent != null ? `${r.max_discount_percent}%` : "—"}
                  </TableCell>
                )}
                <TableCell>
                  <Badge variant={r.is_active ? "default" : "secondary"}>
                    {r.is_active ? t("statusActive") : t("statusInactive")}
                  </Badge>
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex justify-end gap-1">
                    <Button size="icon" variant="ghost"
                      onClick={() => { setEditing(r); setFormOpen(true); }}>
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button size="icon" variant="ghost"
                      onClick={() => {
                        if (confirm(t("deleteConfirmBody", { code: r.code }))) {
                          deleteMut.mutate(r.id);
                        }
                      }}>
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <ReasonFormDialog
        open={formOpen}
        initial={editing}
        kind={kind}
        onOpenChange={setFormOpen}
        onSaved={() => { setFormOpen(false); refresh(); }}
      />
    </div>
  );
}

function ReasonFormDialog({
  open, initial, kind, onOpenChange, onSaved,
}: {
  open: boolean;
  initial: Reason | null;
  kind: Kind;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const t = useTranslations("reasonCodes");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [code, setCode] = React.useState("");
  const [labels, setLabels] = React.useState<Record<string, string>>({});
  const [requiresApproval, setRequiresApproval] = React.useState(false);
  const [maxPercent, setMaxPercent] = React.useState("");
  const [displayOrder, setDisplayOrder] = React.useState("0");
  const [isActive, setIsActive] = React.useState(true);
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (!open) return;
    if (initial) {
      setCode(initial.code);
      setLabels(initial.labels ?? {});
      setRequiresApproval(initial.requires_approval);
      setMaxPercent(initial.max_discount_percent != null ? String(initial.max_discount_percent) : "");
      setDisplayOrder(String(initial.display_order ?? 0));
      setIsActive(initial.is_active);
    } else {
      setCode("");
      setLabels({});
      setRequiresApproval(false);
      setMaxPercent("");
      setDisplayOrder("0");
      setIsActive(true);
    }
  }, [open, initial]);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const body: Record<string, unknown> = {
        code,
        labels,
        requires_approval: requiresApproval,
        display_order: parseInt(displayOrder, 10) || 0,
        is_active: isActive,
      };
      if (kind === "discount") {
        body.max_discount_percent = maxPercent ? parseFloat(maxPercent) : null;
      }
      if (initial) {
        await clientFetch({
          path: `/admin/reasons/${kind}/${initial.id}`,
          method: "PUT",
          body,
        });
        toast({ title: t("updateSuccess") });
      } else {
        await clientFetch({
          path: `/admin/reasons/${kind}`,
          method: "POST",
          body,
        });
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
            <DialogTitle>{initial ? t("editReason") : t("addReason")}</DialogTitle>
            <DialogDescription>{t("formHint")}</DialogDescription>
          </DialogHeader>
          <div className="space-y-3 py-3">
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-1 col-span-2">
                <Label>{t("colCode")}</Label>
                <Input
                  required
                  value={code}
                  onChange={(e) => setCode(e.target.value.toUpperCase())}
                  disabled={!!initial}
                  placeholder="WRONG_ORDER"
                  className="font-mono"
                />
              </div>
              <div className="space-y-1">
                <Label>{t("colOrder")}</Label>
                <Input
                  type="number"
                  min="0"
                  value={displayOrder}
                  onChange={(e) => setDisplayOrder(e.target.value)}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label>{t("labelsLabel")}</Label>
              <div className="space-y-1.5">
                {LOCALES.map((loc) => (
                  <div key={loc} className="flex items-center gap-2">
                    <span className="w-8 text-[11px] font-mono uppercase text-muted-foreground">{loc}</span>
                    <Input
                      value={labels[loc] ?? ""}
                      onChange={(e) => setLabels({ ...labels, [loc]: e.target.value })}
                      placeholder={t("labelPlaceholder", { locale: loc.toUpperCase() })}
                    />
                  </div>
                ))}
              </div>
            </div>
            {kind === "discount" && (
              <div className="space-y-1">
                <Label>{t("maxPercentLabel")}</Label>
                <Input
                  type="number"
                  min="0"
                  max="100"
                  step="0.1"
                  value={maxPercent}
                  onChange={(e) => setMaxPercent(e.target.value)}
                  placeholder="50"
                />
                <p className="text-xs text-muted-foreground">{t("maxPercentHint")}</p>
              </div>
            )}
            <div className="flex items-center gap-2">
              <input
                id="rsn-approval"
                type="checkbox"
                className="h-4 w-4"
                checked={requiresApproval}
                onChange={(e) => setRequiresApproval(e.target.checked)}
              />
              <Label htmlFor="rsn-approval" className="font-normal cursor-pointer">
                {t("requiresApprovalLabel")}
              </Label>
            </div>
            <div className="flex items-center gap-2">
              <input
                id="rsn-active"
                type="checkbox"
                className="h-4 w-4"
                checked={isActive}
                onChange={(e) => setIsActive(e.target.checked)}
              />
              <Label htmlFor="rsn-active" className="font-normal cursor-pointer">
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
