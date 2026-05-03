"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Plus,
  Search,
  MoreHorizontal,
  Pencil,
  Trash2,
  Lock,
  Loader2,
  Package,
} from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";
import type { MenuProduct, MenuCategory } from "@/lib/api-types";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";

const LOCALES = ["tr", "de", "en", "fr", "it"] as const;
type LocaleCode = (typeof LOCALES)[number];

const ALLERGENS = [
  "gluten",
  "dairy",
  "nuts",
  "egg",
  "soy",
  "fish",
  "shellfish",
  "celery",
  "mustard",
] as const;

// ─── Schema ─────────────────────────────────────────────────────────────
//
// Backend now persists name_translations + description_translations as JSONB
// (migration 022). The form stores all 5 languages in one map; the primary
// language string is mirrored to `name` / `description` on submit so legacy
// code that reads only the single field keeps working.
const PRIMARY_LANG: LocaleCode = "tr";

const ProductFormSchema = z.object({
  name_translations: z.record(z.string(), z.string()).default({}),
  description_translations: z.record(z.string(), z.string()).default({}),
  category_id: z.string().min(1),
  price_chf: z.coerce.number().min(0),
  price_takeaway_chf: z.coerce.number().min(0).optional(),
  price_delivery_chf: z.coerce.number().min(0).optional(),
  tax_group: z.string().min(1),
  image_path: z.string().optional(),
  is_active: z.boolean(),
  display_order: z.coerce.number().int().min(0),
  allergens: z.array(z.string()).default([]),
}).refine(
  (v) => (v.name_translations[PRIMARY_LANG] ?? "").trim().length > 0,
  { message: "primary language name is required", path: ["name_translations"] },
);
type ProductFormInput = z.infer<typeof ProductFormSchema>;

const TAX_GROUPS = [
  { value: "standard", label: "Standart (%7.7)" },
  { value: "reduced", label: "İndirimli (%2.5)" },
  { value: "zero", label: "%0" },
];

interface Props {
  initialProducts: MenuProduct[];
  initialCategories: MenuCategory[];
}

