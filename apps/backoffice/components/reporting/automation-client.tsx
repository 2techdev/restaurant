"use client";

/**
 * Otomatik Raporlar — list + CRUD + manual send + log viewer.
 *
 * Backed by /api/v1/reporting/scheduled (CRUD + send-now) and
 *           /api/v1/reporting/logs   (recent send results).
 *
 * Operators pick a frequency from preset buttons (daily 23:59, weekly Mon
 * 09:00, monthly 1st 09:00) or paste a raw cron expression. Recipients are
 * a multi-email input, locale defaults to the page locale.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Plus,
  Edit,
  Trash2,
  Play,
  CheckCircle2,
  XCircle,
  Mail,
  Eye,
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
import type { ScheduledReportRow, ReportLogRow } from "@/lib/server-data";

const REPORT_TYPES = [
  { value: "daily_digest", labelKey: "typeDailyDigest" },
  { value: "sales_summary", labelKey: "typeSalesSummary" },
  { value: "hourly_sales", labelKey: "typeHourlySales" },
  { value: "staff_performance", labelKey: "typeStaffPerformance" },
  { value: "inventory_health", labelKey: "typeInventoryHealth" },
  { value: "customer_activity", labelKey: "typeCustomerActivity" },
] as const;

const SCHEDULE_PRESETS = [
  { value: "59 23 * * *", labelKey: "presetDaily" },
  { value: "0 9 * * 1", labelKey: "presetWeeklyMon" },
  { value: "0 9 1 * *", labelKey: "presetMonthly1st" },
  { value: "0 8 * * *", labelKey: "presetDailyMorning" },
] as const;

const FORMATS = [
  { value: "html", labelKey: "formatHtml" },
  { value: "pdf", labelKey: "formatPdf" },
  { value: "csv", labelKey: "formatCsv" },
] as const;

const LOCALES = ["tr", "de", "en", "fr", "it"] as const;

export function AutomationClient({
  initialReports,
  initialLogs,
  locale,
  defaultRecipient,
}: {
  initialReports: ScheduledReportRow[];
  initialLogs: ReportLogRow[];
  locale: string;
  defaultRecipient: string;
}) {
  const t = useTranslations("automation");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const [formOpen, setFormOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<ScheduledReportRow | null>(null);
  const [confirmDelete, setConfirmDelete] =
    React.useState<ScheduledReportRow | null>(null);
  const [previewURL, setPreviewURL] = React.useState<string | null>(null);

  const { data: reports = initialReports } = useQuery({
    queryKey: ["scheduled-reports"],
    queryFn: async () => {
      const r = await clientFetch<{ data: ScheduledReportRow[] }>({
        path: "/reporting/scheduled",
      });
      return r?.data ?? [];
    },
    initialData: initialReports,
  });

  const { data: logs = initialLogs } = useQuery({
    queryKey: ["report-logs"],
    queryFn: async () => {
      const r = await clientFetch<{ data: ReportLogRow[] }>({
        path: "/reporting/logs?limit=50",
      });
      return r?.data ?? [];
    },
    initialData: initialLogs,
    refetchInterval: 30_000,
  });

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["scheduled-reports"] });
    qc.invalidateQueries({ queryKey: ["report-logs"] });
  };

  const sendNowMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({
        path: `/reporting/scheduled/${id}/send-now`,
        method: "POST",
      }),
    onSuccess: () => {
      toast({ title: t("sendNowDispatched") });
      refresh();
    },
    onError: (e: Error) =>
      toast({
        title: t("sendNowError"),
        description: e.message,
        variant: "destructive",
      }),
  });

  const deleteMut = useMutation({
    mutationFn: (id: string) =>
      clientFetch({ path: `/reporting/scheduled/${id}`, method: "DELETE" }),
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
    mutationFn: (row: ScheduledReportRow) =>
      clientFetch({
        path: `/reporting/scheduled/${row.id}`,
        method: "PUT",
        body: {
          name: row.name,
          report_type: row.report_type,
          schedule_cron: row.schedule_cron,
          recipients_emails: row.recipients_emails,
          format: row.format,
          filters: row.filters,
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
            {t("addReport")}
          </Button>
        </div>

        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("colName")}</TableHead>
                <TableHead>{t("colType")}</TableHead>
                <TableHead>{t("colSchedule")}</TableHead>
                <TableHead>{t("colRecipients")}</TableHead>
                <TableHead>{t("colNextRun")}</TableHead>
                <TableHead>{t("colLastStatus")}</TableHead>
                <TableHead>{t("colActive")}</TableHead>
                <TableHead className="text-right">{t("colActions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {reports.length === 0 && (
                <TableRow>
                  <TableCell
                    colSpan={8}
                    className="text-center text-muted-foreground py-8"
                  >
                    {t("emptyState")}
                  </TableCell>
                </TableRow>
              )}
              {reports.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline" className="font-mono text-xs">
                      {t(reportTypeLabelKey(r.report_type))}
                    </Badge>
                  </TableCell>
                  <TableCell className="font-mono text-xs">
                    {r.schedule_cron}
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground max-w-xs truncate">
                    {r.recipients_emails.join(", ") || "—"}
                  </TableCell>
                  <TableCell className="text-sm text-muted-foreground">
                    {r.next_run_at
                      ? new Date(r.next_run_at).toLocaleString()
                      : "—"}
                  </TableCell>
                  <TableCell>
                    <StatusPill status={r.last_status} />
                  </TableCell>
                  <TableCell>
                    <Switch
                      checked={r.is_active}
                      onCheckedChange={() => toggleMut.mutate(r)}
                    />
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1">
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={t("sendNow")}
                        title={t("sendNow")}
                        onClick={() => sendNowMut.mutate(r.id)}
                        disabled={sendNowMut.isPending}
                      >
                        <Play className="h-4 w-4" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={t("preview")}
                        title={t("preview")}
                        onClick={() =>
                          setPreviewURL(
                            `/api/v1/reporting/digest/preview?locale=${r.locale}`,
                          )
                        }
                      >
                        <Eye className="h-4 w-4" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={t("edit")}
                        title={t("edit")}
                        onClick={() => {
                          setEditing(r);
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
                        onClick={() => setConfirmDelete(r)}
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
        <LogsTable logs={logs} />
      </TabsContent>

      <ReportFormDialog
        open={formOpen}
        onOpenChange={setFormOpen}
        initial={editing}
        defaultLocale={locale}
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

      <PreviewDialog url={previewURL} onClose={() => setPreviewURL(null)} />
    </Tabs>
  );
}

function reportTypeLabelKey(t: string): string {
  const m = REPORT_TYPES.find((r) => r.value === t);
  return m?.labelKey ?? "typeDailyDigest";
}

function StatusPill({ status }: { status?: string | null }) {
  const t = useTranslations("automation");
  if (!status) return <span className="text-muted-foreground">—</span>;
  if (status === "success")
    return (
      <Badge className="bg-emerald-500/15 text-emerald-700 border-emerald-500/30 hover:bg-emerald-500/20">
        <CheckCircle2 className="h-3 w-3 mr-1" />
        {t("statusSuccess")}
      </Badge>
    );
  if (status === "failed")
    return (
      <Badge variant="destructive">
        <XCircle className="h-3 w-3 mr-1" />
        {t("statusFailed")}
      </Badge>
    );
  return <Badge variant="secondary">{status}</Badge>;
}

// =============================================================================
// CRUD dialog
// =============================================================================

function ReportFormDialog({
  open,
  onOpenChange,
  initial,
  defaultLocale,
  defaultRecipient,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initial: ScheduledReportRow | null;
  defaultLocale: string;
  defaultRecipient: string;
  onSaved: () => void;
}) {
  const t = useTranslations("automation");
  const tCommon = useTranslations("common");
  const { toast } = useToast();

  const [name, setName] = React.useState("");
  const [reportType, setReportType] = React.useState("daily_digest");
  const [schedule, setSchedule] = React.useState("59 23 * * *");
  const [recipientsRaw, setRecipientsRaw] = React.useState("");
  const [format, setFormat] = React.useState("html");
  const [emailLocale, setEmailLocale] = React.useState(defaultLocale);
  const [submitting, setSubmitting] = React.useState(false);

  React.useEffect(() => {
    if (open) {
      if (initial) {
        setName(initial.name);
        setReportType(initial.report_type);
        setSchedule(initial.schedule_cron);
        setRecipientsRaw(initial.recipients_emails.join(", "));
        setFormat(initial.format);
        setEmailLocale(initial.locale);
      } else {
        setName(t("defaultName"));
        setReportType("daily_digest");
        setSchedule("59 23 * * *");
        setRecipientsRaw(defaultRecipient);
        setFormat("html");
        setEmailLocale(defaultLocale);
      }
    }
  }, [open, initial, defaultLocale, defaultRecipient, t]);

  const isEdit = !!initial;

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    try {
      const recipients = recipientsRaw
        .split(/[,;\n]/)
        .map((s) => s.trim())
        .filter((s) => s.length > 0);

      const body = {
        name,
        report_type: reportType,
        schedule_cron: schedule,
        recipients_emails: recipients,
        format,
        filters: {},
        locale: emailLocale,
      };

      if (isEdit && initial) {
        await clientFetch({
          path: `/reporting/scheduled/${initial.id}`,
          method: "PUT",
          body,
        });
        toast({ title: t("updateSuccess") });
      } else {
        await clientFetch({
          path: "/reporting/scheduled",
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
            <DialogTitle>{isEdit ? t("editReport") : t("addReport")}</DialogTitle>
            <DialogDescription>
              {isEdit ? t("editSubtitle") : t("addSubtitle")}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-3">
            <div className="space-y-1">
              <Label htmlFor="r-name">{t("colName")}</Label>
              <Input
                id="r-name"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>

            <div className="space-y-1">
              <Label htmlFor="r-type">{t("colType")}</Label>
              <Select value={reportType} onValueChange={setReportType}>
                <SelectTrigger id="r-type">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {REPORT_TYPES.map((rt) => (
                    <SelectItem key={rt.value} value={rt.value}>
                      {t(rt.labelKey)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1">
              <Label>{t("colSchedule")}</Label>
              <div className="flex flex-wrap gap-1">
                {SCHEDULE_PRESETS.map((p) => (
                  <Button
                    key={p.value}
                    type="button"
                    size="sm"
                    variant={schedule === p.value ? "default" : "outline"}
                    onClick={() => setSchedule(p.value)}
                  >
                    {t(p.labelKey)}
                  </Button>
                ))}
              </div>
              <Input
                value={schedule}
                onChange={(e) => setSchedule(e.target.value)}
                className="font-mono text-sm mt-2"
                placeholder="m h dom mon dow"
              />
              <p className="text-xs text-muted-foreground">{t("scheduleHint")}</p>
            </div>

            <div className="space-y-1">
              <Label htmlFor="r-recip">{t("colRecipients")}</Label>
              <Input
                id="r-recip"
                value={recipientsRaw}
                onChange={(e) => setRecipientsRaw(e.target.value)}
                placeholder="manager@example.com, owner@example.com"
              />
              <p className="text-xs text-muted-foreground">{t("recipientsHint")}</p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label htmlFor="r-fmt">{t("colFormat")}</Label>
                <Select value={format} onValueChange={setFormat}>
                  <SelectTrigger id="r-fmt">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {FORMATS.map((f) => (
                      <SelectItem key={f.value} value={f.value}>
                        {t(f.labelKey)}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label htmlFor="r-loc">{t("colLocale")}</Label>
                <Select value={emailLocale} onValueChange={setEmailLocale}>
                  <SelectTrigger id="r-loc">
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

// =============================================================================
// Logs table
// =============================================================================

function LogsTable({ logs }: { logs: ReportLogRow[] }) {
  const t = useTranslations("automation");
  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t("logColTime")}</TableHead>
            <TableHead>{t("logColType")}</TableHead>
            <TableHead>{t("logColRecipients")}</TableHead>
            <TableHead>{t("logColTrigger")}</TableHead>
            <TableHead>{t("logColStatus")}</TableHead>
            <TableHead>{t("logColDuration")}</TableHead>
            <TableHead>{t("logColError")}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {logs.length === 0 && (
            <TableRow>
              <TableCell colSpan={7} className="text-center text-muted-foreground py-8">
                {t("logEmpty")}
              </TableCell>
            </TableRow>
          )}
          {logs.map((l) => (
            <TableRow key={l.id}>
              <TableCell className="text-sm whitespace-nowrap">
                {new Date(l.sent_at).toLocaleString()}
              </TableCell>
              <TableCell className="text-xs font-mono">{l.report_type}</TableCell>
              <TableCell className="text-sm text-muted-foreground">
                {l.sent_recipients_count} <Mail className="h-3 w-3 inline ml-1" />
              </TableCell>
              <TableCell>
                <Badge variant="outline" className="text-xs">{l.trigger_source}</Badge>
              </TableCell>
              <TableCell><StatusPill status={l.status} /></TableCell>
              <TableCell className="text-sm text-muted-foreground">
                {l.duration_ms ? `${l.duration_ms} ms` : "—"}
              </TableCell>
              <TableCell className="text-xs text-destructive max-w-xs truncate">
                {l.error_message ?? ""}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

// =============================================================================
// Preview dialog — opens digest HTML in an iframe
// =============================================================================

function PreviewDialog({
  url,
  onClose,
}: {
  url: string | null;
  onClose: () => void;
}) {
  const t = useTranslations("automation");
  return (
    <Dialog open={!!url} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>{t("previewTitle")}</DialogTitle>
          <DialogDescription>{t("previewSubtitle")}</DialogDescription>
        </DialogHeader>
        {url && (
          <iframe
            src={url}
            className="w-full border rounded-md"
            style={{ height: 600 }}
            sandbox="allow-same-origin"
          />
        )}
      </DialogContent>
    </Dialog>
  );
}
