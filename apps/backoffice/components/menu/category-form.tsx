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
import { ColorPicker } from "./color-picker";
import { EmojiPicker } from "./emoji-picker";
import type { MenuCategory } from "@/lib/api-types";

export const categorySchema = z.object({
  name: z.string().min(1),
  display_order: z.coerce.number().int().min(0),
  color: z.string().nullable().optional(),
  icon: z.string().nullable().optional(),
  is_active: z.boolean(),
});

export type CategoryInput = z.infer<typeof categorySchema>;

export function CategoryForm({
  initial,
  onSubmit,
  onCancel,
}: {
  initial?: Partial<MenuCategory>;
  onSubmit: (data: CategoryInput) => Promise<void> | void;
  onCancel: () => void;
}) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");
  const form = useForm<CategoryInput>({
    resolver: zodResolver(categorySchema),
    defaultValues: {
      name: initial?.name ?? "",
      display_order: initial?.display_order ?? 0,
      color: initial?.color ?? "",
      icon: initial?.icon ?? "",
      is_active: initial?.is_active ?? true,
    },
  });
  const [color, setColor] = React.useState(initial?.color ?? "");
  const [icon, setIcon] = React.useState(initial?.icon ?? "");
  const [active, setActive] = React.useState(initial?.is_active ?? true);

  const submit = form.handleSubmit(async (vals) => {
    await onSubmit({ ...vals, color, icon, is_active: active });
  });

  return (
    <form onSubmit={submit} className="space-y-4" data-testid="category-form">
      <div className="space-y-1.5">
        <Label htmlFor="cat-name">{t("name")}</Label>
        <Input id="cat-name" {...form.register("name")} />
        {form.formState.errors.name && (
          <p className="text-xs text-destructive">{form.formState.errors.name.message}</p>
        )}
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label htmlFor="cat-order">{t("displayOrder")}</Label>
          <Input id="cat-order" type="number" {...form.register("display_order")} />
        </div>
        <div className="flex items-center justify-between gap-2 pt-6">
          <Label htmlFor="cat-active">{tCommon("active")}</Label>
          <Switch id="cat-active" checked={active} onCheckedChange={setActive} />
        </div>
      </div>
      <div className="space-y-1.5">
        <Label>{t("color")}</Label>
        <ColorPicker value={color} onChange={setColor} />
      </div>
      <div className="space-y-1.5">
        <Label>{t("icon")}</Label>
        <EmojiPicker value={icon} onChange={setIcon} />
      </div>
      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="outline" onClick={onCancel}>
          {tCommon("cancel")}
        </Button>
        <Button type="submit" disabled={form.formState.isSubmitting}>
          {tCommon("save")}
        </Button>
      </div>
    </form>
  );
}
