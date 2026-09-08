"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";
import { requirePublicSupabaseConfig, SUPABASE_COOKIE_OPTIONS } from "./config";

let browserClient: SupabaseClient | undefined;

export function createClient(): SupabaseClient {
  if (!browserClient) {
    const { url, publishableKey } = requirePublicSupabaseConfig();
    browserClient = createBrowserClient(url, publishableKey, {
      cookieOptions: SUPABASE_COOKIE_OPTIONS,
    });
  }
  return browserClient;
}
