# Localization (l10n)

GastroCore POS ships with four UI locales:

| Code | Market            | File           |
|------|-------------------|----------------|
| `de` | Swiss German      | `app_de.arb`   |
| `fr` | Swiss French      | `app_fr.arb`   |
| `it` | Swiss Italian     | `app_it.arb`   |
| `en` | Fallback / dev    | `app_en.arb`   |

`app_de.arb` is the **template** — declared in `l10n.yaml` via
`template-arb-file: app_de.arb`. Only the template carries `@key`
metadata blocks (descriptions, placeholders, plural rules). The other
three locales hold value strings only.

## Adding a new key

1. Append the key + value + `@key` metadata block to `app_de.arb`.
2. Append the key + value (no `@key` block) to the other three ARBs.
3. Run `flutter gen-l10n` (or just `flutter run` — it runs automatically).
4. Use it via `AppLocalizations.of(context).yourKey`.

The `test/l10n/arb_parity_test.dart` suite fails CI if any locale
drifts. It also guards Swiss typography (no `ß` in Swiss German).

## Swiss typography rules

- Swiss German uses `ss` everywhere, never `ß`.
- Currency: `CHF 12.50` with a thin space, period as decimal mark,
  apostrophe as thousands separator (`1'234.50`).
- VAT is `MWST` (DE) / `TVA` (FR) / `IVA` (IT) / `VAT` (EN), rates
  are `8.1 %`, `2.6 %`, `3.8 %` with a space before `%`.
- Payment types include `TWINT` (verbatim).

## Project convention: Turkish UI vs localized UI

Most Turkish text is part of the active development UI and lives in
Dart string literals (not ARB). ARBs hold only the strings that are
needed to render the app in German, French, Italian, or English for a
Swiss pilot customer. When in doubt: Turkish → inline, German-family
→ ARB key.
