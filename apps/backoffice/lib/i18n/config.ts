export const locales = ["tr", "de", "en", "fr", "it"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "tr";
export const localeNames: Record<Locale, string> = {
  tr: "Türkçe",
  de: "Deutsch",
  en: "English",
  fr: "Français",
  it: "Italiano",
};
