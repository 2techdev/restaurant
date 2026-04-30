"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Edit, Trash2, Lock, Unlock, Send, Search } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatChf, formatDate, chfToCents, centsToChfStr } from "@/lib/utils";

type LockType = "FLEXIBLE" | "PRICE_LOCKED" | "FULLY_LOCKED";

interface MasterCategory {
  id: string;
  name: string;
}

interface MasterProduct {
  id: string;
  category_id: string;
  category_name?: string;
  name: string;
  description?: string | null;
  price: number; // cents
  tax_group?: string;
  policy_lock?: LockType;
  linked_restaurants?: number;
  updated_at?: string;
}

interface MasterMenuResponse {
  categories?: MasterCategory[];
  products?: MasterProduct[];
  current_version?: number;
  member_count?: number;
}

const productSchema = z.object({
  category_id: z.string().min(1),
  name: z.string().min(1),
  description: z.string().optional().or(z.literal("")),
  price_chf: z.string().min(1),
  tax_group: z.string().min(1).default("standard"),
  policy_lock: z.enum(["FLEXIBLE", "PRICE_LOCKED", "FULLY_LOCKED"]).default("FLEXIBLE"),
});
type ProductForm = z.infer<typeof productSchema>;

function lockBadgeVariant(lock?: LockType): "default" | "secondary" | "destructive" | "outline" {
  switch (lock) {
    case "FULLY_LOCKED":
      return "destructive";
    case "PRICE_LOCKED":
      return "default";
    case "FLEXIBLE":
    default:
      return "secondary";
  }
}

