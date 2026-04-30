"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useQuery, useMutation } from "@tanstack/react-query";
import { Search } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";

interface MasterProduct {
  id: string;
  name: string;
  category_id: string;
  price: number;
  policy_lock?: string;
}

const schema = z.object({
  product_id: z.string().min(1),
  lock_type: z.enum(["FLEXIBLE", "PRICE_LOCKED", "FULLY_LOCKED"]),
  allow_local_additions: z.boolean(),
  allow_local_disable: z.boolean(),
});
type Form = z.infer<typeof schema>;

export function NewPolicyClient({ orgId, locale }: { orgId: string; locale: string }) {
  const t = useTranslations("newPolicy");
  const tCommon = useTranslations("common");
  const router = useRouter();
  const { toast } = useToast();
  const [search, setSearch] = React.useState("");

  const products = useQuery<MasterProduct[]>({
    queryKey: ["master-menu-products", orgId],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ products?: MasterProduct[] }>({
          path: `/org/${orgId}/master-menu`,
        });
        return data.products ?? [];
      } catch {
        return [];
      }
    },
  });

  const filtered = (products.data ?? []).filter((p) =>
    !search || p.name.toLowerCase().includes(search.toLowerCase())
  );

  const form = useForm<Form>({
    resolver: zodResolver(schema),
    defaultValues: {
      product_id: "",
      lock_type: "PRICE_LOCKED",
      allow_local_additions: false,
      allow_local_disable: false,
    },
  });

  const create = useMutation({
    mutationFn: async (values: Form) =>
      clientFetch({
        path: `/org/${orgId}/policies`,
        method: "POST",
        body: values,
      }),
    onSuccess: () => {
      toast({ title: t("createSuccess") });
      router.push(`/${locale}/organization/menu-policies`);
    },
    onError: (e) =>
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : String(e),
        variant: "destructive",
      }),
  });

  const selectedProductId = form.watch("product_id");
  const selectedProduct = (products.data ?? []).find((p) => p.id === selectedProductId);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
      <Card className="lg:col-span-2">
        <CardHeader>
          <CardTitle className="text-base">{t("selectProduct")}</CardTitle>
          <CardDescription>{t("selectProductHint")}</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="relative">
            <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder={tCommon("search")}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-8"
            />
          </div>
          <div className="max-h-[300px] overflow-y-auto rounded border divide-y">
            {products.isLoading ? (
              <div className="p-4 text-sm text-muted-foreground">{tCommon("loading")}</div>
            ) : filtered.length === 0 ? (
              <div className="p-4 text-sm text-muted-foreground text-center">{tCommon("noData")}</div>
            ) : (
              filtered.map((p) => (
                <label
                  key={p.id}
                  className={`flex items-center justify-between p-3 cursor-pointer hover:bg-muted/40 ${
                    selectedProductId === p.id ? "bg-muted" : ""
                  }`}
                >
                  <div className="flex items-center gap-3">
                    <input
                      type="radio"
                      name="product_id"
                      value={p.id}
                      checked={selectedProductId === p.id}
                      onChange={() => form.setValue("product_id", p.id)}
                      className="accent-primary"
                    />
                    <div>
                      <div className="text-sm font-medium">{p.name}</div>
                      {p.policy_lock && p.policy_lock !== "FLEXIBLE" ? (
                        <div className="text-xs text-amber-600 mt-1">
                          {t("alreadyHasPolicy", { lock: p.policy_lock })}
                        </div>
                      ) : null}
                    </div>
                  </div>
                  <div className="text-sm tabular-nums text-muted-foreground">
                    {formatChf(p.price)}
                  </div>
                </label>
              ))
            )}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t("policyConfig")}</CardTitle>
          <CardDescription>
            {selectedProduct?.name ?? t("noSelection")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form
            onSubmit={form.handleSubmit((v) => create.mutate(v))}
            className="space-y-4"
          >
            <div className="space-y-1">
              <Label htmlFor="np-lock">{t("lockType")}</Label>
              <Select
                value={form.watch("lock_type")}
                onValueChange={(v) => form.setValue("lock_type", v as Form["lock_type"])}
              >
                <SelectTrigger id="np-lock">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="FLEXIBLE">{t("lockFlexible")}</SelectItem>
                  <SelectItem value="PRICE_LOCKED">{t("lockPrice")}</SelectItem>
                  <SelectItem value="FULLY_LOCKED">{t("lockFully")}</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground mt-1">
                {form.watch("lock_type") === "FLEXIBLE"
                  ? t("lockFlexibleHint")
                  : form.watch("lock_type") === "PRICE_LOCKED"
                  ? t("lockPriceHint")
                  : t("lockFullyHint")}
              </p>
            </div>

            <div className="flex items-center justify-between rounded border p-3">
              <div>
                <div className="text-sm font-medium">{t("allowLocalAdditions")}</div>
                <div className="text-xs text-muted-foreground">{t("allowLocalAdditionsHint")}</div>
              </div>
              <Switch
                checked={form.watch("allow_local_additions")}
                onCheckedChange={(v) => form.setValue("allow_local_additions", v)}
              />
            </div>

            <div className="flex items-center justify-between rounded border p-3">
              <div>
                <div className="text-sm font-medium">{t("allowLocalDisable")}</div>
                <div className="text-xs text-muted-foreground">{t("allowLocalDisableHint")}</div>
              </div>
              <Switch
                checked={form.watch("allow_local_disable")}
                onCheckedChange={(v) => form.setValue("allow_local_disable", v)}
              />
            </div>

            <p className="text-xs text-muted-foreground italic">{t("appliesAllRestaurants")}</p>

            <div className="flex justify-end gap-2 pt-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => router.push(`/${locale}/organization/menu-policies`)}
              >
                {tCommon("cancel")}
              </Button>
              <Button type="submit" disabled={!selectedProductId || create.isPending}>
                {create.isPending ? tCommon("loading") : t("createPolicy")}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
