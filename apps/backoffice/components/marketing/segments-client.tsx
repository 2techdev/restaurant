"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Trash2, Edit, Sparkles, Loader2 } from "lucide-react";
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

// Mirrors crm.SegmentFilter.
type FilterType =
  | "last_visit_before_days"
  | "last_visit_after_days"
  | "never_visited"
  | "total_visits_min"
  | "total_visits_max"
  | "total_spend_min_cents"
  | "total_spend_max_cents"
  | "has_tag"
  | "has_dietary_tag"
  | "has_allergen"
  | "birthday_in_days"
  | "anniversary_in_days"
  | "first_visit_before_days"
  | "preferred_hour_bucket_in"
  | "preferred_payment_method";

interface Filter {
  type: FilterType;
  days?: number;
  value?: number;
  tag?: string;
  hours?: number[];
}

interface Definition {
  combinator: "AND" | "OR";
  filters: Filter[];
}

interface Segment {
  id: string;
  tenant_id: string;
  name: string;
  description?: string | null;
  definition: Definition;
  is_dynamic: boolean;
  created_at: string;
  updated_at: string;
  member_count?: number;
}

const FILTER_LABELS: Record<FilterType, string> = {
  last_visit_before_days: "Letzter Besuch vor N Tagen",
  last_visit_after_days: "Letzter Besuch in N Tagen",
  never_visited: "Nie besucht",
  total_visits_min: "Mind. N Besuche",
  total_visits_max: "Höchstens N Besuche",
  total_spend_min_cents: "Mind. Ausgaben (Rappen)",
  total_spend_max_cents: "Max. Ausgaben (Rappen)",
  has_tag: "Tag gesetzt",
  has_dietary_tag: "Ernährungs-Tag",
  has_allergen: "Allergen",
  birthday_in_days: "Geburtstag in N Tagen",
  anniversary_in_days: "Jubiläum in N Tagen",
  first_visit_before_days: "Erstbesuch vor N Tagen",
  preferred_hour_bucket_in: "Stunde (kommagetrennt)",
  preferred_payment_method: "Bevorzugte Zahlung",
};

const FILTER_NEEDS: Record<FilterType, ("days" | "value" | "tag" | "hours")[]> = {
  last_visit_before_days: ["days"],
  last_visit_after_days: ["days"],
  never_visited: [],
  total_visits_min: ["value"],
  total_visits_max: ["value"],
  total_spend_min_cents: ["value"],
  total_spend_max_cents: ["value"],
  has_tag: ["tag"],
  has_dietary_tag: ["tag"],
  has_allergen: ["tag"],
  birthday_in_days: ["days"],
  anniversary_in_days: ["days"],
  first_visit_before_days: ["days"],
  preferred_hour_bucket_in: ["hours"],
  preferred_payment_method: ["tag"],
};

const PRESETS: { key: string; name: string; def: Definition }[] = [
  {
    key: "inactive_30d",
    name: "Inaktiv (30 Tage)",
    def: { combinator: "AND", filters: [{ type: "last_visit_before_days", days: 30 }] },
  },
  {
    key: "loyal_5_visits_30d",
    name: "Loyal (≥5 Besuche / 30T)",
    def: {
      combinator: "AND",
      filters: [
        { type: "last_visit_after_days", days: 30 },
        { type: "total_visits_min", value: 5 },
      ],
    },
  },
  {
    key: "birthday_this_week",
    name: "Geburtstag diese Woche",
    def: { combinator: "AND", filters: [{ type: "birthday_in_days", days: 7 }] },
  },
  {
    key: "single_visit",
    name: "Einmal-Besucher",
    def: { combinator: "AND", filters: [{ type: "total_visits_max", value: 1 }] },
  },
  {
    key: "vip",
    name: "VIP-Tag",
    def: { combinator: "AND", filters: [{ type: "has_tag", tag: "VIP" }] },
  },
];

