/**
 * POST /api/admin/impersonate/exit — end the active impersonation session.
 *
 * 1. Calls Go server `/api/v1/admin/impersonate/exit` with the impersonation
 *    JWT (so impersonation_sessions.ended_at gets set).
 * 2. Restores the super admin's original session from *_ORIG cookies via
 *    endImpersonation(). Drops *_ORIG cookies on the way out.
 *
 * If there's no active impersonation (cookies not present), this is a no-op
 * but still returns 200 — idempotent client retry safe.
 */

import { NextResponse } from "next/server";
import { getSession, endImpersonation } from "@/lib/auth";
import { apiPost } from "@/lib/api";

export async function POST() {
  const session = await getSession();

  // Best-effort: tell Go server to mark session ended. We don't gate the
  // cookie restore on this — even if the upstream call fails, restoring the
  // super admin's session locally is the right thing to do (otherwise the
  // user would be stranded in an expired impersonation).
  if (session) {
    try {
      await apiPost("/admin/impersonate/exit", {}, { token: session.token });
    } catch {
      // Already-exited / expired-token / network — log only.
    }
  }

  const restored = await endImpersonation();

  return NextResponse.json({
    success: true,
    restored,
  });
}
