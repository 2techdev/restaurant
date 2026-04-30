"use client";

/**
 * Receipt templates — UI only (in-memory).
 *
 * Backend `/api/v1/restaurant/receipt-templates` not wired yet. Templates are
 * persisted to localStorage so the operator can iterate on the layout with
 * the print/POS team. When the endpoint lands, swap localStorage for a
 * tenant.settings_json mutation; the editor + preview don't need to change.
 *
 * Variables supported in template body:
 *   {{order_no}} {{date}} {{items}} {{total}} {{tax}} {{tenant_name}}
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { Plus, AlertCircle, Trash2, Pencil, Receipt } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Alert, AlertDescription } from "@/components/ui/alert";
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
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";

const STORAGE_KEY = "bo.receiptTemplates.drafts.v1";

interface Template {
  id: string;
  name: string;
  language: string;
  width: "58mm" | "80mm";
  isDefault: boolean;
  header: string;
  body: string;
  footer: string;
}

const VARS = [
  "{{order_no}}",
  "{{date}}",
  "{{items}}",
  "{{total}}",
  "{{tax}}",
  "{{tenant_name}}",
];

const DEFAULT_BODY = `{{tenant_name}}
{{date}}
Sipariş: {{order_no}}
--------------------------------
{{items}}
--------------------------------
Ara Toplam:        {{total}}
KDV:                {{tax}}
================================
Afiyet olsun!`;

function load(): Template[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Template[]) : [];
  } catch {
    return [];
  }
}
function save(items: Template[]) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch {
    // ignore
  }
}

export function ReceiptTemplatesClient() {
  const t = useTranslations("restaurantMgmt.receiptTemplates");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [items, setItems] = React.useState<Template[]>([]);
  const [editing, setEditing] = React.useState<Template | "create" | null>(null);

  React.useEffect(() => {
    setItems(load());
  }, []);

  const persist = (next: Template[]) => {
    setItems(next);
    save(next);
  };

  const onSave = (tpl: Template) => {
    let next: Template[];
    if (editing === "create") {
      next = [...items, tpl];
    } else {
      next = items.map((x) => (x.id === tpl.id ? tpl : x));
    }
    // Ensure at most one default
    if (tpl.isDefault) {
      next = next.map((x) => (x.id === tpl.id ? x : { ...x, isDefault: false }));
    }
    persist(next);
    toast({ title: editing === "create" ? t("createdToast") : t("updatedToast") });
    setEditing(null);
  };

  return (
    <div className="space-y-4">
      <Alert>
        <AlertCircle className="h-4 w-4" />
        <AlertDescription>{t("plannedBackend")}</AlertDescription>
      </Alert>

      <div className="flex justify-end">
        <Button onClick={() => setEditing("create")}>
          <Plus className="h-4 w-4" />
          {t("newTemplate")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 text-sm font-medium">
          {t("listHeader", { count: items.length })}
        </div>
        {items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Receipt className="h-12 w-12 mx-auto text-muted-foreground/50" />
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
                <TableHead className="w-12"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((tpl) => (
                <TableRow key={tpl.id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{tpl.name}</TableCell>
                  <TableCell className="uppercase text-xs">{tpl.language}</TableCell>
                  <TableCell className="font-mono text-xs">{tpl.width}</TableCell>
                  <TableCell>
                    {tpl.isDefault && (
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
                        onClick={() => setEditing(tpl)}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-error"
                        onClick={() => persist(items.filter((x) => x.id !== tpl.id))}
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

      <TemplateEditor
        editing={editing}
        onClose={() => setEditing(null)}
        onSave={onSave}
      />
    </div>
  );
}

function TemplateEditor({
  editing,
  onClose,
  onSave,
}: {
  editing: Template | "create" | null;
  onClose: () => void;
  onSave: (tpl: Template) => void;
}) {
  const t = useTranslations("restaurantMgmt.receiptTemplates");
  const tCommon = useTranslations("common");
  const isEdit = editing && editing !== "create";
  const initial = isEdit ? (editing as Template) : null;

  const [name, setName] = React.useState("");
  const [language, setLanguage] = React.useState("tr");
  const [width, setWidth] = React.useState<"58mm" | "80mm">("58mm");
  const [isDefault, setIsDefault] = React.useState(false);
  const [header, setHeader] = React.useState("");
  const [body, setBody] = React.useState(DEFAULT_BODY);
  const [footer, setFooter] = React.useState("");

  React.useEffect(() => {
    if (initial) {
      setName(initial.name);
      setLanguage(initial.language);
      setWidth(initial.width);
      setIsDefault(initial.isDefault);
      setHeader(initial.header);
      setBody(initial.body);
      setFooter(initial.footer);
    } else {
      setName("");
      setLanguage("tr");
      setWidth("58mm");
      setIsDefault(false);
      setHeader("");
      setBody(DEFAULT_BODY);
      setFooter("");
    }
  }, [editing, initial]);

  const insertVar = (target: "header" | "body" | "footer", v: string) => {
    if (target === "header") setHeader((h) => h + v);
    else if (target === "footer") setFooter((f) => f + v);
    else setBody((b) => b + v);
  };

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    onSave({
      id: initial?.id ?? crypto.randomUUID(),
      name: name.trim(),
      language,
      width,
      isDefault,
      header,
      body,
      footer,
    });
  };

  // Width-aware preview char count (rough guide for thermal printers)
  const widthChars = width === "58mm" ? 32 : 48;
  const previewBody = body
    .replace(/\{\{order_no\}\}/g, "4729")
    .replace(/\{\{date\}\}/g, "30.04.2026 14:32")
    .replace(/\{\{items\}\}/g, "1× Margherita        14.00\n2× Espresso           7.00")
    .replace(/\{\{total\}\}/g, "21.00")
    .replace(/\{\{tax\}\}/g, "1.62")
    .replace(/\{\{tenant_name\}\}/g, "Pizzeria Da Mario");

  return (
    <Sheet open={editing !== null} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full sm:max-w-3xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{isEdit ? t("editTemplate") : t("newTemplate")}</SheetTitle>
          <SheetDescription>{t("editorHint")}</SheetDescription>
        </SheetHeader>

        <form onSubmit={onSubmit} className="space-y-4 mt-4">
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1 col-span-2">
              <Label>{t("col.name")}</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} required />
            </div>
            <div className="space-y-1">
              <Label>{t("col.language")}</Label>
              <Select value={language} onValueChange={setLanguage}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="tr">TR</SelectItem>
                  <SelectItem value="de">DE</SelectItem>
                  <SelectItem value="en">EN</SelectItem>
                  <SelectItem value="fr">FR</SelectItem>
                  <SelectItem value="it">IT</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3 items-end">
            <div className="space-y-1">
              <Label>{t("col.width")}</Label>
              <Select value={width} onValueChange={(v) => setWidth(v as "58mm" | "80mm")}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="58mm">58mm (32 char)</SelectItem>
                  <SelectItem value="80mm">80mm (48 char)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-center gap-2">
              <Switch checked={isDefault} onCheckedChange={setIsDefault} />
              <Label>{t("setAsDefault")}</Label>
            </div>
          </div>

          <div className="space-y-1">
            <div className="flex items-center justify-between">
              <Label>{t("variables")}</Label>
            </div>
            <div className="flex flex-wrap gap-1">
              {VARS.map((v) => (
                <button
                  key={v}
                  type="button"
                  onClick={() => insertVar("body", v)}
                  className="font-mono text-[11px] px-2 py-0.5 rounded border bg-muted hover:bg-muted/70"
                >
                  {v}
                </button>
              ))}
            </div>
            <p className="text-[11px] text-muted-foreground">{t("variablesHint")}</p>
          </div>

          <div className="grid grid-cols-2 gap-4">
            {/* Editor */}
            <div className="space-y-3">
              <div className="space-y-1">
                <Label>{t("section.header")}</Label>
                <textarea
                  rows={2}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                  value={header}
                  onChange={(e) => setHeader(e.target.value)}
                />
              </div>
              <div className="space-y-1">
                <Label>{t("section.body")}</Label>
                <textarea
                  rows={10}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                />
              </div>
              <div className="space-y-1">
                <Label>{t("section.footer")}</Label>
                <textarea
                  rows={2}
                  className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono"
                  value={footer}
                  onChange={(e) => setFooter(e.target.value)}
                />
              </div>
            </div>

            {/* Preview */}
            <div className="space-y-1">
              <Label>{t("preview")} ({widthChars} char)</Label>
              <div
                className="rounded-md border border-dashed bg-muted/30 p-3 font-mono text-[11px] whitespace-pre-wrap leading-snug"
                style={{ maxWidth: `${widthChars * 0.62}em` }}
              >
                {[header, previewBody, footer].filter(Boolean).join("\n")}
              </div>
              <p className="text-[10px] text-muted-foreground">{t("previewHint")}</p>
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-3 border-t">
            <Button type="button" variant="outline" onClick={onClose}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit">{tCommon("save")}</Button>
          </div>
        </form>
      </SheetContent>
    </Sheet>
  );
}
