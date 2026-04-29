import { describe, it, expect } from "vitest";
import { formatChf, chfToCents, centsToChfStr } from "@/lib/utils";

describe("currency helpers", () => {
  it("formatChf renders 'CHF 12.50' for 1250 cents", () => {
    const out = formatChf(1250, "de-CH");
    expect(out).toMatch(/CHF/);
    expect(out).toMatch(/12[.,]50/);
  });

  it("formatChf zero", () => {
    expect(formatChf(0, "de-CH")).toMatch(/0[.,]00/);
  });

  it("chfToCents accepts dot or comma", () => {
    expect(chfToCents("12.50")).toBe(1250);
    expect(chfToCents("12,50")).toBe(1250);
    expect(chfToCents(0.01)).toBe(1);
  });

  it("chfToCents handles invalid", () => {
    expect(chfToCents("abc")).toBe(0);
  });

  it("centsToChfStr round-trip", () => {
    expect(centsToChfStr(1250)).toBe("12.50");
    expect(centsToChfStr(99)).toBe("0.99");
  });
});
