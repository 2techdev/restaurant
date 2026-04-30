"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { MoreHorizontal, Smartphone, Trash2, Loader2 } from "lucide-react";
import { clientFetch } from "@/lib/api-client";
import { useTenant } from "@/components/shell/tenant-context";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { useToast } from "@/components/ui/use-toast";
import { StatusBadge } from "@/components/ui/status-badge";

interface PosDevice {
  id: string;
  name: string;
  api_key_prefix: string;
  tenant_id: string;
  created_at: string;
  last_seen_at: string | null;
  device_fingerprint: string | null;
}

interface DevicesPageClientProps {
  locale: string;
  title: string;
}

export function DevicesPageClient({ title }: DevicesPageClientProps) {
  const t = useTranslations("devices");
  const tCommon = useTranslations("common");
  const { activeTenantId } = useTenant();
  const qc = useQueryClient();
  const { toast } = useToast();
  const [revokeTarget, setRevokeTarget] = React.useState<PosDevice | null>(null);

  const aggregate = activeTenantId === "all";

  const list = useQuery({
    enabled: !aggregate && !!activeTenantId,
    queryKey: ["devices", activeTenantId],
    queryFn: async () => {
      const data = await clientFetch<{ data: PosDevice[] } | { success: boolean; data: PosDevice[] }>({
        path: `/me/devices?tenant_id=${encodeURIComponent(activeTenantId)}`,
      });
      // Backend wraps payloads as `{success, data}`; the proxy passes that
      // through unchanged, so unwrap defensively.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (raw?.data ?? raw) as PosDevice[];
    },
  });

  const revoke = useMutation({
    mutationFn: async (id: string) => {
      await clientFetch({
        path: `/me/devices/${id}`,
        method: "DELETE",
      });
    },
    onSuccess: () => {
      toast({ title: t("revokeSuccess") });
      qc.invalidateQueries({ queryKey: ["devices", activeTenantId] });
    },
    onError: (e: Error) => {
      toast({
        title: t("revokeError"),
        description: e.message,
        variant: "destructive",
      });
    },
  });

  const items = list.data ?? [];

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {t("subtitle")}
          </p>
        </div>
      </div>

      {aggregate && (
        <Card className="p-6 border-warning/30 bg-warning-soft/30">
          <p className="text-sm">
            <strong className="font-medium">{t("aggregateNotice.title")}</strong>{" "}
            {t("aggregateNotice.body")}
          </p>
        </Card>
      )}

      {!aggregate && (
        <>
          <Card className="p-6 border-primary/20 bg-primary-soft/40">
            <h2 className="font-medium mb-2 flex items-center gap-2">
              <Smartphone className="h-4 w-4" />
              {t("howToPair.title")}
            </h2>
            <ol className="text-sm text-muted-foreground list-decimal list-inside space-y-1">
              <li>{t("howToPair.step1")}</li>
              <li>{t("howToPair.step2")}</li>
              <li>{t("howToPair.step3")}</li>
            </ol>
          </Card>

          <Card className="overflow-hidden">
            <div className="border-b px-6 py-3 flex items-center justify-between">
              <span className="text-sm font-medium">
                {t("listHeader", { count: items.length })}
              </span>
              {list.isFetching && (
                <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
              )}
            </div>

            {list.isLoading ? (
              <div className="p-12 text-center text-muted-foreground text-sm">
                {tCommon("loading")}
              </div>
            ) : list.error ? (
              <div className="p-12 text-center text-error text-sm">
                {(list.error as Error).message}
              </div>
            ) : items.length === 0 ? (
              <div className="p-12 text-center text-muted-foreground text-sm">
                {t("emptyState")}
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead className="bg-muted/40 text-muted-foreground text-[11px] uppercase tracking-wider">
                  <tr>
                    <th className="text-left px-6 py-3 font-medium">{t("colName")}</th>
                    <th className="text-left px-6 py-3 font-medium">{t("colKeyPrefix")}</th>
                    <th className="text-left px-6 py-3 font-medium">{t("colCreatedAt")}</th>
                    <th className="text-left px-6 py-3 font-medium">{t("colLastSeen")}</th>
                    <th className="w-12 px-6 py-3"></th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((d) => (
                    <tr key={d.id} className="border-t border-border hover:bg-muted/30">
                      <td className="px-6 py-3">
                        <div className="flex items-center gap-2">
                          <Smartphone className="h-4 w-4 text-muted-foreground" />
                          <div>
                            <div className="font-medium">{d.name}</div>
                            {d.device_fingerprint && (
                              <div className="text-[11px] text-muted-foreground font-mono truncate max-w-[280px]">
                                {d.device_fingerprint}
                              </div>
                            )}
                          </div>
                        </div>
                      </td>
                      <td className="px-6 py-3 font-mono text-[12px]">
                        {d.api_key_prefix}…
                      </td>
                      <td className="px-6 py-3 text-muted-foreground">
                        {formatDate(d.created_at)}
                      </td>
                      <td className="px-6 py-3">
                        <LastSeenCell at={d.last_seen_at} t={t} />
                      </td>
                      <td className="px-6 py-3 text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon" className="h-8 w-8">
                              <MoreHorizontal className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem
                              className="text-error"
                              onSelect={() => setRevokeTarget(d)}
                            >
                              <Trash2 className="h-4 w-4" />
                              {t("revokeAction")}
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Card>
        </>
      )}

      <AlertDialog
        open={revokeTarget !== null}
        onOpenChange={(o) => !o && setRevokeTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("revokeConfirmTitle")}</AlertDialogTitle>
            <AlertDialogDescription>
              {t("revokeConfirmBody", { name: revokeTarget?.name ?? "" })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{tCommon("cancel")}</AlertDialogCancel>
            <AlertDialogAction
              className="bg-error text-error-foreground hover:bg-error/90"
              onClick={() => {
                if (revokeTarget) revoke.mutate(revokeTarget.id);
                setRevokeTarget(null);
              }}
            >
              {t("revokeAction")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function LastSeenCell({ at, t }: { at: string | null; t: (key: string) => string }) {
  if (!at) {
    return <StatusBadge variant="neutral">{t("neverSeen")}</StatusBadge>;
  }
  const date = new Date(at);
  const ms = Date.now() - date.getTime();
  const minutes = Math.floor(ms / 60_000);
  let variant: "success" | "warning" | "neutral" = "neutral";
  if (minutes < 5) variant = "success";
  else if (minutes < 60) variant = "warning";
  return (
    <StatusBadge variant={variant} withDot>
      {formatRelative(date)}
    </StatusBadge>
  );
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleString("tr-CH", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatRelative(d: Date): string {
  const ms = Date.now() - d.getTime();
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return `${sec}s önce`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}dk önce`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}sa önce`;
  const day = Math.floor(hr / 24);
  return `${day}g önce`;
}
