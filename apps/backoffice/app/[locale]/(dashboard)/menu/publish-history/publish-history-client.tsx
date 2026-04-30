"use client";

/**
 * Menu publish history.
 *
 * Backend versioning is wired to `tenants.menu_version_current` + the
 * snapshot endpoint already exposes the current version. A dedicated
 * `/menu/snapshots` endpoint listing past versions doesn't exist yet — this
 * page renders the live current-version pill + diff viewer on the planned
 * shape so the operator + designer can iterate on it. Once Agent A wires
 * the listing endpoint, swap the mock fallback in `useQuery.queryFn` for a
 * real fetch; the table layout stays.
 */

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { Info, History, ArrowLeftRight } from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { useTenant } from "@/components/shell/tenant-context";
import { Card } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDateTime } from "@/lib/utils";

interface PublishVersion {
  version: number;
  publishedAt: string;
  publishedBy: string;
  added: number;
  modified: number;
  removed: number;
  isCurrent?: boolean;
}

export function PublishHistoryClient() {
  const t = useTranslations("menu.publishHistoryPage");
  const { activeTenantId } = useTenant();
  const [diffOpen, setDiffOpen] = React.useState<PublishVersion | null>(null);

  // Pull the current version from /menu/version/{tenantId}; the listing
  // endpoint isn't there yet so we fabricate a single-row history seeded
  // with the live version. When the real endpoint lands, swap to:
  //   const data = await clientFetch({ path: `/menu/snapshots?tenantId=${activeTenantId}` })
  const live = useQuery({
    enabled: !!activeTenantId && activeTenantId !== "all",
    queryKey: ["menu-version-live", activeTenantId],
    queryFn: async () => {
      try {
        const r = await clientFetch<{
          data?: { menuVersion?: number; publishedAt?: string };
        }>({ path: `/menu/version/${activeTenantId}` });
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        return (r as any)?.data ?? null;
      } catch {
        return null;
      }
    },
  });

  const items: PublishVersion[] = React.useMemo(() => {
    const v = live.data?.menuVersion;
    if (!v) return [];
    return [
      {
        version: v,
        publishedAt: live.data?.publishedAt ?? new Date().toISOString(),
        publishedBy: "—",
        added: 0,
        modified: 0,
        removed: 0,
        isCurrent: true,
      },
    ];
  }, [live.data]);

  return (
    <div className="space-y-4">
      <Alert>
        <Info className="h-4 w-4" />
        <AlertDescription>{t("plannedBackend")}</AlertDescription>
      </Alert>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 text-sm font-medium">
          {t("listHeader", { count: items.length })}
        </div>

        {activeTenantId === "all" ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {t("aggregateNotice")}
          </div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <History className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.version")}</TableHead>
                <TableHead>{t("col.publishedAt")}</TableHead>
                <TableHead>{t("col.publishedBy")}</TableHead>
                <TableHead>{t("col.diff")}</TableHead>
                <TableHead className="text-right">{t("col.actions")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((v) => (
                <TableRow key={v.version} className="hover:bg-muted/30">
                  <TableCell className="font-mono">
                    v{v.version}
                    {v.isCurrent && (
                      <StatusBadge variant="success" className="ml-2">
                        {t("current")}
                      </StatusBadge>
                    )}
                  </TableCell>
                  <TableCell className="text-muted-foreground">
                    {formatDateTime(v.publishedAt)}
                  </TableCell>
                  <TableCell>{v.publishedBy}</TableCell>
                  <TableCell>
                    <span className="font-mono text-[12px] text-muted-foreground">
                      <span className="text-success">+{v.added}</span> /{" "}
                      <span className="text-warning">~{v.modified}</span> /{" "}
                      <span className="text-error">-{v.removed}</span>
                    </span>
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setDiffOpen(v)}
                    >
                      <ArrowLeftRight className="h-3.5 w-3.5" />
                      {t("viewDiff")}
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>

      <Sheet open={diffOpen !== null} onOpenChange={(o) => !o && setDiffOpen(null)}>
        <SheetContent side="right" className="w-full sm:max-w-3xl">
          <SheetHeader>
            <SheetTitle>
              {t("diffTitle", { version: diffOpen?.version ?? 0 })}
            </SheetTitle>
            <SheetDescription>{t("diffPlaceholder")}</SheetDescription>
          </SheetHeader>
          <div className="mt-6 p-12 text-center text-sm text-muted-foreground border border-dashed rounded-lg">
            {t("diffNotImplementedYet")}
          </div>
        </SheetContent>
      </Sheet>
    </div>
  );
}
