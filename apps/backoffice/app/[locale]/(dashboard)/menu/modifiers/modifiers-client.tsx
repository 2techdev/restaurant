"use client";

/**
 * Modifier groups — read-only list.
 *
 * Backend currently exposes `GET /api/v1/menu/modifiers` only. CRUD endpoints
 * are not wired yet (planned: Agent A's modifier-group epic). Until those land
 * the operator manages modifier groups from the POS BackOffice tab; this page
 * surfaces what's already in the database so the menu reviewer can audit.
 */

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { Loader2, Settings2, Info } from "lucide-react";

import { clientFetch } from "@/lib/api-client";
import { Card } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { StatusBadge } from "@/components/ui/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { ModifierGroup } from "@/lib/api-types";

export function ModifiersClient() {
  const t = useTranslations("menu.modifierGroupsPage");

  const list = useQuery({
    queryKey: ["modifier-groups"],
    queryFn: async () => {
      const data = await clientFetch<{ modifiers?: ModifierGroup[]; data?: ModifierGroup[] } | ModifierGroup[]>(
        { path: "/menu/modifiers" }
      );
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const raw = data as any;
      return (Array.isArray(raw) ? raw : raw?.modifiers ?? raw?.data ?? []) as ModifierGroup[];
    },
  });

  const items = list.data ?? [];

  return (
    <div className="space-y-4">
      <Alert>
        <Info className="h-4 w-4" />
        <AlertDescription>{t("readOnlyNotice")}</AlertDescription>
      </Alert>

      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3 flex items-center justify-between">
          <span className="text-sm font-medium">
            {t("listHeader", { count: items.length })}
          </span>
          {list.isFetching && (
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
        </div>

        {list.isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">
            {t("loading")}
          </div>
        ) : list.error ? (
          <div className="p-12 text-center text-sm text-error">
            {(list.error as Error).message}
          </div>
        ) : items.length === 0 ? (
          <div className="p-12 text-center space-y-3">
            <Settings2 className="h-12 w-12 mx-auto text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">{t("emptyState")}</p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t("col.name")}</TableHead>
                <TableHead>{t("col.type")}</TableHead>
                <TableHead>{t("col.bounds")}</TableHead>
                <TableHead>{t("col.modifierCount")}</TableHead>
                <TableHead>{t("col.required")}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.map((g) => (
                <TableRow key={g.id} className="hover:bg-muted/30">
                  <TableCell className="font-medium">{g.name}</TableCell>
                  <TableCell>
                    <StatusBadge variant={g.selection_type === "single" ? "info" : "neutral"}>
                      {g.selection_type === "single" ? t("type.single") : t("type.multi")}
                    </StatusBadge>
                  </TableCell>
                  <TableCell className="font-mono text-[12px]">
                    {g.min_selections} – {g.max_selections}
                  </TableCell>
                  <TableCell className="tabular-nums">
                    {g.modifiers?.length ?? 0}
                  </TableCell>
                  <TableCell>
                    {g.is_required ? (
                      <StatusBadge variant="warning">{t("required")}</StatusBadge>
                    ) : (
                      <span className="text-xs text-muted-foreground">—</span>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </Card>
    </div>
  );
}
