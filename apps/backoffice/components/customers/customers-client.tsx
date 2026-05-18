"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Search, Edit, Trash2, Sparkles, RefreshCw, TagIcon } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatChf, formatDate } from "@/lib/utils";

// Mirrors crm.Customer in server/internal/crm/models.go.
export interface Customer {
  id: string;
  name: string;
  email?: string | null;
  phone?: string | null;
  birthday?: string | null;
  anniversary?: string | null;
  notes?: string | null;
  loyalty_points: number;
  total_visits: number;
  total_spent_cents: number;
  avg_ticket_cents: number;
  first_visit_at?: string | null;
  last_visit_at?: string | null;
  tags: string[];
  allergens: string[];
  dietary_tags: string[];
  preferred_payment_method?: string | null;
  preferred_hour_bucket?: number | null;
  favorite_category_id?: string | null;
  favorite_product_id?: string | null;
  created_at?: string;
}

const DIETARY_PRESETS = ["vegan", "vegetarian", "gluten-free", "lactose-free", "halal", "kosher"];
const ALLERGEN_PRESETS = ["gluten", "dairy", "nuts", "egg", "soy", "fish", "shellfish"];

const customerSchema = z.object({
  name: z.string().min(2),
  email: z.string().email().optional().or(z.literal("")),
  phone: z.string().optional().or(z.literal("")),
  birthday: z.string().optional().or(z.literal("")),
  anniversary: z.string().optional().or(z.literal("")),
  notes: z.string().optional().or(z.literal("")),
  tagsCsv: z.string().optional().or(z.literal("")),
  dietaryCsv: z.string().optional().or(z.literal("")),
  allergensCsv: z.string().optional().or(z.literal("")),
});
type CustomerForm = z.infer<typeof customerSchema>;

function csvToArr(s: string | undefined | null): string[] {
  if (!s) return [];
  return s.split(",").map((x) => x.trim()).filter(Boolean);
}

