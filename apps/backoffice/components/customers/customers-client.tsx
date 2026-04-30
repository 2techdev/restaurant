"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Search, Edit, Trash2 } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatChf, formatDate } from "@/lib/utils";

interface Customer {
  id: string;
  name: string;
  email?: string | null;
  phone?: string | null;
  loyalty_points?: number;
  total_spent?: number; // cents
  visit_count?: number;
  last_visit_at?: string | null;
  notes?: string | null;
  created_at?: string;
}

const customerSchema = z.object({
  name: z.string().min(2),
  email: z.string().email().optional().or(z.literal("")),
  phone: z.string().optional().or(z.literal("")),
  notes: z.string().optional().or(z.literal("")),
});
type CustomerForm = z.infer<typeof customerSchema>;

export function CustomersClient() {
  const t = useTranslations("customers");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [search, setSearch] = React.useState("");
  const [editing, setEditing] = React.useState<Customer | null>(null);
  const [open, setOpen] = React.useState(false);

  const query = useQuery<Customer[]>({
    queryKey: ["customers"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ customers?: Customer[] } | Customer[]>({
          path: "/customers",
        });
        if (Array.isArray(data)) return data;
        return data.customers ?? [];
      } catch {
        return [];
      }
    },
  });

  const items = (query.data ?? []).filter((c) => {
    if (!search) return true;
    const q = search.toLowerCase();
    return (
      c.name?.toLowerCase().includes(q) ||
      c.email?.toLowerCase().includes(q) ||
      c.phone?.includes(q)
    );
  });

  const form = useForm<CustomerForm>({ resolver: zodResolver(customerSchema) });

  const save = useMutation({
    mutationFn: async (values: CustomerForm) => {
      const path = editing ? `/customers/${editing.id}` : "/customers";
      return clientFetch({
        path,
        method: editing ? "PUT" : "POST",
        body: values,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["customers"] });
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
      clientFetch({ path: `/customers/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["customers"] });
      toast({ title: tCommon("success") });
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  function openCreate() {
    setEditing(null);
    form.reset({ name: "", email: "", phone: "", notes: "" });
    setOpen(true);
  }
  function openEdit(c: Customer) {
    setEditing(c);
    form.reset({
      name: c.name,
      email: c.email ?? "",
      phone: c.phone ?? "",
      notes: c.notes ?? "",
    });
    setOpen(true);
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative max-w-sm flex-1">
          <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder={tCommon("search")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-8"
          />
        </div>
        <Button onClick={openCreate} className="ml-auto">
          <Plus className="mr-2 h-4 w-4" />
          {t("newCustomer")}
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
                  <TableHead>{t("colEmail")}</TableHead>
                  <TableHead>{t("colPhone")}</TableHead>
                  <TableHead className="text-right">{t("colLoyalty")}</TableHead>
                  <TableHead className="text-right">{t("colSpent")}</TableHead>
                  <TableHead className="text-right">{t("colVisits")}</TableHead>
                  <TableHead>{t("colLastVisit")}</TableHead>
                  <TableHead className="w-[100px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">{c.name}</TableCell>
                    <TableCell className="text-muted-foreground">{c.email || "—"}</TableCell>
                    <TableCell className="text-muted-foreground">{c.phone || "—"}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {(c.loyalty_points ?? 0) > 0 ? (
                        <Badge variant="secondary" className="tabular-nums">
                          {c.loyalty_points}
                        </Badge>
                      ) : (
                        "—"
                      )}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {formatChf(c.total_spent ?? 0)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{c.visit_count ?? 0}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {c.last_visit_at ? formatDate(c.last_visit_at) : "—"}
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <Button size="icon" variant="ghost" onClick={() => openEdit(c)}>
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          size="icon"
                          variant="ghost"
                          onClick={() => {
                            if (confirm(t("confirmDelete", { name: c.name }))) remove.mutate(c.id);
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
          <form
            onSubmit={form.handleSubmit((values) => {
              save.mutate(values);
            })}
            className="space-y-4"
          >
            <DialogHeader>
              <DialogTitle>{editing ? t("editCustomer") : t("newCustomer")}</DialogTitle>
              <DialogDescription>{t("formDescription")}</DialogDescription>
            </DialogHeader>
            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="cust-name">{t("colName")}</Label>
                <Input id="cust-name" {...form.register("name")} />
                {form.formState.errors.name ? (
                  <p className="text-xs text-destructive">{form.formState.errors.name.message}</p>
                ) : null}
              </div>
              <div className="space-y-1">
                <Label htmlFor="cust-email">{t("colEmail")}</Label>
                <Input id="cust-email" type="email" {...form.register("email")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="cust-phone">{t("colPhone")}</Label>
                <Input id="cust-phone" {...form.register("phone")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="cust-notes">{t("notes")}</Label>
                <Input id="cust-notes" {...form.register("notes")} />
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
