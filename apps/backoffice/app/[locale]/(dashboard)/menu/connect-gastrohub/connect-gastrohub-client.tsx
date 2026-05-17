"use client";

/**
 * Onboarding wizard — Gastro Hub'dan menü import.
 *
 * Akış:
 *   1. Bağlantı kodu girişi (XXX-XXX format)
 *   2. Diff preview (POS Go server → /menu/import-from-token dryRun=true)
 *   3. Sonuç (apply edilince stats + redirect)
 *
 * Backend endpoint: POST /api/menu/import-from-token
 * Body: { token, mode: "merge", dryRun: true|false }
 */

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useMutation } from "@tanstack/react-query";
import { ArrowLeft, ArrowRight, CheckCircle2, Link2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useToast } from "@/components/ui/use-toast";

import { DiffPreview, type ImportPreview } from "@/components/menu-import/diff-preview";

// Alphabet matches Reservation backend (Confusing chars 0/O/1/I/L excluded).
const TOKEN_REGEX = /^[A-HJKMNP-Z2-9]{3}-[A-HJKMNP-Z2-9]{3}$/;
const TOKEN_CHARS = /[^A-HJKMNP-Z2-9]/g;

type ApplyResult = {
  applied: true;
  syncEventId: string;
  linkedAt: string;
  stats?: {
    categoriesAdded: number;
    categoriesUpdated: number;
    productsAdded: number;
    productsUpdated: number;
    modifiersAdded: number;
    modifiersUpdated: number;
  };
};

type Step = "input" | "preview" | "result";

