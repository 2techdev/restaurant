/**
 * Server-only session helpers. Partner portal uses a single cookie
 * `pp_token` (JWT) plus `pp_user` (base64-JSON profile). No refresh token
 * yet — pilot scope. Different cookie names than the backoffice
 * (`bo_token` / `bo_user`) so a browser logged into both never confuses
 * sessions.
 */

import "server-only";
import { cookies } from "next/headers";

export const COOKIE_TOKEN = "pp_token";
export const COOKIE_USER = "pp_user";

export interface PartnerUser {
  id: string;
  email: string;
  name: string;
  role: "OPERATOR" | "BD" | "MANAGER" | "EMPLOYEE";
  status: string;
}

export interface SessionPayload {
  token: string;
  user: PartnerUser;
}

const ONE_DAY = 60 * 60 * 24;
const SEVEN_DAYS = ONE_DAY * 7;

export async function getSession(): Promise<SessionPayload | null> {
  const c = await cookies();
  const token = c.get(COOKIE_TOKEN)?.value;
  const userRaw = c.get(COOKIE_USER)?.value;
  if (!token || !userRaw) return null;
  try {
    const user = JSON.parse(Buffer.from(userRaw, "base64").toString("utf-8")) as PartnerUser;
    return { token, user };
  } catch {
    return null;
  }
}

export async function setSessionCookies(payload: SessionPayload) {
  const c = await cookies();
  const secure = process.env.NODE_ENV === "production";
  c.set(COOKIE_TOKEN, payload.token, {
    httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: ONE_DAY,
  });
  const userB64 = Buffer.from(JSON.stringify(payload.user), "utf-8").toString("base64");
  c.set(COOKIE_USER, userB64, {
    httpOnly: true, sameSite: "lax", secure, path: "/", maxAge: SEVEN_DAYS,
  });
}

export async function clearSession() {
  const c = await cookies();
  c.delete(COOKIE_TOKEN);
  c.delete(COOKIE_USER);
}

export function isAtLeast(role: PartnerUser["role"], min: PartnerUser["role"]): boolean {
  const rank = { EMPLOYEE: 1, MANAGER: 2, BD: 3, OPERATOR: 4 } as const;
  return rank[role] >= rank[min];
}
