import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "GastroCore Backoffice",
  description: "GastroCore restoran yönetim paneli",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return children;
}