export function ConnectGastroHubClient({ locale }: { locale: string }) {
  const t = useTranslations("menu.import");
  const tCommon = useTranslations("common");
  const router = useRouter();
  const { toast } = useToast();

  const [step, setStep] = useState<Step>("input");
  const [tokenRaw, setTokenRaw] = useState("");
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [result, setResult] = useState<ApplyResult | null>(null);

  const token = useMemo(() => formatToken(tokenRaw), [tokenRaw]);
  const isTokenValid = TOKEN_REGEX.test(token);

  const previewMutation = useMutation({
    mutationFn: () =>
      callImport({ token, dryRun: true }) as Promise<ImportPreview>,
    onSuccess: (data) => {
      setPreview(data);
      setStep("preview");
    },
    onError: (e: Error) => {
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" });
    },
  });

  const applyMutation = useMutation({
    mutationFn: () =>
      callImport({ token, dryRun: false }) as Promise<ApplyResult>,
    onSuccess: (data) => {
      setResult(data);
      setStep("result");
    },
    onError: (e: Error) => {
      toast({ title: tCommon("error"), description: e.message, variant: "destructive" });
    },
  });

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div className="flex items-center gap-3">
        <Link2 className="h-6 w-6 text-primary" />
        <h1 className="text-2xl font-bold tracking-tight">{t("title")}</h1>
      </div>

      <StepIndicator currentStep={step} />

      {step === "input" && (
        <Card>
          <CardHeader>
            <CardTitle>{t("step1.heading")}</CardTitle>
            <CardDescription>{t("step1.description")}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="token">{t("step1.codeLabel")}</Label>
              <Input
                id="token"
                value={token}
                onChange={(e) => setTokenRaw(e.target.value)}
                placeholder={t("codePlaceholder")}
                className="max-w-xs font-mono text-lg uppercase tracking-widest"
                maxLength={7}
                autoComplete="off"
                spellCheck={false}
                data-testid="token-input"
              />
              <p className="text-xs text-muted-foreground">{t("step1.codeHint")}</p>
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <Button
                variant="ghost"
                onClick={() => router.push(`/${locale}/menu`)}
                data-testid="cancel-button"
              >
                <ArrowLeft className="mr-1 h-4 w-4" /> {tCommon("cancel")}
              </Button>
              <Button
                onClick={() => previewMutation.mutate()}
                disabled={!isTokenValid || previewMutation.isPending}
                data-testid="preview-button"
              >
                {previewMutation.isPending ? tCommon("loading") : t("step1.previewButton")}
                <ArrowRight className="ml-1 h-4 w-4" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {step === "preview" && preview && (
        <Card>
          <CardHeader>
            <CardTitle>{t("step2.heading")}</CardTitle>
            <CardDescription>{t("step2.description")}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <DiffPreview data={preview} />

            <div className="flex justify-end gap-2 pt-2">
              <Button
                variant="ghost"
                onClick={() => {
                  setPreview(null);
                  setStep("input");
                }}
                data-testid="back-button"
              >
                <ArrowLeft className="mr-1 h-4 w-4" /> {tCommon("cancel")}
              </Button>
              <Button
                onClick={() => applyMutation.mutate()}
                disabled={applyMutation.isPending}
                data-testid="apply-button"
              >
                {applyMutation.isPending ? tCommon("loading") : t("step2.applyButton")}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {step === "result" && result && (
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <CheckCircle2 className="h-6 w-6 text-green-600" />
              <CardTitle>{t("step3.heading")}</CardTitle>
            </div>
            <CardDescription>{t("step3.description")}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {result.stats && <ResultStats stats={result.stats} />}

            <div className="rounded-lg border bg-muted/30 p-3 text-sm">
              <div className="text-muted-foreground">{t("step3.linkedAt")}</div>
              <div className="font-mono text-xs">{result.linkedAt}</div>
              <div className="mt-2 text-muted-foreground">{t("step3.syncEventId")}</div>
              <div className="font-mono text-xs">{result.syncEventId}</div>
            </div>

            <div className="flex justify-end pt-2">
              <Button
                onClick={() => router.push(`/${locale}/menu`)}
                data-testid="view-menu-button"
              >
                {t("step3.viewMenuButton")}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function StepIndicator({ currentStep }: { currentStep: Step }) {
  const t = useTranslations("menu.import");
  const steps: { key: Step; label: string }[] = [
    { key: "input", label: t("steps.input") },
    { key: "preview", label: t("steps.preview") },
    { key: "result", label: t("steps.result") },
  ];
  const currentIdx = steps.findIndex((s) => s.key === currentStep);

  return (
    <ol className="flex items-center gap-2 text-sm">
      {steps.map((s, i) => {
        const done = i < currentIdx;
        const active = i === currentIdx;
        return (
          <li key={s.key} className="flex items-center gap-2">
            <span
              className={`flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold ${
                active
                  ? "bg-primary text-primary-foreground"
                  : done
                  ? "bg-green-100 text-green-700"
                  : "bg-muted text-muted-foreground"
              }`}
            >
              {done ? "✓" : i + 1}
            </span>
            <span className={active ? "font-medium" : "text-muted-foreground"}>{s.label}</span>
            {i < steps.length - 1 && <span className="text-muted-foreground">→</span>}
          </li>
        );
      })}
    </ol>
  );
}

function ResultStats({ stats }: { stats: NonNullable<ApplyResult["stats"]> }) {
  const t = useTranslations("menu.import.step3");
  const rows: { label: string; added: number; updated: number }[] = [
    { label: t("categories"), added: stats.categoriesAdded, updated: stats.categoriesUpdated },
    { label: t("products"), added: stats.productsAdded, updated: stats.productsUpdated },
    { label: t("modifiers"), added: stats.modifiersAdded, updated: stats.modifiersUpdated },
  ];
  return (
    <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
      {rows.map((r) => (
        <div key={r.label} className="rounded-lg border bg-card p-3 text-sm">
          <div className="text-xs uppercase tracking-wide text-muted-foreground">{r.label}</div>
          <div className="mt-1 text-base">
            <span className="font-semibold text-green-700">+{r.added}</span>{" "}
            <span className="text-muted-foreground">/ {r.updated} {t("updated")}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

/** Auto-format tokens: uppercase, strip confusing chars, dash at position 3. */
function formatToken(input: string): string {
  const cleaned = input.toUpperCase().replace(TOKEN_CHARS, "");
  if (cleaned.length <= 3) return cleaned;
  return `${cleaned.slice(0, 3)}-${cleaned.slice(3, 6)}`;
}

/** Local fetch helper — calls /api/menu/import-from-token route handler. */
async function callImport(body: { token: string; dryRun: boolean }): Promise<unknown> {
  const res = await fetch("/api/menu/import-from-token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...body, mode: "merge" }),
  });
  const text = await res.text();
  const data: unknown = text ? safeJson(text) : null;
  if (!res.ok) {
    const p = data as { message?: string; code?: string } | null;
    throw new Error(p?.message || `HTTP ${res.status}`);
  }
  return data;
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}
