import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Format CHF cents (integer) as "CHF 12.50". */
export function formatChf(cents: number, locale = "de-CH"): string {
  const value = (cents ?? 0) / 100;
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency: "CHF",
    maximumFractionDigits: 2,
  }).format(value);
}

/** Format ISO date as "29.04.2026 14:32" (locale-aware). */
export function formatDateTime(iso: string | Date | null | undefined, locale = "de-CH") {
  if (!iso) return "—";
  const d = typeof iso === "string" ? new Date(iso) : iso;
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "short",
    timeStyle: "short",
  }).format(d);
}

export function formatDate(iso: string | Date | null | undefined, locale = "de-CH") {
  if (!iso) return "—";
  const d = typeof iso === "string" ? new Date(iso) : iso;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(d);
}

/** Convert CHF input ("12.50") to cents (1250). */
export function chfToCents(input: string | number): number {
  const n = typeof input === "string" ? parseFloat(input.replace(",", ".")) : input;
  if (isNaN(n)) return 0;
  return Math.round(n * 100);
}

/** Convert cents to CHF decimal string ("12.50"). */
export function centsToChfStr(cents: number): string {
  return (cents / 100).toFixed(2);
}
