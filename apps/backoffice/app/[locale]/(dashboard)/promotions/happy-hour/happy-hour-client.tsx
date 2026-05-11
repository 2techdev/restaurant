"use client";

/**
 * Happy-hour rules — backed by `/api/v1/discounts` (migration 030).
 *
 * A happy-hour rule is a discount with a day-of-week + hour-of-day window
 * set. The discounts catalog still shows it (since it's a real Discount
 * row), but this page filters down to the time-bounded subset and presents
 * the operator-friendly Mon-Sun checkbox + start/end time pickers. The
 * underlying API surface is the same one /discounts uses, so any code
 * that already consumes /api/v1/discounts (POS pricing, audit log, sync
 * snapshots) picks up happy-hour rules automatically.
 *
 * Previous version persisted to localStorage; that path is gone.
 */

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { Plus, Trash2, Pencil, Clock, Loader2 } from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";

// Backend uses ISO day-of-week as int (0=Sun .. 6=Sat) per migration 030.
// The UI keeps a friendly Mon-first order; the mapper below converts.
const UI_DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type UiDay = (typeof UI_DAYS)[number];
const DAY_TO_INT: Record<UiDay, number> = {
  sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6,
};
const INT_TO_DAY: Record<number, UiDay> = {
  0: "sun", 1: "mon", 2: "tue", 3: "wed", 4: "thu", 5: "fri", 6: "sat",
};

interface HappyHourRule {
  id: string;
  tenant_id: string;
  name: string;
  type: "PERCENT" | "FIXED";
  value: number;
  active: boolean;
  days_of_week: number[];
  hours_from?: string | null;
  hours_to?: string | null;
}

