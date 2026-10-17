/* eslint-disable @typescript-eslint/no-require-imports -- Node test harness uses CommonJS. */
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');const ts=require('typescript');
function load(file,requires={},globals={}) {
 const loaded={exports:{}};
 const source=ts.transpileModule(fs.readFileSync(path.join(__dirname,'..',file),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 vm.runInNewContext(source,{exports:loaded.exports,module:loaded,require:(name)=>name in requires?requires[name]:require(name),Request,Response,console,...globals});return loaded.exports;
}
const normalizer=load('app/lib/admin/testflight.ts');
test('browser command contains only a stored request ID, never a destination address or group',()=>{
 const value=normalizer.normalizeTestFlightRequest({op:'invite',id:'68043320-6433-4064-8676-243382064000',email:'ignored@example.invalid',groupId:'ignored'});
 assert.equal(JSON.stringify(value),JSON.stringify({op:'invite',id:'68043320-6433-4064-8676-243382064000'}));
 for(const value of [{op:'invite',id:'invalid'},{op:'list',offset:-1,filter:'active'},{op:'list',offset:0,filter:'launch'}])assert.throws(()=>normalizer.normalizeTestFlightRequest(value));
});
test('BFF refuses invalid origin and ID before calling the provider function',async()=>{
 let called=false;
 class RequestError extends Error {status=403;}
 const {POST}=load('app/api/admin/testflight/route.ts',{
  '../../../lib/admin/bff':{callAdminEdge:async()=>{called=true;}},
  '../../../lib/admin/testflight':normalizer,
  '../../../lib/admin/request':{assertAdminRequestOrigin:()=>{throw new RequestError('Origin rejected.');},AdminRequestError:RequestError,noStoreHeaders:()=>({'Cache-Control':'private, no-store'}),readJsonObject:async()=>({})}
 });
 const r=await POST(new Request('https://plated.food/api/admin/testflight',{method:'POST'}));assert.equal(r.status,403);assert.equal(called,false);assert.match(r.headers.get('cache-control'),/no-store/);
});
test('MFA step-up errors survive the BFF response without exposing provider data',async()=>{
 const {POST}=load('app/api/admin/testflight/route.ts',{
  '../../../lib/admin/bff':{callAdminEdge:async()=>({ok:false,status:403,error:'Verify again.',code:'mfa_step_up_required',requestId:'qa'})},
  '../../../lib/admin/testflight':normalizer,
  '../../../lib/admin/request':{assertAdminRequestOrigin:()=>{},AdminRequestError:class extends Error{},noStoreHeaders:()=>({'Cache-Control':'private, no-store'}),readJsonObject:async()=>({op:'connection'})}
 });
 const r=await POST(new Request('https://plated.food/api/admin/testflight',{method:'POST'}));assert.equal(r.status,403);assert.equal((await r.json()).code,'mfa_step_up_required');
});

test('TestFlight BFF requires fresh MFA and signs only the fixed Supabase endpoint',async()=>{
 let authOptions;let sent;
 class SessionError extends Error {}
 const {callAdminEdge}=load('app/lib/admin/bff.ts',{
  'server-only':{},
  './auth':{AdminSessionError:SessionError,requireAdminSession:async(options)=>{authOptions=options;return {accessToken:'synthetic-user-jwt'};}},
  '../supabase/config':{getPublicSupabaseConfig:()=>({url:'https://example.supabase.co',publishableKey:'public-test-key'})}
 },{process:{env:{ADMIN_API_SECRET:'a'.repeat(32),ADMIN_COMMAND_FUNCTION_URL:'https://untrusted.invalid'}},Buffer,URL,TextDecoder,Uint8Array,AbortController,setTimeout,clearTimeout,
 fetch:async(url,init)=>{sent={url:String(url),...init};return Response.json({error:'Verify again.',code:'mfa_step_up_required'},{status:403});}});
 const result=await callAdminEdge('testflight',{op:'connection'});
 assert.equal(authOptions.recentTotp,true);
 assert.equal(sent.url,'https://example.supabase.co/functions/v1/admin-testflight');
 const expected=require('node:crypto').createHmac('sha256','a'.repeat(32)).update(`v1:${sent.headers['x-plated-ts']}:POST:/admin-testflight:${sent.body}`).digest('hex');
 assert.equal(sent.headers['x-plated-sig'],expected);
 assert.equal(result.code,'mfa_step_up_required');assert.equal(result.status,403);
});
