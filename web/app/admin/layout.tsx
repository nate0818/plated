import type { Metadata } from "next";

// Not a page for finding. The robots file says so too.
export const metadata: Metadata = {
  title: "Founder console",
  description: "Private Plated operations console.",
  robots: { index: false, follow: false, nocache: true },
};

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return children;
}
