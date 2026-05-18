"use client";

/**
 * HACCP digital-checklist module — backoffice console.
 *
 * Three tabs surfaced from a single page so the operator can flip
 * between today's pending checklists, the catalogue of templates
 * authored for the tenant, and the open-alerts list. The reports
 * card sits above the tabs so completion-rate is always visible.
 *
 * Wire-format: every call routes through `/api/proxy/api/v1/tasks/*`
 * to the Go backend (see `server/internal/tasks/handlers.go`).
 *
 * HACCP audit-trail rule is enforced server-side: once an instance is
 * completed, the items_data is locked. The UI surfaces this by hiding
 * the Edit button for `is_locked` instances and exposing an
 * append-only Correction note dialog.
 */

import * as React from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, AlertTriangle, CheckCircle2, Clock, Thermometer } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

// ---------------------------------------------------------------------------
// Types — mirror server/internal/tasks/models.go
// ---------------------------------------------------------------------------

type Category = "opening" | "closing" | "temperature" | "cleaning" | "delivery" | "custom";
type ItemType = "checkbox" | "number" | "temperature" | "photo" | "signature" | "text";
type InstanceStatus = "pending" | "in_progress" | "completed" | "missed" | "cancelled";

interface ItemValidation {
  min?: number;
  max?: number;
  unit?: string;
}

interface TemplateItem {
  id: string;
  type: ItemType;
  label: Record<string, string>;
  required: boolean;
  validation?: ItemValidation;
}

