import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../cloudflare/public-api/src/index.js',import.meta.url),'utf8');
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const env={SUPABASE_URL:'https://backend.example.org',SUPABASE_PUBLISHABLE_KEY:'fixture-public',PLAYBACK_BACKEND_SECRET:'server-private-secret-for-gateway-tests'};
const entry='repo:match:'+'a'.repeat(28);
async function withFetch(fetcher,run){const old=globalThis.fetch;globalThis.fetch=fetcher;try{await run();}finally{globalThis.fetch=old;}}
test('Live 2 lists independent repository fixtures and protects native MPD playback with its published key pair',async()=>{
 await withFetch(async(url,init)=>{
  assert.equal(new URL(url).pathname,'/rest/v1/rpc/get_repository_metadata_for_gateway');
  const body=JSON.parse(init.body);assert.equal(body.p_secret,env.PLAYBACK_BACKEND_SECRET);
  return body.p_entry_id==null?Response.json({matches:[{source_id:entry,home_team:'Napoli',away_team:'Lazio',anchors:[{room_num:entry}]}]}):
   Response.json({match_valid:true,streams:[{id:'repository-line',label:'HD',stream_type:'dash',stream_url:'https://private-cdn.example.org/video.mpd',referer:'https://private-player.example.org/watch',key_id:'a'.repeat(32),key_data:'b'.repeat(32),is_active:true}]});
 },async()=>{
  const listing=await worker.fetch(new Request('https://api.example.org/sources/repository/matches'),env,{});
  assert.equal(listing.status,200);assert.equal((await listing.json()).matches[0].home_team,'Napoli');
  const response=await worker.fetch(new Request('https://api.example.org/sources/repository/streams',{method:'POST',body:JSON.stringify({source_id:entry})}),env,{});
  assert.equal(response.status,200);const data=await response.json();assert.equal(data.streams.length,1);
  assert(data.streams[0].stream_url.startsWith('https://api.example.org/p/'));
  assert.equal(data.streams[0].key_id,'a'.repeat(32));assert.equal(data.streams[0].key_data,'b'.repeat(32));
  assert(!JSON.stringify(data).includes('private-cdn'));assert(!JSON.stringify(data).includes('private-player'));assert(!JSON.stringify(data).includes(env.PLAYBACK_BACKEND_SECRET));
 });
});
test('removed or malformed Live 2 fixtures do not expose stale lines and Totalsportek is absent',async()=>{
 let calls=0;await withFetch(async()=>{calls++;return Response.json({match_valid:false,streams:[]});},async()=>{
  const request=value=>new Request('https://api.example.org/sources/repository/streams',{method:'POST',body:JSON.stringify({source_id:value})});
  assert.equal((await worker.fetch(request('https://evil.example.org'),env,{})).status,400);assert.equal(calls,0);
  assert.equal((await worker.fetch(request(entry),env,{})).status,404);
  assert.equal((await worker.fetch(new Request('https://api.example.org/sources/totalsportek/matches'),env,{})).status,404);
 });
});
test('team-logo relay uses one fixed public image host and returns CORS image bytes, rejecting HTML or oversized responses',async()=>{
 await withFetch(async(url,init)=>{assert.equal(url,'https://img.sofascore.com/api/v1/team/2964/image');assert.equal(init.headers.Authorization,undefined);return new Response(new Uint8Array([137,80,78,71]),{headers:{'Content-Type':'image/png'}});},async()=>{
  const response=await worker.fetch(new Request('https://api.example.org/team-logos/2964?url=https://evil.example.org/'),env,{});
  assert.equal(response.status,200);assert.equal(response.headers.get('Access-Control-Allow-Origin'),'*');assert.equal(response.headers.get('Content-Type'),'image/png');assert.equal((await response.arrayBuffer()).byteLength,4);
 });
 for(const body of [new Response('<html>blocked</html>'),new Response(new Uint8Array(300000),{headers:{'Content-Type':'image/png'}})])await withFetch(async()=>body,async()=>{
  assert.equal((await worker.fetch(new Request('https://api.example.org/team-logos/2964'),env,{})).status,502);
 });
});
