"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { CheckCircle2, AlertCircle, Clock } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { clientFetch } from "@/lib/api-client";
import { formatDateTime } from "@/lib/utils";

type CascadeStatus = "pending" | "applied" | "failed";

interface CascadeRow {
  tenant_id: string;
  tenant_name: string;
  status: CascadeStatus;
  applied_at?: string | null;
  error?: string | null;
}

interface PublishVersion {
  version: number;
  published_by_name?: string;
  published_at: string;
  affected_count: number;
  applied_count: number;
  failed_count: number;
  pending_count: number;
  cascades?: CascadeRow[];
}

function statusBadge(s: CascadeStatus) {
  switch (s) {
    case "applied":
      return (
        <Badge variant="secondary" className="gap-1">
          <CheckCircle2 className="h-3 w-3 text-emerald-500" /> applied
        </Badge>
      );
    case "failed":
      return (
        <Badge variant="destructive" className="gap-1">
          <AlertCircle className="h-3 w-3" /> failed
        </Badge>
      );
    case "pending":
    default:
      return (
        <Badge variant="outline" className="gap-1">
          <Clock className="h-3 w-3" /> pending
        </Badge>
      );
  }
}

export function PublishHistoryClient({ orgId }: { orgId: string }) {
  const t = useTranslations("publishHistory");
  const tCommon = useTranslations("common");
  const [selected, setSelected] = React.useState<PublishVersion | null>(null);

  const query = useQuery<PublishVersion[]>({
    queryKey: ["master-menu-versions", orgId],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ versions?: PublishVersion[] } | PublishVersion[]>({
          path: `/org/${orgId}/master-menu/versions`,
        });
        if (Array.isArray(data)) return data;
        return data.versions ?? [];
      } catch {
        return [];
      }
    },
  });

  const versions = query.data ?? [];

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : versions.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">
              {t("emptyHistory")}
              <div className="text-xs mt-2 italic">{t("backendTbd")}</div>
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[80px]">{t("colVersion")}</TableHead>
                  <TableHead>{t("colPublishedBy")}</TableHead>
                  <TableHead>{t("colPublishedAt")}</TableHead>
                  <TableHead className="text-right">{t("colAffected")}</TableHead>
                  <TableHead>{t("colCascadeStatus")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {versions.map((v) => (
                  <TableRow
                    key={v.version}
                    className="cursor-pointer hover:bg-muted/40"
                    onClick={() => setSelected(v)}
                  >
                    <TableCell className="font-mono">v{v.version}</TableCell>
                    <TableCell>{v.published_by_name || "—"}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {formatDateTime(v.published_at)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{v.affected_count}</TableCell>
                    <TableCell>
                      <div className="flex gap-2 text-xs">
                        {v.applied_count > 0 ? (
                          <span className="text-emerald-600">
                            ✓ {v.applied_count} {t("applied")}
                          </span>
                        ) : null}
                        {v.pending_count > 0 ? (
                          <span className="text-muted-foreground">
                            ⋯ {v.pending_count} {t("pending")}
                          </span>
                        ) : null}
                        {v.failed_count > 0 ? (
                          <span className="text-destructive">
                            ✗ {v.failed_count} {t("failed")}
                          </span>
                        ) : null}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Sheet open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <SheetContent className="sm:max-w-lg">
          {selected ? (
            <>
              <SheetHeader>
                <SheetTitle>
                  {t("cascadeTitle")} — v{selected.version}
                </SheetTitle>
                <SheetDescription>
                  {formatDateTime(selected.published_at)} ·{" "}
                  {selected.published_by_name || "—"}
                </SheetDescription>
              </SheetHeader>
              <div className="mt-6 space-y-2">
                {(selected.cascades ?? []).length === 0 ? (
                  <div className="text-sm text-muted-foreground italic">{tCommon("noData")}</div>
                ) : (
                  (selected.cascades ?? []).map((c) => (
                    <div
                      key={c.tenant_id}
                      className="flex items-center justify-between rounded border p-2 text-sm"
                    >
                      <div>
                        <div className="font-medium">{c.tenant_name}</div>
                        {c.error ? (
                          <div className="text-xs text-destructive mt-1">{c.error}</div>
                        ) : c.applied_at ? (
                          <div className="text-xs text-muted-foreground">
                            {formatDateTime(c.applied_at)}
                          </div>
                        ) : null}
                      </div>
                      {statusBadge(c.status)}
                    </div>
                  ))
                )}
              </div>
            </>
          ) : null}
        </SheetContent>
      </Sheet>
    </div>
  );
}
