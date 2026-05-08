/**
 * GET /api/admin/tenants — super admin tenant list (organizations + first
 * non-super-admin admin user as "owner" hint + admin user count + last
 * active timestamp). Forwards to Go server `/api/v1/admin/tenants`.
 *
 * Used by /[locale]/(dashboard)/admin/tenants page.
 */

import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { apiGet } from "@/lib/api";
import type { TenantInfo } from "@/lib/api-types";

export async function GET() {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ code: "UNAUTHORIZED", message: "Login required" }, { status: 401 });
  }
  if (!session.user.is_super_admin) {
    return NextResponse.json({ code: "FORBIDDEN", message: "Super admin role required" }, { status: 403 });
  }

  try {
    const data = await apiGet<{ tenants: TenantInfo[] }>("/admin/tenants", { token: session.token });
    return NextResponse.json(data);
  } catch (e) {
    const err = e as { status?: number; code?: string; message?: string };
    return NextResponse.json(
      { code: err.code ?? "TENANTS_FAILED", message: err.message ?? "Failed to load tenants" },
      { status: err.status ?? 500 }
    );
  }
}
