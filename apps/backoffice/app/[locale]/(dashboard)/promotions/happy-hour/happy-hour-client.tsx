"use client";

/**
 * Happy hour rules — UI only (in-memory).
 *
 * Backend `happy_hour_rules` is not wired yet. The client persists draft
 * rules to localStorage so the operator can sketch the rule set with the
 * design team. Once the backend lands, swap the localStorage store for
 * TanStack Query mutations.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { z } from "zod";
import { Plus, AlertCircle, Trash2, Pencil, Clock } from "lucide-react";

import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Alert, AlertDescription } from "@/components/ui/alert";
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

const STORAGE_KEY = "bo.happyhour.drafts.v1";

const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
type Day = (typeof DAYS)[number];

const RuleSchema = z.object({
  id: z.string(),
  name: z.string().min(1),
  days: z.array(z.string()),
  start_time: z.string(),
  end_time: z.string(),
  discount_type: z.enum(["PERCENT", "FIXED"]),
  discount_value: z.number().min(0),
  active: z.boolean(),
});
type Rule = z.infer<typeof RuleSchema>;

function load(): Rule[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((x): x is Rule => RuleSchema.safeParse(x).success);
  } catch {
    return [];
  }
}
function save(items: Rule[]) {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch {
    // ignore
  }
}

export function HappyHourClient() {
  const t = useTranslations("promotions.happyHour");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [items, setItems] = React.useState<Rule[]>([]);
  const [editing, setEditing] = React.useState<Rule | "create" | null>(null);

  React.useEffect(() => {
    setItems(load());
  }, []);

  const persist = (next: Rule[]) => {
    setItems(next);
    save(next);
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
          {t("newRule")}
        </Button>
      </div>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 text-sm font-medium">
          {t("listHeader", { count: items.length })}
        </div>
        {items.length === 0 ? (
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
                <TableHead className="w-12"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((r) => (
                <TableRow key={r.id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{r.name}</TableCell>
                  <TableCell>
                    <div className="flex gap-1 flex-wrap">
                      {r.days.map((d) => (
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
                    {r.start_time} → {r.end_time}
                  </TableCell>
                  <TableCell className="font-mono tabular-nums">
                    {r.discount_type === "PERCENT" ? `%${r.discount_value}` : `CHF ${r.discount_value}`}
                  </TableCell>
                  <TableCell>
                    {r.active ? (
                      <StatusBadge variant="success" withDot>
                        {tCommon("active")}
                      </StatusBadge>
                    ) : (
                      <StatusBadge variant="neutral">{tCommon("inactive")}</StatusBadge>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8"
                        onClick={() => setEditing(r)}
                      >
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-error"
                        onClick={() => persist(items.filter((x) => x.id !== r.id))}
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

      <RuleForm
        editing={editing}
        onClose={() => setEditing(null)}
        onSubmit={(rule) => {
          if (editing === "create") {
            persist([...items, rule]);
            toast({ title: t("createdToast") });
          } else if (editing) {
            persist(items.map((x) => (x.id === rule.id ? rule : x)));
            toast({ title: t("updatedToast") });
          }
          setEditing(null);
        }}
      />
    </div>
  );
}

function RuleForm({
  editing,
  onClose,
  onSubmit,
}: {
  editing: Rule | "create" | null;
  onClose: () => void;
  onSubmit: (rule: Rule) => void;
}) {
  const t = useTranslations("promotions.happyHour");
  const tCommon = useTranslations("common");
  const isEdit = editing && editing !== "create";
  const initial: Rule | null = isEdit ? (editing as Rule) : null;

  const [name, setName] = React.useState("");
  const [days, setDays] = React.useState<string[]>([]);
  const [startTime, setStartTime] = React.useState("17:00");
  const [endTime, setEndTime] = React.useState("19:00");
  const [type, setType] = React.useState<"PERCENT" | "FIXED">("PERCENT");
  const [value, setValue] = React.useState(20);
  const [active, setActive] = React.useState(true);

  React.useEffect(() => {
    if (initial) {
      setName(initial.name);
      setDays(initial.days);
      setStartTime(initial.start_time);
      setEndTime(initial.end_time);
      setType(initial.discount_type);
      setValue(initial.discount_value);
      setActive(initial.active);
    } else {
      setName("");
      setDays([]);
      setStartTime("17:00");
      setEndTime("19:00");
      setType("PERCENT");
      setValue(20);
      setActive(true);
    }
  }, [editing, initial]);

  const toggleDay = (d: Day) => {
    setDays((prev) => (prev.includes(d) ? prev.filter((x) => x !== d) : [...prev, d]));
  };

  const onSave = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || days.length === 0) return;
    onSubmit({
      id: initial?.id ?? crypto.randomUUID(),
      name: name.trim(),
      days,
      start_time: startTime,
      end_time: endTime,
      discount_type: type,
      discount_value: value,
      active,
    });
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
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t("namePlaceholder")}
            />
          </div>
          <div className="space-y-1">
            <Label>{t("col.days")}</Label>
            <div className="flex gap-1">
              {DAYS.map((d) => {
                const on = days.includes(d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => toggleDay(d)}
                    className={`flex-1 py-2 rounded text-xs font-medium uppercase tracking-wider transition-colors ${
                      on
                        ? "bg-primary text-primary-foreground"
                        : "bg-muted text-muted-foreground hover:bg-muted/70"
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
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
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
            <Button type="button" variant="outline" onClick={onClose}>
              {tCommon("cancel")}
            </Button>
            <Button type="submit">{tCommon("save")}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
