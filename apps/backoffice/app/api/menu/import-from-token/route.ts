import { NextResponse } from "next/server";
import { z } from "zod";
import { apiFetch, ApiClientError } from "@/lib/api";
import { getSession } from "@/lib/auth";

/**
 * /api/menu/import-from-token — POS Go server'a forward eder.
 *
 * Backend endpoint: POST /api/v1/menu/import-from-token
 * Auth: server-side cookie'den admin JWT + tenant ID alınır, header'a eklenir.
 *
 * Hata kodları → kullanıcı diline çevrilir (toast'ta göstermek için):
 *   - 401 UNAUTHORIZED → backoffice oturumu yok
 *   - 404 TOKEN_NOT_FOUND → kod geçersiz
 *   - 410 TOKEN_EXPIRED → kod süresi dolmuş
 *   - 429 RATE_LIMITED → çok fazla deneme
 */

const bodySchema = z.object({
  token: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-HJKMNP-Z2-9]{3}-[A-HJKMNP-Z2-9]{3}$/, "INVALID_TOKEN_FORMAT"),
  mode: z.literal("merge").default("merge"),
  dryRun: z.boolean().default(true),
});

export async function POST(req: Request) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json(
      { code: "UNAUTHORIZED", message: "Oturum bulunamadı." },
      { status: 401 }
    );
  }

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return NextResponse.json(
      { code: "INVALID_BODY", message: "Geçersiz istek gövdesi." },
      { status: 400 }
    );
  }

  const parsed = bodySchema.safeParse(raw);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const code = issue?.message ?? "INVALID_BODY";
    return NextResponse.json(
      {
        code,
        message:
          code === "INVALID_TOKEN_FORMAT"
            ? "Bağlantı kodu XXX-XXX biçiminde olmalı."
            : "Gövde doğrulanamadı.",
      },
      { status: 400 }
    );
  }

  try {
    const data = await apiFetch("/menu/import-from-token", {
      method: "POST",
      body: parsed.data,
      token: session.token,
      tenantId: session.tenantId,
    });
    return NextResponse.json(data ?? null);
  } catch (e) {
    const err = e as ApiClientError;
    const status = err.status ?? 500;
    const upstreamCode = err.code ?? "UPSTREAM_ERROR";
    const message = mapErrorToMessage(status, upstreamCode, err.message);
    return NextResponse.json(
      { code: upstreamCode, message },
      { status }
    );
  }
}

function mapErrorToMessage(status: number, code: string, fallback: string): string {
  if (status === 404 || code === "TOKEN_NOT_FOUND") {
    return "Bağlantı kodu bulunamadı. Lütfen Gastro Hub'da yeni bir kod üretin.";
  }
  if (status === 410 || code === "TOKEN_EXPIRED") {
    return "Bağlantı kodunun süresi dolmuş. Lütfen Gastro Hub'da yeni bir kod üretin.";
  }
  if (status === 429 || code === "RATE_LIMITED") {
    return "Çok fazla deneme yapıldı. Birkaç dakika sonra tekrar deneyin.";
  }
  if (status === 401) {
    return "Yetkilendirme hatası. Lütfen yeniden giriş yapın.";
  }
  if (status === 0 || code === "NETWORK_ERROR") {
    return "Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.";
  }
  return fallback || "Beklenmeyen bir hata oluştu.";
}
