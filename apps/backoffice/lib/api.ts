/**
 * Fetch client — Go backend ile iletişim.
 *
 * Sunucu tarafında (RSC, Route Handler, Server Action): cookies()'tan token + tenant okur.
 * Client tarafında: aynı endpoint'leri Next.js route handler'larından (proxy) çağırırız.
 *
 * Hata: ApiError throw eder (.code, .message, .status alanlarıyla).
 */

import type { ApiError } from "./api-types";

export const API_BASE_URL =
  process.env.API_BASE_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  "https://api.gastrocore.ch/api/v1";

export interface ApiOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
  token?: string;
  tenantId?: string;
  /** Mutlak URL kullan; default false (path → API_BASE_URL'e ekle) */
  absolute?: boolean;
}

export class ApiClientError extends Error implements ApiError {
  code: string;
  status: number;
  constructor(message: string, code: string, status: number) {
    super(message);
    this.code = code;
    this.status = status;
    this.name = "ApiClientError";
  }
}

export async function apiFetch<T = unknown>(
  path: string,
  opts: ApiOptions = {}
): Promise<T> {
  const url = opts.absolute ? path : `${API_BASE_URL}${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    ...(opts.headers as Record<string, string>),
  };
  if (opts.token) headers["Authorization"] = `Bearer ${opts.token}`;
  if (opts.tenantId) headers["X-Tenant-ID"] = opts.tenantId;

  const init: RequestInit = {
    ...opts,
    headers,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
    cache: opts.cache ?? "no-store",
  };

  let res: Response;
  try {
    res = await fetch(url, init);
  } catch (e) {
    throw new ApiClientError(
      e instanceof Error ? e.message : "Network error",
      "NETWORK_ERROR",
      0
    );
  }

  // 204 No Content
  if (res.status === 204) return undefined as T;

  const text = await res.text();
  let payload: unknown = null;
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch {
      payload = text;
    }
  }

  if (!res.ok) {
    const p = payload as { code?: string; message?: string; error?: { code?: string; message?: string } } | null;
    const err = p?.error ?? p ?? {};
    throw new ApiClientError(
      err.message || `HTTP ${res.status}`,
      err.code || `HTTP_${res.status}`,
      res.status
    );
  }

  return payload as T;
}

/** Convenience helpers (server-side import only — token/tenant explicit) */
export const apiGet = <T = unknown>(path: string, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "GET" });

export const apiPost = <T = unknown>(path: string, body?: unknown, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "POST", body });

export const apiPut = <T = unknown>(path: string, body?: unknown, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "PUT", body });

export const apiDelete = <T = unknown>(path: string, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "DELETE" });
