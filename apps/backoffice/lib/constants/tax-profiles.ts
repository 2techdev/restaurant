/**
 * Swiss VAT (MWST) rates — effective from 2024-01-01.
 *
 * Old rates 7.7 / 2.5 / 3.7 are obsolete. Single source of truth for
 * dropdowns + reports. Backend `tax_profiles` table mirrors these via
 * migration 018; the seed (`server/cmd/seed/main.go`) already inserts the
 * new rates.
 */
export const CH_TAX_PROFILES = [
  { id: "standard", name: "Standart", rate: 0.081, label: "%8.1" },
  { id: "reduced", name: "İndirimli", rate: 0.026, label: "%2.6" },
  { id: "accommodation", name: "Konaklama", rate: 0.038, label: "%3.8" },
  { id: "exempt", name: "Muaf", rate: 0, label: "%0" },
] as const;

export type ChTaxProfileId = (typeof CH_TAX_PROFILES)[number]["id"];

/** Look up the human label by id (e.g. "Standart (%8.1)"). */
export function chTaxLabel(id: string): string {
  const p = CH_TAX_PROFILES.find((x) => x.id === id);
  return p ? `${p.name} (${p.label})` : id;
}
