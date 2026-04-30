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
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

interface OrgInfo {
  id?: string;
  name: string;
  logo_url?: string | null;
  billing_email?: string | null;
  billing_address?: string | null;
  vat_number?: string | null;
}

const schema = z.object({
  name: z.string().min(1),
  logo_url: z.string().url().optional().or(z.literal("")),
  billing_email: z.string().email().optional().or(z.literal("")),
  billing_address: z.string().optional().or(z.literal("")),
  vat_number: z.string().optional().or(z.literal("")),
});
type Form = z.infer<typeof schema>;

export function OrgInfoClient() {
  const t = useTranslations("orgInfo");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const qc = useQueryClient();

  const query = useQuery<OrgInfo | null>({
    queryKey: ["org-info"],
    queryFn: async () => {
      try {
        return await clientFetch<OrgInfo>({ path: "/org/info" });
      } catch {
        return null;
      }
    },
  });

  const form = useForm<Form>({
    resolver: zodResolver(schema),
    values: {
      name: query.data?.name ?? "",
      logo_url: query.data?.logo_url ?? "",
      billing_email: query.data?.billing_email ?? "",
      billing_address: query.data?.billing_address ?? "",
      vat_number: query.data?.vat_number ?? "",
    },
  });

  const save = useMutation({
    mutationFn: async (values: Form) =>
      clientFetch({ path: "/org/info", method: "PUT", body: values }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["org-info"] });
      toast({ title: tCommon("success") });
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  return (
    <Card className="max-w-2xl">
      <CardHeader>
        <CardTitle className="text-base">{t("orgDetails")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="space-y-4" onSubmit={form.handleSubmit((v) => save.mutate(v))}>
          <div className="space-y-1">
            <Label htmlFor="org-name">{t("orgName")}</Label>
            <Input id="org-name" {...form.register("name")} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="org-logo">{t("logoUrl")}</Label>
            <Input id="org-logo" type="url" placeholder="https://..." {...form.register("logo_url")} />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label htmlFor="org-billemail">{t("billingEmail")}</Label>
              <Input id="org-billemail" type="email" {...form.register("billing_email")} />
            </div>
            <div className="space-y-1">
              <Label htmlFor="org-vat">{t("vatNumber")}</Label>
              <Input id="org-vat" placeholder="CHE-..." {...form.register("vat_number")} />
            </div>
          </div>
          <div className="space-y-1">
            <Label htmlFor="org-billaddr">{t("billingAddress")}</Label>
            <Input id="org-billaddr" {...form.register("billing_address")} />
          </div>
          <div className="flex justify-end pt-2">
            <Button type="submit" disabled={save.isPending}>
              {save.isPending ? tCommon("loading") : tCommon("save")}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
