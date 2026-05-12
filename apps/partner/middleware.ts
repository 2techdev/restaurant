import { NextResponse, type NextRequest } from "next/server";
import { COOKIE_TOKEN } from "@/lib/cookies";
import { defaultLocale, locales, type Locale } from "@/lib/i18n/config";

const PUBLIC_PATHS = [/^\/[a-z]{2}\/login(\/.*)?$/, /^\/login(\/.*)?$/];

function detectLocale(req: NextRequest): Locale {
  const fromCookie = req.cookies.get("NEXT_LOCALE")?.value;
  if (fromCookie && (locales as readonly string[]).includes(fromCookie)) {
    return fromCookie as Locale;
  }
  const accept = req.headers.get("accept-language") ?? "";
  for (const tag of accept.split(",")) {
    const lang = tag.split(";")[0].trim().toLowerCase().split("-")[0];
    if ((locales as readonly string[]).includes(lang)) return lang as Locale;
  }
  return defaultLocale;
}

function publicRedirect(req: NextRequest, target: string): NextResponse {
  const host = req.headers.get("host") ?? "partner.gastrocore.ch";
  const proto = req.headers.get("x-forwarded-proto") ?? "https";
  return NextResponse.redirect(`${proto}://${host}${target}`, 307);
}

export function middleware(req: NextRequest) {
  const { pathname, search } = req.nextUrl;
  if (
    pathname.startsWith("/_next") ||
    pathname.startsWith("/favicon") ||
    pathname.startsWith("/api/")
  ) {
    return NextResponse.next();
  }
  const localeMatch = pathname.match(/^\/([a-z]{2})(?:\/|$)/);
  const localeFromUrl =
    localeMatch && (locales as readonly string[]).includes(localeMatch[1])
      ? (localeMatch[1] as Locale)
      : null;
  if (!localeFromUrl) {
    const chosen = detectLocale(req);
    const token = req.cookies.get(COOKIE_TOKEN)?.value;
    const target =
      pathname === "/"
        ? token
          ? `/${chosen}/dashboard`
          : `/${chosen}/login`
        : `/${chosen}${pathname}${search}`;
    return publicRedirect(req, target);
  }
  if (PUBLIC_PATHS.some((re) => re.test(pathname))) {
    return NextResponse.next();
  }
  const token = req.cookies.get(COOKIE_TOKEN)?.value;
  if (!token) {
    return publicRedirect(
      req,
      `/${localeFromUrl}/login?from=${encodeURIComponent(pathname)}`,
    );
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next|.*\\..*).*)"],
};
