"use client";

/**
 * Eşik Uyarıları — list + CRUD + test trigger + log viewer.
 *
 * Six alert types, each with a small per-type config:
 *   sales_drop        → { percent }
 *   stockout_count    → { count }
 *   online_ack_delay  → { minutes }
 *   revenue_target    → { amount_cents }
 *   refund_spike      → { count_today }
 *   failed_payments   → { count_today }
 *
 * Server enforces cooldown. "Test" button bypasses cooldown so operators
 * can verify the rule fires without waiting.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Plus,
  Edit,
  Trash2,
  TestTube2,
  CheckCircle2,
  XCircle,
  AlertTriangle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import type { ThresholdAlertRow, AlertLogRow } from "@/lib/server-data";

const ALERT_TYPES = [
  { value: "sales_drop", labelKey: "typeSalesDrop", configKey: "percent", configHintKey: "configPercent" },
  { value: "stockout_count", labelKey: "typeStockout", configKey: "count", configHintKey: "configCount" },
  { value: "online_ack_delay", labelKey: "typeOnlineAckDelay", configKey: "minutes", configHintKey: "configMinutes" },
  { value: "revenue_target", labelKey: "typeRevenueTarget", configKey: "amount_cents", configHintKey: "configAmountCents" },
  { value: "refund_spike", labelKey: "typeRefundSpike", configKey: "count_today", configHintKey: "configCountToday" },
  { value: "failed_payments", labelKey: "typeFailedPayments", configKey: "count_today", configHintKey: "configCountToday" },
] as const;

const LOCALES = ["tr", "de", "en", "fr", "it"] as const;

export function AlertsClient({
  initialAlerts,
  initialLogs,
  defaultRecipient,
}: {
  initialAlerts: ThresholdAlertRow[];
  initialLogs: AlertLogRow[];
  defaultRecipient: string;
}) {
  const t = useTranslations("alerts");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<ThresholdAlertRow | null>(null);
  const [confirmDelete, setConfirmDelete] =
    React.useState<ThresholdAlertRow | null>(null);

  const { data: alerts = initialAlerts } = useQuery({
    queryKey: ["threshold-alerts"],
    queryFn: async () => {
      const r = await clientFetch<{ data: ThresholdAlertRow[] }>({
        path: "/reporting/alerts",
      });
      return r?.data ?? [];
    },
    initialData: initialAlerts,
  });

  const { data: logs = initialLogs } = useQuery({
    queryKey: ["alert-logs"],
    queryFn: async () => {
      const r = await clientFetch<{ data: AlertLogRow[] }>({
        path: "/reporting/alerts/logs?limit=50",
      });
      return r?.data ?? [];
    },
    initialData: initialLogs,
    refetchInterval: 30_000,
  });

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["threshold-alerts"] });
    qc.invalidateQueries({ queryKey: ["alert-logs"] });
  };

  const testMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/reporting/alerts/${id}/test`, method: "POST" }),
    onSuccess: () => {
      toast({ title: t("testDispatched") });
      refresh();
    },
    onError: (e: Error) =>
      toast({
        title: t("testError"),
        description: e.message,
        variant: "destructive",
      }),
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/reporting/alerts/${id}`, method: "DELETE" }),
    onSuccess: () => {
      toast({ title: t("deleteSuccess") });
      refresh();
      setConfirmDelete(null);
    },
    onError: (e: Error) =>
      toast({
        title: t("deleteError"),
        description: e.message,
        variant: "destructive",
      }),
  });

  const toggleMut = useMutation({
    mutationFn: (row: ThresholdAlertRow) =>
      clientFetch({
        path: `/reporting/alerts/${row.id}`,
        method: "PUT",
        body: {
          name: row.name,
          alert_type: row.alert_type,
          threshold: row.threshold,
          recipients_emails: row.recipients_emails,
          cooldown_minutes: row.cooldown_minutes,
          locale: row.locale,
          is_active: !row.is_active,
        },
      }),
    onSuccess: () => refresh(),
  });

  return (
    <Tabs defaultValue="list" className="space-y-4">
      <TabsList>
        <TabsTrigger value="list">{t("tabList")}</TabsTrigger>
        <TabsTrigger value="logs">{t("tabLogs")}</TabsTrigger>
      </TabsList>

      <TabsContent value="list" className="space-y-4">
        <div className="flex justify-end">
          <Button
            onClick={() => {
              setEditing(null);
              setFormOpen(true);
            }}
            className="gap-2"
          >
            <Plus className="h-4 w-4" />
            {t("addAlert")}
          </Button>
        </div>

        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("colName")}</TableHead>
                <TableHead>{t("colType")}</TableHead>
                <TableHead>{t("colThreshold")}</TableHead>
                <TableHead>{t("colRecipients")}</TableHead>
                <TableHead>{t("colCooldown")}</TableHead>
                <TableHead>{t("colLastTriggered")}</TableHead>
                <TableHead>{t("colActive")}</TableHead>
                <TableHead className="text-right">{t("colActions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {alerts.length === 0 && (
                <TableRow>
                  <TableCell
                    colSpan={8}
                    className="text-center text-muted-foreground py-8"
                  >
                    {t("emptyState")}
                  </TableCell>
                </TableRow>
              )}
              {alerts.map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="font-medium">{a.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className="text-xs">
                      {t(alertTypeLabelKey(a.alert_type))}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-sm font-mono text-muted-foreground">
                    {summarizeThreshold(a.alert_type, a.threshold)}
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground max-w-xs truncate">
                    {a.recipients_emails.join(", ") || "—"}
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {a.cooldown_minutes}m
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {a.last_triggered_at
                      ? new Date(a.last_triggered_at).toLocaleString()
                      : "—"}
                  </TableCell>
                  <TableCell>
                    <Switch
                      checked={a.is_active}
                      onCheckedChange={() => toggleMut.mutate(a)}
                    />
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={t("test")}
                        title={t("test")}
                        onClick={() => testMut.mutate(a.id)}
                        disabled={testMut.isPending}
                      >
                        <TestTube2 className="h-4 w-4" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={t("edit")}
                        title={t("edit")}
                        onClick={() => {
                          setEditing(a);
                          setFormOpen(true);
                        }}
                      >
                        <Edit className="h-4 w-4" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={t("delete")}
                        title={t("delete")}
                        onClick={() => setConfirmDelete(a)}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </TabsContent>

      <TabsContent value="logs">
        <AlertLogsTable logs={logs} />
      </TabsContent>

      <AlertFormDialog
        open={formOpen}
        onOpenChange={setFormOpen}
        initial={editing}
        defaultRecipient={defaultRecipient}
        onSaved={() => {
          setFormOpen(false);
          refresh();
        }}
      />

      <AlertDialog
        open={!!confirmDelete}
        onOpenChange={(open) => !open && setConfirmDelete(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("deleteTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("deleteBody", { name: confirmDelete?.name ?? "" })}
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
    </Tabs>
  );
}

function alertTypeLabelKey(typ: string): string {
  return ALERT_TYPES.find((a) => a.value === typ)?.labelKey ?? "typeSalesDrop";
}

function summarizeThreshold(typ: string, th: Record<string, unknown>): string {
  switch (typ) {
    case "sales_drop":
      return `≥ ${th.percent ?? "?"}%`;
    case "stockout_count":
      return `≥ ${th.count ?? "?"}`;
    case "online_ack_delay":
      return `> ${th.minutes ?? "?"} min`;
    case "revenue_target": {
      const cents = Number(th.amount_cents ?? 0);
      return `< CHF ${(cents / 100).toFixed(2)}`;
    }
    case "refund_spike":
    case "failed_payments":
      return `≥ ${th.count_today ?? "?"} /gün`;
    default:
      return "";
  }
}

// =============================================================================
// CRUD dialog
// =============================================================================

function AlertFormDialog({
  open,
  onOpenChange,
  initial,
  defaultRecipient,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: ThresholdAlertRow | null;
  defaultRecipient: string;
  onSaved: () => void;
}) {
  const t = useTranslations("alerts");
  const tCommon = useTranslations("common");
  const { toast } = useToast();

  const [name, setName] = React.useState("");
  const [alertType, setAlertType] = React.useState<string>("sales_drop");
  const [thresholdValue, setThresholdValue] = React.useState<string>("20");
  const [recipientsRaw, setRecipientsRaw] = React.useState("");
  const [cooldown, setCooldown] = React.useState("60");
  const [emailLocale, setEmailLocale] = React.useState("tr");
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (open) {
      if (initial) {
        setName(initial.name);
        setAlertType(initial.alert_type);
        setThresholdValue(extractThresholdValue(initial.alert_type, initial.threshold));
        setRecipientsRaw(initial.recipients_emails.join(", "));
        setCooldown(String(initial.cooldown_minutes));
        setEmailLocale(initial.locale);
      } else {
        setName(t("defaultName"));
        setAlertType("sales_drop");
        setThresholdValue("20");
        setRecipientsRaw(defaultRecipient);
        setCooldown("60");
        setEmailLocale("tr");
      }
    }
  }, [open, initial, defaultRecipient, t]);

  const meta = ALERT_TYPES.find((a) => a.value === alertType)!;
  const isEdit = !!initial;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const recipients = recipientsRaw
        .split(/[,;\n]/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0);

      const num = parseFloat(thresholdValue);
      const threshold: Record<string, number> = {};
      threshold[meta.configKey] = isNaN(num) ? 0 : num;

      const body = {
        name,
        alert_type: alertType,
        threshold,
        recipients_emails: recipients,
        cooldown_minutes: parseInt(cooldown, 10) || 60,
        locale: emailLocale,
      };

      if (isEdit && initial) {
        await clientFetch({
          path: `/reporting/alerts/${initial.id}`,
          method: "PUT",
          body,
        });
        toast({ title: t("updateSuccess") });
      } else {
        await clientFetch({
          path: "/reporting/alerts",
          method: "POST",
          body,
        });
        toast({ title: t("createSuccess") });
      }
      onSaved();
    } catch (err) {
      toast({
        title: t("saveError"),
        description: (err as Error).message,
        variant: "destructive",
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{isEdit ? t("editAlert") : t("addAlert")}</DialogTitle>
            <DialogDescription>
              {isEdit ? t("editSubtitle") : t("addSubtitle")}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-3">
            <div className="space-y-1">
              <Label htmlFor="a-name">{t("colName")}</Label>
              <Input
                id="a-name"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>

            <div className="space-y-1">
              <Label htmlFor="a-type">{t("colType")}</Label>
              <Select
                value={alertType}
                onValueChange={(v) => {
                  setAlertType(v);
                  setThresholdValue(defaultThresholdFor(v));
                }}
              >
                <SelectTrigger id="a-type">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ALERT_TYPES.map((at) => (
                    <SelectItem key={at.value} value={at.value}>
                      {t(at.labelKey)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1">
              <Label htmlFor="a-thr">
                {t("colThreshold")} ({meta.configKey})
              </Label>
              <Input
                id="a-thr"
                type="number"
                value={thresholdValue}
                onChange={(e) => setThresholdValue(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">{t(meta.configHintKey)}</p>
            </div>

            <div className="space-y-1">
              <Label htmlFor="a-recip">{t("colRecipients")}</Label>
              <Input
                id="a-recip"
                value={recipientsRaw}
                onChange={(e) => setRecipientsRaw(e.target.value)}
                placeholder="manager@example.com, owner@example.com"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label htmlFor="a-cd">{t("colCooldown")}</Label>
                <Input
                  id="a-cd"
                  type="number"
                  min="0"
                  value={cooldown}
                  onChange={(e) => setCooldown(e.target.value)}
                />
                <p className="text-xs text-muted-foreground">{t("cooldownHint")}</p>
              </div>
              <div className="space-y-1">
                <Label htmlFor="a-loc">{t("colLocale")}</Label>
                <Select value={emailLocale} onValueChange={setEmailLocale}>
                  <SelectTrigger id="a-loc">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {LOCALES.map((l) => (
                      <SelectItem key={l} value={l}>
                        {l.toUpperCase()}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={submitting}>
              {submitting ? tCommon("loading") : tCommon("save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function defaultThresholdFor(typ: string): string {
  switch (typ) {
    case "sales_drop":
      return "20";
    case "stockout_count":
      return "5";
    case "online_ack_delay":
      return "10";
    case "revenue_target":
      return "100000"; // CHF 1000.00 in cents
    case "refund_spike":
    case "failed_payments":
      return "5";
    default:
      return "0";
  }
}

function extractThresholdValue(typ: string, th: Record<string, unknown>): string {
  const key = ALERT_TYPES.find((a) => a.value === typ)?.configKey;
  if (!key) return "0";
  const v = th[key];
  return v == null ? defaultThresholdFor(typ) : String(v);
}

// =============================================================================
// Logs table
// =============================================================================

function AlertLogsTable({ logs }: { logs: AlertLogRow[] }) {
  const t = useTranslations("alerts");
  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("logColTime")}</TableHead>
            <TableHead>{t("logColMessage")}</TableHead>
            <TableHead>{t("logColValue")}</TableHead>
            <TableHead>{t("logColRecipients")}</TableHead>
            <TableHead>{t("logColStatus")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {logs.length === 0 && (
            <TableRow>
              <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                {t("logEmpty")}
              </TableCell>
            </TableRow>
          )}
          {logs.map((l) => (
            <TableRow key={l.id}>
              <TableCell className="text-sm whitespace-nowrap">
                {new Date(l.triggered_at).toLocaleString()}
              </TableCell>
              <TableCell className="text-sm">{l.message}</TableCell>
              <TableCell className="font-mono text-sm">
                {l.value != null ? l.value.toFixed(2) : "—"}
              </TableCell>
              <TableCell className="text-sm text-muted-foreground">
                {l.sent_to.length || 0}
              </TableCell>
              <TableCell><AlertStatusPill status={l.status} /></TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function AlertStatusPill({ status }: { status: string }) {
  const t = useTranslations("alerts");
  if (status === "fired")
    return (
      <Badge className="bg-amber-500/15 text-amber-700 border-amber-500/30 hover:bg-amber-500/20">
        <AlertTriangle className="h-3 w-3 mr-1" />
        {t("statusFired")}
      </Badge>
    );
  if (status === "send_failed")
    return (
      <Badge variant="destructive">
        <XCircle className="h-3 w-3 mr-1" />
        {t("statusSendFailed")}
      </Badge>
    );
  if (status === "suppressed_cooldown")
    return (
      <Badge variant="secondary">
        <CheckCircle2 className="h-3 w-3 mr-1" />
        {t("statusSuppressed")}
      </Badge>
    );
  return <Badge variant="secondary">{status}</Badge>;
}
