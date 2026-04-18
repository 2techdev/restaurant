# Restaurant — i18n / Localization

**Date:** 2026-04-17
**Owner:** quizzical-fermat worktree (i18n pass)
**Scope:** Flutter `apps/pos`, `apps/dashboard`, `apps/online` + `packages/gastrocore_models`.
**Pilot priority:** Swiss fine dining → **de-CH (primary)**, **tr** (multilingual staff pool), **en** (fallback), then fr-CH / it-CH.

## 1. Packages and tooling

| Layer | Package / tool |
|---|---|
| Flutter locale resolver | `flutter_localizations` (SDK) |
| Plural / select / date helpers | `intl` 0.20.2 (already in `apps/pos`, `apps/dashboard`, `apps/online`) |
| Code generator | `flutter gen-l10n` driven by `l10n.yaml` per app |
| Swiss rounding / number format | `packages/gastrocore_models/lib/src/utils/money.dart` |
| Locale-aware date format (pure Dart) | `packages/gastrocore_models/lib/src/utils/date_format.dart` |

> **Note.** A separate Next.js backoffice (`backoffice.gastrocore.ch`) was in the
> brief but **does not yet exist in this repo** — no `next.config.*`, no
> `package.json` outside `apps/online/web`. When it lands, pair `next-intl` with
> the same message keys and reuse the terminology table below.

## 2. ARB file locations

Each Flutter app owns its own ARB set. DE is the template in `apps/pos` and
`apps/dashboard` (Swiss-German-first); EN is the template in `apps/online` (it
was that way before this pass — kept to avoid churn in QR-menu copy).

```
apps/pos/lib/l10n/         app_de.arb  app_tr.arb  app_en.arb  app_fr.arb  app_it.arb
apps/dashboard/lib/l10n/   app_de.arb  app_tr.arb  app_en.arb  app_fr.arb  app_it.arb
apps/online/lib/l10n/      app_en.arb  app_tr.arb  app_de.arb  app_fr.arb  app_it.arb
```

Regenerate after editing ARBs:

```
cd apps/pos && flutter gen-l10n
cd apps/dashboard && flutter gen-l10n
cd apps/online && flutter gen-l10n
```

`apps/dashboard/pubspec.yaml` previously lacked `flutter: generate: true`, which
silently skipped code-gen. Flag added 2026-04-17.

## 3. Locale wiring

* `apps/pos/lib/features/settings/domain/entities/app_settings.dart` —
  `AppLanguage` enum now contains `de, tr, en, fr, it` (order = pilot priority).
* `apps/pos/lib/core/providers/locale_provider.dart` — maps `AppLanguage` to
  `Locale('de', 'CH')`, `Locale('tr')`, `Locale('en')`, `Locale('fr', 'CH')`,
  `Locale('it', 'CH')`. de/fr/it carry the `CH` region so `intl` picks Swiss
  thousand separators automatically for anything using `DateFormat`.
* `apps/dashboard/lib/app.dart` — now wires `AppLocalizations.delegate` and uses
  `AppLocalizations.supportedLocales`. Previously no app-level delegate.
* `apps/online/lib/providers/locale_provider.dart` + `widgets/language_selector.dart`
  — TR option added to the picker (flag 🇹🇷, label "Türkçe"). DE uses the 🇨🇭 flag
  in both apps, matching the Swiss pilot framing.

Persistence is unchanged: POS stores `AppSettings` JSON via `shared_preferences`,
online stores the language code under `gastrocore_online_locale`. Because the
storage is the same, a language switch survives restart — covered in the smoke
test below.

## 4. Terminology table

Keys that reflect user preference from the brief. Where a key previously
existed with another spelling, only the locales listed here were touched.

| Concept | Key | de-CH | tr | en | fr-CH | it-CH |
|---|---|---|---|---|---|---|
| Tax abbreviation (on receipt) | `fiscalReceiptVat` | MWST | KDV | VAT | TVA | IVA |
| Tax (generic line in POS UI) | `posVat` | MWST | KDV | VAT | TVA | IVA |
| Service charge | `posServiceCharge` | Service | Servis bedeli | Service | Service | Servizio |
| Cover / guests | `posCover` | Gäste | Kişi sayısı | Cover | Couverts | Coperti |
| Course label | `courseLabel(n)` | `1. Gang` | **`Gang 1`** (user pref) | `Course 1` | `Plat 1` | `Portata 1` |
| Menu cat. — starter | `menuCategoryStarter` | Vorspeise | Antre | Starter | Entrée | Antipasto |
| Menu cat. — main | `menuCategoryMain` | Hauptgang | Ana Yemek | Main | Plat principal | Secondo |
| Menu cat. — dessert | `menuCategoryDessert` | Dessert | Tatlı | Dessert | Dessert | Dessert |
| Guest count plural | `tableGuest(n)` | `{n} Gäste` | `{n} kişi` | `{n} guests` | (unchanged) | (unchanged) |
| Language & region group | `settingsLocale` | Sprache & Region | Dil ve Bölge | Language & Region | Langue et région | Lingua e regione |

