"use client";

import { Analytics } from "@vercel/analytics/next";
import { usePathname } from "next/navigation";

/**
 * The founder console is an operations surface. Keeping it outside the public
 * site's analytics avoids mixing founder navigation into acquisition numbers.
 */
export default function AnalyticsGate() {
  const pathname = usePathname();

  if (pathname === "/admin" || pathname.startsWith("/admin/")) {
    return null;
  }

  return <Analytics />;
}
