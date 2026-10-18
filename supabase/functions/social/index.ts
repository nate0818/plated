declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
import { createClient } from "jsr:@supabase/supabase-js@2.115.0";
import { apnsConfigured, sendOne } from "../_shared/apns.ts";
import { CloudKit, identifier, Rejected, verifyEvent, verifyRoom, type Environment, type VerifiedEvent, type VerifiedNotice } from "./cloudkit.ts";
import { digest, preferences, pushFor, retryDelay } from "./policy.ts";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {auth:{persistSession:false}});
const json = (status: number, value: unknown) => Response.json(value, {status,headers:{"Cache-Control":"no-store"}});
async function config(key: string): Promise<string> {
  const {data,error} = await db.from("social_config").select("value").eq("key",key).maybeSingle();
  if (error || !data) throw new Rejected(503,"not_configured");
  return data.value;
}
async function rpc(name: string, args: Record<string,unknown>): Promise<unknown> {
  const {data,error} = await db.rpc(name,args);
  if (error) { console.error("Social database operation failed",name,error.code); throw new Rejected(503,"queue_unavailable"); }
  return data;
}
interface Job {
  delivery_id:string; lease_id:string; event_id:string; installation_id:string;
  payload:VerifiedEvent; notice:VerifiedNotice; preferences:unknown;
  apns_token:string; environment:Environment; registered_at:string; attempts:number;
}
async function drain(): Promise<number> {
  if (!apnsConfigured()) throw new Rejected(503,"apns_not_configured");
  const jobs = await rpc("social_claim",{p_limit:20}) as Job[];
  await Promise.all(jobs.map(async j => {
    // Re-read the installation after claiming: a concurrent mute, sign-out,
    // permission change or account switch must win before contacting APNs.
    const {data:current,error} = await db.from("social_installations").select("preferences,apns_token,cloud_id,revoked_at,registered_at").eq("id",j.installation_id).maybeSingle();
    if (error) return; // Lease recovers this attempt; never assume defaults on an error.
    let push = current && !current.revoked_at && current.cloud_id === j.notice.recipient && current.apns_token === j.apns_token
      ? pushFor(j.payload,j.notice,preferences(current.preferences)) : null;
    const {data:state,error:stateError} = await db.from("social_deliveries").select("state,lease").eq("id",j.delivery_id).maybeSingle();
    if (stateError) return;
    if (state?.state !== "sending" || state.lease !== j.lease_id) return;
    let outcome = "suppressed", reason = "preferences_or_binding", apnsID:string|null=null, invalid=false;
    if (push) {
      push = {...push,collapseID:await digest(j.notice.category === "plates" ? `${j.installation_id}|${j.notice.kind}|${j.notice.post}` : j.delivery_id)};
      const result = await sendOne({apns_token:j.apns_token,apns_environment:j.environment === "development" ? "sandbox" : "production",token_registered_at:j.registered_at},push);
      outcome = result.state === "accepted" ? "accepted" : result.state === "retryable" ? "pending" : "failed";
      reason = result.reason; apnsID=result.apnsID; invalid=result.invalidateToken;
    }
    await rpc("social_finish",{p_id:j.delivery_id,p_lease:j.lease_id,p_state:outcome,p_reason:reason,p_apns_id:apnsID,
      p_delay:retryDelay(j.attempts),p_invalid:invalid,p_token:j.apns_token,p_registered:j.registered_at});
  }));
  return jobs.length;
}
Deno.serve(async req => {
  try {
    if (req.method !== "POST") return json(405,{error:"method_not_allowed"});
    if (Number(req.headers.get("content-length") ?? 0)>65536) return json(413,{error:"body_too_large"});
    const raw = await req.text();
    if (raw.length>65536) return json(413,{error:"body_too_large"});
    let body:Record<string,unknown>;
    try { body=JSON.parse(raw); } catch { return json(400,{error:"invalid_json"}); }
    if (!body || Array.isArray(body) || typeof body !== "object") return json(400,{error:"invalid_json"});
    if (body.action === "drain") {
      const token = req.headers.get("X-Plated-Worker") ?? "";
      if (token.length<32 || await digest(token) !== await config("worker_hash")) return json(401,{error:"unauthorized"});
      return json(200,{processed:await drain()});
    }
    const session = req.headers.get("X-Plated-Session") ?? "";
    if (!/^[0-9a-f-]{36}$/i.test(session)) return json(401,{error:"unauthorized"});
    const {data:user,error} = await db.from("directory_users").select("id,display_name").eq("api_token",session).maybeSingle();
    if (error) throw new Rejected(503,"directory_unavailable");
    if (!user) return json(401,{error:"unauthorized"});
    if (!await rpc("social_allow_request",{p_user:user.id})) return json(429,{error:"rate_limited"});
    if (body.action === "local_claim") {
      if (!Array.isArray(body.keys) || body.keys.length > 100 || body.keys.some(k => typeof k !== "string" || k.length > 600)) throw new Rejected(400,"invalid_keys");
      const keys = await rpc("social_local_claim",{p_user:user.id,p_installation:identifier(body.installation),p_keys:body.keys});
      return json(200,{keys});
    }
    if (body.action === "unregister") {
      const {error} = await db.from("social_installations").update({revoked_at:new Date().toISOString()}).eq("id",identifier(body.installation)).eq("user_id",user.id);
      if (error) throw new Rejected(503,"queue_unavailable");
      return json(200,{ok:true});
    }
    if (body.environment !== "development" && body.environment !== "production") throw new Rejected(400,"invalid_environment");
    const environment = body.environment as Environment;
    const apiToken = await config(`cloudkit_${environment}`);
    if (body.action === "config") return json(200,{api_token:apiToken,enabled:apnsConfigured()});
    const cloud = new CloudKit(apiToken,body.web_token as string,environment);
    const me = await cloud.identity();
    if (body.action === "register") {
      if (typeof body.apns_token !== "string" || !/^[a-f0-9]{64}$/i.test(body.apns_token)) throw new Rejected(400,"invalid_device_token");
      if (typeof body.installation !== "string" || !/^[0-9a-f-]{36}$/i.test(body.installation)) throw new Rejected(400,"invalid_installation");
      await rpc("social_register",{p_id:body.installation,p_user:user.id,p_cloud:me,p_environment:environment,
        p_token:body.apns_token.toLowerCase(),p_preferences:preferences(body.preferences)});
      return json(200,{ok:true,cloud_id:me});
    }
    if (body.action === "room") {
      const room = await verifyRoom(cloud,me,typeof body.owner === "string" ? body.owner : "",identifier(body.zone));
      await rpc("social_reconcile_room",{p_room:room.room,p_members:[...room.members]});
      return json(200,{ok:true});
    }
    if (body.action !== "event") throw new Rejected(400,"invalid_action");
    const event = await verifyEvent(cloud,me,typeof body.owner === "string" ? body.owner : "",identifier(body.zone),identifier(body.record),user.display_name);
    await rpc("social_enqueue",{p_id:await digest(event.key),p_environment:environment,p_event:event});
    // Persistence is the acknowledgement. A failed immediate APNs attempt is
    // retried by the scheduler and must not make the sender create another event.
    const worker = drain().catch(() => console.error("Social immediate delivery deferred to worker"));
    EdgeRuntime.waitUntil(worker);
    return json(202,{queued:true});
  } catch (e) {
    if (e instanceof Rejected) return json(e.status,{error:e.code});
    console.error("Social request failed",e instanceof Error ? e.name : "unknown");
    return json(500,{error:"retry_later"});
  }
});