## 5. Currency and date format

### Money helpers (`packages/gastrocore_models/lib/src/utils/money.dart`)

* `Money.format('CHF')` → `"CHF 15.00"` (unchanged).
* `Money.roundTo5Rappen()` — 5 Rappen rounding (unchanged; already shipped).
* **New** `Money.formatSwiss()` → `"1'234'567.89"` for receipts/reports.
* **New** `Money.formatForLocale(code)` — switches separators:
  * de/fr/it → apostrophe thousands, dot decimal (`1'234.56`)
  * en → comma / dot (`1,234.56`)
  * tr → dot / comma (`1.234,56`)

### Dates (`packages/gastrocore_models/lib/src/utils/date_format.dart`)

Pure-Dart helper (no Flutter binding) so that receipt printing and the sync
layer can render dates identically to the UI.

```dart
formatDate(dt, 'de');                             // 17.04.2026
formatDate(dt, 'tr');                             // 17.04.2026
formatDate(dt, 'en');                             // 2026-04-17
formatDate(dt, 'de', DateStyle.longDate);         // 17. April 2026
formatDate(dt, 'tr', DateStyle.longDate);         // 17 Nisan 2026
formatDate(dt, 'en', DateStyle.dateTime);         // 2026-04-17 14:05
```

## 6. Hard-coded string inventory (not yet migrated)

A ripgrep sweep for `Text('…[Turkish char]…')` and German fragments in widget
files turns up **37 literal strings across 13 files**. They were **not**
migrated in this pass to avoid merge conflicts with the parallel sessions
working in the same screens. Per-file atomic commits are the recommended path:

```
apps/pos/lib/features/customers/presentation/screens/customer_form_screen.dart
apps/pos/lib/features/customers/presentation/screens/loyalty_screen.dart
apps/pos/lib/features/dashboard/presentation/screens/analytics_screen.dart
apps/pos/lib/features/orders/presentation/screens/refund_screen.dart
apps/pos/lib/features/orders/presentation/screens/void_screen.dart
apps/pos/lib/features/orders/presentation/widgets/discount_dialog.dart
apps/pos/lib/features/settings/presentation/screens/settings_screen.dart
apps/dashboard/lib/features/dashboard/dashboard_screen.dart
apps/dashboard/lib/features/menu/menu_screen.dart
apps/dashboard/lib/features/orders/orders_screen.dart
apps/dashboard/lib/features/reports/reports_screen.dart
apps/dashboard/lib/features/settings/settings_screen.dart
apps/online/lib/screens/checkout_screen.dart
```

`refund_screen.dart` is the most obviously bilingual (title reads
`"Refund / İade"`) and is the best first target once the parallel sessions
settle.

## 7. Tests

* `apps/pos/test/l10n/localization_smoke_test.dart` — 7 cases covering locale
  load, 10+ string resolution per locale, and terminology invariants (MWST/KDV/VAT,
  Gäste/Kişi sayısı/Cover, Gang in TR). Status: **7/7 passing**.
* `packages/gastrocore_models/test/locale_format_test.dart` — 9 cases covering
  Money apostrophe grouping, 5-Rappen rounding, and per-locale date format.
  Status: **9/9 passing**.

Run:

```
cd apps/pos && flutter test test/l10n/localization_smoke_test.dart
cd packages/gastrocore_models && dart test
```

## 8. Follow-ups

1. Migrate the 13 files above, one PR per file.
2. Add a build-time lint that fails if any new `Text('…')` literal sneaks in.
   The existing `project-gap-analysis.md §5.7` already flags the missing-key
   detection gap; reuse that tracker.
3. When the Next.js backoffice lands, mirror the terminology table in
   `messages/{de,tr,en}.json` and add the same three invariant assertions.
4. If the pilot asks for Swiss-French / Swiss-Italian staff, audit long-date
   month casing — French and Italian in `date_format.dart` use lowercase month
   names as is customary; German and Turkish use title case.
