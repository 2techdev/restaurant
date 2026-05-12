"use client";

import * as React from "react";
import type { AdminUser, Tenant } from "@/lib/api-types";

interface TenantContextValue {
  user: AdminUser;
  tenants: Tenant[];
  activeTenantId: string;
  /** "all" mode = HQ aggregate görünümü */
  isAllMode: boolean;
  /** Resolves only after the bo_tenant cookie has been set by the server. */
  setActive: (id: string) => Promise<void>;
}

const Ctx = React.createContext<TenantContextValue | null>(null);

export function TenantContextProvider({
  user,
  tenants,
  activeTenantId,
  children,
}: {
  user: AdminUser;
  tenants: Tenant[];
  activeTenantId: string;
  children: React.ReactNode;
}) {
  const [active, setActive] = React.useState(activeTenantId);

  const setActiveAndPersist = React.useCallback(async (id: string) => {
    setActive(id);
    // Must await — caller (TenantSwitcher) needs the bo_tenant Set-Cookie to
    // land before triggering a reload, otherwise SSR re-renders with the old
    // tenant. Regressed once before (jolly-final pre-pilot); keep awaited.
    await fetch("/api/auth/tenant", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tenantId: id }),
    });
  }, []);

  return (
    <Ctx.Provider
      value={{
        user,
        tenants,
        activeTenantId: active,
        isAllMode: active === "all",
        setActive: setActiveAndPersist,
      }}
    >
      {children}
    </Ctx.Provider>
  );
}

export function useTenant() {
  const ctx = React.useContext(Ctx);
  if (!ctx) throw new Error("useTenant must be used inside TenantContextProvider");
  return ctx;
}