interface TaskTemplate {
  id: string;
  tenant_id: string;
  name: string;
  name_jsonb?: Record<string, string>;
  description?: string;
  category: Category;
  schedule_cron: string;
  items_jsonb: TemplateItem[] | string; // server returns raw json
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

interface TaskInstance {
  id: string;
  template_id: string;
  tenant_id: string;
  scheduled_for: string;
  status: InstanceStatus;
  items_data_jsonb: unknown;
  completed_at?: string;
  is_locked: boolean;
  template?: TaskTemplate;
}

interface TaskAlert {
  id: string;
  instance_id: string;
  alert_type: "out_of_range" | "missing" | "late" | "validation_failed";
  message: string;
  severity: "info" | "warn" | "critical";
  created_at: string;
  resolved_at?: string;
}

interface ReportSummary {
  window_days: number;
  total_instances: number;
  completed: number;
  missed: number;
  open: number;
  completion_rate: number;
  alerts_by_type: Record<string, number>;
}

interface ListEnvelope<T> {
  data?: T[];
  items?: T[];
}

function unwrap<T>(payload: unknown): T[] {
  if (!payload) return [];
  if (Array.isArray(payload)) return payload as T[];
  const env = payload as ListEnvelope<T>;
  return env.data ?? env.items ?? [];
}

function safeItems(t: TaskTemplate): TemplateItem[] {
  const raw = t.items_jsonb;
  if (Array.isArray(raw)) return raw as TemplateItem[];
  if (typeof raw === "string") {
    try {
      return JSON.parse(raw) as TemplateItem[];
    } catch {
      return [];
    }
  }
  return [];
}

// ---------------------------------------------------------------------------
// TasksClient — top-level component
// ---------------------------------------------------------------------------

export function TasksClient({ locale }: { locale: string }) {
  const t = useTranslations("tasksModule");
  const router = useRouter();
  const search = useSearchParams();
  const tab = (search.get("tab") as "today" | "templates" | "alerts" | "reports") ?? "today";

  const setTab = (next: string) => {
    const params = new URLSearchParams(search?.toString());
    if (next === "today") {
      params.delete("tab");
    } else {
      params.set("tab", next);
    }
    const qs = params.toString();
    router.replace(`/${locale}/operations/tasks${qs ? `?${qs}` : ""}`);
  };

  return (
    <div className="space-y-6">
      <ReportCard />
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="today">{t("tabToday")}</TabsTrigger>
          <TabsTrigger value="templates">{t("tabTemplates")}</TabsTrigger>
          <TabsTrigger value="alerts">{t("tabAlerts")}</TabsTrigger>
        </TabsList>
        <TabsContent value="today" className="mt-4">
          <TodayTab locale={locale} />
        </TabsContent>
        <TabsContent value="templates" className="mt-4">
          <TemplatesTab locale={locale} />
        </TabsContent>
        <TabsContent value="alerts" className="mt-4">
          <AlertsTab />
        </TabsContent>
      </Tabs>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Reports — summary card
// ---------------------------------------------------------------------------

function ReportCard() {
  const t = useTranslations("tasksModule");
  const { data } = useQuery<ReportSummary>({
    queryKey: ["tasks", "report-summary"],
    queryFn: async () => clientFetch<ReportSummary>({ path: "/api/v1/tasks/reports/summary?days=7" }),
    refetchInterval: 60_000,
  });
  const rate = data ? Math.round(data.completion_rate * 100) : 0;
  const tone = rate >= 90 ? "text-emerald-600" : rate >= 70 ? "text-amber-600" : "text-rose-600";
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <CheckCircle2 className="h-4 w-4" /> {t("reportSummaryTitle")}
        </CardTitle>
        <CardDescription>{t("reportSummaryHint")}</CardDescription>
      </CardHeader>
      <CardContent className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <Metric label={t("metricCompletionRate")} value={`${rate}%`} className={tone} />
        <Metric label={t("metricCompleted")} value={data?.completed ?? "—"} />
        <Metric label={t("metricMissed")} value={data?.missed ?? "—"} />
        <Metric
          label={t("metricOpenAlerts")}
          value={
            data
              ? Object.values(data.alerts_by_type).reduce((s, n) => s + n, 0)
              : "—"
          }
        />
      </CardContent>
    </Card>
  );
}

function Metric({
  label,
  value,
  className,
}: {
  label: string;
  value: React.ReactNode;
  className?: string;
}) {
  return (
    <div className="space-y-1">
      <div className="text-xs text-muted-foreground uppercase tracking-wide">{label}</div>
      <div className={`text-2xl font-semibold ${className ?? ""}`}>{value}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Today tab — instances scheduled for the current day
// ---------------------------------------------------------------------------

function TodayTab({ locale }: { locale: string }) {
  const t = useTranslations("tasksModule");
  const { data, isLoading } = useQuery<TaskInstance[]>({
    queryKey: ["tasks", "today"],
    queryFn: async () =>
      unwrap<TaskInstance>(await clientFetch({ path: "/api/v1/tasks/today" })),
    refetchInterval: 30_000,
  });
  const [active, setActive] = React.useState<TaskInstance | null>(null);

  if (isLoading) {
    return <div className="text-sm text-muted-foreground">{t("loading")}</div>;
  }
  if (!data || data.length === 0) {
    return (
      <Card>
        <CardContent className="py-10 text-center text-sm text-muted-foreground">
          {t("todayEmpty")}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colTemplate")}</TableHead>
              <TableHead>{t("colCategory")}</TableHead>
              <TableHead>{t("colScheduledFor")}</TableHead>
              <TableHead>{t("colStatus")}</TableHead>
              <TableHead className="text-right">{t("colAction")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((inst) => {
              const name =
                inst.template?.name_jsonb?.[locale] ?? inst.template?.name ?? "—";
              return (
                <TableRow key={inst.id}>
                  <TableCell className="font-medium">{name}</TableCell>
                  <TableCell>
                    <CategoryChip cat={inst.template?.category ?? "custom"} />
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {new Date(inst.scheduled_for).toLocaleTimeString(locale, {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </TableCell>
                  <TableCell>
                    <StatusChip status={inst.status} />
                  </TableCell>
                  <TableCell className="text-right">
                    {!inst.is_locked && inst.status !== "completed" ? (
                      <Button size="sm" variant="outline" onClick={() => setActive(inst)}>
                        {t("actionComplete")}
                      </Button>
                    ) : (
                      <Button size="sm" variant="ghost" onClick={() => setActive(inst)}>
                        {t("actionView")}
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </CardContent>
      {active ? (
        <CompleteInstanceDialog
          instance={active}
          locale={locale}
          onClose={() => setActive(null)}
        />
      ) : null}
    </Card>
  );
}

function StatusChip({ status }: { status: InstanceStatus }) {
  const t = useTranslations("tasksModule");
  const map: Record<InstanceStatus, { label: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
    pending: { label: t("statusPending"), variant: "outline" },
    in_progress: { label: t("statusInProgress"), variant: "secondary" },
    completed: { label: t("statusCompleted"), variant: "default" },
    missed: { label: t("statusMissed"), variant: "destructive" },
    cancelled: { label: t("statusCancelled"), variant: "outline" },
  };
  const m = map[status];
  return <Badge variant={m.variant}>{m.label}</Badge>;
}

function CategoryChip({ cat }: { cat: Category }) {
  const t = useTranslations("tasksModule");
  return (
    <Badge variant="outline" className="capitalize">
      {t(`category_${cat}`)}
    </Badge>
  );
}

// ---------------------------------------------------------------------------
// Complete-instance dialog
// ---------------------------------------------------------------------------

function CompleteInstanceDialog({
  instance,
  locale,
  onClose,
}: {
  instance: TaskInstance;
  locale: string;
  onClose: () => void;
}) {
  const t = useTranslations("tasksModule");
  const items = instance.template ? safeItems(instance.template) : [];
  const [values, setValues] = React.useState<Record<string, string>>({});
  const [note, setNote] = React.useState("");
  const { toast } = useToast();
  const qc = useQueryClient();

  const isLocked = instance.is_locked;

  const completeMut = useMutation({
    mutationFn: async () => {
      const payload = {
        items: items.map((it) => ({
          item_id: it.id,
          value: values[it.id] ?? "",
        })),
      };
      return clientFetch({
        path: `/api/v1/tasks/instances/${instance.id}/complete`,
        method: "POST",
        body: payload,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["tasks"] });
      toast({ title: t("toastCompleted") });
      onClose();
    },
    onError: (e: Error) => {
      toast({ title: t("toastError"), description: e.message, variant: "destructive" });
    },
  });

  const correctionMut = useMutation({
    mutationFn: async () =>
      clientFetch({
        path: `/api/v1/tasks/instances/${instance.id}/correction`,
        method: "POST",
        body: { note },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["tasks"] });
      setNote("");
      toast({ title: t("toastCorrectionSaved") });
    },
    onError: (e: Error) => {
      toast({ title: t("toastError"), description: e.message, variant: "destructive" });
    },
  });

  return (
    <Dialog open onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>
            {instance.template?.name_jsonb?.[locale] ?? instance.template?.name ?? "—"}
          </DialogTitle>
          <DialogDescription>
            {new Date(instance.scheduled_for).toLocaleString(locale)} ·{" "}
            <StatusChip status={instance.status} />
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          {items.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("noItems")}</p>
          ) : (
            items.map((it) => (
              <div key={it.id} className="space-y-1">
                <Label className="flex items-center gap-2">
                  {it.label?.[locale] ?? it.label?.de ?? it.label?.en ?? it.id}
                  {it.required ? <span className="text-rose-600">*</span> : null}
                  {it.type === "temperature" ? (
                    <Thermometer className="h-3.5 w-3.5 text-muted-foreground" />
                  ) : null}
                </Label>
                {it.type === "checkbox" ? (
                  <Switch
                    disabled={isLocked}
                    checked={values[it.id] === "true"}
                    onCheckedChange={(v) =>
                      setValues((s) => ({ ...s, [it.id]: v ? "true" : "false" }))
                    }
                  />
                ) : (
                  <Input
                    disabled={isLocked}
                    type={it.type === "temperature" || it.type === "number" ? "number" : "text"}
                    step={it.type === "temperature" ? "0.1" : undefined}
                    value={values[it.id] ?? ""}
                    onChange={(e) => setValues((s) => ({ ...s, [it.id]: e.target.value }))}
                    placeholder={
                      it.validation
                        ? `${it.validation.min ?? ""}–${it.validation.max ?? ""} ${it.validation.unit ?? ""}`
                        : ""
                    }
                  />
                )}
              </div>
            ))
          )}
          {isLocked ? (
            <div className="space-y-1 pt-3 border-t">
              <Label>{t("correctionNoteLabel")}</Label>
              <Input
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder={t("correctionNotePlaceholder")}
              />
              <p className="text-xs text-muted-foreground">{t("correctionNoteHelp")}</p>
            </div>
          ) : null}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            {t("close")}
          </Button>
          {isLocked ? (
            <Button
              disabled={!note.trim() || correctionMut.isPending}
              onClick={() => correctionMut.mutate()}
            >
              {t("submitCorrection")}
            </Button>
          ) : (
            <Button disabled={completeMut.isPending} onClick={() => completeMut.mutate()}>
              {t("submitComplete")}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Templates tab
// ---------------------------------------------------------------------------

function TemplatesTab({ locale }: { locale: string }) {
  const t = useTranslations("tasksModule");
  const qc = useQueryClient();
  const { toast } = useToast();
  const [editing, setEditing] = React.useState<TaskTemplate | "new" | null>(null);

  const { data, isLoading } = useQuery<TaskTemplate[]>({
    queryKey: ["tasks", "templates"],
    queryFn: async () =>
      unwrap<TaskTemplate>(await clientFetch({ path: "/api/v1/tasks/templates" })),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/api/v1/tasks/templates/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["tasks"] });
      toast({ title: t("toastDeleted") });
    },
    onError: (e: Error) => toast({ title: t("toastError"), description: e.message, variant: "destructive" }),
  });

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <div>
          <CardTitle>{t("templatesTitle")}</CardTitle>
          <CardDescription>{t("templatesHint")}</CardDescription>
        </div>
        <Button onClick={() => setEditing("new")}>
          <Plus className="h-4 w-4 mr-1" /> {t("newTemplate")}
        </Button>
      </CardHeader>
      <CardContent className="p-0">
        {isLoading ? (
          <div className="p-6 text-sm text-muted-foreground">{t("loading")}</div>
        ) : data && data.length > 0 ? (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("colName")}</TableHead>
                <TableHead>{t("colCategory")}</TableHead>
                <TableHead>{t("colSchedule")}</TableHead>
                <TableHead>{t("colItems")}</TableHead>
                <TableHead>{t("colActive")}</TableHead>
                <TableHead className="text-right">{t("colAction")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.map((tpl) => {
                const name = tpl.name_jsonb?.[locale] ?? tpl.name;
                return (
                  <TableRow key={tpl.id}>
                    <TableCell className="font-medium">{name}</TableCell>
                    <TableCell>
                      <CategoryChip cat={tpl.category} />
                    </TableCell>
                    <TableCell className="font-mono text-xs">{tpl.schedule_cron}</TableCell>
                    <TableCell>{safeItems(tpl).length}</TableCell>
                    <TableCell>
                      {tpl.is_active ? (
                        <Badge variant="default">{t("active")}</Badge>
                      ) : (
                        <Badge variant="outline">{t("inactive")}</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-right space-x-2">
                      <Button size="sm" variant="ghost" onClick={() => setEditing(tpl)}>
                        {t("edit")}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-rose-600"
                        onClick={() => {
                          if (confirm(t("confirmDelete"))) deleteMut.mutate(tpl.id);
                        }}
                      >
                        {t("delete")}
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        ) : (
          <div className="p-6 text-sm text-muted-foreground">{t("templatesEmpty")}</div>
        )}
      </CardContent>
      {editing ? (
        <TemplateEditorDialog
          template={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
        />
      ) : null}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Template editor dialog
// ---------------------------------------------------------------------------

function TemplateEditorDialog({
  template,
  onClose,
}: {
  template: TaskTemplate | null;
  onClose: () => void;
}) {
  const t = useTranslations("tasksModule");
  const qc = useQueryClient();
  const { toast } = useToast();

  const initialItems: TemplateItem[] = template ? safeItems(template) : [];
  const [name, setName] = React.useState(template?.name ?? "");
  const [category, setCategory] = React.useState<Category>(template?.category ?? "custom");
  const [scheduleCron, setScheduleCron] = React.useState(template?.schedule_cron ?? "0 6 * * *");
  const [isActive, setIsActive] = React.useState(template?.is_active ?? true);
  const [items, setItems] = React.useState<TemplateItem[]>(initialItems);

  const upsertMut = useMutation({
    mutationFn: async () => {
      const payload = {
        name,
        category,
        schedule_cron: scheduleCron,
        is_active: isActive,
        items_jsonb: items,
      };
      if (template) {
        return clientFetch({
          path: `/api/v1/tasks/templates/${template.id}`,
          method: "PUT",
          body: payload,
        });
      }
      return clientFetch({
        path: `/api/v1/tasks/templates`,
        method: "POST",
        body: payload,
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["tasks"] });
      toast({ title: t("toastSaved") });
      onClose();
    },
    onError: (e: Error) => toast({ title: t("toastError"), description: e.message, variant: "destructive" }),
  });

  const addItem = () =>
    setItems((s) => [
      ...s,
      {
        id: `i${s.length + 1}`,
        type: "checkbox",
        label: { de: "", en: "" },
        required: true,
      },
    ]);

  return (
    <Dialog open onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{template ? t("editTemplate") : t("newTemplate")}</DialogTitle>
          <DialogDescription>{t("templateEditorHint")}</DialogDescription>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("fieldName")}</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>{t("fieldCategory")}</Label>
              <Select value={category} onValueChange={(v) => setCategory(v as Category)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(["opening", "closing", "temperature", "cleaning", "delivery", "custom"] as Category[]).map((c) => (
                    <SelectItem key={c} value={c}>
                      {t(`category_${c}`)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>{t("fieldSchedule")}</Label>
              <Input
                value={scheduleCron}
                onChange={(e) => setScheduleCron(e.target.value)}
                className="font-mono"
              />
              <p className="text-xs text-muted-foreground">{t("scheduleHint")}</p>
            </div>
            <div className="space-y-1">
              <Label>{t("fieldActive")}</Label>
              <Switch checked={isActive} onCheckedChange={setIsActive} />
            </div>
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label>{t("itemsLabel")}</Label>
              <Button size="sm" variant="outline" onClick={addItem}>
                <Plus className="h-3 w-3 mr-1" /> {t("addItem")}
              </Button>
            </div>
            {items.length === 0 ? (
              <p className="text-xs text-muted-foreground">{t("itemsEmpty")}</p>
            ) : (
              <div className="space-y-2">
                {items.map((it, idx) => (
                  <div key={it.id} className="border rounded p-2 space-y-2">
                    <div className="grid grid-cols-3 gap-2">
                      <Input
                        placeholder={t("itemId")}
                        value={it.id}
                        onChange={(e) => {
                          const next = [...items];
                          next[idx] = { ...it, id: e.target.value };
                          setItems(next);
                        }}
                      />
                      <Select
                        value={it.type}
                        onValueChange={(v) => {
                          const next = [...items];
                          next[idx] = { ...it, type: v as ItemType };
                          setItems(next);
                        }}
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {(["checkbox", "number", "temperature", "photo", "signature", "text"] as ItemType[]).map((tp) => (
                            <SelectItem key={tp} value={tp}>
                              {tp}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <div className="flex items-center gap-2">
                        <Switch
                          checked={it.required}
                          onCheckedChange={(v) => {
                            const next = [...items];
                            next[idx] = { ...it, required: v };
                            setItems(next);
                          }}
                        />
                        <span className="text-xs">{t("required")}</span>
                      </div>
                    </div>
                    <Input
                      placeholder="DE label"
                      value={it.label?.de ?? ""}
                      onChange={(e) => {
                        const next = [...items];
                        next[idx] = { ...it, label: { ...it.label, de: e.target.value } };
                        setItems(next);
                      }}
                    />
                    <Input
                      placeholder="EN label"
                      value={it.label?.en ?? ""}
                      onChange={(e) => {
                        const next = [...items];
                        next[idx] = { ...it, label: { ...it.label, en: e.target.value } };
                        setItems(next);
                      }}
                    />
                    {(it.type === "temperature" || it.type === "number") ? (
                      <div className="grid grid-cols-3 gap-2">
                        <Input
                          type="number"
                          step="0.1"
                          placeholder={t("min")}
                          value={it.validation?.min ?? ""}
                          onChange={(e) => {
                            const next = [...items];
                            next[idx] = {
                              ...it,
                              validation: {
                                ...it.validation,
                                min: e.target.value === "" ? undefined : Number(e.target.value),
                              },
                            };
                            setItems(next);
                          }}
                        />
                        <Input
                          type="number"
                          step="0.1"
                          placeholder={t("max")}
                          value={it.validation?.max ?? ""}
                          onChange={(e) => {
                            const next = [...items];
                            next[idx] = {
                              ...it,
                              validation: {
                                ...it.validation,
                                max: e.target.value === "" ? undefined : Number(e.target.value),
                              },
                            };
                            setItems(next);
                          }}
                        />
                        <Input
                          placeholder={t("unit")}
                          value={it.validation?.unit ?? ""}
                          onChange={(e) => {
                            const next = [...items];
                            next[idx] = {
                              ...it,
                              validation: { ...it.validation, unit: e.target.value },
                            };
                            setItems(next);
                          }}
                        />
                      </div>
                    ) : null}
                    <Button
                      size="sm"
                      variant="ghost"
                      className="text-rose-600"
                      onClick={() => setItems(items.filter((_, i) => i !== idx))}
                    >
                      {t("removeItem")}
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            {t("cancel")}
          </Button>
          <Button disabled={upsertMut.isPending || !name.trim()} onClick={() => upsertMut.mutate()}>
            {t("save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Alerts tab
// ---------------------------------------------------------------------------

function AlertsTab() {
  const t = useTranslations("tasksModule");
  const qc = useQueryClient();
  const { toast } = useToast();
  const { data, isLoading } = useQuery<TaskAlert[]>({
    queryKey: ["tasks", "alerts"],
    queryFn: async () =>
      unwrap<TaskAlert>(await clientFetch({ path: "/api/v1/tasks/alerts" })),
    refetchInterval: 60_000,
  });

  const resolveMut = useMutation({
    mutationFn: async ({ id, note }: { id: string; note: string }) =>
      clientFetch({
        path: `/api/v1/tasks/alerts/${id}/resolve`,
        method: "POST",
        body: { note },
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["tasks", "alerts"] });
      toast({ title: t("toastResolved") });
    },
    onError: (e: Error) => toast({ title: t("toastError"), description: e.message, variant: "destructive" }),
  });

  if (isLoading) return <div className="text-sm text-muted-foreground">{t("loading")}</div>;
  if (!data || data.length === 0) {
    return (
      <Card>
        <CardContent className="py-10 text-center text-sm text-muted-foreground">
          {t("alertsEmpty")}
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("colSeverity")}</TableHead>
              <TableHead>{t("colType")}</TableHead>
              <TableHead>{t("colMessage")}</TableHead>
              <TableHead>{t("colCreated")}</TableHead>
              <TableHead className="text-right">{t("colAction")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((a) => (
              <TableRow key={a.id}>
                <TableCell>
                  <SeverityChip s={a.severity} />
                </TableCell>
                <TableCell className="text-xs uppercase tracking-wide">{a.alert_type}</TableCell>
                <TableCell className="text-sm">{a.message}</TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {new Date(a.created_at).toLocaleString()}
                </TableCell>
                <TableCell className="text-right">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => {
                      const note = window.prompt(t("resolveNotePrompt"));
                      if (note !== null) resolveMut.mutate({ id: a.id, note });
                    }}
                  >
                    {t("resolve")}
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function SeverityChip({ s }: { s: TaskAlert["severity"] }) {
  if (s === "critical") {
    return (
      <Badge variant="destructive" className="gap-1">
        <AlertTriangle className="h-3 w-3" /> critical
      </Badge>
    );
  }
  if (s === "warn") {
    return (
      <Badge className="bg-amber-100 text-amber-900 hover:bg-amber-100">
        <Clock className="h-3 w-3 mr-1" /> warn
      </Badge>
    );
  }
  return <Badge variant="outline">info</Badge>;
}
