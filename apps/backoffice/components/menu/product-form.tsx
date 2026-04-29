"use client";

import * as React from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { Badge } from "@/components/ui/badge";
import { Lock } from "lucide-react";
import { chfToCents, centsToChfStr } from "@/lib/utils";
import type { MenuCategory, MenuProduct, ModifierGroup } from "@/lib/api-types";

export const productSchema = z.object({
  name: z.string().min(1),
  category_id: z.string().min(1),
  price_chf: z.string(),
  price_takeaway_chf: z.string().optional(),
  price_delivery_chf: z.string().optional(),
  tax_group: z.string().min(1),
  image_path: z.string().optional(),
  is_active: z.boolean(),
  display_order: z.coerce.number().int().min(0),
  modifier_group_ids: z.array(z.string()).default([]),
});

export type ProductInput = z.infer<typeof productSchema>;

export interface ProductSubmitPayload {
  name: string;
  category_id: string;
  price: number;
  price_takeaway: number;
  price_delivery: number;
  tax_group: string;
  image_path?: string;
  is_active: boolean;
  display_order: number;
  modifier_group_ids: string[];
}

export function ProductForm({
  initial,
  categories,
  modifierGroups,
  onSubmit,
  onCancel,
}: {
  initial?: Partial<MenuProduct> & { modifier_group_ids?: string[] };
  categories: MenuCategory[];
  modifierGroups: ModifierGroup[];
  onSubmit: (data: ProductSubmitPayload) => Promise<void> | void;
  onCancel: () => void;
}) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");

  const isLocked = initial?.policy_lock === "FULLY_LOCKED";
  const isPriceLocked = initial?.policy_lock === "PRICE_LOCKED";

  const form = useForm<ProductInput>({
    resolver: zodResolver(productSchema),
    defaultValues: {
      name: initial?.name ?? "",
      category_id: initial?.category_id ?? categories[0]?.id ?? "",
      price_chf: centsToChfStr(initial?.price ?? 0),
      price_takeaway_chf: centsToChfStr(initial?.price_takeaway ?? initial?.price ?? 0),
      price_delivery_chf: centsToChfStr(initial?.price_delivery ?? initial?.price ?? 0),
      tax_group: initial?.tax_group ?? "standard",
      image_path: initial?.image_path ?? "",
      is_active: initial?.is_active ?? true,
      display_order: initial?.display_order ?? 0,
      modifier_group_ids: initial?.modifier_group_ids ?? [],
    },
  });

  const [active, setActive] = React.useState(initial?.is_active ?? true);
  const [categoryId, setCategoryId] = React.useState(initial?.category_id ?? categories[0]?.id ?? "");
  const [taxGroup, setTaxGroup] = React.useState(initial?.tax_group ?? "standard");
  const [selectedMods, setSelectedMods] = React.useState<string[]>(initial?.modifier_group_ids ?? []);

  const submit = form.handleSubmit(async (vals) => {
    await onSubmit({
      name: vals.name,
      category_id: categoryId,
      price: chfToCents(vals.price_chf),
      price_takeaway: chfToCents(vals.price_takeaway_chf || vals.price_chf),
      price_delivery: chfToCents(vals.price_delivery_chf || vals.price_chf),
      tax_group: taxGroup,
      image_path: vals.image_path || undefined,
      is_active: active,
      display_order: vals.display_order,
      modifier_group_ids: selectedMods,
    });
  });

  const lockedField = (children: React.ReactNode) =>
    isLocked || isPriceLocked ? (
      <Tooltip>
        <TooltipTrigger asChild>
          <div className="opacity-60 pointer-events-none">{children}</div>
        </TooltipTrigger>
        <TooltipContent>{t("lockedTooltip")}</TooltipContent>
      </Tooltip>
    ) : (
      children
    );

  return (
    <form onSubmit={submit} className="space-y-4" data-testid="product-form">
      {(isLocked || isPriceLocked) && (
        <div className="flex items-center gap-2">
          <Badge variant="warning"><Lock className="h-3 w-3" /> {t("lockedBadge")}</Badge>
          <span className="text-xs text-muted-foreground">{t("lockedTooltip")}</span>
        </div>
      )}

      <div className="space-y-1.5">
        <Label htmlFor="p-name">{t("name")}</Label>
        {isLocked ? (
          lockedField(<Input id="p-name" {...form.register("name")} disabled />)
        ) : (
          <Input id="p-name" {...form.register("name")} />
        )}
        {form.formState.errors.name && <p className="text-xs text-destructive">{form.formState.errors.name.message}</p>}
      </div>

      <div className="space-y-1.5">
        <Label>{t("category")}</Label>
        <Select value={categoryId} onValueChange={setCategoryId} disabled={isLocked}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            {categories.map((c) => (
              <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <div className="grid grid-cols-3 gap-2">
        <div className="space-y-1.5">
          <Label htmlFor="p-price">{t("priceStandard")}</Label>
          <Input id="p-price" {...form.register("price_chf")} type="text" inputMode="decimal" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="p-takeaway">{t("priceTakeaway")}</Label>
          <Input id="p-takeaway" {...form.register("price_takeaway_chf")} type="text" inputMode="decimal" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="p-delivery">{t("priceDelivery")}</Label>
          <Input id="p-delivery" {...form.register("price_delivery_chf")} type="text" inputMode="decimal" />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label>{t("taxGroup")}</Label>
          <Select value={taxGroup} onValueChange={setTaxGroup} disabled={isLocked}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="standard">Standard (7.7%)</SelectItem>
              <SelectItem value="reduced">Reduced (2.5%)</SelectItem>
              <SelectItem value="zero">Zero (0%)</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="p-order">{t("displayOrder")}</Label>
          <Input id="p-order" type="number" {...form.register("display_order")} disabled={isLocked} />
        </div>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="p-image">{t("imageUrl")}</Label>
        <Input id="p-image" {...form.register("image_path")} placeholder="https://..." disabled={isLocked} />
      </div>

      <div className="space-y-1.5">
        <Label>{t("modifiers")}</Label>
        <div className="grid grid-cols-2 gap-2 max-h-40 overflow-y-auto rounded border p-2">
          {modifierGroups.map((g) => {
            const checked = selectedMods.includes(g.id);
            return (
              <label key={g.id} className="flex items-center gap-2 text-sm cursor-pointer">
                <input
                  type="checkbox"
                  checked={checked}
                  disabled={isLocked}
                  onChange={() =>
                    setSelectedMods((prev) =>
                      checked ? prev.filter((x) => x !== g.id) : [...prev, g.id]
                    )
                  }
                />
                {g.name}
              </label>
            );
          })}
          {modifierGroups.length === 0 && (
            <span className="text-xs text-muted-foreground col-span-2 text-center py-2">{tCommon("noData")}</span>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between gap-2">
        <Label htmlFor="p-active">{tCommon("active")}</Label>
        <Switch id="p-active" checked={active} onCheckedChange={setActive} disabled={isLocked} />
      </div>

      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="outline" onClick={onCancel}>{tCommon("cancel")}</Button>
        <Button type="submit" disabled={form.formState.isSubmitting || isLocked}>{tCommon("save")}</Button>
      </div>
    </form>
  );
}
