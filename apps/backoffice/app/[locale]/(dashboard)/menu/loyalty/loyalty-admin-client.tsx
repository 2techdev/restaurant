"use client";

/**
 * Loyalty program admin UI — tenant-scoped settings + tier editor + bonus
 * campaigns. Reads from /api/v1/loyalty/{settings,tiers,bonus-campaigns}.
 *
 * Tier list comes pre-seeded by migration 036 (Bronze / Silber / Gold / Platin
 * with Swiss-DE labels) — operator can override any field.
 */

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus, Pencil, Trash2, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from "@/components/ui/table";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

interface Settings {
  is_enabled: boolean;
  earn_rate_points_per_chf: number;
  redeem_rate_points_per_chf: number;
  expiry_months: number;
}

interface Tier {
  id: string;
  code: string;
  name: string;
  name_translations?: Record<string, string>;
  min_points: number;
  max_points: number | null;
  multiplier: number;
  benefits: Array<{ type: string; value?: number }>;
  color_hex?: string | null;
  sort_order: number;
  is_active: boolean;
}

interface BonusCampaign {
  id: string;
  name: string;
  description?: string;
  multiplier: number;
  starts_at: string;
  ends_at: string;
  is_active: boolean;
}

const canEdit = (role: string) =>
  ["OWNER", "MANAGER", "HQ_ADMIN", "HQ_MANAGER"].includes(role);

