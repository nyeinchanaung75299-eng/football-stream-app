import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {GET as proxy} from '../vercel/network-backup/api/proxy.js';
import {GET as logo} from '../vercel/network-backup/api/channel-logo.js';
const source = readFileSync(new URL('../cloudflare/public-api/src/index.js', import.meta.url), 'utf8');
const {default: worker} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const env = {SUPABASE_URL:'https://database.example',SUPABASE_PUBLISHABLE_KEY:'public-test-key'};
const id = '11111111-1111-4111-8111-111111111111';
const origin = 'https://nca-network-backup-test.vercel.app';
function cache() {
 const rows = new Map();
 return {async match(req){return rows.get(req.url)?.clone();},async put(req,res){rows.set(req.url,res.clone());}};
}
async function using(fetcher, action, cached = cache()) {
 const oldFetch = globalThis.fetch, oldCaches = globalThis.caches;
 globalThis.fetch=fetcher;globalThis.caches={default:cached};
 try{return await action();}finally{globalThis.fetch=oldFetch;globalThis.caches=oldCaches;}
}
test('fresh published EPG serves current saved stations without calling any Vercel guide function', async()=>{
 let vercel=0, database=0, snapshots=0, rows;
 const station={id,name:'NBC',epg_source:'US2',epg_id:'NBC.us2'};
 rows=[station];
 await using(async target=>{
  const url=new URL(target);
  if(url.pathname==='/rest/v1/channels'){database++;return Response.json(rows);}
  if(url.hostname==='raw.githubusercontent.com'){snapshots++;return Response.json({ok:true,updated_at:new Date().toISOString(),channels:[
   {...station,matchedEPG:true,programmes:[{start:Date.now(),end:Date.now()+3600000,title:'Live football',key_data:'private'}]},
   {...station,id:'deleted-station'},
  ]});}
  if(url.hostname.endsWith('.vercel.app'))vercel++;
  throw Error('A paused service must not be required');
 },async()=>{
  const response=await worker.fetch(new Request('https://worker.example/tv-schedule'),env,{});
  assert.equal(response.status,200);
  const body=await response.json();assert.equal(body.channels.length,1);
  assert.equal(body.channels[0].matchedEPG,true);assert(!JSON.stringify(body).includes('private'));
  const cached=await worker.fetch(new Request('https://worker.example/tv-schedule'),env,{});
  assert.equal(cached.headers.get('X-NCA-Cached-Guide'),'1');assert.equal((await cached.json()).channels.length,1);
  assert.equal(database,1);assert.equal(snapshots,1);
  rows=[];
  const fresh=await worker.fetch(new Request('https://worker.example/tv-schedule?fresh=1'),env,{});
  assert.equal(fresh.headers.get('Cache-Control'),'no-store');
  assert.equal((await fresh.json()).channels.length,0);assert.equal(database,2);
  assert.equal(vercel,0);
 });
});
test('public catalog caching reuses one backend read and explicit mutation refresh sees deletions immediately',async()=>{
 let calls=0,rows=[{id,name:'Saved station'}];
 await using(async target=>{assert.equal(new URL(target).pathname,'/rest/v1/channels');calls++;return Response.json(rows);},async()=>{
  const get=path=>worker.fetch(new Request('https://worker.example'+path),env,{});
  assert.equal((await (await get('/channels')).json()).channels.length,1);
  rows=[];
  assert.equal((await (await get('/channels')).json()).channels.length,1);assert.equal(calls,1);
  const fresh=await get('/channels?fresh=1');assert.equal(fresh.headers.get('Cache-Control'),'no-store');
  assert.equal((await fresh.json()).channels.length,0);assert.equal(calls,2);
 });
});
test('a thumbnail looks up one active channel once, caches image bytes and never forwards caller credentials',async()=>{
 let database=0,images=0;
 await using(async(target,init)=>{
  const url=new URL(target);assert.equal(new Headers(init?.headers).get('Authorization'),null);
  if(url.hostname==='database.example'){
   database++;assert.equal(url.searchParams.get('select'),'image_url');assert.equal(url.searchParams.get('id'),'eq.'+id);
   return Response.json([{image_url:'https://images.example/known.png'}]);
  }
  assert.equal(url.href,'https://images.example/known.png');images++;
  assert.equal(new Headers(init?.headers).get('apikey'),null);
  assert.equal(new Headers(init?.headers).get('User-Agent'),'Mozilla/5.0');
  return new Response(Uint8Array.from([137,80,78,71,13,10,26,10]),{headers:{'Content-Type':'image/png'}});
 },async()=>{
  const get=()=>worker.fetch(new Request('https://worker.example/channel-logos/'+id,
   {headers:{Authorization:'Bearer private-session'}}),env,{});
  for(let i=0;i<2;i++){const r=await get();assert.equal(r.status,200);assert.equal((await r.arrayBuffer()).byteLength,8);}
  assert.equal(database,1);assert.equal(images,1);
 });
});
test('thumbnail inputs cannot choose a private upstream or turn the route into an arbitrary URL proxy',async()=>{
 let calls=0;
 await using(async target=>{calls++;assert.equal(new URL(target).hostname,'database.example');return Response.json([{image_url:'http://127.0.0.1/private'}]);},async()=>{
  const r=await worker.fetch(new Request('https://worker.example/channel-logos/'+id+'?url=https://attacker.example'),env,{});
  assert.equal(r.status,404);assert.equal(calls,1);
 });
});
test('shared Cloudflare host forwards Auth/REST credentials unchanged and never caches private responses',async()=>{
 await using(async target=>{
  assert(target instanceof Request);assert.equal(target.headers.get('Authorization'),'Bearer user-session');
  assert.equal(target.headers.get('apikey'),'caller-public-key');
  return Response.json({error:'not authorized'}, {status:403});
 },async()=>{
  const r=await worker.fetch(new Request('https://worker.example/rest/v1/profiles',
   {headers:{Authorization:'Bearer user-session',apikey:'caller-public-key'}}),env,{});
  assert.equal(r.status,403);assert.equal(r.headers.get('Cache-Control'),'no-store');
 });
});
test('public metadata keeps canonical static/logo/playback URLs and has CDN TTLs; Auth and signed streams do not',async()=>{
 await using(async()=>Response.json({channels:[{id,image_url:'https://raw.githubusercontent.com/owner/repo/main/logo.png'}],
  streams:[{url:'https://football-api.nyeinchanaung.us.ci/p/private-session'}]}),async()=>{
  const channels=await proxy(new Request(origin+'/channels'));
  assert.equal(channels.headers.get('Vercel-CDN-Cache-Control'),'public, s-maxage=30');
  assert.equal((await channels.json()).channels[0].image_url,'https://raw.githubusercontent.com/owner/repo/main/logo.png');
  for(const path of ['/channels?fresh=1','/matches/'+id+'/streams','/auth/v1/user']){
   const r=await proxy(new Request(origin+path));assert.equal(r.headers.get('Cache-Control'),'no-store');
   assert.equal(r.headers.get('Vercel-CDN-Cache-Control'),null);await r.body.cancel();
  }
 });
});
test('JSON relay returns the first chunk before the complete body and preserves the metadata deadline',async()=>{
 let body;
 await using(async()=>new Response(new ReadableStream({start(c){body=c;c.enqueue(new TextEncoder().encode('{"channels":['));}}),
 {headers:{'Content-Type':'application/json'}}),async()=>{
  const response=await proxy(new Request(origin+'/channels'));
  const reader=response.body.getReader();assert.equal(new TextDecoder().decode((await reader.read()).value),'{"channels":[');
  body.enqueue(new TextEncoder().encode(']}'));body.close();
  assert.equal(new TextDecoder().decode((await reader.read()).value),']}');assert.equal((await reader.read()).done,true);
 });
});
test('legacy Vercel thumbnails make one cached Worker request, with no catalog download or JSON parsing',async()=>{
 let calls=0;
 await using(async(target,init)=>{calls++;assert.equal(new URL(target).pathname,'/channel-logos/'+id);
  assert.equal(new Headers(init.headers).get('Authorization'),null);
  return new Response(new Uint8Array([137,80,78,71,13,10,26,10]),{headers:{'Content-Type':'image/png'}});
 },async()=>{
  const r=await logo(new Request(origin+'/api/channel-logo?id='+id));assert.equal(r.status,200);
  assert.equal(r.headers.get('Vercel-CDN-Cache-Control'),'public, s-maxage=86400');await r.body.cancel();assert.equal(calls,1);
 });
});
