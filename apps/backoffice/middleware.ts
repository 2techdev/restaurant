import { NextResponse, type NextRequest } from "next/server";
import { COOKIE_TOKEN } from "@/lib/cookies";
import { defaultLocale, locales, type Locale } from "@/lib/i18n/config";

// Public, locale-prefixed paths that bypass the auth gate.
const PUBLIC_PATHS = [/^\/[a-z]{2}\/login(\/.*)?$/, /^\/login(\/.*)?$/];

// Pick a locale from cookie → Accept-Language → default.
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

// Build an absolute redirect using the *forwarded* Host + proto rather than
// req.nextUrl (which under output:'standalone' resolves Host to HOSTNAME=
// 127.0.0.1 → "Location: https://localhost:3001/..." — a broken redirect
// for browsers coming in via Caddy). Next's edge runtime parses the Location
// header with `new URL(...)` so a bare relative path also fails with
// ERR_INVALID_URL — absolute is required.
function publicRedirect(req: NextRequest, target: string): NextResponse {
  const host = req.headers.get("host") ?? "backoffice.gastrocore.ch";
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

  // No locale prefix: pick one and redirect to the prefixed equivalent.
  // Root "/" routes to /<locale> when authenticated, /<locale>/login otherwise.
  if (!localeFromUrl) {
    const chosen = detectLocale(req);
    const token = req.cookies.get(COOKIE_TOKEN)?.value;
    const target =
      pathname === "/"
        ? token
          ? `/${chosen}`
          : `/${chosen}/login`
        : `/${chosen}${pathname}${search}`;
    return publicRedirect(req, target);
  }

  // Locale-prefixed public path → render directly, no rewrite, no auth.
  if (PUBLIC_PATHS.some((re) => re.test(pathname))) {
    return NextResponse.next();
  }

  // Locale-prefixed protected path → require token; otherwise bounce to login.
  const token = req.cookies.get(COOKIE_TOKEN)?.value;
  if (!token) {
    return publicRedirect(
      req,
      `/${localeFromUrl}/login?from=${encodeURIComponent(pathname)}`,
    );
  }

  // Authenticated, prefixed page: render. Skipping next-intl middleware here
  // is intentional — under output:'standalone' it emits a self-rewrite to
  // https://localhost:3001/... which Next tries to fetch back to itself
  // (ECONNREFUSED). Locale is already in the URL, so no rewrite is needed.
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next|.*\\..*).*)"],
};
