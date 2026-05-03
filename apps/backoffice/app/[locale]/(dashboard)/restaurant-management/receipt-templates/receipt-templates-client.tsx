"use client";

/**
 * Receipt templates — three template types per tenant: kitchen ticket,
 * customer receipt, Z-report. Backend: /api/v1/receipt-templates with
 * ?type=… filter (migration 021).
 *
 * Variable palette is type-aware — kitchen tickets do not get tax/total
 * placeholders, customer receipts do, Z-reports get aggregate counters.
 */

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  Plus,
  Loader2,
  Pencil,
  Trash2,
  Receipt,
  ChefHat,
  FileBarChart2,
} from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { StatusBadge } from "@/components/ui/status-badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";

type TemplateType = "kitchen_ticket" | "customer_receipt" | "z_report";

interface Template {
  id: string;
  tenant_id: string;
  name: string;
  template_type: TemplateType;
  language: string;
  width_mm: number;
  is_default: boolean;
  header: string;
  body_format: string;
  footer: string;
  paper_cut: boolean;
  open_drawer: boolean;
  copies: number;
}

interface ListResp {
  data: Template[];
}

const VARS_BY_TYPE: Record<TemplateType, readonly string[]> = {
  customer_receipt: [
    "{{tenant_name}}",
    "{{tenant_address}}",
    "{{tenant_uid}}",
    "{{tenant_iban}}",
    "{{order_no}}",
    "{{date_ch}}",
    "{{time_ch}}",
    "{{table_or_takeaway}}",
    "{{cashier_name}}",
    "{{customer_name}}",
    "{{items_ch}}",
    "{{subtotal}}",
    "{{discount_line_if_any}}",
    "{{vat_breakdown}}",
    "{{vat_8_1_amount}}",
    "{{vat_2_6_amount}}",
    "{{vat_3_8_amount}}",
    "{{total}}",
    "{{rounded_total}}",
    "{{rounding_diff}}",
    "{{payment_method}}",
    "{{twint_qr_if_tip}}",
  ],
  kitchen_ticket: [
    "{{order_no}}",
    "{{date_ch}}",
    "{{time_ch}}",
    "{{table_or_takeaway}}",
    "{{cashier_name}}",
    "{{items_kitchen}}",
  ],
  z_report: [
    "{{tenant_name}}",
    "{{date_ch}}",
    "{{time_ch}}",
    "{{total_revenue}}",
    "{{order_count}}",
    "{{avg_order}}",
    "{{vat_8_1_amount}}",
    "{{vat_2_6_amount}}",
    "{{vat_3_8_amount}}",
    "{{cash_total}}",
    "{{card_total}}",
    "{{twint_total}}",
  ],
};

const DEFAULT_BODY_BY_TYPE: Record<TemplateType, string> = {
  customer_receipt: `Beleg Nr: {{order_no}}
{{date_ch}} {{time_ch}}
Tisch: {{table_or_takeaway}}
--------------------------------
{{items_ch}}
--------------------------------
Zwischensumme:    {{subtotal}}
{{vat_breakdown}}
================================
TOTAL:            CHF {{total}}
Zahlungsart: {{payment_method}}`,
  kitchen_ticket: `*** KÜCHE / MUTFAK ***
Beleg: {{order_no}}
{{date_ch}} {{time_ch}}
Tisch: {{table_or_takeaway}}
--------------------------------
{{items_kitchen}}
--------------------------------`,
  z_report: `==== Z-RAPOR ====
{{tenant_name}}
{{date_ch}} {{time_ch}}
--------------------------------
Toplam Ciro:      {{total_revenue}}
Sipariş Sayısı:   {{order_count}}
Ort. Sipariş:     {{avg_order}}
--------------------------------
MWST 8.1%:        {{vat_8_1_amount}}
MWST 2.6%:        {{vat_2_6_amount}}
MWST 3.8%:        {{vat_3_8_amount}}
--------------------------------
Nakit:            {{cash_total}}
Karte:            {{card_total}}
TWINT:            {{twint_total}}`,
};

const FormSchema = z.object({
  name: z.string().min(1),
  template_type: z.enum(["kitchen_ticket", "customer_receipt", "z_report"]),
  language: z.enum(["tr", "de", "en", "fr", "it"]),
  width_mm: z.union([z.literal(58), z.literal(80)]),
  is_default: z.boolean(),
  header: z.string(),
  body_format: z.string().min(1),
  footer: z.string(),
  paper_cut: z.boolean(),
  open_drawer: z.boolean(),
  copies: z.coerce.number().int().min(1).max(5),
});
type FormInput = z.infer<typeof FormSchema>;

