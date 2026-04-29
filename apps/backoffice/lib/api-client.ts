"use client";

/**
 * Browser-side API helper. Tüm istekleri Next.js'in kendi route handler'larına gönderir
 * (`/api/proxy/*`); cookie httpOnly olduğu için token doğrudan browser'dan kullanılamaz.
 */

import { ApiClientError } from "./api";

export interface ClientFetchOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
  /** API path, ör. "/menu/categories" — /api/proxy prefix'i otomatik eklenir */
  path: string;
}

export async function clientFetch<T = unknown>(opts: ClientFetchOptions): Promise<T> {
  const { path, body, ...rest } = opts;
  const url = `/api/proxy${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    ...(rest.headers as Record<string, string>),
  };
  const res = await fetch(url, {
    ...rest,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const payload: unknown = text ? safeJson(text) : null;
  if (!res.ok) {
    const p = payload as { code?: string; message?: string; error?: { code?: string; message?: string } } | null;
    const err = p?.error ?? p ?? {};
    throw new ApiClientError(err.message || `HTTP ${res.status}`, err.code || `HTTP_${res.status}`, res.status);
  }
  return payload as T;
}

function safeJson(text: string): unknown {
  try { return JSON.parse(text); } catch { return text; }
}
