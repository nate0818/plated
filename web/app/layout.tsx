import type { Metadata, Viewport } from "next";
import { Gabarito, Plus_Jakarta_Sans } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import AnimatedFavicon from "./components/AnimatedFavicon";
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

// What a stranger sees before the page: the tab title, the search snippet,
// the card when the link is pasted into Messages. Every claim here is one
// the homepage also makes, so the snippet never promises more than the site.
const DESCRIPTION =
  "Plated is a dinner planner for households and the people they cook for. Plan the week together, keep the recipes you love, and share what you made with the people you invite. Coming to iPhone and iPad.";

export const metadata: Metadata = {
  metadataBase: new URL("https://plated.food"),
  title: {
    default: "Plated: plan the week's dinners together",
    template: "%s · Plated",
  },
  description: DESCRIPTION,
  applicationName: "Plated",
  keywords: [
    "meal planner",
    "dinner planner",
    "weekly meal planning app",
    "family meal planner",
    "household meal planning",
    "recipe app",
    "grocery list app",
    "iPhone",
    "iPad",
  ],
  authors: [{ name: "Plated" }],
  creator: "Plated",
  category: "food",
  alternates: { canonical: "/" },
  openGraph: {
    siteName: "Plated",
    type: "website",
    locale: "en_US",
    url: "https://plated.food",
    title: "Plated: plan the week's dinners together",
    description: DESCRIPTION,
  },
  twitter: {
    card: "summary_large_image",
    title: "Plated: plan the week's dinners together",
    description: DESCRIPTION,
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 },
  },
  formatDetection: { telephone: false, email: false, address: false },
  icons: {
    // Safari pinned tabs want a monochrome SVG and paint it in this colour.
    other: [{ rel: "mask-icon", url: "/mask-icon.svg", color: "#FF5A3C" }],
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
      <body>
        <AnimatedFavicon />
        {children}
        <Analytics />
      </body>
    </html>
  );
}