export function MasterProductsClient({ orgId }: { orgId: string }) {
  const t = useTranslations("masterProducts");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [search, setSearch] = React.useState("");
  const [categoryFilter, setCategoryFilter] = React.useState<string>("all");
  const [lockFilter, setLockFilter] = React.useState<string>("all");
  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<MasterProduct | null>(null);
  const [publishOpen, setPublishOpen] = React.useState(false);

  const query = useQuery<MasterMenuResponse | null>({
    queryKey: ["master-menu", orgId],
    queryFn: async () => {
      try {
        return await clientFetch<MasterMenuResponse>({
          path: `/org/${orgId}/master-menu`,
        });
      } catch {
        return null;
      }
    },
  });

  const data = query.data;
  const categories = data?.categories ?? [];
  const products = data?.products ?? [];
  const memberCount = data?.member_count ?? 0;
  const currentVersion = data?.current_version ?? 0;

  const filtered = products.filter((p) => {
    if (categoryFilter !== "all" && p.category_id !== categoryFilter) return false;
    if (lockFilter !== "all" && (p.policy_lock ?? "FLEXIBLE") !== lockFilter) return false;
    if (search) {
      const q = search.toLowerCase();
      if (!p.name.toLowerCase().includes(q)) return false;
    }
    return true;
  });

  const form = useForm<ProductForm>({
    resolver: zodResolver(productSchema),
    defaultValues: {
      category_id: "",
      name: "",
      description: "",
      price_chf: "",
      tax_group: "standard",
      policy_lock: "FLEXIBLE",
    },
  });

  const save = useMutation({
    mutationFn: async (values: ProductForm) => {
      const body = {
        category_id: values.category_id,
        name: values.name,
        description: values.description || undefined,
        price: chfToCents(values.price_chf),
        tax_group: values.tax_group,
        policy_lock: values.policy_lock,
      };
      const path = editing
        ? `/org/${orgId}/master-menu/products/${editing.id}`
        : `/org/${orgId}/master-menu/products`;
      return clientFetch({ path, method: editing ? "PUT" : "POST", body });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["master-menu", orgId] });
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
      clientFetch({ path: `/org/${orgId}/master-menu/products/${id}`, method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["master-menu", orgId] }),
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  const publish = useMutation({
    mutationFn: async () =>
      clientFetch({ path: `/org/${orgId}/master-menu/publish`, method: "POST" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["master-menu", orgId] });
      qc.invalidateQueries({ queryKey: ["master-menu-versions", orgId] });
      toast({ title: t("publishSuccess") });
      setPublishOpen(false);
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
    form.reset({
      category_id: categories[0]?.id ?? "",
      name: "",
      description: "",
      price_chf: "",
      tax_group: "standard",
      policy_lock: "FLEXIBLE",
    });
    setOpen(true);
  }
  function openEdit(p: MasterProduct) {
    setEditing(p);
    form.reset({
      category_id: p.category_id,
      name: p.name,
      description: p.description ?? "",
      price_chf: centsToChfStr(p.price),
      tax_group: p.tax_group ?? "standard",
      policy_lock: p.policy_lock ?? "FLEXIBLE",
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
        <Select value={categoryFilter} onValueChange={setCategoryFilter}>
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder={t("filterCategory")} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{tCommon("all")}</SelectItem>
            {categories.map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={lockFilter} onValueChange={setLockFilter}>
          <SelectTrigger className="w-[180px]">
            <SelectValue placeholder={t("filterLock")} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">{tCommon("all")}</SelectItem>
            <SelectItem value="FLEXIBLE">{t("lockFlexible")}</SelectItem>
            <SelectItem value="PRICE_LOCKED">{t("lockPrice")}</SelectItem>
            <SelectItem value="FULLY_LOCKED">{t("lockFully")}</SelectItem>
          </SelectContent>
        </Select>
        <div className="ml-auto flex items-center gap-2">
          <Badge variant="outline" className="font-mono text-xs">
            v{currentVersion} · {memberCount} {t("memberRestaurants")}
          </Badge>
          <Button variant="outline" onClick={openCreate} disabled={!categories.length}>
            <Plus className="mr-2 h-4 w-4" />
            {t("newProduct")}
          </Button>
          <Button onClick={() => setPublishOpen(true)} disabled={!products.length}>
            <Send className="mr-2 h-4 w-4" />
            {t("publishToAll")}
          </Button>
        </div>
      </div>

      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : filtered.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">
              {products.length === 0 ? t("emptyMaster") : tCommon("noData")}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("colName")}</TableHead>
                  <TableHead>{t("colCategory")}</TableHead>
                  <TableHead className="text-right">{t("colPrice")}</TableHead>
                  <TableHead>{t("colLock")}</TableHead>
                  <TableHead className="text-right">{t("colLinked")}</TableHead>
                  <TableHead>{t("colUpdated")}</TableHead>
                  <TableHead className="w-[100px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((p) => {
                  const cat = categories.find((c) => c.id === p.category_id);
                  const lock = p.policy_lock ?? "FLEXIBLE";
                  return (
                    <TableRow key={p.id}>
                      <TableCell className="font-medium">{p.name}</TableCell>
                      <TableCell className="text-muted-foreground">{cat?.name || "—"}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatChf(p.price)}</TableCell>
                      <TableCell>
                        <Badge variant={lockBadgeVariant(lock)} className="gap-1">
                          {lock === "FULLY_LOCKED" ? (
                            <Lock className="h-3 w-3" />
                          ) : lock === "PRICE_LOCKED" ? (
                            <Lock className="h-3 w-3" />
                          ) : (
                            <Unlock className="h-3 w-3" />
                          )}
                          {t(`lock${lock === "FLEXIBLE" ? "Flexible" : lock === "PRICE_LOCKED" ? "Price" : "Fully"}`)}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {p.linked_restaurants ?? memberCount}
                      </TableCell>
                      <TableCell className="text-muted-foreground">
                        {p.updated_at ? formatDate(p.updated_at) : "—"}
                      </TableCell>
                      <TableCell>
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
        <DialogContent className="sm:max-w-lg">
          <form
            onSubmit={form.handleSubmit((v) => save.mutate(v))}
            className="space-y-4"
          >
            <DialogHeader>
              <DialogTitle>{editing ? t("editProduct") : t("newProduct")}</DialogTitle>
              <DialogDescription>{t("formDesc")}</DialogDescription>
            </DialogHeader>
            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="mp-cat">{t("colCategory")}</Label>
                <Select
                  value={form.watch("category_id")}
                  onValueChange={(v) => form.setValue("category_id", v)}
                >
                  <SelectTrigger id="mp-cat">
                    <SelectValue placeholder={t("selectCategory")} />
                  </SelectTrigger>
                  <SelectContent>
                    {categories.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label htmlFor="mp-name">{t("colName")}</Label>
                <Input id="mp-name" {...form.register("name")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="mp-desc">{t("description")}</Label>
                <Input id="mp-desc" {...form.register("description")} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label htmlFor="mp-price">{t("priceChf")}</Label>
                  <Input id="mp-price" type="text" placeholder="12.50" {...form.register("price_chf")} />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="mp-tax">{t("taxGroup")}</Label>
                  <Input id="mp-tax" placeholder="standard" {...form.register("tax_group")} />
                </div>
              </div>
              <div className="space-y-1">
                <Label htmlFor="mp-lock">{t("policyLock")}</Label>
                <Select
                  value={form.watch("policy_lock")}
                  onValueChange={(v) => form.setValue("policy_lock", v as LockType)}
                >
                  <SelectTrigger id="mp-lock">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="FLEXIBLE">{t("lockFlexible")} — {t("lockFlexibleHint")}</SelectItem>
                    <SelectItem value="PRICE_LOCKED">{t("lockPrice")} — {t("lockPriceHint")}</SelectItem>
                    <SelectItem value="FULLY_LOCKED">{t("lockFully")} — {t("lockFullyHint")}</SelectItem>
                  </SelectContent>
                </Select>
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

      <AlertDialog open={publishOpen} onOpenChange={setPublishOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("publishToAll")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("publishConfirm", { count: memberCount })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction onClick={() => publish.mutate()} disabled={publish.isPending}>
              {publish.isPending ? tCommon("loading") : t("confirmPublish")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
