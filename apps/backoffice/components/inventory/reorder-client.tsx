"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, ShoppingCart } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useToast } from "@/components/ui/use-toast";
import { clientFetch } from "@/lib/api-client";

interface InventoryItem {
  id: string;
  sku: string;
  name: string;
  unit: string;
  current_stock: number;
  threshold: number;
  supplier_name?: string | null;
}

export function ReorderClient() {
  const t = useTranslations("reorder");
  const tCommon = useTranslations("common");
  const { toast } = useToast();

  const query = useQuery<InventoryItem[]>({
    queryKey: ["inventory"],
    queryFn: async () => {
      try {
        const data = await clientFetch<{ items?: InventoryItem[] } | InventoryItem[]>({
          path: "/inventory",
        });
        if (Array.isArray(data)) return data;
        return data.items ?? [];
      } catch {
        return [];
      }
    },
  });

  const lowStock = (query.data ?? []).filter((it) => it.current_stock <= it.threshold);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <Badge variant="destructive" className="gap-1">
          <AlertTriangle className="h-3 w-3" />
          {t("alertsCount", { count: lowStock.length })}
        </Badge>
      </div>

      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : lowStock.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">{t("allGood")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("colSku")}</TableHead>
                  <TableHead>{t("colName")}</TableHead>
                  <TableHead className="text-right">{t("colStock")}</TableHead>
                  <TableHead className="text-right">{t("colThreshold")}</TableHead>
                  <TableHead>{t("colSupplier")}</TableHead>
                  <TableHead className="w-[140px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {lowStock.map((it) => (
                  <TableRow key={it.id}>
                    <TableCell className="font-mono text-xs">{it.sku}</TableCell>
                    <TableCell className="font-medium">{it.name}</TableCell>
                    <TableCell className="text-right tabular-nums font-semibold text-destructive">
                      {it.current_stock} {it.unit}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {it.threshold} {it.unit}
                    </TableCell>
                    <TableCell className="text-muted-foreground">{it.supplier_name || "—"}</TableCell>
                    <TableCell>
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() =>
                          toast({
                            title: t("reorderQueued"),
                            description: it.name,
                          })
                        }
                      >
                        <ShoppingCart className="h-4 w-4 mr-2" />
                        {t("reorder")}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
