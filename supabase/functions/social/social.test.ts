import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { CloudKit, Rejected, verifyEvent, type CKRecord, type VerifiedEvent } from "./cloudkit.ts";
import { preferences, pushFor, retryDelay } from "./policy.ts";
const now = 1792300000000;
const record = (recordName:string,recordType:string,fields:Record<string,unknown>={},author="alessandra"): CKRecord => ({
  recordName,recordType,fields:Object.fromEntries(Object.entries(fields).map(([k,value])=>[k,{value}])),
  parent:{recordName:"table-root"},created:{userRecordName:author,timestamp:now-1000},modified:{userRecordName:author,timestamp:now-1000},
});
function fixture() {
  const records:Record<string,CKRecord> = {
    "table-root":{...record("table-root","Table"),share:{recordName:"share-1"}},
    "share-1":{...record("share-1","cloudKit.share"),owner:{userIdentity:{userRecordName:"nate"}},participants:[
      {userIdentity:{userRecordName:"alessandra"},acceptanceStatus:"ACCEPTED",permission:"READ_WRITE"},
      {userIdentity:{userRecordName:"friend"},acceptanceStatus:"ACCEPTED",permission:"READ_WRITE"},
      {userIdentity:{userRecordName:"pending"},acceptanceStatus:"INVITED",permission:"READ_WRITE"},
    ]},
    "post-1":record("post-1","PlatedDish",{authorID:"nate",dishTitle:"Dinner at the market"},"nate"),
    "note-1":record("note-1","PlatedDishNote",{authorID:"alessandra",postRecordName:"post-1",text:"That was great"}),
    "note-parent":record("note-parent","PlatedDishNote",{authorID:"friend",postRecordName:"post-1",text:"Where?"},"friend"),
    "plate-1":record("plate-1","PlatedDishPlate",{authorID:"alessandra",postRecordName:"post-1",active:1}),
  };
  const cloud = {environment:"production" as const,record:async(name:string)=>{
    if (!records[name]) throw new Rejected(409,"record_unavailable"); return records[name];
  }};
  return {records,run:(name="note-1")=>verifyEvent(cloud,"alessandra","nate","PlatedTable",name,"Alessandra",now)};
}
Deno.test("comment recipient and copy come from the actual CloudKit post",async()=>{
  const e=await fixture().run(); assertEquals(e.notices.map(n=>[n.recipient,n.key,n.category]),[["nate","note:note-1","comments"]]);
  assertEquals(e.notices[0].body,"That was great");
});
Deno.test("reply reaches parent author and post author once each",async()=>{
  const f=fixture(); f.records["note-1"].fields!.parentCommentID={value:"note-parent"};
  const e=await f.run(); assertEquals(e.notices.map(n=>[n.recipient,n.category]),[["friend","replies"],["nate","comments"]]);
});
Deno.test("same parent/post author receives only the direct reply",async()=>{
  const f=fixture(); f.records["note-parent"].fields!.authorID={value:"nate"};f.records["note-1"].fields!.parentCommentID={value:"note-parent"};
  assertEquals((await f.run()).notices.map(n=>n.category),["replies"]);
});
Deno.test("self reactions never alert the actor",async()=>{
  const f=fixture();f.records["post-1"].fields!.authorID={value:"alessandra"};assertEquals((await f.run("plate-1")).notices,[]);
});
Deno.test("comment reaction targets the comment owner, links the post",async()=>{
  const f=fixture();f.records["plate-1"].fields!.postRecordName={value:"note-parent"};
  const n=(await f.run("plate-1")).notices[0];assertEquals([n.recipient,n.post,n.kind,n.key],["friend","post-1","commentLikes","commentLike:note-parent:alessandra"]);
});
Deno.test("undo and deletion cancel rather than send a fresh alert",async()=>{
  const f=fixture();f.records["plate-1"].fields!.active={value:0};assertEquals((await f.run("plate-1")).cancelled,true);
  f.records["note-1"].fields!.deletedAt={value:now};assertEquals((await f.run()).cancelled,true);
});
Deno.test("removed and invited participants cannot originate alerts",async()=>{
  for (const status of ["INVITED","REMOVED"]) {
    const f=fixture();f.records["share-1"].participants![0].acceptanceStatus=status;
    await assertRejects(()=>f.run(),Rejected,"not_a_member");
  }
});
Deno.test("removed recipient and nonmembers are not delivered private content",async()=>{
  const f=fixture();f.records["post-1"].fields!.authorID={value:"pending"};assertEquals((await f.run()).notices,[]);
});
Deno.test("spoofed author or modified metadata is refused",async()=>{
  const f=fixture();f.records["note-1"].fields!.authorID={value:"friend"};await assertRejects(()=>f.run(),Rejected,"invalid_event");
  f.records["note-1"].fields!.authorID={value:"alessandra"};f.records["note-1"].modified!.userRecordName="friend";
  await assertRejects(()=>f.run(),Rejected,"not_your_event");
});
Deno.test("unshared root, forged owner, wrong parent and cross-post replies fail closed",async()=>{
  let f=fixture();delete f.records["table-root"].share;await assertRejects(()=>f.run(),Rejected,"share_unavailable");
  f=fixture();f.records["share-1"].owner!.userIdentity!.userRecordName="stranger";await assertRejects(()=>f.run(),Rejected,"invalid_share");
  f=fixture();f.records["note-1"].parent!.recordName="private-root";await assertRejects(()=>f.run(),Rejected,"not_your_event");
  f=fixture();f.records["note-1"].fields!.parentCommentID={value:"note-parent"};f.records["note-parent"].fields!.postRecordName={value:"other-post"};
  await assertRejects(()=>f.run(),Rejected,"invalid_reply");
});
Deno.test("old history cannot be replayed as a fresh comment by editing it",async()=>{
  const f=fixture();f.records["note-1"].created!.timestamp=now-172800000;await assertRejects(()=>f.run(),Rejected,"event_expired");
});
Deno.test("household join uses the new seat generation and honors root revocation",async()=>{
  const root={...record("household-root","PlatedHousehold"),share:{recordName:"share-1"}};
  const share={...record("share-1","cloudKit.share"),owner:{userIdentity:{userRecordName:"nate"}},participants:[{userIdentity:{userRecordName:"alessandra"},acceptanceStatus:"ACCEPTED",permission:"READ_WRITE"}]};
  const seat={...record("seat-new","PlatedHouseholdSeat",{userRecordName:"alessandra",seat:"joined",joinedAt:now}),parent:{recordName:"household-root"}};
  const cloud={environment:"production" as const,record:async(name:string)=>({"household-root":root,"share-1":share,"seat-new":seat}[name]!)};
  const run=()=>verifyEvent(cloud,"alessandra","nate","PlatedHousehold","seat-new","Alessandra",now);
  const e=await run();assertEquals(e.notices[0].key,"household:alessandra:seat-new");assertEquals(e.notices[0].recipient,"nate");
  root.fields!.removedIDs={value:["alessandra"]};await assertRejects(run,Rejected,"not_a_member");
});
const prefs=preferences({enabled:true,authorized:true,timeZone:"America/New_York"});
Deno.test("preferences block master, permission, category, person and muted thread",async()=>{
  const e=await fixture().run(),n=e.notices[0];
  for(const p of [{...prefs,enabled:false},{...prefs,authorized:false},{...prefs,categories:{comments:false}},{...prefs,blocked:["alessandra"]},{...prefs,muted:["post-1"]}]) assertEquals(pushFor(e,n,p),null);
  assertEquals(pushFor(e,{...n,category:"replies"},{...prefs,muted:["post-1"]})!==null,true);
});
Deno.test("reactions stay passive; replies use sound; household joins quiet overnight",async()=>{
  const f=fixture(),e=await f.run("plate-1");
  const night=new Date("2026-10-18T04:00:00Z");
  assertEquals(pushFor(e,e.notices[0],prefs,night)?.level,"passive");
  assertEquals(pushFor(e,e.notices[0],prefs,night)?.sound,false);
  const c=await f.run();assertEquals(pushFor(c,c.notices[0],prefs,night)?.sound,true);
  const n={...c.notices[0],kind:"householdSeat" as const,category:"seats" as const,direct:false,post:""};
  assertEquals(pushFor(c,n,prefs,night)?.level,"passive");assertEquals(pushFor(c,n,prefs,night)?.link,"plated://home");
});
Deno.test("CloudKit uses fixed origin, user proof and rotated single-use tokens",async()=>{
  const tokens:string[]=[];
  const fetcher=(async (input:RequestInfo|URL,init?:RequestInit)=>{
    const u=new URL(String(input)); tokens.push(u.searchParams.get("ckWebAuthToken")!);
    assertEquals(u.host,"api.apple-cloudkit.com");assertEquals(new Headers(init?.headers).get("Origin"),"https://dyvrksooelbkzkprqlhk.supabase.co");
    if(tokens.length===1){
      assertEquals(u.pathname,"/database/1/iCloud.com.natemeadows.plated/production/public/users/caller");
      return Response.json({users:[{userRecordName:"nate"}],ckWebAuthToken:"next-token"});
    }
    return Response.json({records:[record("table-root","Table")],ckWebAuthToken:"third-token"});
  }) as typeof fetch;
  const cloud=new CloudKit("public-api","initial-token-long-enough","production",fetcher);
  assertEquals(await cloud.identity(),"nate");await cloud.record("table-root","PlatedTable","nate","nate");
  assertEquals(tokens,["initial-token-long-enough","next-token"]);
});
Deno.test("CloudKit refuses an identity response without exactly one caller",async()=>{
  const fetcher=(async()=>Response.json({users:[],ckWebAuthToken:"next-token"})) as typeof fetch;
  const cloud=new CloudKit("public-api","initial-token-long-enough","production",fetcher);
  await assertRejects(()=>cloud.identity(),Rejected,"cloud_identity_unavailable");
});
Deno.test("CloudKit accepts the direct identity returned by CloudKit JS 2",async()=>{
  for (const caller of [{userRecordName:"nate"},{lookupInfo:{userRecordName:"nate"}}]) {
    const fetcher=(async()=>Response.json({...caller,ckWebAuthToken:"next-token"})) as typeof fetch;
    const cloud=new CloudKit("public-api","initial-token-long-enough","production",fetcher);
    assertEquals(await cloud.identity(),"nate");
  }
});
Deno.test("CloudKit rejects malformed or ambiguous caller envelopes",async()=>{
  for (const body of [
    {}, {users:[] ,userRecordName:"nate"}, {users:[[]]},
    {users:[{userRecordName:"nate"},{userRecordName:"another"}]},
    {users:[{userRecordName:"nate"}],userRecordName:"another"},
    {userRecordName:"nate",lookupInfo:{userRecordName:"another"}},
    {lookupInfo:{emailAddress:"person@example.com"}},
  ]) {
    const cloud=new CloudKit("public-api","initial-token-long-enough","production",
      (async()=>Response.json(body)) as typeof fetch);
    await assertRejects(()=>cloud.identity(),Rejected,"cloud_identity_unavailable");
  }
});
Deno.test("CloudKit accepts a privacy-protected caller's lookup record name",async()=>{
  const fetcher=(async()=>Response.json({users:[{lookupInfo:{userRecordName:"nate"}}],ckWebAuthToken:"next-token"})) as typeof fetch;
  const cloud=new CloudKit("public-api","initial-token-long-enough","production",fetcher);
  assertEquals(await cloud.identity(),"nate");
});
Deno.test("CloudKit rejects conflicting or unbound caller identities",async()=>{
  for(const caller of [
    {userRecordName:"nate",lookupInfo:{userRecordName:"another"}},
    {lookupInfo:{emailAddress:"person@example.com"}},
  ]) {
    const fetcher=(async()=>Response.json({users:[caller],ckWebAuthToken:"next-token"})) as typeof fetch;
    const cloud=new CloudKit("public-api","initial-token-long-enough","production",fetcher);
    await assertRejects(()=>cloud.identity(),Rejected,"cloud_identity_unavailable");
  }
});
Deno.test("CloudKit failures never leak token-bearing URL errors",async()=>{
  const cloud=new CloudKit("api","secret-token-long-enough","production",(()=>Promise.reject(new Error("secret-url"))) as typeof fetch);
  const e=await assertRejects(()=>cloud.identity(),Rejected,"cloud_unavailable");assertEquals(e.message.includes("secret"),false);
});
Deno.test("retry backoff is bounded",()=>assertEquals([1,2,3,40].map(retryDelay),[15,30,60,1800]));

