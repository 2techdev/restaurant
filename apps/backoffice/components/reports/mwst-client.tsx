"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useQuery } from "@tanstack/react-query";
import { Download, FileText } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { clientFetch } from "@/lib/api-client";
import { formatChf } from "@/lib/utils";

interface MwstRow {
  rate: number; // 8.1 / 3.8 / 2.6 / 0
  net: number;
  tax: number;
  gross: number;
}

interface MwstResponse {
  from: string;
  to: string;
  total_net: number;
  total_tax: number;
  total_gross: number;
  rows: MwstRow[];
}

const QUARTERS = [
  { value: "Q1", label: "Q1 (01-03)" },
  { value: "Q2", label: "Q2 (04-06)" },
  { value: "Q3", label: "Q3 (07-09)" },
  { value: "Q4", label: "Q4 (10-12)" },
] as const;

function quarterRange(year: number, q: string): { from: string; to: string } {
  const map: Record<string, [number, number]> = {
    Q1: [0, 2],
    Q2: [3, 5],
    Q3: [6, 8],
    Q4: [9, 11],
  };
  const [start, end] = map[q] ?? [0, 11];
  const from = new Date(Date.UTC(year, start, 1)).toISOString().slice(0, 10);
  const to = new Date(Date.UTC(year, end + 1, 0)).toISOString().slice(0, 10);
  return { from, to };
}

export function MwstClient() {
  const t = useTranslations("reports");
  const tCommon = useTranslations("common");
  const currentYear = new Date().getFullYear();
  const [year, setYear] = React.useState<number>(currentYear);
  const [quarter, setQuarter] = React.useState<string>("Q1");
  const range = quarterRange(year, quarter);

  const query = useQuery<MwstResponse | null>({
    queryKey: ["mwst", year, quarter],
    queryFn: async () => {
      try {
        return await clientFetch<MwstResponse>({
          path: `/reports/mwst?from=${range.from}&to=${range.to}`,
        });
      } catch {
        return null;
      }
    },
  });

  const data = query.data;
  const rows = data?.rows ?? [];

  function downloadDatev() {
    const xml = `<?xml version="1.0" encoding="UTF-8"?>
<mwst-export from="${range.from}" to="${range.to}">
${rows
  .map(
    (r) => `  <line rate="${r.rate}" net="${(r.net / 100).toFixed(2)}" tax="${(r.tax / 100).toFixed(
      2
    )}" gross="${(r.gross / 100).toFixed(2)}"/>`
  )
  .join("\n")}
</mwst-export>`;
    const blob = new Blob([xml], { type: "application/xml" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `mwst-${year}-${quarter}.xml`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-2">
          <label className="text-sm font-medium">{t("year")}</label>
          <Select value={String(year)} onValueChange={(v) => setYear(Number(v))}>
            <SelectTrigger className="w-[120px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {[currentYear, currentYear - 1, currentYear - 2].map((y) => (
                <SelectItem key={y} value={String(y)}>
                  {y}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <label className="text-sm font-medium">{t("quarter")}</label>
          <Select value={quarter} onValueChange={setQuarter}>
            <SelectTrigger className="w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {QUARTERS.map((q) => (
                <SelectItem key={q.value} value={q.value}>
                  {q.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="ml-auto flex gap-2">
          <Button variant="outline" size="sm" onClick={downloadDatev} disabled={!rows.length}>
            <Download className="mr-2 h-4 w-4" />
            {t("downloadDatev")}
          </Button>
          <Button variant="outline" size="sm" onClick={() => window.print()} disabled={!rows.length}>
            <FileText className="mr-2 h-4 w-4" />
            {t("preparePdf")}
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            {t("mwstBreakdown")} — {range.from} → {range.to}
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {query.isLoading ? (
            <div className="p-6 text-sm text-muted-foreground">{tCommon("loading")}</div>
          ) : rows.length === 0 ? (
            <div className="p-6 text-sm text-muted-foreground text-center">{tCommon("noData")}</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t("vatRate")}</TableHead>
                  <TableHead className="text-right">{t("net")}</TableHead>
                  <TableHead className="text-right">{t("vat")}</TableHead>
                  <TableHead className="text-right">{t("gross")}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r) => (
                  <TableRow key={r.rate}>
                    <TableCell className="font-medium">{r.rate.toFixed(1)}%</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(r.net)}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(r.tax)}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(r.gross)}</TableCell>
                  </TableRow>
                ))}
                {data && (
                  <TableRow className="font-semibold border-t-2">
                    <TableCell>{t("total")}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(data.total_net)}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(data.total_tax)}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatChf(data.total_gross)}</TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
