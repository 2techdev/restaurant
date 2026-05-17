/**
 * POST /api/admin/impersonate — start a super admin impersonation session.
 *
 * Forwards to Go server `POST /api/v1/admin/impersonate` with the calling
 * super admin's JWT. On success, swaps the active session cookies
 * (bo_token/bo_user/bo_tenant) for the short-lived (15 min) target session
 * and stashes the originals in *_ORIG cookies for `exit` to restore.
 *
 * F1 — Wallee-style ghost login. Pairs with /api/admin/impersonate/exit.
 */

import { NextResponse } from "next/server";
import { getSession, startImpersonation } from "@/lib/auth";
import { apiPost } from "@/lib/api";
import type { ImpersonateResponse } from "@/lib/api-types";

export async function POST(req: Request) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ code: "UNAUTHORIZED", message: "Login required" }, { status: 401 });
  }
  if (!session.user.is_super_admin) {
    return NextResponse.json({ code: "FORBIDDEN", message: "Super admin role required" }, { status: 403 });
  }

  let body: { target_user_id?: string; reason?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ code: "INVALID_BODY", message: "Invalid JSON body" }, { status: 400 });
  }
  if (!body.target_user_id) {
    return NextResponse.json(
      { code: "VALIDATION_ERROR", message: "target_user_id required" },
      { status: 400 }
    );
  }

  try {
    const data = await apiPost<ImpersonateResponse>(
      "/admin/impersonate",
      { target_user_id: body.target_user_id, reason: body.reason ?? "" },
      { token: session.token }
    );

    await startImpersonation({
      token: (data as ImpersonateResponse & { token: string }).token,
      targetUser: {
        id: data.target_user.id,
        organization_id: data.target_user.organization_id,
        email: data.target_user.email,
        name: data.target_user.name,
        role: data.target_user.role,
      },
      tenantId: data.target_user.organization_id,
      superAdminEmail: session.user.email,
      superAdminId: session.user.id,
    });

    return NextResponse.json({
      success: true,
      session_id: data.session_id,
      expires_at: data.expires_at,
      target_user: data.target_user,
    });
  } catch (e) {
    const err = e as { status?: number; code?: string; message?: string };
    return NextResponse.json(
      { code: err.code ?? "IMPERSONATE_FAILED", message: err.message ?? "Impersonate failed" },
      { status: err.status ?? 500 }
    );
  }
}
