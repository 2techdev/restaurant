// Package i18n provides Accept-Language → locale negotiation and an
// error-message catalog so handlers can return localized error envelopes
// without each one importing a translation library.
//
// Supported locales: de (default), en, fr, it, tr.
//
// Usage:
//
//	lang := i18n.FromContext(r.Context())
//	msg := i18n.T(lang, "VALIDATION_ERROR")
//
// Unknown codes fall back to the English string, or — if even that is
// missing — return the code itself so callers always get something
// printable.
package i18n

import (
	"context"
	"net/http"
	"strings"
)

// Locale is a string alias for clarity at call sites.
type Locale string

const (
	LocaleDE      Locale = "de"
	LocaleEN      Locale = "en"
	LocaleFR      Locale = "fr"
	LocaleIT      Locale = "it"
	LocaleTR      Locale = "tr"
	DefaultLocale        = LocaleDE
)

var supported = map[Locale]bool{
	LocaleDE: true,
	LocaleEN: true,
	LocaleFR: true,
	LocaleIT: true,
	LocaleTR: true,
}

// contextKey is unexported to prevent collisions with other packages.
type contextKey struct{}

var langKey = contextKey{}

// FromContext returns the locale from ctx or the default.
func FromContext(ctx context.Context) Locale {
	if v, ok := ctx.Value(langKey).(Locale); ok && v != "" {
		return v
	}
	return DefaultLocale
}

// WithLocale attaches a locale to a context (used by the middleware and
// from tests).
func WithLocale(ctx context.Context, l Locale) context.Context {
	return context.WithValue(ctx, langKey, l)
}

// ParseAcceptLanguage picks the best-supported locale from an
// Accept-Language header. Quality factors are honored loosely — first
// matching weighted candidate wins. Empty/unparseable input → default.
//
// Examples:
//
//	"de-CH,de;q=0.9,en;q=0.8"        → de
//	"en-US"                          → en
//	"fr-CH,fr;q=0.9,en-US;q=0.5"     → fr
//	"zh-CN,zh;q=0.9"                 → de  (default; no Chinese catalog)
func ParseAcceptLanguage(header string) Locale {
	if header == "" {
		return DefaultLocale
	}
	type cand struct {
		tag string
		q   float64
	}
	parts := strings.Split(header, ",")
	cands := make([]cand, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		tag := p
		q := 1.0
		if semi := strings.Index(p, ";"); semi >= 0 {
			tag = strings.TrimSpace(p[:semi])
			if qIdx := strings.Index(p[semi:], "q="); qIdx >= 0 {
				qStr := strings.TrimSpace(p[semi+qIdx+2:])
				// Stop at next ';' just in case (RFC permits multiple params).
				if sc := strings.Index(qStr, ";"); sc >= 0 {
					qStr = qStr[:sc]
				}
				// Best-effort numeric parse — ignore failures.
				if parsed, ok := parseQ(qStr); ok {
					q = parsed
				}
			}
		}
		cands = append(cands, cand{tag: tag, q: q})
	}
	// Stable order by q desc.
	for i := 1; i < len(cands); i++ {
		for j := i; j > 0 && cands[j-1].q < cands[j].q; j-- {
			cands[j-1], cands[j] = cands[j], cands[j-1]
		}
	}
	for _, c := range cands {
		base := c.tag
		if dash := strings.Index(base, "-"); dash > 0 {
			base = base[:dash]
		}
		base = strings.ToLower(base)
		if supported[Locale(base)] {
			return Locale(base)
		}
	}
	return DefaultLocale
}

func parseQ(s string) (float64, bool) {
	// Tiny parser — avoid pulling strconv for the float dependency just for
	// this. RFC allows "0", "0.x", "1", "1.0", "1.000". Reject anything weirder.
	if s == "" {
		return 0, false
	}
	neg := false
	if s[0] == '-' {
		neg = true
		s = s[1:]
	}
	dot := strings.Index(s, ".")
	if dot < 0 {
		switch s {
		case "0":
			return 0, true
		case "1":
			if neg {
				return -1, true
			}
			return 1, true
		default:
			return 0, false
		}
	}
	whole := s[:dot]
	frac := s[dot+1:]
	if whole != "0" && whole != "1" {
		return 0, false
	}
	if len(frac) > 6 {
		frac = frac[:6]
	}
	w := 0.0
	if whole == "1" {
		w = 1.0
	}
	f := 0.0
	scale := 1.0
	for _, ch := range frac {
		if ch < '0' || ch > '9' {
			return 0, false
		}
		scale *= 10.0
		f = f*10 + float64(ch-'0')
	}
	v := w + f/scale
	if neg {
		v = -v
	}
	return v, true
}

// Middleware extracts Accept-Language and stores the chosen locale in ctx.
func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		locale := ParseAcceptLanguage(r.Header.Get("Accept-Language"))
		w.Header().Set("Content-Language", string(locale))
		next.ServeHTTP(w, r.WithContext(WithLocale(r.Context(), locale)))
	})
}

// T returns the translated string for the given code in the requested
// locale. Falls back to English, then to the code itself.
func T(lang Locale, code string) string {
	if catalog, ok := messages[lang]; ok {
		if s, ok := catalog[code]; ok {
			return s
		}
	}
	if catalog, ok := messages[LocaleEN]; ok {
		if s, ok := catalog[code]; ok {
			return s
		}
	}
	return code
}

