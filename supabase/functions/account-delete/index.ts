// POST /account-delete
//
// Deletes the developer-side directory account authenticated by the same
// private bearer the iOS app uses for directory requests. The database RPC is
// the trust boundary and owns the transaction; this function only validates
// the HTTP shape and maps the result to a deliberately small response.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { accountDeleteHandler } from "./handler.ts";

const database = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(accountDeleteHandler({
  deleteAccount: async (credential, requestID) => {
    const { data, error } = await database.rpc("delete_directory_account", {
      p_credential: credential,
      p_request_id: requestID,
    });
    if (error) throw error;
    return data === true;
  },
}));
