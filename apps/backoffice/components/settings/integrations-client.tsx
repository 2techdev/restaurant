"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Mail, CreditCard, Smartphone, FileSignature, Webhook } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import type { LucideIcon } from "lucide-react";

interface Integrations {
  stripe_enabled: boolean;
  stripe_key?: string;
  twint_enabled: boolean;
  fiskaly_enabled: boolean;
  fiskaly_key?: string;
  smtp_enabled: boolean;
  smtp_host?: string;
  smtp_user?: string;
  webhook_enabled: boolean;
  webhook_url?: string;
}

const DEFAULT: Integrations = {
  stripe_enabled: false,
  twint_enabled: false,
  fiskaly_enabled: false,
  smtp_enabled: false,
  webhook_enabled: false,
};

interface IntegrationCardProps {
  icon: LucideIcon;
  title: string;
  description: string;
  enabled: boolean;
  onToggle: (v: boolean) => void;
  children?: React.ReactNode;
}

function IntegrationCard({ icon: Icon, title, description, enabled, onToggle, children }: IntegrationCardProps) {
  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <div>
          <CardTitle className="text-base flex items-center gap-2">
            <Icon className="h-4 w-4" /> {title}
          </CardTitle>
          <CardDescription>{description}</CardDescription>
        </div>
        <Switch checked={enabled} onCheckedChange={onToggle} />
      </CardHeader>
      {children && enabled ? <CardContent className="space-y-2 pt-0">{children}</CardContent> : null}
    </Card>
  );
}

export function IntegrationsClient() {
  const t = useTranslations("integrations");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const query = useQuery<Integrations | null>({
    queryKey: ["integrations"],
    queryFn: async () => {
      try {
        return await clientFetch<Integrations>({ path: "/settings/integrations" });
      } catch {
        return null;
      }
    },
  });

  const [state, setState] = React.useState<Integrations>(query.data ?? DEFAULT);

  React.useEffect(() => {
    if (query.data) setState(query.data);
  }, [query.data]);

  const save = useMutation({
    mutationFn: async () =>
      clientFetch({ path: "/settings/integrations", method: "PUT", body: state }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["integrations"] });
      toast({ title: tCommon("success") });
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  function update<K extends keyof Integrations>(k: K, v: Integrations[K]) {
    setState((s) => ({ ...s, [k]: v }));
  }

  return (
    <div className="space-y-4">
      <IntegrationCard
        icon={CreditCard}
        title={t("stripe")}
        description={t("stripeDesc")}
        enabled={state.stripe_enabled}
        onToggle={(v) => update("stripe_enabled", v)}
      >
        <Label htmlFor="int-stripe-key" className="text-xs text-muted-foreground">
          {t("apiKey")}
        </Label>
        <Input
          id="int-stripe-key"
          type="password"
          placeholder="sk_live_..."
          value={state.stripe_key ?? ""}
          onChange={(e) => update("stripe_key", e.target.value)}
        />
      </IntegrationCard>

      <IntegrationCard
        icon={Smartphone}
        title={t("twint")}
        description={t("twintDesc")}
        enabled={state.twint_enabled}
        onToggle={(v) => update("twint_enabled", v)}
      />

      <IntegrationCard
        icon={FileSignature}
        title={t("fiskaly")}
        description={t("fiskalyDesc")}
        enabled={state.fiskaly_enabled}
        onToggle={(v) => update("fiskaly_enabled", v)}
      >
        <Label htmlFor="int-fiskaly-key" className="text-xs text-muted-foreground">
          {t("apiKey")}
        </Label>
        <Input
          id="int-fiskaly-key"
          type="password"
          value={state.fiskaly_key ?? ""}
          onChange={(e) => update("fiskaly_key", e.target.value)}
        />
      </IntegrationCard>

      <IntegrationCard
        icon={Mail}
        title={t("smtp")}
        description={t("smtpDesc")}
        enabled={state.smtp_enabled}
        onToggle={(v) => update("smtp_enabled", v)}
      >
        <div className="grid grid-cols-2 gap-2">
          <div className="space-y-1">
            <Label htmlFor="int-smtp-host" className="text-xs text-muted-foreground">
              {t("smtpHost")}
            </Label>
            <Input
              id="int-smtp-host"
              placeholder="smtp.example.com"
              value={state.smtp_host ?? ""}
              onChange={(e) => update("smtp_host", e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="int-smtp-user" className="text-xs text-muted-foreground">
              {t("smtpUser")}
            </Label>
            <Input
              id="int-smtp-user"
              value={state.smtp_user ?? ""}
              onChange={(e) => update("smtp_user", e.target.value)}
            />
          </div>
        </div>
      </IntegrationCard>

      <IntegrationCard
        icon={Webhook}
        title={t("webhook")}
        description={t("webhookDesc")}
        enabled={state.webhook_enabled}
        onToggle={(v) => update("webhook_enabled", v)}
      >
        <Label htmlFor="int-webhook" className="text-xs text-muted-foreground">
          {t("webhookUrl")}
        </Label>
        <Input
          id="int-webhook"
          type="url"
          placeholder="https://..."
          value={state.webhook_url ?? ""}
          onChange={(e) => update("webhook_url", e.target.value)}
        />
      </IntegrationCard>

      <div className="flex justify-end">
        <Button onClick={() => save.mutate()} disabled={save.isPending}>
          {save.isPending ? tCommon("loading") : tCommon("save")}
        </Button>
      </div>
    </div>
  );
}
