import { NextResponse } from "next/server";
import { apiPost } from "@/lib/api";
import { setSessionCookies } from "@/lib/auth";
import type { AdminLoginResponse } from "@/lib/api-types";

export async function POST(req: Request) {
  let body: { email?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ code: "INVALID_BODY", message: "Invalid JSON body" }, { status: 400 });
  }
  if (!body.email || !body.password) {
    return NextResponse.json({ code: "VALIDATION_ERROR", message: "email & password required" }, { status: 400 });
  }

  try {
    const data = await apiPost<AdminLoginResponse>("/auth/admin/login", {
      email: body.email,
      password: body.password,
    });
    // Pick the active tenant: HQ-tier admins land on the org context so the
    // sidebar/topbar can show aggregate views and offer a switcher; restaurant
    // managers land directly on their assigned tenant (matches the JWT
    // tenant_id the backend stamped, so X-Tenant-ID stays consistent).
    const isHQ =
      data.user.org_role === "HQ_ADMIN" ||
      data.user.org_role === "HQ_MANAGER" ||
      !!data.user.is_super_admin;
    const activeTenant = isHQ
      ? data.user.organization_id || data.user.store_ids?.[0]
      : data.user.store_ids?.[0] || data.user.organization_id;
    await setSessionCookies({
      token: data.access_token,
      refreshToken: data.refresh_token,
      user: data.user,
      tenantId: activeTenant,
    });
    return NextResponse.json({ user: data.user });
  } catch (e) {
    const err = e as { status?: number; code?: string; message?: string };
    return NextResponse.json(
      { code: err.code ?? "LOGIN_FAILED", message: err.message ?? "Login failed" },
      { status: err.status ?? 500 }
    );
  }
}