export function CustomersClient() {
  const t = useTranslations("customers");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [search, setSearch] = React.useState("");
  const [editing, setEditing] = React.useState<Customer | null>(null);
  const [open, setOpen] = React.useState(false);
  const [filterTag, setFilterTag] = React.useState<string | null>(null);

  const query = useQuery<Customer[]>({
    queryKey: ["customers"],
    queryFn: async () => {
      const data = await clientFetch<{ data?: Customer[]; customers?: Customer[] } | Customer[]>({
        path: "/customers",
      });
      const list = Array.isArray(data)
        ? data
        : ((data as { data?: Customer[] }).data ?? (data as { customers?: Customer[] }).customers ?? []);
      // Normalise null/empty arrays from the wire so downstream code can rely on them.
      return list.map((c) => ({
        ...c,
        tags: c.tags ?? [],
        allergens: c.allergens ?? [],
        dietary_tags: c.dietary_tags ?? [],
      }));
    },
  });

  const items = (query.data ?? []).filter((c) => {
    if (filterTag && !c.tags.includes(filterTag)) return false;
    if (!search) return true;
    const q = search.toLowerCase();
    return (
      c.name?.toLowerCase().includes(q) ||
      c.email?.toLowerCase().includes(q) ||
      (c.phone ?? "").includes(q)
    );
  });

  const allTags = React.useMemo(() => {
    const s = new Set<string>();
    (query.data ?? []).forEach((c) => c.tags.forEach((t) => s.add(t)));
    return Array.from(s).sort();
  }, [query.data]);

  const form = useForm<CustomerForm>({ resolver: zodResolver(customerSchema) });

  const save = useMutation({
    mutationFn: async (values: CustomerForm) => {
      const body = {
        ...(editing ? {} : { id: crypto.randomUUID() }),
        name: values.name,
        email: values.email || null,
        phone: values.phone || null,
        birthday: values.birthday || null,
        anniversary: values.anniversary || null,
        notes: values.notes || null,
        tags: csvToArr(values.tagsCsv),
        dietary_tags: csvToArr(values.dietaryCsv),
        allergens: csvToArr(values.allergensCsv),
      };
      const path = editing ? `/customers/${editing.id}` : "/customers";
      return clientFetch({ path, method: editing ? "PUT" : "POST", body });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["customers"] });
      toast({ title: tCommon("success") });
      setOpen(false);
      setEditing(null);
      form.reset();
    },
    onError: (e) =>
      toast({ title: tCommon("error"), description: e instanceof Error ? e.message : String(e), variant: "destructive" }),
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/customers/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["customers"] });
      toast({ title: tCommon("success") });
    },
  });

  const refresh = useMutation({
    mutationFn: async () => clientFetch({ path: "/crm/aggregates/refresh", method: "POST" }),
    onSuccess: (data: unknown) => {
      const r = data as { customers_updated?: number; duration_ms?: number };
      toast({
        title: t("aggregatesRefreshed"),
        description: t("aggregatesRefreshedDesc", {
          n: r.customers_updated ?? 0,
          ms: r.duration_ms ?? 0,
        }),
      });
      qc.invalidateQueries({ queryKey: ["customers"] });
    },
    onError: (e) =>
      toast({ title: tCommon("error"), description: e instanceof Error ? e.message : String(e), variant: "destructive" }),
  });

  function openCreate() {
    setEditing(null);
    form.reset({
      name: "", email: "", phone: "", birthday: "", anniversary: "",
      notes: "", tagsCsv: "", dietaryCsv: "", allergensCsv: "",
    });
    setOpen(true);
  }
  function openEdit(c: Customer) {
    setEditing(c);
    form.reset({
      name: c.name,
      email: c.email ?? "",
      phone: c.phone ?? "",
      birthday: c.birthday ?? "",
      anniversary: c.anniversary ?? "",
      notes: c.notes ?? "",
      tagsCsv: c.tags.join(", "),
      dietaryCsv: c.dietary_tags.join(", "),
      allergensCsv: c.allergens.join(", "),
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
        <Button
          variant="outline"
          onClick={() => refresh.mutate()}
          disabled={refresh.isPending}
          title={t("refreshAggregatesHint")}
        >
          <RefreshCw className={`mr-2 h-4 w-4 ${refresh.isPending ? "animate-spin" : ""}`} />
          {t("refreshAggregates")}
        </Button>
        <Button onClick={openCreate}>
          <Plus className="mr-2 h-4 w-4" />
          {t("newCustomer")}
        </Button>
      </div>

      {allTags.length > 0 && (
        <div className="flex flex-wrap gap-2 items-center">
          <TagIcon className="h-3.5 w-3.5 text-muted-foreground" />
          <Badge
            variant={filterTag === null ? "default" : "outline"}
            className="cursor-pointer"
            onClick={() => setFilterTag(null)}
          >
            {tCommon("all")}
          </Badge>
          {allTags.map((tag) => (
            <Badge
              key={tag}
              variant={filterTag === tag ? "default" : "outline"}
              className="cursor-pointer"
              onClick={() => setFilterTag(filterTag === tag ? null : tag)}
            >
              {tag}
            </Badge>
          ))}
        </div>
      )}

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
                  <TableHead>{t("colTags")}</TableHead>
                  <TableHead className="text-right">{t("colLoyalty")}</TableHead>
                  <TableHead className="text-right">{t("colSpent")}</TableHead>
                  <TableHead className="text-right">{t("colAvgTicket")}</TableHead>
                  <TableHead className="text-right">{t("colVisits")}</TableHead>
                  <TableHead>{t("colLastVisit")}</TableHead>
                  <TableHead className="w-[100px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {items.map((c) => (
                  <TableRow key={c.id}>
                    <TableCell className="font-medium">
                      <div>{c.name}</div>
                      <div className="text-[11px] text-muted-foreground">
                        {c.birthday && `🎂 ${c.birthday}`}
                        {c.preferred_payment_method && ` · ${c.preferred_payment_method}`}
                        {typeof c.preferred_hour_bucket === "number" &&
                          ` · ${String(c.preferred_hour_bucket).padStart(2, "0")}:00`}
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground text-xs">
                      {c.email && <div>{c.email}</div>}
                      {c.phone && <div>{c.phone}</div>}
                      {!c.email && !c.phone && "—"}
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {c.tags.slice(0, 3).map((tag) => (
                          <Badge key={tag} variant="secondary" className="text-[10px]">
                            {tag}
                          </Badge>
                        ))}
                        {c.dietary_tags.slice(0, 2).map((tag) => (
                          <Badge key={tag} variant="outline" className="text-[10px]">
                            {tag}
                          </Badge>
                        ))}
                        {(c.tags.length === 0 && c.dietary_tags.length === 0) && (
                          <span className="text-muted-foreground text-xs">—</span>
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {c.loyalty_points > 0 ? (
                        <Badge variant="secondary" className="tabular-nums">
                          {c.loyalty_points}
                        </Badge>
                      ) : "—"}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {formatChf(c.total_spent_cents)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {c.avg_ticket_cents > 0 ? formatChf(c.avg_ticket_cents) : "—"}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{c.total_visits}</TableCell>
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
        <DialogContent className="max-w-xl">
          <form
            onSubmit={form.handleSubmit((values) => save.mutate(values))}
            className="space-y-4"
          >
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                {editing ? t("editCustomer") : t("newCustomer")}
                {editing && <Sparkles className="h-4 w-4 text-primary" />}
              </DialogTitle>
              <DialogDescription>{t("formDescription")}</DialogDescription>
            </DialogHeader>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1 col-span-2">
                <Label htmlFor="cust-name">{t("colName")}</Label>
                <Input id="cust-name" {...form.register("name")} />
                {form.formState.errors.name && (
                  <p className="text-xs text-destructive">{form.formState.errors.name.message}</p>
                )}
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
                <Label htmlFor="cust-bday">{t("birthday")}</Label>
                <Input id="cust-bday" type="date" {...form.register("birthday")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="cust-anniv">{t("anniversary")}</Label>
                <Input id="cust-anniv" type="date" {...form.register("anniversary")} />
              </div>
              <div className="space-y-1 col-span-2">
                <Label htmlFor="cust-tags">{t("tags")}</Label>
                <Input
                  id="cust-tags"
                  placeholder="VIP, Vegan, Stammgast"
                  {...form.register("tagsCsv")}
                />
                <p className="text-[11px] text-muted-foreground">{t("tagsHint")}</p>
              </div>
              <div className="space-y-1">
                <Label htmlFor="cust-diet">{t("dietary")}</Label>
                <Input
                  id="cust-diet"
                  placeholder={DIETARY_PRESETS.slice(0, 3).join(", ")}
                  {...form.register("dietaryCsv")}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="cust-allerg">{t("allergens")}</Label>
                <Input
                  id="cust-allerg"
                  placeholder={ALLERGEN_PRESETS.slice(0, 3).join(", ")}
                  {...form.register("allergensCsv")}
                />
              </div>
              <div className="space-y-1 col-span-2">
                <Label htmlFor="cust-notes">{t("notes")}</Label>
                <Input id="cust-notes" {...form.register("notes")} />
              </div>
            </div>

            {editing && (
              <div className="rounded-md border bg-muted/30 p-3 text-xs space-y-1">
                <div>
                  {t("lifetimeSpent")}: <span className="font-mono">{formatChf(editing.total_spent_cents)}</span>
                </div>
                <div>
                  {t("avgTicket")}: <span className="font-mono">{editing.avg_ticket_cents > 0 ? formatChf(editing.avg_ticket_cents) : "—"}</span>
                </div>
                <div>
                  {t("totalVisits")}: <span className="font-mono">{editing.total_visits}</span>
                </div>
                {editing.first_visit_at && (
                  <div>{t("firstVisit")}: <span className="font-mono">{formatDate(editing.first_visit_at)}</span></div>
                )}
              </div>
            )}

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
