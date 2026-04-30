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

interface Supplier {
  id: string;
  name: string;
  contact?: string | null;
  email?: string | null;
  phone?: string | null;
  notes?: string | null;
}

const schema = z.object({
  name: z.string().min(1),
  contact: z.string().optional().or(z.literal("")),
  email: z.string().email().optional().or(z.literal("")),
  phone: z.string().optional().or(z.literal("")),
  notes: z.string().optional().or(z.literal("")),
});
type Form = z.infer<typeof schema>;

export function SuppliersClient() {
  const t = useTranslations("suppliers");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Supplier | null>(null);

  const query = useQuery<Supplier[]>({
    queryKey: ["suppliers"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ suppliers?: Supplier[] } | Supplier[]>({
          path: "/suppliers",
        });
        if (Array.isArray(data)) return data;
        return data.suppliers ?? [];
      } catch {
        return [];
      }
    },
  });
  const items = query.data ?? [];

  const form = useForm<Form>({ resolver: zodResolver(schema) });

  const save = useMutation({
    mutationFn: async (values: Form) =>
      clientFetch({
        path: editing ? `/suppliers/${editing.id}` : "/suppliers",
        method: editing ? "PUT" : "POST",
        body: values,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["suppliers"] });
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
      clientFetch({ path: `/suppliers/${id}`, method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["suppliers"] }),
  });

  function openCreate() {
    setEditing(null);
    form.reset({ name: "", contact: "", email: "", phone: "", notes: "" });
    setOpen(true);
  }
  function openEdit(s: Supplier) {
    setEditing(s);
    form.reset({
      name: s.name,
      contact: s.contact ?? "",
      email: s.email ?? "",
      phone: s.phone ?? "",
      notes: s.notes ?? "",
    });
    setOpen(true);
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={openCreate}>
          <Plus className="mr-2 h-4 w-4" />
          {t("newSupplier")}
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
                  <TableHead>{t("colName")}</TableHead>
                  <TableHead>{t("colContact")}</TableHead>
                  <TableHead>{t("colEmail")}</TableHead>
                  <TableHead>{t("colPhone")}</TableHead>
                  <TableHead className="w-[100px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((s) => (
                  <TableRow key={s.id}>
                    <TableCell className="font-medium">{s.name}</TableCell>
                    <TableCell className="text-muted-foreground">{s.contact || "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{s.email || "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{s.phone || "—"}</TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <Button size="icon" variant="ghost" onClick={() => openEdit(s)}>
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          size="icon"
                          variant="ghost"
                          onClick={() => {
                            if (confirm(t("confirmDelete", { name: s.name }))) remove.mutate(s.id);
                          }}
                        >
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
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
              <DialogTitle>{editing ? t("editSupplier") : t("newSupplier")}</DialogTitle>
            </DialogHeader>
            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="sup-name">{t("colName")}</Label>
                <Input id="sup-name" {...form.register("name")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="sup-contact">{t("colContact")}</Label>
                <Input id="sup-contact" {...form.register("contact")} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label htmlFor="sup-email">{t("colEmail")}</Label>
                  <Input id="sup-email" type="email" {...form.register("email")} />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="sup-phone">{t("colPhone")}</Label>
                  <Input id="sup-phone" {...form.register("phone")} />
                </div>
              </div>
              <div className="space-y-1">
                <Label htmlFor="sup-notes">{t("notes")}</Label>
                <Input id="sup-notes" {...form.register("notes")} />
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