Deno.test("fresh reinvitation grant permits only its matching seat",async()=>{
  const seatName="seat-fresh";
  const hash=[...new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(seatName)))].map(b=>b.toString(16).padStart(2,"0")).join("");
  const root={...record("household-root","PlatedHousehold",{removedIDs:["alessandra",`plated-reinvite-v1:${btoa("alessandra")}:${hash}`]}),share:{recordName:"share-1"}};
  const share={...record("share-1","cloudKit.share"),owner:{userIdentity:{userRecordName:"nate"}},participants:[{userIdentity:{userRecordName:"alessandra"},acceptanceStatus:"ACCEPTED",permission:"READ_WRITE"}]};
  const seat={...record(seatName,"PlatedHouseholdSeat",{userRecordName:"alessandra",seat:"joined",joinedAt:now}),parent:{recordName:"household-root"}};
  const cloud={environment:"production" as const,record:async(name:string)=>({"household-root":root,"share-1":share,[seatName]:seat}[name]!)};
  assertEquals((await verifyEvent(cloud,"alessandra","nate","PlatedHousehold",seatName,"Alessandra",now)).notices.length,1);
  await assertRejects(()=>verifyEvent(cloud,"alessandra","nate","PlatedHousehold","seat-old","Alessandra",now),Rejected,"not_a_member");
});