// messages holds the per-locale catalogs. Keys mirror the response.Error
// `code` field. Add entries as new error codes are introduced.
var messages = map[Locale]map[string]string{
	LocaleDE: {
		"UNAUTHORIZED":      "Anmeldung erforderlich",
		"FORBIDDEN":         "Keine Berechtigung",
		"NOT_FOUND":         "Nicht gefunden",
		"VALIDATION_ERROR":  "Validierungsfehler",
		"INVALID_BODY":      "Ungültiger Anfrage-Body",
		"INTERNAL_ERROR":    "Interner Serverfehler",
		"DB_ERROR":          "Datenbankfehler",
		"NOT_IMPLEMENTED":   "Funktion noch nicht verfügbar",
		"TOKEN_NOT_FOUND":   "Token ungültig",
		"TOKEN_EXPIRED":     "Token abgelaufen oder bereits verwendet",
		"RATE_LIMITED":      "Zu viele Anfragen",
		"UPSTREAM_AUTH":     "Authentifizierung beim Reservierungsserver fehlgeschlagen",
		"UPSTREAM_ERROR":    "Reservierungsserver nicht erreichbar",
		"INVALID_SNAPSHOT":  "Ungültiger Menü-Snapshot",
		"CONFIG_ERROR":      "Serverkonfiguration unvollständig",
		"APPLY_FAILED":      "Import konnte nicht abgeschlossen werden",
	},
	LocaleEN: {
		"UNAUTHORIZED":      "Login required",
		"FORBIDDEN":         "Not allowed",
		"NOT_FOUND":         "Not found",
		"VALIDATION_ERROR":  "Validation error",
		"INVALID_BODY":      "Invalid request body",
		"INTERNAL_ERROR":    "Internal server error",
		"DB_ERROR":          "Database error",
		"NOT_IMPLEMENTED":   "Feature not yet available",
		"TOKEN_NOT_FOUND":   "Token not found",
		"TOKEN_EXPIRED":     "Token expired or already consumed",
		"RATE_LIMITED":      "Too many requests",
		"UPSTREAM_AUTH":     "Reservation server rejected the signature",
		"UPSTREAM_ERROR":    "Reservation server unreachable",
		"INVALID_SNAPSHOT":  "Invalid menu snapshot",
		"CONFIG_ERROR":      "Server configuration incomplete",
		"APPLY_FAILED":      "Menu import failed",
	},
	LocaleFR: {
		"UNAUTHORIZED":      "Connexion requise",
		"FORBIDDEN":         "Accès refusé",
		"NOT_FOUND":         "Introuvable",
		"VALIDATION_ERROR":  "Erreur de validation",
		"INVALID_BODY":      "Requête invalide",
		"INTERNAL_ERROR":    "Erreur interne du serveur",
		"DB_ERROR":          "Erreur de base de données",
		"NOT_IMPLEMENTED":   "Fonctionnalité indisponible",
		"TOKEN_NOT_FOUND":   "Jeton introuvable",
		"TOKEN_EXPIRED":     "Jeton expiré ou déjà utilisé",
		"RATE_LIMITED":      "Trop de requêtes",
		"UPSTREAM_AUTH":     "Authentification refusée par le serveur de réservation",
		"UPSTREAM_ERROR":    "Serveur de réservation injoignable",
		"INVALID_SNAPSHOT":  "Snapshot de menu invalide",
		"CONFIG_ERROR":      "Configuration du serveur incomplète",
		"APPLY_FAILED":      "Échec de l'importation du menu",
	},
	LocaleIT: {
		"UNAUTHORIZED":      "Accesso richiesto",
		"FORBIDDEN":         "Non autorizzato",
		"NOT_FOUND":         "Non trovato",
		"VALIDATION_ERROR":  "Errore di validazione",
		"INVALID_BODY":      "Corpo richiesta non valido",
		"INTERNAL_ERROR":    "Errore interno del server",
		"DB_ERROR":          "Errore del database",
		"NOT_IMPLEMENTED":   "Funzione non ancora disponibile",
		"TOKEN_NOT_FOUND":   "Token non trovato",
		"TOKEN_EXPIRED":     "Token scaduto o già utilizzato",
		"RATE_LIMITED":      "Troppe richieste",
		"UPSTREAM_AUTH":     "Autenticazione respinta dal server di prenotazione",
		"UPSTREAM_ERROR":    "Server di prenotazione non raggiungibile",
		"INVALID_SNAPSHOT":  "Snapshot del menu non valido",
		"CONFIG_ERROR":      "Configurazione del server incompleta",
		"APPLY_FAILED":      "Importazione del menu fallita",
	},
	LocaleTR: {
		"UNAUTHORIZED":      "Giriş gerekli",
		"FORBIDDEN":         "Yetkisiz işlem",
		"NOT_FOUND":         "Bulunamadı",
		"VALIDATION_ERROR":  "Doğrulama hatası",
		"INVALID_BODY":      "Geçersiz istek gövdesi",
		"INTERNAL_ERROR":    "Sunucu hatası",
		"DB_ERROR":          "Veritabanı hatası",
		"NOT_IMPLEMENTED":   "Bu özellik henüz aktif değil",
		"TOKEN_NOT_FOUND":   "Token bulunamadı",
		"TOKEN_EXPIRED":     "Token süresi dolmuş veya kullanılmış",
		"RATE_LIMITED":      "Çok fazla istek",
		"UPSTREAM_AUTH":     "Rezervasyon sunucusu imzayı reddetti",
		"UPSTREAM_ERROR":    "Rezervasyon sunucusuna ulaşılamıyor",
		"INVALID_SNAPSHOT":  "Geçersiz menü snapshot'ı",
		"CONFIG_ERROR":      "Sunucu yapılandırması eksik",
		"APPLY_FAILED":      "Menü içe aktarma başarısız",
	},
}
