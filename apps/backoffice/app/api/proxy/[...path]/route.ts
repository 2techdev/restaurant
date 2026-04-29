import { NextResponse } from "next/server";
import { apiFetch } from "@/lib/api";
import { getSession } from "@/lib/auth";

/**
 * /api/proxy/* — generic backend proxy. Server-side cookie'den token + tenant okur,
 * Bearer + X-Tenant-ID header'larını ekleyerek backend'e iletir.
 */

async function handler(req: Request, ctx: { params: Promise<{ path: string[] }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ code: "UNAUTHORIZED", message: "Not signed in" }, { status: 401 });

  const { path } = await ctx.params;
  const url = `/${path.join("/")}` + (new URL(req.url).search || "");
  const method = req.method;

  let body: unknown = undefined;
  if (method !== "GET" && method !== "HEAD") {
    const text = await req.text();
    if (text) {
      try { body = JSON.parse(text); } catch { body = text; }
    }
  }

  try {
    const data = await apiFetch(url, {
      method,
      body,
      token: session.token,
      tenantId: session.tenantId,
    });
    return NextResponse.json(data ?? null);
  } catch (e) {
    const err = e as { status?: number; code?: string; message?: string };
    return NextResponse.json(
      { code: err.code ?? "PROXY_ERROR", message: err.message ?? "Proxy error" },
      { status: err.status ?? 500 }
    );
  }
}

export const GET = handler;
export const POST = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
