"use client";

/**
 * Order Profiles — time-based presets for pricing / service charge / print
 * routing.  Backed by `/api/v1/order-profiles` (CRUD) + `/active` (the
 * server's computed winner against any timestamp).  The schedule UI is
 * deliberately minimal — one row per slot, weekday toggle chips, two HH:MM
 * inputs — because the server is the source of truth for "is this slot
 * active now"; the client only renders + edits.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Clock, Tag, AlertCircle, Loader2, Play } from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { useToast } from "@/components/ui/use-toast";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { StatusBadge } from "@/components/ui/status-badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
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
import type { MenuCategory, MenuProduct } from "@/lib/api-types";

const LOCALES = ["tr", "de", "en", "fr", "it"] as const;
type Locale = (typeof LOCALES)[number];
const PRIMARY_LANG: Locale = "de";

// Weekday convention matches Go's time.Weekday: 0=Sunday … 6=Saturday.
const WEEKDAYS: { num: number; key: string }[] = [
  { num: 1, key: "mon" },
  { num: 2, key: "tue" },
  { num: 3, key: "wed" },
  { num: 4, key: "thu" },
  { num: 5, key: "fri" },
  { num: 6, key: "sat" },
  { num: 0, key: "sun" },
];

interface ScheduleSlot {
  weekdays: number[];
  startsAt: string;
  endsAt: string;
}
interface ServiceCharge {
  kind: "percent" | "fixed";
  valueCents: number;
  label: string;
}
interface PrintRules {
  kitchen: boolean;
  bar: boolean;
  receiptCopies: number;
}
interface Visibility {
  mode: "include" | "exclude";
  categories: string[];
  products: string[];
}
interface ProfileSettings {
  schedule: ScheduleSlot[];
  serviceCharge?: ServiceCharge | null;
  printRules?: PrintRules | null;
  visibility?: Visibility | null;
  receiptTemplateId?: string | null;
}
interface PricingRule {
  id?: string;
  categoryId?: string | null;
  productId?: string | null;
  overridePriceCents?: number | null;
  discountPercent?: number | null;
}
interface Profile {
  id: string;
  tenantId: string;
  code: string;
  name: string;
  nameTranslations: Record<string, string>;
  description: string;
  isActive: boolean;
  isDefault: boolean;
  priority: number;
  settings: ProfileSettings;
  pricingRules: PricingRule[];
  createdAt: string;
  updatedAt: string;
}
interface ActiveResp {
  tenantId: string;
  computedAt: string;
  activeIds: string[];
  defaultId?: string;
  winnerId?: string;
  winnerProfile?: Profile;
}

interface ProfilesResp {
  success?: boolean;
  data?: { profiles?: Profile[] };
}
interface ActiveEnvelope {
  success?: boolean;
  data?: ActiveResp;
}

function emptyProfile(): Profile {
  return {
    id: "",
    tenantId: "",
    code: "",
    name: "",
    nameTranslations: {},
    description: "",
    isActive: true,
    isDefault: false,
    priority: 10,
    settings: {
      schedule: [],
      printRules: { kitchen: true, bar: true, receiptCopies: 1 },
    },
    pricingRules: [],
    createdAt: "",
    updatedAt: "",
  };
}

function summarizeSchedule(s: ScheduleSlot[]): string {
  if (!s || s.length === 0) return "—";
  return s
    .map((slot) => {
      const days = slot.weekdays
        .map((n) => WEEKDAYS.find((w) => w.num === n)?.key ?? "?")
        .join(",");
      return `${days} ${slot.startsAt}-${slot.endsAt}`;
    })
    .join(" · ");
}

export function OrderProfilesClient({
  categories,
  products,
}: {
  categories: MenuCategory[];
  products: MenuProduct[];
}) {
  const t = useTranslations("menu.orderProfilesPage");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();

  const [editing, setEditing] = React.useState<Profile | null>(null);
  const [confirmDelete, setConfirmDelete] = React.useState<Profile | null>(null);
  const [testAt, setTestAt] = React.useState<string>("");

  const list = useQuery({
    queryKey: ["order-profiles"],
    queryFn: async () => {
      const r = await clientFetch<ProfilesResp>({ path: "/order-profiles" });
      return r?.data?.profiles ?? [];
    },
  });

  const activeNow = useQuery({
    queryKey: ["order-profiles-active"],
    queryFn: async () => {
      const r = await clientFetch<ActiveEnvelope>({ path: "/order-profiles/active" });
      return r?.data ?? null;
    },
    refetchInterval: 60_000,
  });

  const testActive = useQuery({
    enabled: !!testAt,
    queryKey: ["order-profiles-test", testAt],
    queryFn: async () => {
      const r = await clientFetch<ActiveEnvelope>({
        path: `/order-profiles/active?at=${encodeURIComponent(testAt)}`,
      });
      return r?.data ?? null;
    },
  });

  const upsert = useMutation({
    mutationFn: async (p: Profile) => {
      const body = {
        code: p.code,
        name: p.name,
        nameTranslations: p.nameTranslations,
        description: p.description,
        isActive: p.isActive,
        isDefault: p.isDefault,
        priority: p.priority,
        settings: p.settings,
        pricingRules: p.pricingRules,
      };
      if (p.id) {
        return clientFetch({ path: `/order-profiles/${p.id}`, method: "PUT", body });
      }
      return clientFetch({ path: "/order-profiles", method: "POST", body });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["order-profiles"] });
      qc.invalidateQueries({ queryKey: ["order-profiles-active"] });
      setEditing(null);
      toast({ title: t("savedToast") });
    },
    onError: (e: Error) => {
      toast({ title: t("saveError"), description: e.message, variant: "destructive" });
    },
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/order-profiles/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["order-profiles"] });
      qc.invalidateQueries({ queryKey: ["order-profiles-active"] });
      setConfirmDelete(null);
      toast({ title: t("deletedToast") });
    },
    onError: (e: Error) => {
      toast({ title: t("deleteError"), description: e.message, variant: "destructive" });
    },
  });

  const profiles = list.data ?? [];
  const winnerId = activeNow.data?.winnerId ?? null;

  return (
    <div className="space-y-4">
      <Card className="p-4">
        <div className="flex items-center justify-between gap-3">
          <div className="text-sm">
            <div className="font-medium">{t("activeNowHeader")}</div>
            <div className="text-muted-foreground">
              {activeNow.isLoading ? (
                <Loader2 className="h-3 w-3 animate-spin inline" />
              ) : activeNow.data?.winnerProfile ? (
                <>
                  <StatusBadge variant="success" withDot className="mr-2">
                    {activeNow.data.winnerProfile.name}
                  </StatusBadge>
                  <span className="text-xs">
                    {activeNow.data.activeIds.length > 1
                      ? t("multipleActive", { n: activeNow.data.activeIds.length })
                      : t("singleActive")}
                  </span>
                </>
              ) : (
                <span className="text-xs">{t("noneActive")}</span>
              )}
            </div>
          </div>
          <Button onClick={() => setEditing(emptyProfile())}>
            <Plus className="h-4 w-4" /> {t("newProfile")}
          </Button>
        </div>
      </Card>

      <Card className="p-4 space-y-3">
        <div className="flex items-center gap-2 text-sm font-medium">
          <Play className="h-4 w-4" />
          {t("testModeHeader")}
        </div>
        <p className="text-xs text-muted-foreground">{t("testModeHint")}</p>
        <div className="flex items-end gap-3 flex-wrap">
          <div className="space-y-1">
            <Label className="text-xs">{t("testTimeLabel")}</Label>
            <Input
              type="datetime-local"
              value={testAt}
              onChange={(e) =>
                setTestAt(
                  e.target.value
                    ? new Date(e.target.value).toISOString()
                    : "",
                )
              }
              className="w-[260px]"
            />
          </div>
          {testAt && (
            <div className="text-xs">
              {testActive.isFetching ? (
                <Loader2 className="h-3 w-3 animate-spin inline" />
              ) : testActive.data?.winnerProfile ? (
                <>
                  {t("testWinner")}:{" "}
                  <StatusBadge variant="info">
                    {testActive.data.winnerProfile.name}
                  </StatusBadge>
                </>
              ) : (
                <span className="text-muted-foreground">
                  {t("testNoWinner")}
                </span>
              )}
              <Button
                size="sm"
                variant="ghost"
                className="ml-2"
                onClick={() => setTestAt("")}
              >
                {tCommon("cancel")}
              </Button>
            </div>
          )}
        </div>
      </Card>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 flex items-center justify-between">
          <span className="text-sm font-medium">
            {t("listHeader", { count: profiles.length })}
          </span>
          {list.isFetching && (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
        </div>
        {list.isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            <Loader2 className="h-6 w-6 mx-auto animate-spin mb-2" />
            {t("loading")}
          </div>
        ) : list.error ? (
          <div className="p-12 text-center text-sm text-error">
            {(list.error as Error).message}
          </div>
        ) : profiles.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Clock className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
            <Button variant="outline" onClick={() => setEditing(emptyProfile())}>
              <Plus className="h-4 w-4" /> {t("newProfile")}
            </Button>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.schedule")}</TableHead>
                <TableHead>{t("col.rules")}</TableHead>
                <TableHead>{t("col.priority")}</TableHead>
                <TableHead>{t("col.status")}</TableHead>
                <TableHead className="w-24 text-right">{t("col.actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {profiles.map((p) => (
                <TableRow key={p.id} className="hover:bg-muted/30">
                  <TableCell>
                    <div className="font-medium flex items-center gap-2">
                      {p.name}
                      {p.isDefault && (
                        <StatusBadge variant="neutral">{t("defaultBadge")}</StatusBadge>
                      )}
                      {p.id === winnerId && (
                        <StatusBadge variant="success" withDot>
                          {t("activeNowBadge")}
                        </StatusBadge>
                      )}
                    </div>
                    {p.description && (
                      <div className="text-[11px] text-muted-foreground mt-0.5">
                        {p.description}
                      </div>
                    )}
                  </TableCell>
                  <TableCell className="text-xs font-mono text-muted-foreground">
                    {summarizeSchedule(p.settings.schedule)}
                  </TableCell>
                  <TableCell className="text-xs tabular-nums">
                    {p.pricingRules.length > 0 && (
                      <span>
                        <Tag className="h-3 w-3 inline" /> {p.pricingRules.length}
                      </span>
                    )}
                    {p.settings.serviceCharge && (
                      <span className="ml-2 text-muted-foreground">
                        {p.settings.serviceCharge.kind === "percent"
                          ? `+${p.settings.serviceCharge.valueCents / 100}%`
                          : `+${(p.settings.serviceCharge.valueCents / 100).toFixed(2)}`}
                      </span>
                    )}
                  </TableCell>
                  <TableCell className="tabular-nums">{p.priority}</TableCell>
                  <TableCell>
                    {p.isActive ? (
                      <StatusBadge variant="success">{tCommon("active")}</StatusBadge>
                    ) : (
                      <StatusBadge variant="neutral">{tCommon("inactive")}</StatusBadge>
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8"
                      onClick={() => setEditing(structuredClone(p))}
                    >
                      <Pencil className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-error"
                      disabled={p.isDefault}
                      onClick={() => setConfirmDelete(p)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      <ProfileSheet
        open={editing !== null}
        profile={editing}
        categories={categories}
        products={products}
        onClose={() => setEditing(null)}
        onSubmit={(p) => upsert.mutate(p)}
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

function ProfileSheet({
  open,
  profile,
  categories,
  products,
  onClose,
  onSubmit,
  submitting,
}: {
  open: boolean;
  profile: Profile | null;
  categories: MenuCategory[];
  products: MenuProduct[];
  onClose: () => void;
  onSubmit: (p: Profile) => void;
  submitting: boolean;
}) {
  const t = useTranslations("menu.orderProfilesPage");
  const tCommon = useTranslations("common");
  const [draft, setDraft] = React.useState<Profile | null>(profile);

  React.useEffect(() => {
    setDraft(profile ? structuredClone(profile) : null);
  }, [profile]);

  if (!draft) return null;

  const update = (patch: Partial<Profile>) => setDraft({ ...draft, ...patch });
  const updateSettings = (patch: Partial<ProfileSettings>) =>
    setDraft({ ...draft, settings: { ...draft.settings, ...patch } });

  const addSlot = () =>
    updateSettings({
      schedule: [...draft.settings.schedule, { weekdays: [1, 2, 3, 4, 5], startsAt: "12:00", endsAt: "14:00" }],
    });
  const updateSlot = (idx: number, patch: Partial<ScheduleSlot>) => {
    const next = draft.settings.schedule.map((s, i) => (i === idx ? { ...s, ...patch } : s));
    updateSettings({ schedule: next });
  };
  const removeSlot = (idx: number) =>
    updateSettings({ schedule: draft.settings.schedule.filter((_, i) => i !== idx) });

  const addRule = () =>
    update({
      pricingRules: [
        ...draft.pricingRules,
        { categoryId: categories[0]?.id ?? null, discountPercent: 10 },
      ],
    });
  const updateRule = (idx: number, patch: Partial<PricingRule>) => {
    const next = draft.pricingRules.map((r, i) => (i === idx ? { ...r, ...patch } : r));
    update({ pricingRules: next });
  };
  const removeRule = (idx: number) =>
    update({ pricingRules: draft.pricingRules.filter((_, i) => i !== idx) });

  const isInvalid = !draft.code || !draft.name;

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full sm:max-w-3xl overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{draft.id ? t("editProfile") : t("newProfile")}</SheetTitle>
          <SheetDescription>{t("editHint")}</SheetDescription>
        </SheetHeader>

        <div className="space-y-5 mt-4">
          <section className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("field.code")}</Label>
              <Input
                value={draft.code}
                onChange={(e) =>
                  update({ code: e.target.value.toLowerCase().replace(/[^a-z0-9_-]/g, "-") })
                }
                placeholder="happy-hour"
                disabled={draft.isDefault}
              />
              <p className="text-[10px] text-muted-foreground">{t("field.codeHint")}</p>
            </div>
            <div className="space-y-1">
              <Label>{t("field.priority")}</Label>
              <Input
                type="number"
                min={0}
                value={draft.priority}
                onChange={(e) => update({ priority: Number(e.target.value) || 0 })}
              />
              <p className="text-[10px] text-muted-foreground">{t("field.priorityHint")}</p>
            </div>
          </section>

          <section className="space-y-1">
            <Label>
              {t("field.name")}{" "}
              <span className="text-[10px] uppercase text-muted-foreground">({PRIMARY_LANG} — Hauptsprache)</span>
            </Label>
            <Input
              value={draft.nameTranslations[PRIMARY_LANG] ?? draft.name}
              onChange={(e) =>
                update({
                  name: e.target.value,
                  nameTranslations: { ...draft.nameTranslations, [PRIMARY_LANG]: e.target.value },
                })
              }
            />
          </section>

          <details className="rounded-md border border-input bg-muted/20">
            <summary className="cursor-pointer select-none px-3 py-2 text-sm font-medium">
              {t("field.otherLanguages")}
            </summary>
            <div className="space-y-2 p-3 border-t">
              {LOCALES.filter((l) => l !== PRIMARY_LANG).map((l) => (
                <div key={l} className="space-y-1">
                  <Label className="text-xs uppercase">{l}</Label>
                  <Input
                    value={draft.nameTranslations[l] ?? ""}
                    onChange={(e) =>
                      update({
                        nameTranslations: { ...draft.nameTranslations, [l]: e.target.value },
                      })
                    }
                  />
                </div>
              ))}
            </div>
          </details>

          <section className="space-y-1">
            <Label>{t("field.description")}</Label>
            <textarea
              rows={2}
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              value={draft.description}
              onChange={(e) => update({ description: e.target.value })}
            />
          </section>

          <section className="space-y-2">
            <div className="flex items-center justify-between">
              <Label className="text-sm font-medium">{t("schedule.title")}</Label>
              <Button size="sm" variant="outline" onClick={addSlot}>
                <Plus className="h-3 w-3" /> {t("schedule.addSlot")}
              </Button>
            </div>
            <p className="text-[11px] text-muted-foreground">{t("schedule.hint")}</p>
            {draft.isDefault && (
              <Alert>
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>{t("schedule.defaultNotice")}</AlertDescription>
              </Alert>
            )}
            {draft.settings.schedule.length === 0 && !draft.isDefault && (
              <p className="text-xs text-warning border border-warning/30 bg-warning-soft/30 rounded px-3 py-2">
                {t("schedule.emptyWarning")}
              </p>
            )}
            {draft.settings.schedule.map((slot, idx) => (
              <div
                key={idx}
                className="rounded-md border border-input p-3 space-y-3 bg-background"
              >
                <div className="flex flex-wrap gap-1.5">
                  {WEEKDAYS.map((wd) => {
                    const on = slot.weekdays.includes(wd.num);
                    return (
                      <button
                        key={wd.num}
                        type="button"
                        onClick={() =>
                          updateSlot(idx, {
                            weekdays: on
                              ? slot.weekdays.filter((d) => d !== wd.num)
                              : [...slot.weekdays, wd.num],
                          })
                        }
                        className={`px-2.5 py-1 rounded text-xs border transition ${
                          on
                            ? "bg-primary text-primary-foreground border-primary"
                            : "bg-muted text-muted-foreground border-border hover:bg-accent"
                        }`}
                      >
                        {t(`weekday.${wd.key}`)}
                      </button>
                    );
                  })}
                </div>
                <div className="flex items-center gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs">{t("schedule.startsAt")}</Label>
                    <Input
                      type="time"
                      value={slot.startsAt}
                      onChange={(e) => updateSlot(idx, { startsAt: e.target.value })}
                      className="w-32"
                    />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">{t("schedule.endsAt")}</Label>
                    <Input
                      type="time"
                      value={slot.endsAt}
                      onChange={(e) => updateSlot(idx, { endsAt: e.target.value })}
                      className="w-32"
                    />
                  </div>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="ml-auto text-error"
                    onClick={() => removeSlot(idx)}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            ))}
          </section>

          <section className="space-y-2">
            <Label className="text-sm font-medium">{t("pricing.title")}</Label>
            <p className="text-[11px] text-muted-foreground">{t("pricing.hint")}</p>
            {draft.pricingRules.length === 0 ? (
              <p className="text-xs text-muted-foreground italic">{t("pricing.empty")}</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t("pricing.col.target")}</TableHead>
                    <TableHead>{t("pricing.col.value")}</TableHead>
                    <TableHead className="w-12"></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {draft.pricingRules.map((rule, idx) => {
                    const targetKind = rule.productId ? "product" : "category";
                    const valueKind = rule.overridePriceCents != null ? "fixed" : "percent";
                    return (
                      <TableRow key={idx}>
                        <TableCell>
                          <div className="flex gap-2 items-center">
                            <Select
                              value={targetKind}
                              onValueChange={(v) => {
                                if (v === "product") {
                                  updateRule(idx, {
                                    productId: products[0]?.id ?? null,
                                    categoryId: null,
                                  });
                                } else {
                                  updateRule(idx, {
                                    categoryId: categories[0]?.id ?? null,
                                    productId: null,
                                  });
                                }
                              }}
                            >
                              <SelectTrigger className="w-[120px]">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="category">{t("pricing.targetCategory")}</SelectItem>
                                <SelectItem value="product">{t("pricing.targetProduct")}</SelectItem>
                              </SelectContent>
                            </Select>
                            {targetKind === "category" ? (
                              <Select
                                value={rule.categoryId ?? ""}
                                onValueChange={(v) => updateRule(idx, { categoryId: v })}
                              >
                                <SelectTrigger className="min-w-[180px]">
                                  <SelectValue placeholder="—" />
                                </SelectTrigger>
                                <SelectContent>
                                  {categories.map((c) => (
                                    <SelectItem key={c.id} value={c.id}>
                                      {c.name}
                                    </SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            ) : (
                              <Select
                                value={rule.productId ?? ""}
                                onValueChange={(v) => updateRule(idx, { productId: v })}
                              >
                                <SelectTrigger className="min-w-[200px]">
                                  <SelectValue placeholder="—" />
                                </SelectTrigger>
                                <SelectContent>
                                  {products.map((p) => (
                                    <SelectItem key={p.id} value={p.id}>
                                      {p.name}
                                    </SelectItem>
                                  ))}
                                </SelectContent>
                              </Select>
                            )}
                          </div>
                        </TableCell>
                        <TableCell>
                          <div className="flex gap-2 items-center">
                            <Select
                              value={valueKind}
                              onValueChange={(v) => {
                                if (v === "percent") {
                                  updateRule(idx, { discountPercent: 10, overridePriceCents: null });
                                } else {
                                  updateRule(idx, { overridePriceCents: 500, discountPercent: null });
                                }
                              }}
                            >
                              <SelectTrigger className="w-[110px]">
                                <SelectValue />
                              </SelectTrigger>
                              <SelectContent>
                                <SelectItem value="percent">{t("pricing.valuePercent")}</SelectItem>
                                <SelectItem value="fixed">{t("pricing.valueFixed")}</SelectItem>
                              </SelectContent>
                            </Select>
                            {valueKind === "percent" ? (
                              <Input
                                type="number"
                                min={0}
                                max={100}
                                step={1}
                                value={rule.discountPercent ?? 0}
                                onChange={(e) =>
                                  updateRule(idx, { discountPercent: Number(e.target.value) || 0 })
                                }
                                className="w-24"
                              />
                            ) : (
                              <Input
                                type="number"
                                min={0}
                                step={0.01}
                                value={(rule.overridePriceCents ?? 0) / 100}
                                onChange={(e) =>
                                  updateRule(idx, {
                                    overridePriceCents: Math.round((Number(e.target.value) || 0) * 100),
                                  })
                                }
                                className="w-28"
                              />
                            )}
                          </div>
                        </TableCell>
                        <TableCell>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="text-error"
                            onClick={() => removeRule(idx)}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}
            <Button size="sm" variant="outline" onClick={addRule}>
              <Plus className="h-3 w-3" /> {t("pricing.addRule")}
            </Button>
          </section>

          <section className="space-y-2">
            <Label className="text-sm font-medium">{t("serviceCharge.title")}</Label>
            <div className="flex items-center gap-2">
              <Switch
                checked={!!draft.settings.serviceCharge}
                onCheckedChange={(v) =>
                  updateSettings({
                    serviceCharge: v ? { kind: "fixed", valueCents: 100, label: "" } : null,
                  })
                }
              />
              <span className="text-xs text-muted-foreground">{t("serviceCharge.toggleHint")}</span>
            </div>
            {draft.settings.serviceCharge && (
              <div className="grid grid-cols-3 gap-2">
                <Select
                  value={draft.settings.serviceCharge.kind}
                  onValueChange={(v) =>
                    updateSettings({
                      serviceCharge: {
                        ...draft.settings.serviceCharge!,
                        kind: v as "percent" | "fixed",
                      },
                    })
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="fixed">CHF</SelectItem>
                    <SelectItem value="percent">%</SelectItem>
                  </SelectContent>
                </Select>
                <Input
                  type="number"
                  step="0.01"
                  min={0}
                  value={draft.settings.serviceCharge.valueCents / 100}
                  onChange={(e) =>
                    updateSettings({
                      serviceCharge: {
                        ...draft.settings.serviceCharge!,
                        valueCents: Math.round((Number(e.target.value) || 0) * 100),
                      },
                    })
                  }
                />
                <Input
                  placeholder={t("serviceCharge.labelPlaceholder")}
                  value={draft.settings.serviceCharge.label}
                  onChange={(e) =>
                    updateSettings({
                      serviceCharge: { ...draft.settings.serviceCharge!, label: e.target.value },
                    })
                  }
                />
              </div>
            )}
          </section>

          <section className="space-y-2">
            <Label className="text-sm font-medium">{t("print.title")}</Label>
            <div className="grid grid-cols-3 gap-3">
              <label className="flex items-center gap-2 text-sm">
                <Switch
                  checked={draft.settings.printRules?.kitchen ?? true}
                  onCheckedChange={(v) =>
                    updateSettings({
                      printRules: {
                        ...(draft.settings.printRules ?? { kitchen: true, bar: true, receiptCopies: 1 }),
                        kitchen: v,
                      },
                    })
                  }
                />
                {t("print.kitchen")}
              </label>
              <label className="flex items-center gap-2 text-sm">
                <Switch
                  checked={draft.settings.printRules?.bar ?? true}
                  onCheckedChange={(v) =>
                    updateSettings({
                      printRules: {
                        ...(draft.settings.printRules ?? { kitchen: true, bar: true, receiptCopies: 1 }),
                        bar: v,
                      },
                    })
                  }
                />
                {t("print.bar")}
              </label>
              <div className="space-y-1">
                <Label className="text-xs">{t("print.copies")}</Label>
                <Input
                  type="number"
                  min={1}
                  max={5}
                  value={draft.settings.printRules?.receiptCopies ?? 1}
                  onChange={(e) =>
                    updateSettings({
                      printRules: {
                        ...(draft.settings.printRules ?? { kitchen: true, bar: true, receiptCopies: 1 }),
                        receiptCopies: Number(e.target.value) || 1,
                      },
                    })
                  }
                />
              </div>
            </div>
          </section>

          <section className="flex flex-wrap items-center gap-6">
            <label className="flex items-center gap-2 text-sm">
              <Switch
                checked={draft.isActive}
                onCheckedChange={(v) => update({ isActive: v })}
              />
              {t("field.isActive")}
            </label>
            <label className="flex items-center gap-2 text-sm">
              <Switch
                checked={draft.isDefault}
                onCheckedChange={(v) => update({ isDefault: v })}
              />
              {t("field.isDefault")}
            </label>
          </section>
        </div>

        <SheetFooter className="gap-2 mt-6">
          <Button variant="outline" onClick={onClose}>{tCommon("cancel")}</Button>
          <Button onClick={() => onSubmit(draft)} disabled={submitting || isInvalid}>
            {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
            {tCommon("save")}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
