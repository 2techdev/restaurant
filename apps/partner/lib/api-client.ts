"use client";

/** Browser-side fetch helper. All requests go through /api/proxy/* which
 *  attaches the partner-portal cookie token server-side. */

import { ApiClientError } from "./api";

export interface ClientFetchOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
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
    const p = payload as { code?: string; message?: string } | null;
    throw new ApiClientError(p?.message || `HTTP ${res.status}`, p?.code || `HTTP_${res.status}`, res.status);
  }
  return payload as T;
}

function safeJson(text: string): unknown {
  try { return JSON.parse(text); } catch { return text; }
}