export function HappyHourClient() {
  const t = useTranslations("promotions.happyHour");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();
  const [editing, setEditing] = React.useState<HappyHourRule | "create" | null>(null);

  const list = useQuery({
    queryKey: ["discounts", "happyHour"],
    queryFn: async () => {
      const data = await clientFetch<
        | { discounts?: HappyHourRule[]; data?: HappyHourRule[] }
        | HappyHourRule[]
      >({ path: "/discounts" });
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      const all = (Array.isArray(raw) ? raw : raw?.discounts ?? raw?.data ?? []) as HappyHourRule[];
      // A happy-hour rule is identified by having BOTH hours_from and
      // hours_to set; the regular /discounts page shows everything.
      return all.filter((d) => d.hours_from && d.hours_to);
    },
  });

  const upsert = useMutation({
    mutationFn: async (input: { id?: string; payload: Record<string, unknown> }) => {
      if (input.id) {
        return clientFetch({ path: `/discounts/${input.id}`, method: "PUT", body: input.payload });
      }
      return clientFetch({ path: "/discounts", method: "POST", body: input.payload });
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: ["discounts"] });
      qc.invalidateQueries({ queryKey: ["discounts", "happyHour"] });
      toast({ title: vars.id ? t("updatedToast") : t("createdToast") });
      setEditing(null);
    },
    onError: (e: Error) => {
      toast({ title: t("saveError") ?? "Save failed", description: e.message, variant: "destructive" });
    },
  });

  const remove = useMutation({
    mutationFn: async (id: string) =>
      clientFetch({ path: `/discounts/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["discounts"] });
      qc.invalidateQueries({ queryKey: ["discounts", "happyHour"] });
      toast({ title: t("deletedToast") ?? "Deleted" });
    },
    onError: (e: Error) => {
      toast({ title: t("deleteError") ?? "Delete failed", description: e.message, variant: "destructive" });
    },
  });

  const items = list.data ?? [];

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={() => setEditing("create")}>
          <Plus className="h-4 w-4" />
          {t("newRule")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 flex items-center justify-between">
          <span className="text-sm font-medium">
            {t("listHeader", { count: items.length })}
          </span>
          {list.isFetching && <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />}
        </div>
        {list.isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">{tCommon("loading")}</div>
        ) : list.error ? (
          <div className="p-12 text-center text-sm text-error">{(list.error as Error).message}</div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Clock className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.days")}</TableHead>
                <TableHead>{t("col.window")}</TableHead>
                <TableHead>{t("col.discount")}</TableHead>
                <TableHead>{t("col.active")}</TableHead>
                <TableHead className="w-20"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((r) => {
                const uiDays = (r.days_of_week ?? []).map((d) => INT_TO_DAY[d]).filter(Boolean);
                return (
                  <TableRow key={r.id} className="hover:bg-muted/30">
                    <TableCell className="font-medium">{r.name}</TableCell>
                    <TableCell>
                      <div className="flex gap-1 flex-wrap">
                        {uiDays.map((d) => (
                          <span
                            key={d}
                            className="text-[10px] uppercase tracking-wider font-mono px-1.5 py-0.5 rounded bg-muted"
                          >
                            {t(`day.${d}`)}
                          </span>
                        ))}
                      </div>
                    </TableCell>
                    <TableCell className="font-mono text-[12px]">
                      {(r.hours_from ?? "").slice(0, 5)} → {(r.hours_to ?? "").slice(0, 5)}
                    </TableCell>
                    <TableCell className="font-mono tabular-nums">
                      {r.type === "PERCENT" ? `%${r.value}` : `CHF ${r.value}`}
                    </TableCell>
                    <TableCell>
                      {r.active ? (
                        <StatusBadge variant="success" withDot>{tCommon("active")}</StatusBadge>
                      ) : (
                        <StatusBadge variant="neutral">{tCommon("inactive")}</StatusBadge>
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-1">
                        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setEditing(r)}>
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 text-error"
                          onClick={() => remove.mutate(r.id)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </Card>

      <RuleForm
        editing={editing}
        onClose={() => setEditing(null)}
        pending={upsert.isPending}
        onSubmit={(rule, id) => upsert.mutate({ id, payload: rule })}
      />
    </div>
  );
}

function RuleForm({
  editing,
  onClose,
  onSubmit,
  pending,
}: {
  editing: HappyHourRule | "create" | null;
  onClose: () => void;
  onSubmit: (payload: Record<string, unknown>, id?: string) => void;
  pending: boolean;
}) {
  const t = useTranslations("promotions.happyHour");
  const tCommon = useTranslations("common");
  const isEdit = editing && editing !== "create";
  const initial: HappyHourRule | null = isEdit ? (editing as HappyHourRule) : null;

  const [name, setName] = React.useState("");
  const [days, setDays] = React.useState<UiDay[]>([]);
  const [startTime, setStartTime] = React.useState("17:00");
  const [endTime, setEndTime] = React.useState("19:00");
  const [type, setType] = React.useState<"PERCENT" | "FIXED">("PERCENT");
  const [value, setValue] = React.useState(20);
  const [active, setActive] = React.useState(true);

  React.useEffect(() => {
    if (initial) {
      setName(initial.name);
      setDays(
        (initial.days_of_week ?? [])
          .map((d) => INT_TO_DAY[d])
          .filter((d): d is UiDay => Boolean(d)),
      );
      setStartTime((initial.hours_from ?? "17:00:00").slice(0, 5));
      setEndTime((initial.hours_to ?? "19:00:00").slice(0, 5));
      setType(initial.type);
      setValue(initial.value);
      setActive(initial.active);
    } else if (editing === "create") {
      setName("");
      setDays([]);
      setStartTime("17:00");
      setEndTime("19:00");
      setType("PERCENT");
      setValue(20);
      setActive(true);
    }
  }, [editing, initial]);

  const toggleDay = (d: UiDay) => {
    setDays((prev) => (prev.includes(d) ? prev.filter((x) => x !== d) : [...prev, d]));
  };

  const onSave = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || days.length === 0) return;
    const payload = {
      name: name.trim(),
      type,
      value,
      active,
      days_of_week: days.map((d) => DAY_TO_INT[d]),
      hours_from: startTime,
      hours_to: endTime,
    };
    onSubmit(payload, initial?.id);
  };

  return (
    <Dialog open={editing !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? t("editRule") : t("newRule")}</DialogTitle>
          <DialogDescription>{t("formHint")}</DialogDescription>
        </DialogHeader>
        <form onSubmit={onSave} className="space-y-3 pt-2">
          <div className="space-y-1">
            <Label>{t("col.name")}</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder={t("namePlaceholder")} />
          </div>
          <div className="space-y-1">
            <Label>{t("col.days")}</Label>
            <div className="flex gap-1">
              {UI_DAYS.map((d) => {
                const on = days.includes(d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => toggleDay(d)}
                    className={`flex-1 py-2 rounded text-xs font-medium uppercase tracking-wider transition-colors ${
                      on ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:bg-muted/70"
                    }`}
                  >
                    {t(`day.${d}`)}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("col.startTime")}</Label>
              <Input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} />
            </div>
            <div className="space-y-1">
              <Label>{t("col.endTime")}</Label>
              <Input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>{t("col.discountType")}</Label>
              <Select value={type} onValueChange={(v) => setType(v as "PERCENT" | "FIXED")}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="PERCENT">{t("type.PERCENT")}</SelectItem>
                  <SelectItem value="FIXED">{t("type.FIXED")}</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label>{t("col.discountValue")}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                value={value}
                onChange={(e) => setValue(parseFloat(e.target.value))}
              />
            </div>
          </div>
          <div className="flex items-center gap-2 pt-2">
            <input
              type="checkbox"
              id="hh-active"
              checked={active}
              onChange={(e) => setActive(e.target.checked)}
            />
            <Label htmlFor="hh-active">{t("col.active")}</Label>
          </div>
          <DialogFooter className="pt-3">
            <Button type="button" variant="outline" onClick={onClose} disabled={pending}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit" disabled={pending}>
              {pending && <Loader2 className="h-4 w-4 animate-spin" />}
              {tCommon("save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
