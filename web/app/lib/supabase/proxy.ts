import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getPublicSupabaseConfig, SUPABASE_COOKIE_OPTIONS } from "./config";

export async function refreshSupabaseSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  const config = getPublicSupabaseConfig();

  if (!config) return response;

  const supabase = createServerClient(config.url, config.publishableKey, {
    cookieOptions: SUPABASE_COOKIE_OPTIONS,
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, cacheHeaders) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
        for (const [name, value] of Object.entries(cacheHeaders ?? {})) {
          response.headers.set(name, value);
        }
      },
    },
  });

  // This verifies and, when necessary, refreshes the JWT. Authorization still
  // happens in each page and Route Handler; the proxy is only cookie plumbing.
  await supabase.auth.getClaims();
  return response;
}
