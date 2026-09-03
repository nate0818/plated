import type { Metadata, Viewport } from "next";
import { Gabarito, Plus_Jakarta_Sans } from "next/font/google";
import "./globals.css";

// The same two faces the app registers at launch, from Google Fonts so
// plated.food and the phone draw the same letters. Gabarito is display only.
const gabarito = Gabarito({
  variable: "--font-gabarito",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  display: "swap",
});

const jakarta = Plus_Jakarta_Sans({
  variable: "--font-jakarta",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://plated.food"),
  title: {
    default: "Plated",
    template: "%s · Plated",
  },
  description:
    "A week you plan together, a private Table you post dinner to, and the recipes worth making again. For iPhone.",
  openGraph: {
    siteName: "Plated",
    type: "website",
    url: "https://plated.food",
  },
};

export const viewport: Viewport = {
  themeColor: "#FFFFFF",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${gabarito.variable} ${jakarta.variable}`}>
      <body>{children}</body>
    </html>
  );
}