export function SegmentsClient() {
  const t = useTranslations("marketing");
  const tCommon = useTranslations("common");
  const qc = useQueryClient();
  const { toast } = useToast();

  const [open, setOpen] = React.useState(false);
  const [editing, setEditing] = React.useState<Segment | null>(null);
  const [name, setName] = React.useState("");
  const [description, setDescription] = React.useState("");
  const [combinator, setCombinator] = React.useState<"AND" | "OR">("AND");
  const [filters, setFilters] = React.useState<Filter[]>([]);
  const [previewCount, setPreviewCount] = React.useState<number | null>(null);
  const [previewLoading, setPreviewLoading] = React.useState(false);

  const list = useQuery<Segment[]>({
    queryKey: ["segments"],
    queryFn: async () => {
      const data = await clientFetch<{ segments?: Segment[] }>({ path: "/crm/segments" });
      return data.segments ?? [];
    },
  });

  const save = useMutation({
    mutationFn: async () => {
      const def: Definition = { combinator, filters };
      if (editing) {
        return clientFetch({
          path: `/crm/segments/${editing.id}`,
          method: "PUT",
          body: { name, description: description || null, definition: def },
        });
      }
      return clientFetch({
        path: "/crm/segments",
        method: "POST",
        body: {
          id: crypto.randomUUID(),
          name,
          description: description || null,
          definition: def,
        },
      });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["segments"] });
      toast({ title: tCommon("success") });
      setOpen(false);
      setEditing(null);
    },
    onError: (e) =>
      toast({ title: tCommon("error"), description: e instanceof Error ? e.message : String(e), variant: "destructive" }),
  });

  const remove = useMutation({
    mutationFn: async (id: string) => clientFetch({ path: `/crm/segments/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["segments"] });
      toast({ title: tCommon("success") });
    },
  });

  React.useEffect(() => {
    if (!open) return;
    let cancelled = false;
    const id = setTimeout(async () => {
      setPreviewLoading(true);
      try {
        const res = await clientFetch<{ matched_count?: number }>({
          path: "/crm/segments/preview",
          method: "POST",
          body: { definition: { combinator, filters } },
        });
        if (!cancelled) setPreviewCount(res.matched_count ?? 0);
      } catch {
        if (!cancelled) setPreviewCount(null);
      } finally {
        if (!cancelled) setPreviewLoading(false);
      }
    }, 350);
    return () => {
      cancelled = true;
      clearTimeout(id);
    };
  }, [combinator, filters, open]);

  function openCreate() {
    setEditing(null);
    setName("");
    setDescription("");
    setCombinator("AND");
    setFilters([]);
    setPreviewCount(null);
    setOpen(true);
  }
  function openEdit(s: Segment) {
    setEditing(s);
    setName(s.name);
    setDescription(s.description ?? "");
    setCombinator(s.definition?.combinator ?? "AND");
    setFilters(s.definition?.filters ?? []);
    setPreviewCount(s.member_count ?? null);
    setOpen(true);
  }
  function applyPreset(key: string) {
    const p = PRESETS.find((x) => x.key === key);
    if (!p) return;
    setName(p.name);
    setCombinator(p.def.combinator);
    setFilters(p.def.filters);
  }

  function addFilter() {
    setFilters([...filters, { type: "last_visit_before_days", days: 30 }]);
  }
  function updateFilter(i: number, f: Filter) {
    const next = [...filters];
    next[i] = f;
    setFilters(next);
  }
  function removeFilter(i: number) {
    setFilters(filters.filter((_, idx) => idx !== i));
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-muted-foreground mr-1">{t("segments.presets")}:</span>
        {PRESETS.map((p) => (
          <Badge
            key={p.key}
            variant="outline"
            className="cursor-pointer"
            onClick={() => {
              openCreate();
              applyPreset(p.key);
            }}
          >
            {p.name}
          </Badge>
        ))}
        <Button onClick={openCreate} className="ml-auto">
          <Plus className="mr-2 h-4 w-4" />
          {t("segments.new")}
        </Button>
      </div>

      {list.isLoading ? (
        <div className="text-sm text-muted-foreground">{tCommon("loading")}</div>
      ) : (list.data ?? []).length === 0 ? (
        <Card>
          <CardContent className="p-6 text-center text-sm text-muted-foreground">
            {t("segments.empty")}
          </CardContent>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {(list.data ?? []).map((s) => (
            <Card key={s.id}>
              <CardContent className="p-4 space-y-3">
                <div className="flex items-start justify-between">
                  <div>
                    <h3 className="font-medium">{s.name}</h3>
                    {s.description && (
                      <p className="text-xs text-muted-foreground">{s.description}</p>
                    )}
                  </div>
                  <Badge variant="secondary" className="tabular-nums">
                    {s.member_count ?? 0}
                  </Badge>
                </div>
                <div className="flex flex-wrap gap-1">
                  {(s.definition?.filters ?? []).slice(0, 4).map((f, i) => (
                    <Badge key={i} variant="outline" className="text-[10px] font-normal">
                      {FILTER_LABELS[f.type]}
                      {f.days != null ? `: ${f.days}d` : ""}
                      {f.value != null ? `: ${f.value}` : ""}
                      {f.tag ? `: ${f.tag}` : ""}
                    </Badge>
                  ))}
                  {(s.definition?.filters ?? []).length === 0 && (
                    <Badge variant="outline" className="text-[10px]">
                      {t("segments.allCustomers")}
                    </Badge>
                  )}
                </div>
                <div className="flex gap-1">
                  <Button size="sm" variant="ghost" onClick={() => openEdit(s)}>
                    <Edit className="h-3.5 w-3.5 mr-1" />
                    {tCommon("edit")}
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      if (confirm(t("segments.confirmDelete", { name: s.name }))) remove.mutate(s.id);
                    }}
                  >
                    <Trash2 className="h-3.5 w-3.5 mr-1 text-destructive" />
                    {tCommon("delete")}
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Sparkles className="h-4 w-4 text-primary" />
              {editing ? t("segments.edit") : t("segments.new")}
            </DialogTitle>
            <DialogDescription>{t("segments.formHint")}</DialogDescription>
          </DialogHeader>

          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label>{t("segments.name")}</Label>
                <Input value={name} onChange={(e) => setName(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label>{t("segments.combinator")}</Label>
                <Select value={combinator} onValueChange={(v) => setCombinator(v as "AND" | "OR")}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="AND">UND (alle erfüllt)</SelectItem>
                    <SelectItem value="OR">ODER (mind. eins)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1 col-span-2">
                <Label>{t("segments.description")}</Label>
                <Input value={description} onChange={(e) => setDescription(e.target.value)} />
              </div>
            </div>

            <div className="space-y-2 rounded-md border p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">{t("segments.filters")}</span>
                <Button size="sm" variant="outline" onClick={addFilter}>
                  <Plus className="h-3.5 w-3.5 mr-1" />
                  {t("segments.addFilter")}
                </Button>
              </div>
              {filters.length === 0 && (
                <p className="text-xs text-muted-foreground">
                  {t("segments.noFiltersHint")}
                </p>
              )}
              {filters.map((f, i) => {
                const needs = FILTER_NEEDS[f.type];
                return (
                  <div key={i} className="grid grid-cols-12 gap-2 items-end">
                    <div className="col-span-6 space-y-1">
                      <Label className="text-xs">{t("segments.filterType")}</Label>
                      <Select
                        value={f.type}
                        onValueChange={(v) =>
                          updateFilter(i, { type: v as FilterType, days: 30 })
                        }
                      >
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          {Object.entries(FILTER_LABELS).map(([k, label]) => (
                            <SelectItem key={k} value={k}>{label}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <div className="col-span-5">
                      {needs.includes("days") && (
                        <div className="space-y-1">
                          <Label className="text-xs">{t("segments.days")}</Label>
                          <Input
                            type="number"
                            value={f.days ?? ""}
                            onChange={(e) => updateFilter(i, { ...f, days: Number(e.target.value) })}
                          />
                        </div>
                      )}
                      {needs.includes("value") && (
                        <div className="space-y-1">
                          <Label className="text-xs">{t("segments.value")}</Label>
                          <Input
                            type="number"
                            value={f.value ?? ""}
                            onChange={(e) => updateFilter(i, { ...f, value: Number(e.target.value) })}
                          />
                        </div>
                      )}
                      {needs.includes("tag") && (
                        <div className="space-y-1">
                          <Label className="text-xs">{t("segments.tag")}</Label>
                          <Input
                            value={f.tag ?? ""}
                            onChange={(e) => updateFilter(i, { ...f, tag: e.target.value })}
                          />
                        </div>
                      )}
                      {needs.includes("hours") && (
                        <div className="space-y-1">
                          <Label className="text-xs">{t("segments.hours")}</Label>
                          <Input
                            placeholder="11,12,13"
                            value={(f.hours ?? []).join(",")}
                            onChange={(e) =>
                              updateFilter(i, {
                                ...f,
                                hours: e.target.value
                                  .split(",")
                                  .map((s) => parseInt(s.trim(), 10))
                                  .filter((n) => !isNaN(n) && n >= 0 && n <= 23),
                              })
                            }
                          />
                        </div>
                      )}
                      {needs.length === 0 && (
                        <p className="text-xs text-muted-foreground">{t("segments.noParam")}</p>
                      )}
                    </div>
                    <div className="col-span-1">
                      <Button size="icon" variant="ghost" onClick={() => removeFilter(i)}>
                        <Trash2 className="h-4 w-4 text-destructive" />
                      </Button>
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="flex items-center justify-between rounded-md bg-muted/30 p-3 text-sm">
              <span className="text-muted-foreground">{t("segments.matchedCount")}:</span>
              <span className="font-mono tabular-nums">
                {previewLoading ? <Loader2 className="h-4 w-4 animate-spin inline" /> : (previewCount ?? "—")}
              </span>
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
    </div>
  );
}
