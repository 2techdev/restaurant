import { describe, it, expect } from "vitest";
import {
  isHqAdmin,
  isHqManager,
  isRestaurantManager,
  canManageMenu,
  canManageHq,
  jwtIsExpired,
  jwtExpiresAt,
} from "@/lib/roles";

describe("role helpers", () => {
  it("isHqAdmin", () => {
    expect(isHqAdmin("HQ_ADMIN")).toBe(true);
    expect(isHqAdmin("RESTAURANT_MANAGER")).toBe(false);
  });

  it("canManageHq covers HQ_ADMIN and HQ_MANAGER", () => {
    expect(canManageHq("HQ_ADMIN")).toBe(true);
    expect(canManageHq("HQ_MANAGER")).toBe(true);
    expect(canManageHq("RESTAURANT_MANAGER")).toBe(false);
    expect(canManageHq("POS_OPERATOR")).toBe(false);
  });

  it("canManageMenu allows managers, restaurants & HQ", () => {
    expect(canManageMenu("HQ_ADMIN")).toBe(true);
    expect(canManageMenu("RESTAURANT_MANAGER")).toBe(true);
    expect(canManageMenu("manager")).toBe(true);
    expect(canManageMenu("POS_OPERATOR")).toBe(false);
    expect(canManageMenu("RESTAURANT_STAFF")).toBe(false);
  });

  it("isRestaurantManager admit legacy 'admin'/'manager' roles", () => {
    expect(isRestaurantManager("admin")).toBe(true);
    expect(isRestaurantManager("manager")).toBe(true);
    expect(isRestaurantManager("staff")).toBe(false);
  });

  it("isHqManager: HQ_ADMIN included in isHqManager", () => {
    expect(isHqManager("HQ_ADMIN")).toBe(true);
    expect(isHqManager("HQ_MANAGER")).toBe(true);
    expect(isHqManager("RESTAURANT_MANAGER")).toBe(false);
  });
});

describe("JWT helpers", () => {
  it("jwtExpiresAt parses exp", () => {
    // {"alg":"none"}.{"exp": 9999999999}.<sig>
    const header = Buffer.from('{"alg":"none"}').toString("base64url");
    const payload = Buffer.from('{"exp":9999999999}').toString("base64url");
    const token = `${header}.${payload}.sig`;
    expect(jwtExpiresAt(token)).toBe(9999999999 * 1000);
    expect(jwtIsExpired(token)).toBe(false);
  });

  it("jwtIsExpired true for past exp", () => {
    const header = Buffer.from('{"alg":"none"}').toString("base64url");
    const payload = Buffer.from('{"exp":1000}').toString("base64url");
    const token = `${header}.${payload}.sig`;
    expect(jwtIsExpired(token)).toBe(true);
  });

  it("jwtExpiresAt returns null for malformed", () => {
    expect(jwtExpiresAt("not-a-jwt")).toBeNull();
  });
});
