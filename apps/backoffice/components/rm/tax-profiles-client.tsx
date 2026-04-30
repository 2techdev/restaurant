"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Edit, Trash2 } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
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

interface TaxProfile {
  id: string;
  name: string;
  rate: number;
  description?: string | null;
  is_default: boolean;
}

const CH_DEFAULTS: Omit<TaxProfile, "id">[] = [
  { name: "Standard", rate: 8.1, description: "CH MWST standard", is_default: true },
  { name: "Reduced", rate: 3.8, description: "Hotel & accommodation", is_default: false },
  { name: "Special", rate: 2.6, description: "Food & essentials", is_default: false },
  { name: "Exempt", rate: 0, description: "Tax-exempt", is_default: false },
];

const schema = z.object({
  name: z.string().min(1),
  rate: z.coerce.number().min(0).max(100),
  description: z.string().optional().or(z.literal("")),
  is_default: z.boolean().default(false),
});
type Form = z.infer<typeof schema>;

export function TaxProfilesClient() {
  const t = useTranslations("taxProfiles");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<TaxProfile | null>(null);

  const query = useQuery<TaxProfile[]>({
    queryKey: ["tax-profiles"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ profiles?: TaxProfile[] } | TaxProfile[]>({
          path: "/restaurant/tax-profiles",
        });
        if (Array.isArray(data)) return data;
        return data.profiles ?? [];
      } catch {
        return [];
      }
    },
  });
  const items = query.data ?? [];
  const showDefaults = !query.isLoading && items.length === 0;

  const form = useForm<Form>({ resolver: zodResolver(schema) });

  const save = useMutation({
    mutationFn: async (values: Form) =>
      clientFetch({
        path: editing ? `/restaurant/tax-profiles/${editing.id}` : "/restaurant/tax-profiles",
        method: editing ? "PUT" : "POST",
        body: values,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["tax-profiles"] });
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
      clientFetch({ path: `/restaurant/tax-profiles/${id}`, method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["tax-profiles"] }),
  });

  function openCreate() {
    setEditing(null);
    form.reset({ name: "", rate: 8.1, description: "", is_default: false });
    setOpen(true);
  }
  function openEdit(p: TaxProfile) {
    setEditing(p);
    form.reset({
      name: p.name,
      rate: p.rate,
      description: p.description ?? "",
      is_default: p.is_default,
    });
    setOpen(true);
  }

  const rows = showDefaults ? CH_DEFAULTS.map((d, i) => ({ ...d, id: `default-${i}` } as TaxProfile)) : items;

  return (
    <div className="space-y-4">
      {showDefaults && (
        <div className="text-xs text-muted-foreground italic">{t("usingDefaults")}</div>
      )}
      <div className="flex justify-end">
        <Button onClick={openCreate}>
          <Plus className="mr-2 h-4 w-4" />
          {t("newProfile")}
        </Button>
      </div>

      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("colName")}</TableHead>
                  <TableHead className="text-right">{t("colRate")}</TableHead>
                  <TableHead>{t("colDescription")}</TableHead>
                  <TableHead>{t("colDefault")}</TableHead>
                  <TableHead className="w-[100px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((p) => (
                  <TableRow key={p.id}>
                    <TableCell className="font-medium">{p.name}</TableCell>
                    <TableCell className="text-right tabular-nums">{p.rate.toFixed(1)}%</TableCell>
                    <TableCell className="text-muted-foreground">{p.description || "—"}</TableCell>
                    <TableCell>{p.is_default ? <Badge>{tCommon("yes")}</Badge> : "—"}</TableCell>
                    <TableCell>
                      {!showDefaults ? (
                        <div className="flex gap-1">
                          <Button size="icon" variant="ghost" onClick={() => openEdit(p)}>
                            <Edit className="h-4 w-4" />
                          </Button>
                          <Button
                            size="icon"
                            variant="ghost"
                            onClick={() => {
                              if (confirm(t("confirmDelete", { name: p.name }))) remove.mutate(p.id);
                            }}
                          >
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        </div>
                      ) : null}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <form onSubmit={form.handleSubmit((v) => save.mutate(v))} className="space-y-4">
            <DialogHeader>
              <DialogTitle>{editing ? t("editProfile") : t("newProfile")}</DialogTitle>
            </DialogHeader>
            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="tax-name">{t("colName")}</Label>
                <Input id="tax-name" {...form.register("name")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="tax-rate">{t("colRate")} (%)</Label>
                <Input id="tax-rate" type="number" step="0.1" {...form.register("rate")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="tax-desc">{t("colDescription")}</Label>
                <Input id="tax-desc" {...form.register("description")} />
              </div>
              <div className="flex items-center gap-2">
                <Switch
                  id="tax-default"
                  checked={form.watch("is_default")}
                  onCheckedChange={(v) => form.setValue("is_default", v)}
                />
                <Label htmlFor="tax-default" className="text-sm">
                  {t("setAsDefault")}
                </Label>
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
