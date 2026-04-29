"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { Send, History } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";
import { formatDateTime } from "@/lib/utils";
import { useTenant } from "@/components/shell/tenant-context";
import type { MenuSnapshotInfo } from "@/lib/api-types";

export function MenuPublishButton({ history }: { history: MenuSnapshotInfo[] }) {
  const t = useTranslations("menu");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const router = useRouter();
  const { activeTenantId } = useTenant();

  const publish = useMutation({
    mutationFn: () =>
      clientFetch<{ version: number }>({
        path: `/menu/publish/${activeTenantId}`,
        method: "POST",
      }),
    onSuccess: (data) => {
      toast({
        title: t("publishSuccess", { version: data?.version ?? "—" }),
      });
      router.refresh();
    },
    onError: (e: Error) =>
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" }),
  });

  return (
    <div className="flex items-center gap-2">
      <Sheet>
        <SheetTrigger asChild>
          <Button variant="outline" size="sm">
            <History className="h-4 w-4" /> {t("publishHistory")}
          </Button>
        </SheetTrigger>
        <SheetContent side="right">
          <SheetHeader>
            <SheetTitle>{t("publishHistory")}</SheetTitle>
          </SheetHeader>
          <div className="mt-6 space-y-3">
            {history.length === 0 && (
              <p className="text-sm text-muted-foreground">{tCommon("noData")}</p>
            )}
            {history.map((s) => (
              <div key={s.version} className="rounded border p-3 text-sm">
                <div className="font-medium">{t("version")} {s.version}</div>
                <div className="text-xs text-muted-foreground mt-1">
                  {formatDateTime(s.published_at)}
                </div>
                <div className="text-xs text-muted-foreground">
                  {t("publishedBy")}: {s.published_by}
                </div>
                <div className="text-xs text-muted-foreground mt-1">
                  {s.category_count} kategori · {s.product_count} ürün
                </div>
              </div>
            ))}
          </div>
        </SheetContent>
      </Sheet>

      <AlertDialog>
        <AlertDialogTrigger asChild>
          <Button size="sm" data-testid="publish-button">
            <Send className="h-4 w-4" /> {t("publishToPos")}
          </Button>
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("publishConfirmTitle")}</AlertDialogTitle>
            <AlertDialogDescription>{t("publishConfirmBody")}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction onClick={() => publish.mutate()}>
              {tCommon("confirm")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
