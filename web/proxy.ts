import { NextResponse, type NextRequest } from "next/server";
import { canonicalAdminOrigin, noStoreHeaders } from "./app/lib/admin/request";
import { refreshSupabaseSession } from "./app/lib/supabase/proxy";

export async function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;
  const apiRequest = pathname === "/api/admin" || pathname.startsWith("/api/admin/");
  let expectedOrigin: string;

  try {
    expectedOrigin = canonicalAdminOrigin(request.url);
  } catch {
    if (apiRequest) {
      return NextResponse.json(
        { error: "The founder console origin is not configured." },
        { status: 503, headers: noStoreHeaders() },
      );
    }
    return new NextResponse("The founder console origin is not configured.", {
      status: 503,
      headers: { ...noStoreHeaders(), "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  if (new URL(request.url).origin !== expectedOrigin) {
    if (apiRequest) {
      return NextResponse.json(
        { error: "This request did not come from the canonical founder console." },
        { status: 403, headers: noStoreHeaders() },
      );
    }

    // Never carry an invite/recovery token or other query data across hosts.
    const destination = pathname === "/admin/auth/confirm"
      ? new URL("/admin/login?notice=link", expectedOrigin)
      : new URL(pathname, expectedOrigin);
    return NextResponse.redirect(destination, { headers: noStoreHeaders() });
  }

  return refreshSupabaseSession(request);
}

export const config = {
  matcher: ["/admin/:path*", "/api/admin/:path*"],
};
