import assert from 'node:assert/strict';
import test from 'node:test';
import {createViewerNetworkApi} from '../supabase/functions/_shared/viewer_network_api.mjs';
const base='https://project.supabase.co/functions/v1/viewer-network-api';
const key='public-test-key';
const request=(path,init={})=>new Request(base+path,{...init,headers:{apikey:key,...init.headers}});
test('independent fallback preserves public listings and does not forward user credentials',async()=>{
 let calls=0;
 const handle=createViewerNetworkApi({apiKey:key,fetcher:async(url,init)=>{
  calls++;assert.equal(url,'https://football-api.nyeinchanaung.us.ci/channels');
  assert.equal(new Headers(init.headers).get('Authorization'),null);assert.equal(new Headers(init.headers).get('Cookie'),null);
  assert.equal(new Headers(init.headers).get('apikey'),null);
  return Response.json({ok:true,channels:[{id:'saved-channel'}]});
 }});
 const a=await handle(request('/channels',{headers:{Authorization:'Bearer user-private',Cookie:'private'}}));
 assert.equal(a.status,200);assert.equal((await a.json()).channels[0].id,'saved-channel');
 const b=await handle(request('/channels'));assert.equal(b.status,200);await b.json();assert.equal(calls,1);
});
test('a definite successful empty refresh replaces saved public data and bypasses caches',async()=>{
 let calls=0,rows=[{id:'old'}];
 const handle=createViewerNetworkApi({apiKey:key,fetcher:async()=>{calls++;return Response.json({ok:true,channels:rows});}});
 await (await handle(request('/channels'))).json();rows=[];
 const fresh=await handle(request('/channels?fresh=1'));assert.equal(fresh.headers.get('Cache-Control'),'no-store');
 assert.deepEqual((await fresh.json()).channels,[]);assert.equal(calls,2);
 assert.deepEqual((await (await handle(request('/channels'))).json()).channels,[]);assert.equal(calls,2);
});
test('gateway requires the public key and cannot access private APIs, arbitrary URLs or video bytes',async()=>{
 let calls=0;const handle=createViewerNetworkApi({apiKey:key,fetcher:async()=>{calls++;throw Error('Must not fetch');}});
 assert.equal((await handle(new Request(base+'/channels'))).status,401);
 for(const path of ['/admin/functions/system-monitor','/auth/v1/user','/rest/v1/profiles','/p/private-session','/https://attacker.example','/sources/viprow/matches'])
  assert.equal((await handle(request(path))).status,404);
 assert.equal(calls,0);
});
test('fixed logo routes accept image requests with the public query key and cache bytes only',async()=>{
 let calls=0;const handle=createViewerNetworkApi({apiKey:key,fetcher:async(url,init)=>{
  calls++;assert.equal(url,'https://football-api.nyeinchanaung.us.ci/team-logos/123');assert.equal(init.redirect,'manual');
  return new Response(new Uint8Array([137,80,78,71,13,10,26,10]),{headers:{'Content-Type':'image/png'}});
 }});
 for(let i=0;i<2;i++){
  const r=await handle(new Request(base+'/team-logos/123?apikey='+key+'&url=https://attacker.example'));
  assert.equal(r.status,200);assert.equal((await r.arrayBuffer()).byteLength,8);assert.equal(r.headers.get('Access-Control-Allow-Origin'),'*');
 }
 assert.equal(calls,1);
});
test('stream resolution remains read-only, bounded, and uncached without exposing privileged credentials',async()=>{
 let calls=0;
 const handle=createViewerNetworkApi({apiKey:key,fetcher:async(url,init)=>{
  calls++;assert.equal(url,'https://football-api.nyeinchanaung.us.ci/sources/repository/streams');
  assert.equal(init.method,'POST');assert.equal(JSON.parse(init.body).source_id,'repo:match:fixture');
  return Response.json({ok:true,streams:[]});
 }});
 for(let i=0;i<2;i++){
  const r=await handle(request('/sources/repository/streams',{method:'POST',body:JSON.stringify({source_id:'repo:match:fixture'})}));
  assert.equal(r.headers.get('Cache-Control'),'no-store');assert.deepEqual((await r.json()).streams,[]);
 }assert.equal(calls,2);
});
test('redirects, failures, non-JSON metadata and excessive responses are never cached or treated as empty success',async()=>{
 let mode=0;const handle=createViewerNetworkApi({apiKey:key,fetcher:async()=>{
  if(mode++===0)return new Response(null,{status:302,headers:{Location:'http://127.0.0.1/private'}});
  if(mode===2)return new Response('Forbidden',{status:403});
  if(mode===3)return new Response('<html>Unavailable</html>');
  return new Response(new Uint8Array(2097153),{headers:{'Content-Type':'application/json'}});
 }});
 for(const status of [502,403,502,502]){
  const r=await handle(request('/channels'));assert.equal(r.status,status);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal(r.headers.get('Location'),null);
 }
});
