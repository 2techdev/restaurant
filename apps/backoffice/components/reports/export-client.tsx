"use client";

import * as React from "react";
import { useTranslations } from "next-intl";
import { useToast } from "@/components/ui/use-toast";
import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const TYPES = ["orders", "menu", "customers", "top-sellers"] as const;
const FORMATS = ["csv", "xlsx", "json"] as const;
const LOCALES = ["tr", "de", "en", "fr", "it"] as const;

type ExportType = (typeof TYPES)[number];
type ExportFormat = (typeof FORMATS)[number];

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function thirtyDaysAgo() {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d.toISOString().slice(0, 10);
}

export function ExportClient() {
  const t = useTranslations("reports");
  const tCommon = useTranslations("common");
  const { toast } = useToast();
  const [type, setType] = React.useState<ExportType>("orders");
  const [from, setFrom] = React.useState<string>(thirtyDaysAgo());
  const [to, setTo] = React.useState<string>(todayIso());
  const [format, setFormat] = React.useState<ExportFormat>("csv");
  const [lang, setLang] = React.useState<string>("tr");
  const [busy, setBusy] = React.useState(false);

  async function runExport() {
    setBusy(true);
    try {
      const url = `/api/proxy/reports/export?type=${type}&from=${from}&to=${to}&format=${format}&lang=${lang}`;
      const res = await fetch(url, { method: "GET" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const blob = await res.blob();
      const dl = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = dl;
      a.download = `${type}-${from}_${to}.${format === "xlsx" ? "xlsx" : format}`;
      a.click();
      URL.revokeObjectURL(dl);
      toast({ title: t("exportSuccess"), description: a.download });
    } catch (e) {
      toast({
        title: tCommon("error"),
        description: e instanceof Error ? e.message : t("exportFailed"),
        variant: "destructive",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card className="max-w-2xl">
      <CardHeader>
        <CardTitle className="text-base">{t("exportWizard")}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="space-y-2">
            <Label htmlFor="export-type">{t("exportType")}</Label>
            <Select value={type} onValueChange={(v) => setType(v as ExportType)}>
              <SelectTrigger id="export-type">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TYPES.map((tp) => (
                  <SelectItem key={tp} value={tp}>
                    {t(`exportType_${tp}` as never)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="export-format">{t("exportFormat")}</Label>
            <Select value={format} onValueChange={(v) => setFormat(v as ExportFormat)}>
              <SelectTrigger id="export-format">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {FORMATS.map((f) => (
                  <SelectItem key={f} value={f}>
                    {f.toUpperCase()}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="export-from">{tCommon("from")}</Label>
            <Input id="export-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="export-to">{tCommon("to")}</Label>
            <Input id="export-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>
          <div className="space-y-2">
            <Label htmlFor="export-lang">{t("exportLang")}</Label>
            <Select value={lang} onValueChange={setLang}>
              <SelectTrigger id="export-lang">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {LOCALES.map((l) => (
                  <SelectItem key={l} value={l}>
                    {l.toUpperCase()}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className="flex justify-end pt-2">
          <Button onClick={runExport} disabled={busy || !from || !to}>
            <Download className="mr-2 h-4 w-4" />
            {busy ? tCommon("loading") : t("downloadExport")}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