export function ProductsClient({ initialProducts, initialCategories }: Props) {
  const t = useTranslations("menu.productsPage");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();

  const [search, setSearch] = React.useState("");
  const [filterCat, setFilterCat] = React.useState<string>("all");
  const [filterActive, setFilterActive] = React.useState<string>("all");
  const [sheet, setSheet] = React.useState<{ mode: "create" | "edit"; row?: MenuProduct } | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<MenuProduct | null>(null);

  const products = useQuery({
    queryKey: ["menu-products"],
    queryFn: async () => {
      const data = await clientFetch<{ products?: MenuProduct[]; data?: MenuProduct[] } | MenuProduct[]>({
        path: "/menu/products",
      });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (Array.isArray(raw) ? raw : raw?.products ?? raw?.data ?? []) as MenuProduct[];
    },
    initialData: initialProducts,
  });

  const categories = useQuery({
    queryKey: ["menu-categories"],
    queryFn: async () => {
      const data = await clientFetch<{ categories?: MenuCategory[] } | MenuCategory[]>({
        path: "/menu/categories",
      });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (Array.isArray(raw) ? raw : raw?.categories ?? []) as MenuCategory[];
    },
    initialData: initialCategories,
  });

  const cats = categories.data ?? [];
  const catName = (id: string) => cats.find((c) => c.id === id)?.name ?? "—";

  const items = React.useMemo(() => {
    const all = products.data ?? [];
    const q = search.trim().toLowerCase();
    return all.filter((p) => {
      if (filterCat !== "all" && p.category_id !== filterCat) return false;
      if (filterActive === "active" && !p.is_active) return false;
      if (filterActive === "inactive" && p.is_active) return false;
      if (q && !p.name.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [products.data, search, filterCat, filterActive]);

  const upsert = useMutation({
    mutationFn: async (input: { id?: string; payload: Record<string, unknown> }) => {
      if (input.id) {
        return clientFetch({
          path: `/menu/products/${input.id}`,
          method: "PUT",
          body: input.payload,
        });
      }
      return clientFetch({
        path: "/menu/products",
        method: "POST",
        body: input.payload,
      });
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ["menu-products"] });
      toast({ title: vars.id ? t("updatedToast") : t("createdToast") });
      setSheet(null);
    },
    onError: (e: Error) => {
      toast({
        title: t("saveError"),
        description: e.message,
        variant: "destructive",
      });
    },
  });

  const toggleActive = useMutation({
    mutationFn: async (p: MenuProduct) =>
      clientFetch({
        path: `/menu/products/${p.id}`,
        method: "PUT",
        body: { ...p, is_active: !p.is_active },
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["menu-products"] }),
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/menu/products/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["menu-products"] });
      toast({ title: t("deletedToast") });
      setConfirmDelete(null);
    },
    onError: (e: Error) => {
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" });
    },
  });

  return (
    <div className="space-y-4">
      <Card className="p-4 space-y-3">
        <div className="flex flex-wrap gap-3 items-end">
          <div className="space-y-1 flex-1 min-w-[220px]">
            <Label className="text-xs">{t("filter.search")}</Label>
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={t("filter.searchPlaceholder")}
                className="pl-8"
              />
            </div>
          </div>
          <div className="space-y-1 min-w-[180px]">
            <Label className="text-xs">{t("filter.category")}</Label>
            <Select value={filterCat} onValueChange={setFilterCat}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{tCommon("all")}</SelectItem>
                {cats.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1 min-w-[140px]">
            <Label className="text-xs">{t("filter.status")}</Label>
            <Select value={filterActive} onValueChange={setFilterActive}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{tCommon("all")}</SelectItem>
                <SelectItem value="active">{tCommon("active")}</SelectItem>
                <SelectItem value="inactive">{tCommon("inactive")}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <Button onClick={() => setSheet({ mode: "create" })}>
            <Plus className="h-4 w-4" />
            {t("newProduct")}
          </Button>
        </div>
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 flex items-center justify-between">
          <span className="text-sm font-medium">
            {t("listHeader", { count: items.length })}
          </span>
          {(products.isFetching || upsert.isPending) && (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
        </div>

        {items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Package className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
            <Button variant="outline" onClick={() => setSheet({ mode: "create" })}>
              <Plus className="h-4 w-4" />
              {t("newProduct")}
            </Button>
          </div>
        ) : (
          <>
            <div className="hidden md:block overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("col.name")}</TableHead>
                    <TableHead>{t("col.category")}</TableHead>
                    <TableHead>{t("col.prices")}</TableHead>
                    <TableHead>{t("col.tax")}</TableHead>
                    <TableHead>{t("col.status")}</TableHead>
                    <TableHead className="w-12"></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {items.map((p) => (
                    <TableRow key={p.id} className="hover:bg-muted/30">
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <div className="h-8 w-8 rounded bg-muted flex items-center justify-center text-[10px] font-mono text-muted-foreground">
                            {p.name.slice(0, 2).toUpperCase()}
                          </div>
                          <div>
                            <div className="font-medium flex items-center gap-1.5">
                              {p.name}
                              {p.policy_lock && p.policy_lock !== "FLEXIBLE" && (
                                <Lock className="h-3 w-3 text-warning" />
                              )}
                            </div>
                            {p.description && (
                              <div className="text-[11px] text-muted-foreground truncate max-w-[280px]">
                                {p.description}
                              </div>
                            )}
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>{catName(p.category_id)}</TableCell>
                      <TableCell>
                        <span className="font-mono text-[12px] tabular-nums">
                          {formatChf((p.price ?? 0) / 100)}
                          {p.price_takeaway != null &&
                            ` / ${formatChf(p.price_takeaway / 100)}`}
                          {p.price_delivery != null &&
                            ` / ${formatChf(p.price_delivery / 100)}`}
                        </span>
                      </TableCell>
                      <TableCell className="text-xs">{p.tax_group}</TableCell>
                      <TableCell>
                        <Switch
                          checked={p.is_active}
                          onCheckedChange={() => toggleActive.mutate(p)}
                          disabled={p.policy_lock === "FULLY_LOCKED"}
                        />
                      </TableCell>
                      <TableCell>
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon" className="h-8 w-8">
                              <MoreHorizontal className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem onSelect={() => setSheet({ mode: "edit", row: p })}>
                              <Pencil className="h-4 w-4" />
                              {tCommon("edit")}
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              className="text-error"
                              onSelect={() => setConfirmDelete(p)}
                              disabled={p.policy_lock === "FULLY_LOCKED"}
                            >
                              <Trash2 className="h-4 w-4" />
                              {tCommon("delete")}
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            {/* mobile cards */}
            <div className="md:hidden divide-y">
              {items.map((p) => (
                <div key={p.id} className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 flex-1">
                      <div className="font-medium flex items-center gap-1.5">
                        {p.name}
                        {p.policy_lock && p.policy_lock !== "FLEXIBLE" && (
                          <Lock className="h-3 w-3 text-warning" />
                        )}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {catName(p.category_id)}
                      </div>
                      <div className="text-xs font-mono mt-1 tabular-nums">
                        {formatChf((p.price ?? 0) / 100)}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Switch
                        checked={p.is_active}
                        onCheckedChange={() => toggleActive.mutate(p)}
                        disabled={p.policy_lock === "FULLY_LOCKED"}
                      />
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        onClick={() => setSheet({ mode: "edit", row: p })}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </Card>

      <ProductSheet
        open={sheet !== null}
        mode={sheet?.mode ?? "create"}
        product={sheet?.row}
        categories={cats}
        onClose={() => setSheet(null)}
        onSubmit={(input) => {
          const primaryName = (input.name_translations[PRIMARY_LANG] ?? "").trim();
          const primaryDesc = (input.description_translations[PRIMARY_LANG] ?? "").trim();
          // Strip empties so the JSONB stays compact + only secondary langs go
          // into the translations map. Primary lang lives in `name` only.
          const stripPrimary = (
            map: Record<string, string>,
          ): Record<string, string> =>
            Object.fromEntries(
              Object.entries(map).filter(
                ([k, v]) => k !== PRIMARY_LANG && v.trim().length > 0,
              ),
            );
          const payload: Record<string, unknown> = {
            name: primaryName,
            name_translations: stripPrimary(input.name_translations),
            description: primaryDesc,
            description_translations: stripPrimary(input.description_translations),
            category_id: input.category_id,
            price: Math.round(input.price_chf * 100),
            tax_group: input.tax_group,
            image_path: input.image_path ?? null,
            is_active: input.is_active,
            display_order: input.display_order,
          };
          if (input.price_takeaway_chf != null) {
            payload.price_takeaway = Math.round(input.price_takeaway_chf * 100);
          }
          if (input.price_delivery_chf != null) {
            payload.price_delivery = Math.round(input.price_delivery_chf * 100);
          }
          // Allergens stored as JSON in description for now (no schema column).
          if (input.allergens && input.allergens.length > 0) {
            payload.allergens = input.allergens;
          }
          upsert.mutate({ id: sheet?.row?.id, payload });
        }}
        submitting={upsert.isPending}
      />

      <AlertDialog
        open={confirmDelete !== null}
        onOpenChange={(o) => !o && setConfirmDelete(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("deleteConfirmTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("deleteConfirmBody", { name: confirmDelete?.name ?? "" })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction
              className="bg-error text-error-foreground hover:bg-error/90"
              onClick={() => confirmDelete && remove.mutate(confirmDelete.id)}
            >
              {tCommon("delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function ProductSheet({
  open,
  mode,
  product,
  categories,
  onClose,
  onSubmit,
  submitting,
}: {
  open: boolean;
  mode: "create" | "edit";
  product?: MenuProduct;
  categories: MenuCategory[];
  onClose: () => void;
  onSubmit: (input: ProductFormInput) => void;
  submitting: boolean;
}) {
  const t = useTranslations("menu.productsPage");
  const tCommon = useTranslations("common");
  const isLockedPrice = product?.policy_lock === "PRICE_LOCKED";
  const isLockedAll = product?.policy_lock === "FULLY_LOCKED";
  const [activeLocale, setActiveLocale] = React.useState<LocaleCode>("tr");

  const form = useForm<ProductFormInput>({
    resolver: zodResolver(ProductFormSchema),
    values: product
      ? {
          name_translations: {
            [PRIMARY_LANG]: product.name,
            ...((product as { name_translations?: Record<string, string> })
              .name_translations ?? {}),
          },
          description_translations: {
            [PRIMARY_LANG]: product.description ?? "",
            ...((product as { description_translations?: Record<string, string> })
              .description_translations ?? {}),
          },
          category_id: product.category_id,
          price_chf: (product.price ?? 0) / 100,
          price_takeaway_chf: product.price_takeaway != null ? product.price_takeaway / 100 : undefined,
          price_delivery_chf: product.price_delivery != null ? product.price_delivery / 100 : undefined,
          tax_group: product.tax_group,
          image_path: product.image_path ?? "",
          is_active: product.is_active,
          display_order: product.display_order,
          allergens: [],
        }
      : {
          name_translations: { [PRIMARY_LANG]: "" },
          description_translations: { [PRIMARY_LANG]: "" },
          category_id: categories[0]?.id ?? "",
          price_chf: 0,
          tax_group: "standard",
          is_active: true,
          display_order: 0,
          allergens: [],
        },
  });

  const allergens = form.watch("allergens") ?? [];
  const toggleAllergen = (a: string) => {
    const next = allergens.includes(a)
      ? allergens.filter((x) => x !== a)
      : [...allergens, a];
    form.setValue("allergens", next, { shouldDirty: true });
  };

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full sm:max-w-2xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            {mode === "create" ? t("newProduct") : t("editProduct")}
            {product?.policy_lock && product.policy_lock !== "FLEXIBLE" && (
              <StatusBadge variant="warning" withDot>
                {product.policy_lock}
              </StatusBadge>
            )}
          </SheetTitle>
          <SheetDescription>{t("formHint")}</SheetDescription>
        </SheetHeader>

        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 mt-4">
          {/* Primary-language name + description — required */}
          <div className="space-y-1">
            <Label>
              {t("col.name")}{" "}
              <span className="text-[10px] uppercase text-muted-foreground">
                ({PRIMARY_LANG} — ana dil)
              </span>
            </Label>
            <Input
              placeholder={t("namePlaceholder")}
              {...form.register(`name_translations.${PRIMARY_LANG}` as const)}
              disabled={isLockedAll}
            />
            {form.formState.errors.name_translations && (
              <p className="text-xs text-error">{tCommon("error")}</p>
            )}
          </div>

          <div className="space-y-1">
            <Label>{t("col.description")}</Label>
            <textarea
              rows={2}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              placeholder={`${PRIMARY_LANG.toUpperCase()} — ${t("col.description")}`}
              {...form.register(`description_translations.${PRIMARY_LANG}` as const)}
              disabled={isLockedAll}
            />
          </div>

          {/* Other languages — collapsible. POS will pick the right
              translation based on the operator's session locale and fall
              back to the primary-language string above. */}
          <details className="rounded-md border border-input bg-muted/20">
            <summary className="cursor-pointer select-none px-3 py-2 text-sm font-medium">
              Diğer Diller (DE / EN / FR / IT)
            </summary>
            <div className="space-y-3 p-3 border-t">
              {LOCALES.filter((l) => l !== PRIMARY_LANG).map((l) => (
                <div key={l} className="space-y-1">
                  <Label className="text-xs uppercase">{l}</Label>
                  <Input
                    placeholder={`${l.toUpperCase()} — ${t("namePlaceholder")}`}
                    {...form.register(`name_translations.${l}` as const)}
                    disabled={isLockedAll}
                  />
                  <textarea
                    rows={2}
                    className="w-full rounded-md border border-input bg-background px-3 py-2 text-xs"
                    placeholder={`${l.toUpperCase()} — ${t("col.description")}`}
                    {...form.register(`description_translations.${l}` as const)}
                    disabled={isLockedAll}
                  />
                </div>
              ))}
              <p className="text-[11px] text-muted-foreground">
                Boş bırakılan diller POS'ta ana dile geri düşer.
              </p>
            </div>
          </details>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("col.category")}</Label>
              <Select
                value={form.watch("category_id")}
                onValueChange={(v) => form.setValue("category_id", v, { shouldDirty: true })}
                disabled={isLockedAll}
              >
                <SelectTrigger>
                  <SelectValue />
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
              <Label>{t("col.tax")}</Label>
              <Select
                value={form.watch("tax_group")}
                onValueChange={(v) => form.setValue("tax_group", v, { shouldDirty: true })}
                disabled={isLockedAll}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {TAX_GROUPS.map((tg) => (
                    <SelectItem key={tg.value} value={tg.value}>
                      {tg.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1">
              <Label>{t("price.standard")}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                {...form.register("price_chf")}
                disabled={isLockedAll || isLockedPrice}
              />
            </div>
            <div className="space-y-1">
              <Label>{t("price.takeaway")}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                {...form.register("price_takeaway_chf")}
                disabled={isLockedAll || isLockedPrice}
              />
            </div>
            <div className="space-y-1">
              <Label>{t("price.delivery")}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                {...form.register("price_delivery_chf")}
                disabled={isLockedAll || isLockedPrice}
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label>{t("col.allergens")}</Label>
            <div className="flex flex-wrap gap-2">
              {ALLERGENS.map((a) => {
                const on = allergens.includes(a);
                return (
                  <button
                    key={a}
                    type="button"
                    onClick={() => !isLockedAll && toggleAllergen(a)}
                    disabled={isLockedAll}
                    className={`px-3 py-1 rounded-full text-xs border transition-colors ${
                      on
                        ? "bg-warning-soft text-warning border-warning/30"
                        : "bg-muted/40 text-muted-foreground border-border hover:bg-muted"
                    } disabled:opacity-50 disabled:cursor-not-allowed`}
                  >
                    {t(`allergen.${a}`)}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("col.image")}</Label>
              <Input
                placeholder="https://…"
                {...form.register("image_path")}
                disabled={isLockedAll}
              />
            </div>
            <div className="space-y-1">
              <Label>{t("col.displayOrder")}</Label>
              <Input
                type="number"
                min="0"
                {...form.register("display_order")}
                disabled={isLockedAll}
              />
            </div>
          </div>

          <div className="flex items-center gap-2">
            <Switch
              checked={form.watch("is_active")}
              onCheckedChange={(v) => form.setValue("is_active", v, { shouldDirty: true })}
              disabled={isLockedAll}
            />
            <Label>{t("col.active")}</Label>
          </div>

          <SheetFooter className="gap-2">
            <Button type="button" variant="outline" onClick={onClose}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={submitting || isLockedAll}>
              {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
              {tCommon("save")}
            </Button>
          </SheetFooter>
        </form>
      </SheetContent>
    </Sheet>
  );
}
