import { createClient } from "npm:@supabase/supabase-js@2.115.0";
import { EARLY_ACCESS_SOURCE, emailPattern } from "./contracts.ts";
import { handleRequest } from "./handler.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(req => handleRequest(req, {
  insert: async entry => { const { error } = await db.from("waitlist").insert(entry); return { error }; },
  upgrade: async email => {
    const { error } = await db.from("waitlist").update({ source: EARLY_ACCESS_SOURCE }).ilike("email", emailPattern(email));
    return { error };
  },
}));