import {classifyAPNsResponse,authoritativeTokenInvalidation,notificationPayload} from "../_shared/apns.ts";
Deno.test("APNs transient and provider failures remain retryable",()=>{
  for(const [status,reason] of [[429,"TooManyRequests"],[503,"ServiceUnavailable"],[403,"ExpiredProviderToken"],[0,"NetworkError"]] as const) assertEquals(classifyAPNsResponse(status,reason).kind,"retryable");
  assertEquals(classifyAPNsResponse(400,"PayloadEmpty").kind,"permanent");
});
Deno.test("a stale APNs invalidation cannot revoke a newly registered token",()=>{
  assertEquals(authoritativeTokenInvalidation(410,"Unregistered",now-1000,new Date(now).toISOString()),false);
  assertEquals(authoritativeTokenInvalidation(410,"Unregistered",now+1000,new Date(now).toISOString()),true);
});
Deno.test("actual APNs payload is contextual, passive, refreshable, and actionable",async()=>{
  const e=await fixture().run(),p=pushFor(e,e.notices[0],prefs)!;
  const data=JSON.parse(notificationPayload(p));
  assertEquals(data.link,"plated://post?id=post-1");assertEquals(data.comment,"note-1");
  assertEquals(data.aps["content-available"],1);assertEquals(data.aps.category,"plated.category.comment");
  const r=await fixture().run("plate-1"),quiet=JSON.parse(notificationPayload(pushFor(r,r.notices[0],prefs)!));
  assertEquals(quiet.aps["interruption-level"],"passive");assertEquals(quiet.aps.sound,undefined);
});
