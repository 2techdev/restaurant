import "@testing-library/jest-dom/vitest";
import { afterEach, vi } from "vitest";
import { cleanup } from "@testing-library/react";

// Auto-cleanup DOM between tests
afterEach(() => cleanup());

// next-intl mock — testlerde TR mesajlarını default kullan
vi.mock("next-intl", async () => {
  const actual = await vi.importActual<typeof import("next-intl")>("next-intl");
  return {
    ...actual,
    useTranslations: (ns?: string) => {
      return (key: string, vars?: Record<string, string | number>) => {
        const k = ns ? `${ns}.${key}` : key;
        if (vars && Object.keys(vars).length) {
          return `${k}(${JSON.stringify(vars)})`;
        }
        return k;
      };
    },
  };
});

// next/navigation mock
vi.mock("next/navigation", () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    refresh: vi.fn(),
    back: vi.fn(),
  }),
  useSearchParams: () => new URLSearchParams(),
  usePathname: () => "/tr/login",
  redirect: vi.fn(),
  notFound: vi.fn(),
}));
