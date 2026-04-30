"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";

interface LoyaltyConfig {
  earn_rate_chf_to_points: number;
  redeem_rate_points_to_chf: number;
  tier_silver_min: number;
  tier_gold_min: number;
}

interface LoyaltyMember {
  customer_id: string;
  name: string;
  points: number;
  tier: "BASIC" | "SILVER" | "GOLD" | string;
  total_spent: number;
}

const configSchema = z.object({
  earn_rate_chf_to_points: z.coerce.number().min(0),
  redeem_rate_points_to_chf: z.coerce.number().min(0),
  tier_silver_min: z.coerce.number().min(0),
  tier_gold_min: z.coerce.number().min(0),
});
type ConfigForm = z.infer<typeof configSchema>;

const adjustSchema = z.object({
  customer_id: z.string().min(1),
  points_delta: z.coerce.number(),
  reason: z.string().min(2),
});
type AdjustForm = z.infer<typeof adjustSchema>;

export function LoyaltyClient() {
  const t = useTranslations("loyalty");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();
  const [adjustOpen, setAdjustOpen] = React.useState(false);

  const cfgQuery = useQuery<LoyaltyConfig | null>({
    queryKey: ["loyalty-config"],
    queryFn: async () => {
      try {
        return await clientFetch<LoyaltyConfig>({ path: "/loyalty/config" });
      } catch {
        return null;
      }
    },
  });

  const membersQuery = useQuery<LoyaltyMember[]>({
    queryKey: ["loyalty-top"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ members?: LoyaltyMember[] } | LoyaltyMember[]>({
          path: "/loyalty/top?limit=20",
        });
        if (Array.isArray(data)) return data;
        return data.members ?? [];
      } catch {
        return [];
      }
    },
  });

  const cfgForm = useForm<ConfigForm>({
    resolver: zodResolver(configSchema),
    values: cfgQuery.data
      ? {
          earn_rate_chf_to_points: cfgQuery.data.earn_rate_chf_to_points ?? 1,
          redeem_rate_points_to_chf: cfgQuery.data.redeem_rate_points_to_chf ?? 100,
          tier_silver_min: cfgQuery.data.tier_silver_min ?? 500,
          tier_gold_min: cfgQuery.data.tier_gold_min ?? 2000,
        }
      : { earn_rate_chf_to_points: 1, redeem_rate_points_to_chf: 100, tier_silver_min: 500, tier_gold_min: 2000 },
  });

  const adjustForm = useForm<AdjustForm>({ resolver: zodResolver(adjustSchema) });

  const saveCfg = useMutation({
    mutationFn: async (values: ConfigForm) =>
      clientFetch({ path: "/loyalty/config", method: "PUT", body: values }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["loyalty-config"] });
      toast({ title: tCommon("success") });
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  const adjust = useMutation({
    mutationFn: async (values: AdjustForm) =>
      clientFetch({ path: `/loyalty/adjust`, method: "POST", body: values }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["loyalty-top"] });
      toast({ title: tCommon("success") });
      setAdjustOpen(false);
      adjustForm.reset();
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("programSettings")}</CardTitle>
        </CardHeader>
        <CardContent>
          <form
            className="space-y-3"
            onSubmit={cfgForm.handleSubmit((v) => saveCfg.mutate(v))}
          >
            <div className="space-y-1">
              <Label htmlFor="earn">{t("earnRate")}</Label>
              <Input id="earn" type="number" step="0.1" {...cfgForm.register("earn_rate_chf_to_points")} />
              <p className="text-xs text-muted-foreground">{t("earnRateHint")}</p>
            </div>
            <div className="space-y-1">
              <Label htmlFor="redeem">{t("redeemRate")}</Label>
              <Input
                id="redeem"
                type="number"
                step="1"
                {...cfgForm.register("redeem_rate_points_to_chf")}
              />
              <p className="text-xs text-muted-foreground">{t("redeemRateHint")}</p>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label htmlFor="silver">{t("silverThreshold")}</Label>
                <Input id="silver" type="number" {...cfgForm.register("tier_silver_min")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="gold">{t("goldThreshold")}</Label>
                <Input id="gold" type="number" {...cfgForm.register("tier_gold_min")} />
              </div>
            </div>
            <div className="flex justify-end pt-2">
              <Button type="submit" disabled={saveCfg.isPending}>
                {saveCfg.isPending ? tCommon("loading") : tCommon("save")}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <CardTitle className="text-base">{t("topMembers")}</CardTitle>
          <Button size="sm" variant="outline" onClick={() => setAdjustOpen(true)}>
            {t("manualAdjust")}
          </Button>
        </CardHeader>
        <CardContent className="p-0">
          {membersQuery.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : (membersQuery.data ?? []).length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">{tCommon("noData")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("colMember")}</TableHead>
                  <TableHead>{t("colTier")}</TableHead>
                  <TableHead className="text-right">{t("colPoints")}</TableHead>
                  <TableHead className="text-right">{t("colSpent")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(membersQuery.data ?? []).map((m) => (
                  <TableRow key={m.customer_id}>
                    <TableCell className="font-medium">{m.name}</TableCell>
                    <TableCell>
                      <Badge variant={m.tier === "GOLD" ? "default" : "secondary"}>{m.tier}</Badge>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{m.points}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(m.total_spent)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Dialog open={adjustOpen} onOpenChange={setAdjustOpen}>
        <DialogContent>
          <form
            onSubmit={adjustForm.handleSubmit((v) => adjust.mutate(v))}
            className="space-y-4"
          >
            <DialogHeader>
              <DialogTitle>{t("manualAdjust")}</DialogTitle>
            </DialogHeader>
            <div className="space-y-3">
              <div className="space-y-1">
                <Label htmlFor="adj-cid">{t("customerId")}</Label>
                <Input id="adj-cid" {...adjustForm.register("customer_id")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="adj-pts">{t("pointsDelta")}</Label>
                <Input id="adj-pts" type="number" {...adjustForm.register("points_delta")} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="adj-reason">{t("reason")}</Label>
                <Input id="adj-reason" {...adjustForm.register("reason")} />
              </div>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setAdjustOpen(false)}>
                {tCommon("cancel")}
              </Button>
              <Button type="submit" disabled={adjust.isPending}>
                {adjust.isPending ? tCommon("loading") : tCommon("apply")}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
