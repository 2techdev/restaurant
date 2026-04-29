"use client";

import * as React from "react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { localeNames, locales, type Locale } from "@/lib/i18n/config";

// ---------------------------------------------------------------------------
// Inline SVG flags. Kept minimal and consistent across platforms (emoji flags
// render very differently on Windows/Android/Apple). 24px viewBox.
// ---------------------------------------------------------------------------

function FlagTR({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <rect width="24" height="24" rx="3" fill="#E30A17" />
      <circle cx="9.5" cy="12" r="4" fill="#fff" />
      <circle cx="10.7" cy="12" r="3.2" fill="#E30A17" />
      <path
        fill="#fff"
        d="m15.7 12-2.55.83.79-2.43-1.58-2.07h2.55l.79-2.43.79 2.43h2.55l-1.58 2.07.79 2.43z"
        transform="translate(-1 0) scale(0.55) translate(8 9)"
      />
    </svg>
  );
}

function FlagDE({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <rect width="24" height="8" rx="0" fill="#000" />
      <rect y="8" width="24" height="8" fill="#DD0000" />
      <rect y="16" width="24" height="8" fill="#FFCE00" />
      <rect width="24" height="24" rx="3" fill="none" />
      <clipPath id="clipDE">
        <rect width="24" height="24" rx="3" />
      </clipPath>
      <g clipPath="url(#clipDE)">
        <rect width="24" height="8" fill="#000" />
        <rect y="8" width="24" height="8" fill="#DD0000" />
        <rect y="16" width="24" height="8" fill="#FFCE00" />
      </g>
    </svg>
  );
}

function FlagEN({ size = 20 }: { size?: number }) {
  // Simplified Union Jack
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <clipPath id="clipEN">
        <rect width="24" height="24" rx="3" />
      </clipPath>
      <g clipPath="url(#clipEN)">
        <rect width="24" height="24" fill="#012169" />
        <path d="M0 0 L24 24 M24 0 L0 24" stroke="#fff" strokeWidth="3" />
        <path d="M0 0 L24 24 M24 0 L0 24" stroke="#C8102E" strokeWidth="1.6" />
        <path d="M12 0 V24 M0 12 H24" stroke="#fff" strokeWidth="4" />
        <path d="M12 0 V24 M0 12 H24" stroke="#C8102E" strokeWidth="2.4" />
      </g>
    </svg>
  );
}

function FlagFR({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <clipPath id="clipFR">
        <rect width="24" height="24" rx="3" />
      </clipPath>
      <g clipPath="url(#clipFR)">
        <rect width="8" height="24" fill="#0055A4" />
        <rect x="8" width="8" height="24" fill="#fff" />
        <rect x="16" width="8" height="24" fill="#EF4135" />
      </g>
    </svg>
  );
}

function FlagIT({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <clipPath id="clipIT">
        <rect width="24" height="24" rx="3" />
      </clipPath>
      <g clipPath="url(#clipIT)">
        <rect width="8" height="24" fill="#009246" />
        <rect x="8" width="8" height="24" fill="#fff" />
        <rect x="16" width="8" height="24" fill="#CE2B37" />
      </g>
    </svg>
  );
}

const flagFor: Record<Locale, (props: { size?: number }) => React.ReactElement> = {
  tr: FlagTR,
  de: FlagDE,
  en: FlagEN,
  fr: FlagFR,
  it: FlagIT,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

interface LocaleSwitcherProps {
  locale: string;
  variant?: "flags" | "dropdown";
  size?: "sm" | "md";
  className?: string;
}

export function LocaleSwitcher({
  locale,
  variant = "flags",
  size = "md",
  className,
}: LocaleSwitcherProps) {
  const router = useRouter();
  const pathname = usePathname();
  const tCommon = useTranslations("common");

  const switchTo = (next: Locale) => {
    if (next === locale) return;
    const segments = pathname.split("/");
    if ((locales as readonly string[]).includes(segments[1] ?? "")) {
      segments[1] = next;
    } else {
      segments.splice(1, 0, next);
    }
    router.push(segments.join("/") || `/${next}`);
  };

  const flagSize = size === "sm" ? 18 : 22;

  if (variant === "dropdown") {
    const ActiveFlag = flagFor[(locale as Locale) ?? "tr"] ?? flagFor.tr;
    return (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="sm"
            className={cn("gap-2", className)}
            aria-label={tCommon("localeSwitcher")}
          >
            <ActiveFlag size={flagSize} />
            <span className="text-xs font-medium uppercase">{locale}</span>
            <ChevronDown className="h-3 w-3 opacity-60" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="min-w-[10rem]">
          {locales.map((l) => {
            const Flag = flagFor[l];
            const active = l === locale;
            return (
              <DropdownMenuItem
                key={l}
                onSelect={() => switchTo(l)}
                className={cn(
                  "gap-2 cursor-pointer",
                  active && "bg-accent/50 font-semibold"
                )}
              >
                <Flag size={18} />
                <span>{localeNames[l]}</span>
              </DropdownMenuItem>
            );
          })}
        </DropdownMenuContent>
      </DropdownMenu>
    );
  }

  // variant === "flags"
  return (
    <div
      className={cn("flex items-center gap-1.5", className)}
      role="group"
      aria-label={tCommon("localeSwitcher")}
    >
      {locales.map((l) => {
        const Flag = flagFor[l];
        const active = l === locale;
        return (
          <button
            key={l}
            type="button"
            onClick={() => switchTo(l)}
            aria-label={localeNames[l]}
            aria-current={active ? "true" : undefined}
            title={localeNames[l]}
            className={cn(
              "flex items-center justify-center rounded-md p-0.5 transition-all",
              "hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              active
                ? "ring-2 ring-primary opacity-100"
                : "opacity-60 hover:opacity-100"
            )}
          >
            <Flag size={flagSize} />
          </button>
        );
      })}
    </div>
  );
}
