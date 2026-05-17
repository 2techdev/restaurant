/**
 * Auth — server-only session/cookie helpers.
 *
 * Login akışı: /login form → POST /api/auth/login (Next.js route handler)
 * → backend admin login → cookie set.
 *
 * Cookie'ler:
 *   - bo_token (httpOnly, sameSite=lax, secure prod) — JWT access token
 *   - bo_refresh (httpOnly) — refresh token
 *   - bo_user (httpOnly) — base64 JSON: { id, email, name, role, organization_id, store_ids }
 *   - bo_tenant (sameSite=lax, NOT httpOnly çünkü client de okuyabilmeli) — aktif tenant_id
 *
 * Pure role helper'ları için bkz. `lib/roles.ts`. Bu modül `next/headers` import
 * eder; sadece server component'ler/route handler'larda kullanılmalı.
 */

import "server-only";
import { cookies } from "next/headers";
import type { AdminUser } from "./api-types";
import {
  COOKIE_TOKEN, COOKIE_REFRESH, COOKIE_USER, COOKIE_TENANT,
  COOKIE_TOKEN_ORIG, COOKIE_USER_ORIG, COOKIE_TENANT_ORIG,
} from "./cookies";

export {
  COOKIE_TOKEN, COOKIE_REFRESH, COOKIE_USER, COOKIE_TENANT,
  COOKIE_TOKEN_ORIG, COOKIE_USER_ORIG, COOKIE_TENANT_ORIG,
};

const ONE_DAY = 60 * 60 * 24;
const SEVEN_DAYS = ONE_DAY * 7;

export interface SessionPayload {
  token: string;
  refreshToken: string;
  user: AdminUser;
  tenantId: string;
}

export async function getSession(): Promise<SessionPayload | null> {
  const c = await cookies();
  const token = c.get(COOKIE_TOKEN)?.value;
  const refresh = c.get(COOKIE_REFRESH)?.value;
  const userRaw = c.get(COOKIE_USER)?.value;
  const tenant = c.get(COOKIE_TENANT)?.value;
  if (!token || !userRaw) return null;
  try {
    const user = JSON.parse(Buffer.from(userRaw, "base64").toString("utf-8")) as AdminUser;
    return {
      token,
      refreshToken: refresh ?? "",
      user,
      tenantId: tenant ?? user.organization_id ?? user.store_ids?.[0] ?? "",
    };
  } catch {
    return null;
  }
}

export async function setSessionCookies(payload: {
  token: string;
  refreshToken: string;
  user: AdminUser;
  tenantId?: string;
}) {
  const c = await cookies();
  const isProd = process.env.NODE_ENV === "production";
  const secure = isProd;
  c.set(COOKIE_TOKEN, payload.token, {
    httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: ONE_DAY,
  });
  c.set(COOKIE_REFRESH, payload.refreshToken, {
    httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: SEVEN_DAYS,
  });
  const userB64 = Buffer.from(JSON.stringify(payload.user), "utf-8").toString("base64");
  c.set(COOKIE_USER, userB64, {
    httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: SEVEN_DAYS,
  });
  c.set(COOKIE_TENANT, payload.tenantId ?? payload.user.organization_id ?? "", {
    httpOnly: false, sameSite: "lax", secure, path: "/", maxAge: SEVEN_DAYS,
  });
}

export async function clearSession() {
  const c = await cookies();
  for (const k of [
    COOKIE_TOKEN, COOKIE_REFRESH, COOKIE_USER, COOKIE_TENANT,
    COOKIE_TOKEN_ORIG, COOKIE_USER_ORIG, COOKIE_TENANT_ORIG,
  ]) {
    c.delete(k);
  }
}

// ── Impersonation session helpers (F1, migration 024) ───────────────────────
export async function startImpersonation(payload: {
  token: string;
  targetUser: AdminUser;
  tenantId: string;
  superAdminEmail: string;
  superAdminId: string;
}) {
  const c = await cookies();
  const isProd = process.env.NODE_ENV === "production";
  const secure = isProd;
  const curToken = c.get(COOKIE_TOKEN)?.value ?? "";
  const curUser = c.get(COOKIE_USER)?.value ?? "";
  const curTenant = c.get(COOKIE_TENANT)?.value ?? "";
  if (curToken) c.set(COOKIE_TOKEN_ORIG, curToken, { httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: ONE_DAY });
  if (curUser) c.set(COOKIE_USER_ORIG, curUser, { httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: ONE_DAY });
  if (curTenant) c.set(COOKIE_TENANT_ORIG, curTenant, { httpOnly: false, sameSite: "lax", secure, path: "/", maxAge: ONE_DAY });
  const FIFTEEN_MIN = 60 * 15;
  c.set(COOKIE_TOKEN, payload.token, { httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: FIFTEEN_MIN });
  const userWithImpersonation: AdminUser = {
    ...payload.targetUser,
    impersonated_by_email: payload.superAdminEmail,
    impersonated_by_id: payload.superAdminId,
  };
  const userB64 = Buffer.from(JSON.stringify(userWithImpersonation), "utf-8").toString("base64");
  c.set(COOKIE_USER, userB64, { httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: FIFTEEN_MIN });
  c.set(COOKIE_TENANT, payload.tenantId, { httpOnly: false, sameSite: "lax", secure, path: "/", maxAge: FIFTEEN_MIN });
}

export async function endImpersonation(): Promise<boolean> {
  const c = await cookies();
  const origToken = c.get(COOKIE_TOKEN_ORIG)?.value;
  const origUser = c.get(COOKIE_USER_ORIG)?.value;
  const origTenant = c.get(COOKIE_TENANT_ORIG)?.value;
  if (!origToken || !origUser) return false;
  const isProd = process.env.NODE_ENV === "production";
  const secure = isProd;
  c.set(COOKIE_TOKEN, origToken, { httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: ONE_DAY });
  c.set(COOKIE_USER, origUser, { httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: SEVEN_DAYS });
  if (origTenant) {
    c.set(COOKIE_TENANT, origTenant, { httpOnly: false, sameSite: "lax", secure, path: "/", maxAge: SEVEN_DAYS });
  }
  c.delete(COOKIE_TOKEN_ORIG);
  c.delete(COOKIE_USER_ORIG);
  c.delete(COOKIE_TENANT_ORIG);
  return true;
}

export async function setActiveTenant(tenantId: string) {
  const c = await cookies();
  c.set(COOKIE_TENANT, tenantId, {
    httpOnly: false,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: SEVEN_DAYS,
  });
}

// Re-export role helpers for convenience in server components.
export {
  isHqAdmin,
  isHqManager,
  isRestaurantManager,
  canManageMenu,
  canManageHq,
  jwtExpiresAt,
  jwtIsExpired,
} from "./roles";