const TYPE_ICON: Record<TemplateType, React.ReactNode> = {
  customer_receipt: <Receipt className="h-4 w-4" />,
  kitchen_ticket: <ChefHat className="h-4 w-4" />,
  z_report: <FileBarChart2 className="h-4 w-4" />,
};

export function ReceiptTemplatesClient() {
  const t = useTranslations("restaurantMgmt.receiptTemplates");
  const [activeTab, setActiveTab] = React.useState<TemplateType>("customer_receipt");
  const [editing, setEditing] = React.useState<Template | "create" | null>(null);

  return (
    <div className="space-y-4">
      <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as TemplateType)}>
        <TabsList>
          <TabsTrigger value="customer_receipt" className="gap-2">
            {TYPE_ICON.customer_receipt}
            {t("type.customerReceipt")}
          </TabsTrigger>
          <TabsTrigger value="kitchen_ticket" className="gap-2">
            {TYPE_ICON.kitchen_ticket}
            {t("type.kitchenTicket")}
          </TabsTrigger>
          <TabsTrigger value="z_report" className="gap-2">
            {TYPE_ICON.z_report}
            {t("type.zReport")}
          </TabsTrigger>
        </TabsList>
        {(["customer_receipt", "kitchen_ticket", "z_report"] as const).map((tt) => (
          <TabsContent key={tt} value={tt} className="space-y-4">
            <TemplatesPanel
              type={tt}
              onEdit={setEditing}
              onCreate={() => setEditing("create")}
            />
          </TabsContent>
        ))}
      </Tabs>

      <TemplateEditor
        editing={editing}
        defaultType={activeTab}
        onClose={() => setEditing(null)}
      />
    </div>
  );
}

