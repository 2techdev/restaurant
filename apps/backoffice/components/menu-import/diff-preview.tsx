"use client";

/**
 * Diff Preview — Gastro Hub'dan import için önizleme tablosu.
 *
 * Reservation MenuImportExportMenu (May 4) UX patterni:
 *   - 3 summary card (kategori / ürün / modifier)
 *   - Status pill: NEW / UPDATE / UNCHANGED / SKIP / ERROR
 *   - Uyarılar listesi
 *   - Detaylı satır tablosu (collapsible)
 */

import { useTranslations } from "next-intl";

export type DiffStatus = "NEW" | "UPDATE" | "UNCHANGED" | "SKIP" | "ERROR";

export type DiffRow = {
  identifier: string;
  status: DiffStatus;
  message?: string;
};

export type DiffSection = {
  new: number;
  update: number;
  unchanged: number;
  skip: number;
  error?: number;
};

export type ImportPreview = {
  preview: {
    categories: DiffSection;
    products: DiffSection;
    modifiers: DiffSection;
    summary: { categoriesTotal: number; productsTotal: number; modifiersTotal: number };
    warnings: string[];
    rows?: DiffRow[];
  };
};

export function DiffPreview({ data }: { data: ImportPreview }) {
  const t = useTranslations("menu.import.preview");
  const p = data.preview;
  const rows = p.rows ?? [];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <SummaryCard label={t("categories")} total={p.summary.categoriesTotal} section={p.categories} />
        <SummaryCard label={t("products")} total={p.summary.productsTotal} section={p.products} />
        <SummaryCard label={t("modifiers")} total={p.summary.modifiersTotal} section={p.modifiers} />
      </div>

      {p.warnings.length > 0 && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          <div className="mb-1 font-medium">⚠️ {t("warnings")}</div>
          <ul className="list-disc space-y-0.5 pl-5">
            {p.warnings.map((w, i) => (
              <li key={i}>{w}</li>
            ))}
          </ul>
        </div>
      )}

      {rows.length > 0 && (
        <details className="text-sm">
          <summary className="cursor-pointer text-muted-foreground">
            {t("rowReport", { count: rows.length })}
          </summary>
          <div className="mt-2 max-h-72 overflow-y-auto rounded border">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-muted/50">
                <tr>
                  <th className="p-2 text-left">{t("recordCol")}</th>
                  <th className="p-2 text-left">{t("statusCol")}</th>
                </tr>
              </thead>
              <tbody>
                {rows.slice(0, 500).map((r, i) => (
                  <tr key={i} className="border-t">
                    <td className="p-2">{r.identifier}</td>
                    <td className="p-2">
                      <StatusPill status={r.status} />
                      {r.message && <span className="ml-2 text-muted-foreground">{r.message}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {rows.length > 500 && (
              <div className="border-t p-2 text-xs text-muted-foreground">
                … {rows.length - 500} {t("moreRows")}
              </div>
            )}
          </div>
        </details>
      )}
    </div>
  );
}

function SummaryCard({
  label,
  total,
  section,
}: {
  label: string;
  total: number;
  section: DiffSection;
}) {
  const t = useTranslations("menu.import.preview");
  return (
    <div className="rounded-lg border bg-card p-3">
      <div className="text-xs uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className="mt-1 text-2xl font-semibold">{total}</div>
      <div className="mt-2 flex flex-wrap gap-1.5 text-xs">
        {section.new > 0 && (
          <Tag color="green">+{section.new} {t("new")}</Tag>
        )}
        {section.update > 0 && (
          <Tag color="amber">{section.update} {t("update")}</Tag>
        )}
        {section.unchanged > 0 && (
          <Tag color="gray">{section.unchanged} {t("unchanged")}</Tag>
        )}
        {section.skip > 0 && (
          <Tag color="orange">{section.skip} {t("skip")}</Tag>
        )}
        {section.error && section.error > 0 ? (
          <Tag color="red">{section.error} {t("error")}</Tag>
        ) : null}
      </div>
    </div>
  );
}

function Tag({
  color,
  children,
}: {
  color: "green" | "amber" | "gray" | "orange" | "red";
  children: React.ReactNode;
}) {
  const map = {
    green: "bg-green-100 text-green-800",
    amber: "bg-amber-100 text-amber-800",
    gray: "bg-gray-100 text-gray-700",
    orange: "bg-orange-100 text-orange-800",
    red: "bg-red-100 text-red-800",
  };
  return (
    <span className={`inline-block rounded px-1.5 py-0.5 font-medium ${map[color]}`}>
      {children}
    </span>
  );
}

export function StatusPill({ status }: { status: DiffStatus }) {
  const map: Record<DiffStatus, string> = {
    NEW: "bg-green-100 text-green-700",
    UPDATE: "bg-amber-100 text-amber-700",
    UNCHANGED: "bg-gray-100 text-gray-600",
    SKIP: "bg-orange-100 text-orange-700",
    ERROR: "bg-red-100 text-red-700",
  };
  return (
    <span className={`inline-block rounded px-1.5 py-0.5 text-xs font-medium ${map[status]}`}>
      {status}
    </span>
  );
}
