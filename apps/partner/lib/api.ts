/**
 * Server-side Go-backend fetch client used by RSC + route handlers.
 * Mirrors apps/backoffice/lib/api.ts (same hash conventions, smaller surface).
 */

export const API_BASE_URL =
  process.env.API_BASE_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  "https://api.gastrocore.ch/api/v1";

export interface ApiOptions extends Omit<RequestInit, "body"> {
  body?: unknown;
  token?: string;
  absolute?: boolean;
}

export class ApiClientError extends Error {
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
  opts: ApiOptions = {},
): Promise<T> {
  const url = opts.absolute ? path : `${API_BASE_URL}${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    ...(opts.headers as Record<string, string>),
  };
  if (opts.token) headers["Authorization"] = `Bearer ${opts.token}`;
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
      0,
    );
  }
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
    const p = payload as { code?: string; message?: string } | null;
    throw new ApiClientError(
      p?.message || `HTTP ${res.status}`,
      p?.code || `HTTP_${res.status}`,
      res.status,
    );
  }
  return payload as T;
}

export const apiGet = <T = unknown>(path: string, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "GET" });
export const apiPost = <T = unknown>(path: string, body?: unknown, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "POST", body });
export const apiPut = <T = unknown>(path: string, body?: unknown, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "PUT", body });
export const apiDelete = <T = unknown>(path: string, opts: ApiOptions = {}) =>
  apiFetch<T>(path, { ...opts, method: "DELETE" });
