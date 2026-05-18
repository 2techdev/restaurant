"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Send, BarChart3, Edit, Trash2, Mail, MessageSquare, BellRing, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatDateTime } from "@/lib/utils";

interface Segment {
  id: string;
  name: string;
  member_count?: number;
}

interface Campaign {
  id: string;
  tenant_id: string;
  segment_id?: string | null;
  name: string;
  channel: "email" | "sms" | "push";
  subject?: string | null;
  body_html?: string | null;
  body_text?: string | null;
  template_key?: string | null;
  scheduled_at?: string | null;
  sent_at?: string | null;
  status: "draft" | "scheduled" | "sending" | "sent" | "failed" | "cancelled";
  sent_count: number;
  opened_count: number;
  clicked_count: number;
  converted_count: number;
  created_at: string;
}

interface CampaignStats {
  campaign_id: string;
  status: string;
  recipients: number;
  sent_count: number;
  opened_count: number;
  clicked_count: number;
  converted_count: number;
  open_rate: number;
  click_rate: number;
  conversion_rate: number;
}

const TEMPLATES: { key: string; name: string; subject: string; body: string }[] = [
  {
    key: "welcome",
    name: "Willkommen",
    subject: "Schön, dass Sie da sind!",
    body: "Hallo,\n\nherzlich willkommen in unserem Restaurant. Bei Ihrem nächsten Besuch erhalten Sie 10% Rabatt — einfach diesen Code zeigen: WELCOME10.\n\nBis bald!",
  },
  {
    key: "birthday",
    name: "Geburtstag",
    subject: "Alles Gute zum Geburtstag!",
    body: "Hallo,\n\nzu Ihrem Geburtstag laden wir Sie ein: Dessert geht aufs Haus. Reservieren Sie diese Woche und genießen Sie den Abend.\n\nHerzliche Grüße",
  },
  {
    key: "re_engagement",
    name: "Reaktivierung",
    subject: "Wir vermissen Sie!",
    body: "Hallo,\n\nes ist eine Weile her — schön wäre es, Sie wiederzusehen. Kommen Sie diese Woche vorbei und erhalten Sie 15% Rabatt mit dem Code COMEBACK15.\n\nWir freuen uns!",
  },
  {
    key: "loyalty_milestone",
    name: "Treuepunkte",
    subject: "Sie haben einen Meilenstein erreicht!",
    body: "Hallo,\n\nherzlichen Glückwunsch — Sie haben über 100 Treuepunkte gesammelt. Beim nächsten Besuch erhalten Sie einen Gratis-Drink.\n\nDanke für Ihre Treue!",
  },
];

const CHANNEL_ICONS = {
  email: Mail,
  sms: MessageSquare,
  push: BellRing,
};

