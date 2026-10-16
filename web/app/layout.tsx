import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import AnalyticsGate from "./components/AnalyticsGate";
import "./globals.css";

// The same font files the app registers at launch, self-hosted so page loads
// and builds never depend on a third-party font service.
const editorial = localFont({
  src: "./fonts/Newsreader.ttf",
  variable: "--font-editorial",
  weight: "200 800",
  display: "swap",
});

const sans = localFont({
  src: "./fonts/DMSans.ttf",
  variable: "--font-sans",
  weight: "100 1000",
  display: "swap",
});

// What a stranger sees before the page: the tab title, the search snippet,
// the card when the link is pasted into Messages. Every claim here is one
// the homepage also makes, so the snippet never promises more than the site.
const DESCRIPTION =
  "A shared meal plan, recipe book, and grocery list for your household. Decide what to cook, share the shopping, and see who’s cooking tonight. For iPhone and iPad.";

export const metadata: Metadata = {
  metadataBase: new URL("https://plated.food"),
  title: {
    default: "Plated: dinner plans, made together",
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
    title: "Plated: dinner plans, made together",
    description: DESCRIPTION,
  },
  twitter: {
    card: "summary_large_image",
    title: "Plated: dinner plans, made together",
    description: DESCRIPTION,
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 },
  },
  formatDetection: { telephone: false, email: false, address: false },
};

export const viewport: Viewport = {
  themeColor: "#191C17",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${editorial.variable} ${sans.variable}`}>
      <body>
        {children}
        <AnalyticsGate />
      </body>
    </html>
  );
}
