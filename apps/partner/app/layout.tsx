import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "GastroCore Partner",
  description: "GastroCore operator / dealer portal",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return children;
}
