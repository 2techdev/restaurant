"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { CreditCard, Banknote, Smartphone, Lock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

interface PaymentMethods {
  cash_enabled: boolean;
  card_enabled: boolean;
  card_terminal_ip?: string | null;
  twint_enabled: boolean;
  stripe_enabled: boolean;
  stripe_api_key?: string | null;
}

const DEFAULT: PaymentMethods = {
  cash_enabled: true,
  card_enabled: false,
  card_terminal_ip: "",
  twint_enabled: false,
  stripe_enabled: false,
  stripe_api_key: "",
};

export function PaymentMethodsClient() {
  const t = useTranslations("paymentMethods");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const query = useQuery<PaymentMethods | null>({
    queryKey: ["payment-methods"],
    queryFn: async () => {
      try {
        return await clientFetch<PaymentMethods>({ path: "/restaurant/payment-methods" });
      } catch {
        return null;
      }
    },
  });

  const [state, setState] = React.useState<PaymentMethods>(query.data ?? DEFAULT);

  React.useEffect(() => {
    if (query.data) setState(query.data);
  }, [query.data]);

  const save = useMutation({
    mutationFn: async () =>
      clientFetch({ path: "/restaurant/payment-methods", method: "PUT", body: state }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["payment-methods"] });
      toast({ title: tCommon("success") });
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  function update<K extends keyof PaymentMethods>(k: K, v: PaymentMethods[K]) {
    setState((s) => ({ ...s, [k]: v }));
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <CardTitle className="text-base flex items-center gap-2">
            <Banknote className="h-4 w-4" /> {t("cash")}
          </CardTitle>
          <Switch checked={state.cash_enabled} onCheckedChange={(v) => update("cash_enabled", v)} />
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">{t("cashHint")}</CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <CardTitle className="text-base flex items-center gap-2">
            <CreditCard className="h-4 w-4" /> {t("card")}
          </CardTitle>
          <Switch checked={state.card_enabled} onCheckedChange={(v) => update("card_enabled", v)} />
        </CardHeader>
        <CardContent className="space-y-2">
          <Label htmlFor="card-ip" className="text-xs text-muted-foreground">
            {t("terminalIp")}
          </Label>
          <Input
            id="card-ip"
            placeholder="192.168.1.50"
            disabled={!state.card_enabled}
            value={state.card_terminal_ip ?? ""}
            onChange={(e) => update("card_terminal_ip", e.target.value)}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <CardTitle className="text-base flex items-center gap-2">
            <Smartphone className="h-4 w-4" /> {t("twint")}
          </CardTitle>
          <Switch checked={state.twint_enabled} onCheckedChange={(v) => update("twint_enabled", v)} />
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">{t("twintHint")}</CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <CardTitle className="text-base flex items-center gap-2">
            <Lock className="h-4 w-4" /> {t("stripe")}
          </CardTitle>
          <Switch checked={state.stripe_enabled} onCheckedChange={(v) => update("stripe_enabled", v)} />
        </CardHeader>
        <CardContent className="space-y-2">
          <Label htmlFor="stripe-key" className="text-xs text-muted-foreground">
            {t("stripeApiKey")}
          </Label>
          <Input
            id="stripe-key"
            type="password"
            placeholder="sk_live_..."
            disabled={!state.stripe_enabled}
            value={state.stripe_api_key ?? ""}
            onChange={(e) => update("stripe_api_key", e.target.value)}
          />
        </CardContent>
      </Card>

      <div className="md:col-span-2 flex justify-end">
        <Button onClick={() => save.mutate()} disabled={save.isPending}>
          {save.isPending ? tCommon("loading") : tCommon("save")}
        </Button>
      </div>
    </div>
  );
}
