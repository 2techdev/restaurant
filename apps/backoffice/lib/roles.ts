/**
 * Role helpers — pure functions, hem server hem client tarafında kullanılabilir.
 * (lib/auth.ts içindeki next/headers'a bağımlı session helper'larından ayrı tutuldu;
 * client component'lerin client bundle'ına next/headers sızmasın.)
 */

import type { UserRole } from "./api-types";

export function isHqAdmin(role: UserRole | string | undefined): boolean {
  return role === "HQ_ADMIN";
}
export function isHqManager(role: UserRole | string | undefined): boolean {
  return role === "HQ_MANAGER" || role === "HQ_ADMIN";
}
export function isRestaurantManager(role: UserRole | string | undefined): boolean {
  return (
    role === "RESTAURANT_MANAGER" ||
    role === "HQ_ADMIN" ||
    role === "HQ_MANAGER" ||
    role === "admin" ||
    role === "manager"
  );
}
export function canManageMenu(role: UserRole | string | undefined): boolean {
  return isRestaurantManager(role);
}
export function canManageHq(role: UserRole | string | undefined): boolean {
  return isHqManager(role);
}

/** JWT exp parse (verification yok — sadece expiry kontrolü) */
export function jwtExpiresAt(token: string): number | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const json =
      typeof window === "undefined"
        ? Buffer.from(b64, "base64").toString("utf-8")
        : decodeURIComponent(
            atob(b64)
              .split("")
              .map((c) => "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2))
              .join("")
          );
    const payload = JSON.parse(json);
    return typeof payload.exp === "number" ? payload.exp * 1000 : null;
  } catch {
    return null;
  }
}

export function jwtIsExpired(token: string): boolean {
  const exp = jwtExpiresAt(token);
  if (!exp) return false;
  return Date.now() >= exp - 30_000;
}