export function CampaignsClient() {
  const t = useTranslations("marketing");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();

  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Campaign | null>(null);
  const [name, setName] = React.useState("");
  const [channel, setChannel] = React.useState<"email" | "sms" | "push">("email");
  const [segmentId, setSegmentId] = React.useState<string>("");
  const [subject, setSubject] = React.useState("");
  const [bodyText, setBodyText] = React.useState("");
  const [statsFor, setStatsFor] = React.useState<Campaign | null>(null);

  const campaigns = useQuery<Campaign[]>({
    queryKey: ["campaigns"],
    queryFn: async () => {
      const data = await clientFetch<{ campaigns?: Campaign[] }>({ path: "/crm/campaigns" });
      return data.campaigns ?? [];
    },
  });

  const segments = useQuery<Segment[]>({
    queryKey: ["segments"],
    queryFn: async () => {
      const data = await clientFetch<{ segments?: Segment[] }>({ path: "/crm/segments" });
      return data.segments ?? [];
    },
  });

  const save = useMutation({
    mutationFn: async () => {
      const body = {
        name,
        channel,
        segment_id: segmentId || null,
        subject: subject || null,
        body_text: bodyText || null,
      };
      if (editing) {
        return clientFetch({ path: `/crm/campaigns/${editing.id}`, method: "PUT", body });
      }
      return clientFetch({
        path: "/crm/campaigns",
        method: "POST",
        body: { id: crypto.randomUUID(), ...body },
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["campaigns"] });
      toast({ title: tCommon("success") });
      setOpen(false);
      setEditing(null);
    },
    onError: (e) =>
      toast({ title: tCommon("error"), description: e instanceof Error ? e.message : String(e), variant: "destructive" }),
  });

  const send = useMutation({
    mutationFn: async (id: string) => clientFetch({ path: `/crm/campaigns/${id}/send`, method: "POST" }),
    onSuccess: (data: unknown) => {
      const r = data as { sent?: number; failed?: number; recipients?: number; status?: string };
      qc.invalidateQueries({ queryKey: ["campaigns"] });
      toast({
        title: t("campaigns.sentToast"),
        description: t("campaigns.sentDesc", {
          sent: r.sent ?? 0,
          failed: r.failed ?? 0,
          total: r.recipients ?? 0,
        }),
      });
    },
    onError: (e) =>
      toast({ title: tCommon("error"), description: e instanceof Error ? e.message : String(e), variant: "destructive" }),
  });

  const remove = useMutation({
    mutationFn: async (id: string) => clientFetch({ path: `/crm/campaigns/${id}`, method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["campaigns"] }),
  });

  function openCreate() {
    setEditing(null);
    setName("");
    setChannel("email");
    setSegmentId("");
    setSubject("");
    setBodyText("");
    setOpen(true);
  }
  function openEdit(c: Campaign) {
    setEditing(c);
    setName(c.name);
    setChannel(c.channel);
    setSegmentId(c.segment_id ?? "");
    setSubject(c.subject ?? "");
    setBodyText(c.body_text ?? "");
    setOpen(true);
  }
  function applyTemplate(key: string) {
    const tpl = TEMPLATES.find((x) => x.key === key);
    if (!tpl) return;
    setName(tpl.name);
    setSubject(tpl.subject);
    setBodyText(tpl.body);
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-end">
        <Button onClick={openCreate}>
          <Plus className="mr-2 h-4 w-4" />
          {t("campaigns.new")}
        </Button>
      </div>

      {campaigns.isLoading ? (
        <div className="text-sm text-muted-foreground">{tCommon("loading")}</div>
      ) : (campaigns.data ?? []).length === 0 ? (
        <Card>
          <CardContent className="p-6 text-center text-sm text-muted-foreground">
            {t("campaigns.empty")}
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {(campaigns.data ?? []).map((c) => {
            const Icon = CHANNEL_ICONS[c.channel] ?? Mail;
            const segName = segments.data?.find((s) => s.id === c.segment_id)?.name;
            const isMutable = c.status === "draft" || c.status === "scheduled";
            return (
              <Card key={c.id}>
                <CardContent className="p-4 space-y-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <h3 className="font-medium truncate flex items-center gap-1.5">
                        <Icon className="h-3.5 w-3.5" />
                        {c.name}
                      </h3>
                      <p className="text-xs text-muted-foreground truncate">
                        {segName ?? t("campaigns.noSegment")}
                      </p>
                    </div>
                    <StatusBadge status={c.status} />
                  </div>
                  {c.subject && <p className="text-xs">{c.subject}</p>}
                  <div className="text-[11px] text-muted-foreground tabular-nums">
                    {t("campaigns.sentN", { n: c.sent_count })} · {t("campaigns.openedN", { n: c.opened_count })}
                    {c.sent_at && ` · ${formatDateTime(c.sent_at)}`}
                  </div>
                  <div className="flex gap-1 flex-wrap">
                    {isMutable && (
                      <>
                        <Button size="sm" variant="ghost" onClick={() => openEdit(c)}>
                          <Edit className="h-3.5 w-3.5 mr-1" />
                          {tCommon("edit")}
                        </Button>
                        <Button
                          size="sm"
                          onClick={() => {
                            if (confirm(t("campaigns.confirmSend", { name: c.name }))) send.mutate(c.id);
                          }}
                          disabled={send.isPending}
                        >
                          {send.isPending ? (
                            <Loader2 className="h-3.5 w-3.5 mr-1 animate-spin" />
                          ) : (
                            <Send className="h-3.5 w-3.5 mr-1" />
                          )}
                          {t("campaigns.send")}
                        </Button>
                      </>
                    )}
                    <Button size="sm" variant="ghost" onClick={() => setStatsFor(c)}>
                      <BarChart3 className="h-3.5 w-3.5 mr-1" />
                      {t("campaigns.stats")}
                    </Button>
                    {isMutable && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => {
                          if (confirm(t("campaigns.confirmDelete", { name: c.name }))) remove.mutate(c.id);
                        }}
                      >
                        <Trash2 className="h-3.5 w-3.5 mr-1 text-destructive" />
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>{editing ? t("campaigns.edit") : t("campaigns.new")}</DialogTitle>
            <DialogDescription>{t("campaigns.formHint")}</DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            <div className="flex flex-wrap gap-2">
              <span className="text-xs text-muted-foreground mr-1">{t("campaigns.templates")}:</span>
              {TEMPLATES.map((tpl) => (
                <Badge
                  key={tpl.key}
                  variant="outline"
                  className="cursor-pointer"
                  onClick={() => applyTemplate(tpl.key)}
                >
                  {tpl.name}
                </Badge>
              ))}
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1 col-span-2">
                <Label>{t("campaigns.name")}</Label>
                <Input value={name} onChange={(e) => setName(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("campaigns.channel")}</Label>
                <Select value={channel} onValueChange={(v) => setChannel(v as "email" | "sms" | "push")}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="email">E-Mail</SelectItem>
                    <SelectItem value="sms">SMS</SelectItem>
                    <SelectItem value="push">Push</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label>{t("campaigns.segment")}</Label>
                <Select value={segmentId || "__none__"} onValueChange={(v) => setSegmentId(v === "__none__" ? "" : v)}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">{t("campaigns.allCustomers")}</SelectItem>
                    {(segments.data ?? []).map((s) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.name} {s.member_count != null ? `(${s.member_count})` : ""}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1 col-span-2">
                <Label>{t("campaigns.subject")}</Label>
                <Input value={subject} onChange={(e) => setSubject(e.target.value)} />
              </div>
              <div className="space-y-1 col-span-2">
                <Label>{t("campaigns.body")}</Label>
                <textarea
                  className="w-full rounded-md border bg-background px-3 py-2 text-sm h-32"
                  value={bodyText}
                  onChange={(e) => setBodyText(e.target.value)}
                />
              </div>
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>{tCommon("cancel")}</Button>
            <Button onClick={() => save.mutate()} disabled={save.isPending || !name}>
              {save.isPending ? tCommon("loading") : tCommon("save")}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {statsFor && <StatsDialog campaign={statsFor} onClose={() => setStatsFor(null)} />}
    </div>
  );
}

function StatusBadge({ status }: { status: Campaign["status"] }) {
  const variant: Record<Campaign["status"], "default" | "secondary" | "outline" | "destructive"> = {
    draft: "outline",
    scheduled: "secondary",
    sending: "secondary",
    sent: "default",
    failed: "destructive",
    cancelled: "outline",
  };
  return <Badge variant={variant[status]} className="text-[10px]">{status.toUpperCase()}</Badge>;
}

function StatsDialog({ campaign, onClose }: { campaign: Campaign; onClose: () => void }) {
  const t = useTranslations("marketing");
  const stats = useQuery<CampaignStats>({
    queryKey: ["campaign-stats", campaign.id],
    queryFn: () => clientFetch<CampaignStats>({ path: `/crm/campaigns/${campaign.id}/stats` }),
  });
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t("campaigns.statsTitle", { name: campaign.name })}</DialogTitle>
        </DialogHeader>
        {stats.isLoading ? (
          <div className="text-sm text-muted-foreground">{t("loading")}</div>
        ) : !stats.data ? (
          <div className="text-sm text-muted-foreground">—</div>
        ) : (
          <div className="grid grid-cols-2 gap-3 text-sm">
            <Stat label={t("campaigns.recipients")} value={stats.data.recipients} />
            <Stat label={t("campaigns.sent")} value={stats.data.sent_count} />
            <Stat label={t("campaigns.opened")} value={stats.data.opened_count} pct={stats.data.open_rate} />
            <Stat label={t("campaigns.clicked")} value={stats.data.clicked_count} pct={stats.data.click_rate} />
            <Stat
              label={t("campaigns.converted")}
              value={stats.data.converted_count}
              pct={stats.data.conversion_rate}
            />
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function Stat({ label, value, pct }: { label: string; value: number; pct?: number }) {
  return (
    <div className="rounded-md border p-3">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="text-xl font-mono tabular-nums">{value}</div>
      {typeof pct === "number" && (
        <div className="text-xs text-muted-foreground tabular-nums">{(pct * 100).toFixed(1)}%</div>
      )}
    </div>
  );
}