function TemplatesPanel({
  type,
  onEdit,
  onCreate,
}: {
  type: TemplateType;
  onEdit: (tpl: Template) => void;
  onCreate: () => void;
}) {
  const t = useTranslations("restaurantMgmt.receiptTemplates");
  const tCommon = useTranslations("common");
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [confirmDelete, setConfirmDelete] = React.useState<Template | null>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ["receipt-templates", type],
    queryFn: () =>
      clientFetch<ListResp>({ path: `/receipt-templates?type=${type}`, method: "GET" }),
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/receipt-templates/${id}`, method: "DELETE" }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["receipt-templates", type] });
      toast({ title: t("deletedToast") });
      setConfirmDelete(null);
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message }),
  });

  const items = data?.data ?? [];

  return (
    <>
      <div className="flex justify-end">
        <Button onClick={onCreate}>
          <Plus className="h-4 w-4" />
          {t("newTemplate")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 text-sm font-medium">
          {t("listHeader", { count: items.length })}
        </div>
        {isLoading ? (
          <div className="p-12 text-center">
            <Loader2 className="h-6 w-6 mx-auto animate-spin text-muted-foreground" />
          </div>
        ) : error ? (
          <div className="p-12 text-center text-sm text-error">
            {(error as Error).message}
          </div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            {TYPE_ICON[type]}
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.language")}</TableHead>
                <TableHead>{t("col.width")}</TableHead>
                <TableHead>{t("col.default")}</TableHead>
                <TableHead className="w-20"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((tpl) => (
                <TableRow key={tpl.id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{tpl.name}</TableCell>
                  <TableCell className="uppercase text-xs">{tpl.language}</TableCell>
                  <TableCell className="font-mono text-xs">{tpl.width_mm}mm</TableCell>
                  <TableCell>
                    {tpl.is_default && (
                      <StatusBadge variant="success" withDot>
                        {t("default")}
                      </StatusBadge>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        onClick={() => onEdit(tpl)}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-error"
                        disabled={tpl.is_default}
                        onClick={() => setConfirmDelete(tpl)}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      <AlertDialog
        open={confirmDelete !== null}
        onOpenChange={(o) => !o && setConfirmDelete(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("deleteTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("deleteHint", { name: confirmDelete?.name ?? "" })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => confirmDelete && deleteMut.mutate(confirmDelete.id)}
              disabled={deleteMut.isPending}
            >
              {tCommon("delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}

function TemplateEditor({
  editing,
  defaultType,
  onClose,
}: {
  editing: Template | "create" | null;
  defaultType: TemplateType;
  onClose: () => void;
}) {
  const t = useTranslations("restaurantMgmt.receiptTemplates");
  const tCommon = useTranslations("common");
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const isEdit = editing && editing !== "create";
  const initial = isEdit ? (editing as Template) : null;

  const form = useForm<FormInput>({
    resolver: zodResolver(FormSchema),
    defaultValues: {
      name: "",
      template_type: defaultType,
      language: "de",
      width_mm: 80,
      is_default: false,
      header: "",
      body_format: DEFAULT_BODY_BY_TYPE[defaultType],
      footer: "",
      paper_cut: true,
      open_drawer: false,
      copies: 1,
    },
  });

  React.useEffect(() => {
    if (initial) {
      form.reset({
        name: initial.name,
        template_type: initial.template_type,
        language: (initial.language as FormInput["language"]) ?? "de",
        width_mm: initial.width_mm === 58 ? 58 : 80,
        is_default: initial.is_default,
        header: initial.header,
        body_format: initial.body_format,
        footer: initial.footer,
        paper_cut: initial.paper_cut,
        open_drawer: initial.open_drawer,
        copies: initial.copies,
      });
    } else if (editing === "create") {
      form.reset({
        name: "",
        template_type: defaultType,
        language: "de",
        width_mm: 80,
        is_default: false,
        header: "",
        body_format: DEFAULT_BODY_BY_TYPE[defaultType],
        footer: "",
        paper_cut: true,
        open_drawer: false,
        copies: 1,
      });
    }
  }, [editing, initial, defaultType, form]);

  const upsertMut = useMutation({
    mutationFn: (input: FormInput) => {
      if (initial) {
        return clientFetch({
          path: `/receipt-templates/${initial.id}`,
          method: "PUT",
          body: input,
        });
      }
      return clientFetch({
        path: `/receipt-templates`,
        method: "POST",
        body: input,
      });
    },
    onSuccess: (_, input) => {
      queryClient.invalidateQueries({ queryKey: ["receipt-templates", input.template_type] });
      toast({ title: initial ? t("updatedToast") : t("createdToast") });
      onClose();
    },
    onError: (e: Error) => toast({ title: tCommon("error"), description: e.message }),
  });

  const tplType = form.watch("template_type");
  const widthMM = form.watch("width_mm");
  const header = form.watch("header");
  const body = form.watch("body_format");
  const footer = form.watch("footer");
  const widthChars = widthMM === 58 ? 32 : 48;
  const vars = VARS_BY_TYPE[tplType];

  const insertVar = (target: "header" | "body_format" | "footer", v: string) => {
    const current = form.getValues(target) ?? "";
    form.setValue(target, current + v, { shouldDirty: true });
  };

  const previewText = (text: string) =>
    text
      .replace(/\{\{order_no\}\}/g, "4729")
      .replace(/\{\{date_ch\}\}/g, "30.04.2026")
      .replace(/\{\{time_ch\}\}/g, "14:32")
      .replace(/\{\{table_or_takeaway\}\}/g, "T-12")
      .replace(/\{\{cashier_name\}\}/g, "Mario")
      .replace(/\{\{customer_name\}\}/g, "—")
      .replace(/\{\{tenant_name\}\}/g, "Pizzeria Da Mario")
      .replace(/\{\{tenant_address\}\}/g, "Bahnhofstrasse 1, 8001 Zürich")
      .replace(/\{\{tenant_uid\}\}/g, "CHE-123.456.789 MWST")
      .replace(/\{\{tenant_iban\}\}/g, "CH00 0000 0000 0000 0000 0")
      .replace(
        /\{\{items_ch\}\}/g,
        "1× Margherita        14.00\n2× Espresso           7.00",
      )
      .replace(
        /\{\{items_kitchen\}\}/g,
        "1× Margherita\n2× Espresso\n  → ohne Zucker",
      )
      .replace(/\{\{subtotal\}\}/g, "21.00")
      .replace(/\{\{discount_line_if_any\}\}/g, "")
      .replace(/\{\{vat_breakdown\}\}/g, "MWST 8.1%:           1.62")
      .replace(/\{\{vat_8_1_amount\}\}/g, "1.62")
      .replace(/\{\{vat_2_6_amount\}\}/g, "0.00")
      .replace(/\{\{vat_3_8_amount\}\}/g, "0.00")
      .replace(/\{\{total\}\}/g, "21.00")
      .replace(/\{\{rounded_total\}\}/g, "21.00")
      .replace(/\{\{rounding_diff\}\}/g, "0.00")
      .replace(/\{\{payment_method\}\}/g, "TWINT")
      .replace(/\{\{twint_qr_if_tip\}\}/g, "")
      .replace(/\{\{total_revenue\}\}/g, "1'248.50")
      .replace(/\{\{order_count\}\}/g, "47")
      .replace(/\{\{avg_order\}\}/g, "26.56")
      .replace(/\{\{cash_total\}\}/g, "412.00")
      .replace(/\{\{card_total\}\}/g, "598.50")
      .replace(/\{\{twint_total\}\}/g, "238.00");

  const onSubmit = (input: FormInput) => upsertMut.mutate(input);

  return (
    <Sheet open={editing !== null} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full sm:max-w-3xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{isEdit ? t("editTemplate") : t("newTemplate")}</SheetTitle>
          <SheetDescription>{t("editorHint")}</SheetDescription>
        </SheetHeader>

        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 mt-4">
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1 col-span-2">
              <Label>{t("col.name")}</Label>
              <Input {...form.register("name")} required />
            </div>
            <div className="space-y-1">
              <Label>{t("col.language")}</Label>
              <Select
                value={form.watch("language")}
                onValueChange={(v) =>
                  form.setValue("language", v as FormInput["language"])
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="de">DE</SelectItem>
                  <SelectItem value="fr">FR</SelectItem>
                  <SelectItem value="it">IT</SelectItem>
                  <SelectItem value="en">EN</SelectItem>
                  <SelectItem value="tr">TR</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3 items-end">
            <div className="space-y-1">
              <Label>{t("col.type")}</Label>
              <Select
                value={tplType}
                onValueChange={(v) => {
                  form.setValue("template_type", v as TemplateType);
                  if (!form.formState.dirtyFields.body_format) {
                    form.setValue("body_format", DEFAULT_BODY_BY_TYPE[v as TemplateType]);
                  }
                }}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="customer_receipt">
                    {t("type.customerReceipt")}
                  </SelectItem>
                  <SelectItem value="kitchen_ticket">
                    {t("type.kitchenTicket")}
                  </SelectItem>
                  <SelectItem value="z_report">{t("type.zReport")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>{t("col.width")}</Label>
              <Select
                value={String(widthMM)}
                onValueChange={(v) =>
                  form.setValue("width_mm", Number(v) as 58 | 80)
                }
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="58">58mm (32 char)</SelectItem>
                  <SelectItem value="80">80mm (48 char)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-center gap-2">
              <Switch
                checked={form.watch("is_default")}
                onCheckedChange={(v) => form.setValue("is_default", v)}
              />
              <Label>{t("setAsDefault")}</Label>
            </div>
          </div>

          <div className="space-y-1">
            <Label>{t("variables")}</Label>
            <div className="flex flex-wrap gap-1">
              {vars.map((v) => (
                <button
                  key={v}
                  type="button"
                  onClick={() => insertVar("body_format", v)}
                  className="font-mono text-[11px] px-2 py-0.5 rounded border bg-muted hover:bg-muted/70"
                >
                  {v}
                </button>
              ))}
            </div>
            <p className="text-[11px] text-muted-foreground">{t("variablesHint")}</p>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-3">
              <div className="space-y-1">
                <Label>{t("section.header")}</Label>
                <textarea
                  rows={2}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                  {...form.register("header")}
                />
              </div>
              <div className="space-y-1">
                <Label>{t("section.body")}</Label>
                <textarea
                  rows={10}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                  {...form.register("body_format")}
                />
              </div>
              <div className="space-y-1">
                <Label>{t("section.footer")}</Label>
                <textarea
                  rows={2}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                  {...form.register("footer")}
                />
              </div>
            </div>

            <div className="space-y-1">
              <Label>
                {t("preview")} ({widthChars} char)
              </Label>
              <div
                className="rounded-md border border-dashed bg-muted/30 p-3 font-mono text-[11px] whitespace-pre-wrap leading-snug"
                style={{ maxWidth: `${widthChars * 0.62}em` }}
              >
                {[previewText(header), previewText(body), previewText(footer)]
                  .filter(Boolean)
                  .join("\n")}
              </div>
              <p className="text-[10px] text-muted-foreground">{t("previewHint")}</p>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3 pt-2 border-t">
            <div className="flex items-center gap-2">
              <Switch
                checked={form.watch("paper_cut")}
                onCheckedChange={(v) => form.setValue("paper_cut", v)}
              />
              <Label className="text-xs">{t("paperCut")}</Label>
            </div>
            <div className="flex items-center gap-2">
              <Switch
                checked={form.watch("open_drawer")}
                onCheckedChange={(v) => form.setValue("open_drawer", v)}
              />
              <Label className="text-xs">{t("openDrawer")}</Label>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">{t("copies")}</Label>
              <Input
                type="number"
                min={1}
                max={5}
                {...form.register("copies", { valueAsNumber: true })}
              />
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-3 border-t">
            <Button type="button" variant="outline" onClick={onClose}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={upsertMut.isPending}>
              {upsertMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              {tCommon("save")}
            </Button>
          </div>
        </form>
      </SheetContent>
    </Sheet>
  );
}