export function LoyaltyAdminClient({ userRole }: { userRole: string }) {
  const t = useTranslations("loyaltyAdmin");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const writable = canEdit(userRole);

  // ------ Settings --------------------------------------------------------
  const settingsQ = useQuery<Settings>({
    queryKey: ["loyalty-settings"],
    queryFn: () => clientFetch<Settings>({ path: "/loyalty/settings" }),
  });

  const saveSettings = useMutation({
    mutationFn: (body: Partial<Settings>) =>
      clientFetch<Settings>({ path: "/loyalty/settings", method: "PUT", body }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["loyalty-settings"] });
      toast({ title: tCommon("success") });
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  // ------ Tiers -----------------------------------------------------------
  const tiersQ = useQuery<{ tiers: Tier[] }>({
    queryKey: ["loyalty-tiers"],
    queryFn: () => clientFetch<{ tiers: Tier[] }>({ path: "/loyalty/tiers" }),
  });

  const [editingTier, setEditingTier] = React.useState<Tier | null>(null);
  const [newTierOpen, setNewTierOpen] = React.useState(false);

  const upsertTier = useMutation({
    mutationFn: async (tier: Partial<Tier> & { id?: string }) => {
      const body = {
        code: tier.code,
        name: tier.name,
        name_translations: tier.name_translations ?? {},
        min_points: tier.min_points,
        max_points: tier.max_points,
        multiplier: tier.multiplier,
        benefits: tier.benefits ?? [],
        color_hex: tier.color_hex,
        sort_order: tier.sort_order ?? 0,
        is_active: tier.is_active ?? true,
      };
      if (tier.id) {
        return clientFetch({ path: `/loyalty/tiers/${tier.id}`, method: "PUT", body });
      }
      return clientFetch({ path: "/loyalty/tiers", method: "POST", body });
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["loyalty-tiers"] });
      setEditingTier(null);
      setNewTierOpen(false);
      toast({ title: tCommon("success") });
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  const deleteTier = useMutation({
    mutationFn: (id: string) => clientFetch({ path: `/loyalty/tiers/${id}`, method: "DELETE" }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["loyalty-tiers"] });
      toast({ title: tCommon("deleted") });
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  // ------ Bonus campaigns -------------------------------------------------
  const campaignsQ = useQuery<{ campaigns: BonusCampaign[] }>({
    queryKey: ["loyalty-bonus-campaigns"],
    queryFn: () =>
      clientFetch<{ campaigns: BonusCampaign[] }>({ path: "/loyalty/bonus-campaigns" }),
  });

  return (
    <div className="space-y-6">
      {/* Program settings */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between gap-2">
            <div>
              <CardTitle>{t("settings.title")}</CardTitle>
              <CardDescription>{t("settings.subtitle")}</CardDescription>
            </div>
            {settingsQ.data && (
              <div className="flex items-center gap-2">
                <Label htmlFor="enable-loyalty">{t("settings.enabled")}</Label>
                <Switch
                  id="enable-loyalty"
                  checked={settingsQ.data.is_enabled}
                  disabled={!writable || saveSettings.isPending}
                  onCheckedChange={(checked) =>
                    saveSettings.mutate({ is_enabled: checked })
                  }
                />
              </div>
            )}
          </div>
        </CardHeader>
        <CardContent>
          {settingsQ.isLoading && (
            <p className="text-sm text-muted-foreground">{tCommon("loading")}</p>
          )}
          {settingsQ.data && (
            <SettingsForm
              initial={settingsQ.data}
              disabled={!writable}
              onSubmit={(patch) => saveSettings.mutate(patch)}
              saving={saveSettings.isPending}
              t={t}
            />
          )}
        </CardContent>
      </Card>

      {/* Tiers */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>{t("tiers.title")}</CardTitle>
              <CardDescription>{t("tiers.subtitle")}</CardDescription>
            </div>
            {writable && (
              <Button size="sm" onClick={() => setNewTierOpen(true)}>
                <Plus className="h-4 w-4 mr-1" /> {t("tiers.add")}
              </Button>
            )}
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("tiers.col.name")}</TableHead>
                <TableHead>{t("tiers.col.range")}</TableHead>
                <TableHead>{t("tiers.col.multiplier")}</TableHead>
                <TableHead>{t("tiers.col.benefits")}</TableHead>
                <TableHead className="w-28 text-right">{tCommon("actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(tiersQ.data?.tiers ?? []).map((tier) => (
                <TableRow key={tier.id}>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <span
                        aria-hidden
                        className="h-3 w-3 rounded-full inline-block"
                        style={{ backgroundColor: tier.color_hex ?? "#888" }}
                      />
                      <span className="font-medium">{tier.name}</span>
                      <Badge variant="outline">{tier.code}</Badge>
                    </div>
                  </TableCell>
                  <TableCell className="font-mono text-xs">
                    {tier.min_points} – {tier.max_points ?? "∞"}
                  </TableCell>
                  <TableCell className="font-mono">×{tier.multiplier.toFixed(2)}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {tier.benefits.length === 0
                      ? "—"
                      : tier.benefits.map((b, i) => (
                          <Badge key={i} variant="secondary" className="mr-1">
                            {b.type}
                            {b.value != null ? ` ${b.value}` : ""}
                          </Badge>
                        ))}
                  </TableCell>
                  <TableCell className="text-right">
                    {writable && (
                      <>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => setEditingTier(tier)}
                        >
                          <Pencil className="h-4 w-4" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => {
                            if (confirm(t("tiers.deleteConfirm"))) {
                              deleteTier.mutate(tier.id);
                            }
                          }}
                        >
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </>
                    )}
                  </TableCell>
                </TableRow>
              ))}
              {!tiersQ.isLoading && (tiersQ.data?.tiers ?? []).length === 0 && (
                <TableRow>
                  <TableCell colSpan={5} className="text-center text-sm text-muted-foreground py-6">
                    {t("tiers.empty")}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Bonus campaigns */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>
                <Sparkles className="h-4 w-4 inline mr-1" />
                {t("campaigns.title")}
              </CardTitle>
              <CardDescription>{t("campaigns.subtitle")}</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("campaigns.col.name")}</TableHead>
                <TableHead>{t("campaigns.col.window")}</TableHead>
                <TableHead>{t("campaigns.col.multiplier")}</TableHead>
                <TableHead>{t("campaigns.col.status")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(campaignsQ.data?.campaigns ?? []).map((c) => {
                const now = new Date();
                const active = c.is_active && new Date(c.starts_at) <= now && new Date(c.ends_at) >= now;
                return (
                  <TableRow key={c.id}>
                    <TableCell>{c.name}</TableCell>
                    <TableCell className="text-xs font-mono">
                      {new Date(c.starts_at).toLocaleDateString()} → {new Date(c.ends_at).toLocaleDateString()}
                    </TableCell>
                    <TableCell className="font-mono">×{c.multiplier.toFixed(2)}</TableCell>
                    <TableCell>
                      <Badge variant={active ? "default" : "outline"}>
                        {active ? t("campaigns.active") : t("campaigns.inactive")}
                      </Badge>
                    </TableCell>
                  </TableRow>
                );
              })}
              {(campaignsQ.data?.campaigns ?? []).length === 0 && (
                <TableRow>
                  <TableCell colSpan={4} className="text-center text-sm text-muted-foreground py-6">
                    {t("campaigns.empty")}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <TierDialog
        open={editingTier !== null || newTierOpen}
        tier={editingTier}
        onClose={() => {
          setEditingTier(null);
          setNewTierOpen(false);
        }}
        onSubmit={(tier) => upsertTier.mutate(tier)}
        saving={upsertTier.isPending}
        t={t}
        tCommon={tCommon}
      />
    </div>
  );
}

function SettingsForm({
  initial, disabled, onSubmit, saving, t,
}: {
  initial: Settings;
  disabled: boolean;
  onSubmit: (patch: Partial<Settings>) => void;
  saving: boolean;
  t: (key: string) => string;
}) {
  const [earn, setEarn] = React.useState(initial.earn_rate_points_per_chf);
  const [redeem, setRedeem] = React.useState(initial.redeem_rate_points_per_chf);
  const [expiry, setExpiry] = React.useState(initial.expiry_months);

  React.useEffect(() => {
    setEarn(initial.earn_rate_points_per_chf);
    setRedeem(initial.redeem_rate_points_per_chf);
    setExpiry(initial.expiry_months);
  }, [initial]);

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div>
        <Label htmlFor="earn-rate">{t("settings.earnRate")}</Label>
        <Input
          id="earn-rate"
          type="number"
          step="0.0001"
          min="0"
          value={earn}
          disabled={disabled}
          onChange={(e) => setEarn(parseFloat(e.target.value))}
          onBlur={() =>
            earn !== initial.earn_rate_points_per_chf &&
            onSubmit({ earn_rate_points_per_chf: earn })
          }
        />
        <p className="text-xs text-muted-foreground mt-1">{t("settings.earnRateHint")}</p>
      </div>
      <div>
        <Label htmlFor="redeem-rate">{t("settings.redeemRate")}</Label>
        <Input
          id="redeem-rate"
          type="number"
          step="0.0001"
          min="0"
          value={redeem}
          disabled={disabled}
          onChange={(e) => setRedeem(parseFloat(e.target.value))}
          onBlur={() =>
            redeem !== initial.redeem_rate_points_per_chf &&
            onSubmit({ redeem_rate_points_per_chf: redeem })
          }
        />
        <p className="text-xs text-muted-foreground mt-1">{t("settings.redeemRateHint")}</p>
      </div>
      <div>
        <Label htmlFor="expiry-months">{t("settings.expiryMonths")}</Label>
        <Input
          id="expiry-months"
          type="number"
          step="1"
          min="1"
          value={expiry}
          disabled={disabled}
          onChange={(e) => setExpiry(parseInt(e.target.value, 10))}
          onBlur={() =>
            expiry !== initial.expiry_months &&
            onSubmit({ expiry_months: expiry })
          }
        />
        <p className="text-xs text-muted-foreground mt-1">{t("settings.expiryHint")}</p>
      </div>
      {saving && <p className="text-xs text-muted-foreground col-span-full">…</p>}
    </div>
  );
}

function TierDialog({
  open, tier, onClose, onSubmit, saving, t, tCommon,
}: {
  open: boolean;
  tier: Tier | null;
  onClose: () => void;
  onSubmit: (tier: Partial<Tier> & { id?: string }) => void;
  saving: boolean;
  t: (key: string) => string;
  tCommon: (key: string) => string;
}) {
  const [form, setForm] = React.useState<Partial<Tier>>({});

  React.useEffect(() => {
    if (open) {
      setForm(
        tier ?? {
          code: "",
          name: "",
          min_points: 0,
          max_points: null,
          multiplier: 1.0,
          benefits: [],
          color_hex: "#888888",
          sort_order: 99,
          is_active: true,
        }
      );
    }
  }, [open, tier]);

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{tier ? t("tiers.edit") : t("tiers.add")}</DialogTitle>
          <DialogDescription>{t("tiers.formHint")}</DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="col-span-1">
            <Label>{t("tiers.col.code")}</Label>
            <Input
              value={form.code ?? ""}
              disabled={!!tier}
              onChange={(e) => setForm({ ...form, code: e.target.value })}
              placeholder="silver"
            />
          </div>
          <div className="col-span-1">
            <Label>{t("tiers.col.name")}</Label>
            <Input
              value={form.name ?? ""}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
          </div>
          <div className="col-span-1">
            <Label>{t("tiers.col.minPoints")}</Label>
            <Input
              type="number"
              value={form.min_points ?? 0}
              onChange={(e) => setForm({ ...form, min_points: parseInt(e.target.value, 10) })}
            />
          </div>
          <div className="col-span-1">
            <Label>{t("tiers.col.maxPoints")}</Label>
            <Input
              type="number"
              placeholder="∞"
              value={form.max_points ?? ""}
              onChange={(e) =>
                setForm({
                  ...form,
                  max_points: e.target.value === "" ? null : parseInt(e.target.value, 10),
                })
              }
            />
          </div>
          <div className="col-span-1">
            <Label>{t("tiers.col.multiplier")}</Label>
            <Input
              type="number"
              step="0.05"
              value={form.multiplier ?? 1}
              onChange={(e) =>
                setForm({ ...form, multiplier: parseFloat(e.target.value) })
              }
            />
          </div>
          <div className="col-span-1">
            <Label>{t("tiers.col.color")}</Label>
            <Input
              type="color"
              value={form.color_hex ?? "#888888"}
              onChange={(e) => setForm({ ...form, color_hex: e.target.value })}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>{tCommon("cancel")}</Button>
          <Button
            disabled={saving || !form.code || !form.name}
            onClick={() => onSubmit({ ...form, id: tier?.id })}
          >
            {tCommon("save")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
