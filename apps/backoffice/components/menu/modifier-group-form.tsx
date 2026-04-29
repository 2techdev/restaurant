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
import { chfToCents, centsToChfStr } from "@/lib/utils";
import type { ModifierGroup, Modifier } from "@/lib/api-types";

export const modifierGroupSchema = z.object({
  name: z.string().min(1),
  selection_type: z.enum(["single", "multiple"]),
  min_selections: z.coerce.number().int().min(0),
  max_selections: z.coerce.number().int().min(0),
  is_required: z.boolean(),
  display_order: z.coerce.number().int().min(0),
});

type GroupInput = z.infer<typeof modifierGroupSchema>;

export interface GroupSubmitPayload extends GroupInput {
  modifiers: { id?: string; name: string; price_delta: number; is_default: boolean; display_order: number }[];
}

export function ModifierGroupForm({
  initial,
  onSubmit,
  onCancel,
}: {
  initial?: Partial<ModifierGroup>;
  onSubmit: (data: GroupSubmitPayload) => Promise<void> | void;
  onCancel: () => void;
}) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");

  const form = useForm<GroupInput>({
    resolver: zodResolver(modifierGroupSchema),
    defaultValues: {
      name: initial?.name ?? "",
      selection_type: (initial?.selection_type as "single" | "multiple") ?? "single",
      min_selections: initial?.min_selections ?? 0,
      max_selections: initial?.max_selections ?? 1,
      is_required: initial?.is_required ?? false,
      display_order: initial?.display_order ?? 0,
    },
  });
  const [selectionType, setSelectionType] = React.useState<"single" | "multiple">(
    (initial?.selection_type as "single" | "multiple") ?? "single"
  );
  const [required, setRequired] = React.useState(initial?.is_required ?? false);

  type Row = { id?: string; name: string; price_delta_chf: string; is_default: boolean; display_order: number };
  const [mods, setMods] = React.useState<Row[]>(() =>
    (initial?.modifiers ?? []).map((m: Modifier) => ({
      id: m.id,
      name: m.name,
      price_delta_chf: centsToChfStr(m.price_delta),
      is_default: m.is_default,
      display_order: m.display_order,
    }))
  );

  const addRow = () =>
    setMods((p) => [...p, { name: "", price_delta_chf: "0.00", is_default: false, display_order: p.length }]);
  const updateRow = (i: number, patch: Partial<Row>) =>
    setMods((p) => p.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));
  const removeRow = (i: number) => setMods((p) => p.filter((_, idx) => idx !== i));

  const submit = form.handleSubmit(async (vals) => {
    await onSubmit({
      ...vals,
      selection_type: selectionType,
      is_required: required,
      modifiers: mods
        .filter((m) => m.name)
        .map((m) => ({
          id: m.id,
          name: m.name,
          price_delta: chfToCents(m.price_delta_chf),
          is_default: m.is_default,
          display_order: m.display_order,
        })),
    });
  });

  return (
    <form onSubmit={submit} className="space-y-4" data-testid="modifier-form">
      <div className="space-y-1.5">
        <Label>{t("name")}</Label>
        <Input {...form.register("name")} />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label>{t("selectionType")}</Label>
          <Select value={selectionType} onValueChange={(v) => setSelectionType(v as "single" | "multiple")}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="single">{t("single")}</SelectItem>
              <SelectItem value="multiple">{t("multiple")}</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="flex items-center justify-between gap-2 pt-6">
          <Label>{t("isRequired")}</Label>
          <Switch checked={required} onCheckedChange={setRequired} />
        </div>
      </div>
      <div className="grid grid-cols-3 gap-2">
        <div className="space-y-1.5">
          <Label>{t("minSelections")}</Label>
          <Input type="number" {...form.register("min_selections")} />
        </div>
        <div className="space-y-1.5">
          <Label>{t("maxSelections")}</Label>
          <Input type="number" {...form.register("max_selections")} />
        </div>
        <div className="space-y-1.5">
          <Label>{t("displayOrder")}</Label>
          <Input type="number" {...form.register("display_order")} />
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <Label>{t("modifiers")}</Label>
          <Button type="button" size="sm" variant="outline" onClick={addRow}>+ {tCommon("add")}</Button>
        </div>
        <div className="space-y-2 max-h-60 overflow-y-auto rounded border p-2">
          {mods.length === 0 && <p className="text-xs text-muted-foreground text-center py-3">{tCommon("noData")}</p>}
          {mods.map((m, i) => (
            <div key={i} className="grid grid-cols-[1fr_120px_24px_28px] gap-2 items-center">
              <Input
                placeholder={t("name")}
                value={m.name}
                onChange={(e) => updateRow(i, { name: e.target.value })}
              />
              <Input
                placeholder="0.00"
                inputMode="decimal"
                value={m.price_delta_chf}
                onChange={(e) => updateRow(i, { price_delta_chf: e.target.value })}
              />
              <input
                type="checkbox"
                checked={m.is_default}
                onChange={(e) => updateRow(i, { is_default: e.target.checked })}
                title="default"
              />
              <Button type="button" variant="ghost" size="icon" onClick={() => removeRow(i)}>×</Button>
            </div>
          ))}
        </div>
      </div>

      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="outline" onClick={onCancel}>{tCommon("cancel")}</Button>
        <Button type="submit" disabled={form.formState.isSubmitting}>{tCommon("save")}</Button>
      </div>
    </form>
  );
}
