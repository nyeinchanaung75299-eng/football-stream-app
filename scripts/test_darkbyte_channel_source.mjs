import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {parseDarkbyteFile,fetchDarkbyteCatalog,publicSourceUrl} from '../supabase/functions/_shared/darkbyte_catalog.mjs';

const key='a'.repeat(32),value='b'.repeat(32),sha='1'.repeat(40);
const base={name:'TNT Sports',visible:true,streams:[{name:'TNT Sports 1',link:'https://cdn.example.org/one.m3u8'}]};
test('published provider formats preserve separate TV channels and stable IDs across URL/header/key rotations',async()=>{
 const first=await parseDarkbyteFile('provider_1/channels.json',[base]);
 const next=await parseDarkbyteFile('provider_1/channels.json',[{...base,streams:[{...base.streams[0],link:'https://new.example.org/rotated.m3u8|Referer=https%3A%2F%2Fplayer.example.org%2Fwatch&Origin=https%3A%2F%2Fplayer.example.org'}]}]);
 assert.equal(first[0].id,next[0].id);assert.equal(first[0].streams[0].id,next[0].streams[0].id);
 assert.equal(next[0].streams[0].referer,'https://player.example.org/watch');
 assert.equal(next[0].streams[0].origin,'https://player.example.org');
 const modern=await parseDarkbyteFile('provider_2/channels.json',[{id:27,title:'TNT Sports',cat:'Sports',publish:1,
  formats:['One','Two'],resolved_streams:[{title:'TNT Sports 1',link:'https://cdn.example.org/one.mpd',type:'1',api:key+':'+value},
   {title:'TNT Sports 2',link:'https://cdn.example.org/two.m3u8',type:'0',api:''}]}]);
 assert.equal(modern.length,2);assert.equal(modern[0].streams[0].key_id,key);assert.equal(modern[0].streams[0].key_data,value);
 assert.equal(modern[0].streams[0].stream_type,'dash');
});
test('unresolved/website playlists stay visible but never become fake native video lines',async()=>{
 const rows=await parseDarkbyteFile('provider_6/sports_channels.json',[{title:'Unresolved',formatsNew:[{title:'No URL'}]},
  {title:'Published playlist',playlist_url:'https://raw.githubusercontent.com/owner/repo/main/list.m3u'},
  {title:'Incomplete key',formats:[{title:'DASH',link:'https://cdn.example.org/private.mpd',type:'1',api:'license-service'}]},
  {title:'Hidden',publish:'0',formats:[{title:'Hidden',link:'https://cdn.example.org/hidden.m3u8'}]},
 ]);
 assert.equal(rows.length,3);assert(rows.every(row=>row.streams.length===0));
 assert.equal(rows.find(row=>row.kind==='playlist').name,'Published playlist');
 assert.equal(rows.find(row=>row.name==='DASH').unsupported_count,1);
});
test('private addresses, credentials and code files are not accepted as source media',async()=>{
 for(const url of ['http://127.0.0.1/a','http://169.254.169.254/a','https://u:p@cdn.example.org/a','https://internal.local/a'])assert.equal(publicSourceUrl(url),null);
 const rows=await parseDarkbyteFile('provider_3/sports_channels.json',[{title:'Group',formats:[
  {title:'Private',link:'http://10.1.1.1/live.m3u8'},{title:'Website',link:'https://example.org/player.html'},
 ]}]);assert(rows.every(row=>row.streams.length===0));
 await assert.rejects(()=>parseDarkbyteFile('.github/workflows/build.json',[]),/Invalid published/);
});
test('catalog pins one public revision, ignores private builder paths, and preserves partial failure status',async()=>{
 const calls=[];
 const fetcher=async target=>{
  calls.push(target);
  if(target.endsWith('/branches/main'))return Response.json({commit:{sha}});
  if(target.includes('/git/trees/'))return Response.json({tree:[
   {type:'blob',path:'provider_1/channels.json'}, {type:'blob',path:'provider_2/channels.json'},
   {type:'blob',path:'.github/workflows/provider_1.yml'},{type:'blob',path:'Provider/logo.png'},
  ]});
  assert(target.startsWith('https://raw.githubusercontent.com/darkbyteprojects/iptv_png/'+sha+'/'));
  if(target.includes('provider_2'))return new Response('',{status:503});
  return Response.json([base]);
 };
 const result=await fetchDarkbyteCatalog({fetcher});assert.equal(result.entries.length,1);
 assert.equal(result.complete,false);assert.equal(result.failed_files,1);assert.equal(calls.length,4);
 calls.length=0;
 const same=await fetchDarkbyteCatalog({fetcher,revision:sha});assert.equal(same.unchanged,true);assert.equal(calls.length,1);
});

let handler;
const oldDeno=globalThis.Deno;globalThis.Deno={serve(fn){handler=fn;}};
let source=readFileSync(new URL('../supabase/functions/channel-source-sync/index.ts',import.meta.url),'utf8')
 .replace(/^import .*jsr:.*;\n/gm,'')
 .replace('"../_shared/darkbyte_catalog.mjs"',JSON.stringify(new URL('../supabase/functions/_shared/darkbyte_catalog.mjs',import.meta.url).href))
 .replace('"../_shared/livetv_sports.mjs"',JSON.stringify(new URL('../supabase/functions/_shared/livetv_sports.mjs',import.meta.url).href));
const {channelSourceRequest}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
globalThis.Deno=oldDeno;
function client(role='admin'){
 const calls=[];
 return {calls,auth:{async getUser(token){return token==='valid'?{data:{user:{id:'user-1',user_metadata:{role:'admin'}}}}:{data:{user:null},error:{}};}},
  from(table){
   const q={select(fields){calls.push({table,fields});return q;},eq(){return q;},
    async maybeSingle(){return {data:table==='profiles'?{role}:null};},
    async single(){return {data:{streams:[{id:'source-hd',stream_type:'hls',stream_url:'https://cdn.example.org/live.m3u8'}]}};}};return q;
  },async rpc(name,args){calls.push({name,args});return {data:{channel_id:'00000000-0000-4000-8000-000000000001'}};}};
}
const request=(body,token)=>new Request('https://backend.example/channel-source-sync',{method:'POST',
 headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
test('anonymous, invalid and Viewer sessions cannot read or import private source records',async()=>{
 for(const [token,role] of [[null,'admin'],['invalid','admin'],['valid','viewer']]){
  const fake=client(role);const result=await channelSourceRequest(request({action:'import',entry_id:'db:p1:channel:'+'0'.repeat(28)},token),fake);
  assert.equal(result.status,403);assert(!fake.calls.some(call=>call.name));
 }
});
test('verified Admin import uses the atomic idempotent link RPC and accepts an explicit existing channel',async()=>{
 const fake=client();const target='00000000-0000-4000-8000-000000000001';
 const result=await channelSourceRequest(request({action:'import',entry_id:'db:p1:channel:'+'0'.repeat(28),channel_id:target},'valid'),fake);
 assert.equal(result.status,200);assert.equal((await result.json()).channel_id,target);
 const call=fake.calls.find(call=>call.name);assert.equal(call.name,'link_channel_source_entry');assert.equal(call.args.p_target_channel_id,target);
 assert.equal(call.args.p_refresh_only,false);
});

test('verified Admin adds one selected source line to a match using server-owned configuration',async()=>{
 const fake=client();const match='00000000-0000-4000-8000-000000000001';
 const response=await channelSourceRequest(request({action:'add_match',entry_id:'db:p1:channel:'+'0'.repeat(28),
  source_line_id:'source-hd',match_id:match,stream_url:'https://untrusted.example/replace'},'valid'),fake);
 assert.equal(response.status,200);
 const call=fake.calls.find(c=>c.name==='add_connected_source_line_to_match');
 assert.equal(call.args.p_match_id,match);assert.equal(call.args.p_source_line_id,'source-hd');
 assert(!JSON.stringify(call).includes('untrusted.example'));
 const missing=await channelSourceRequest(request({action:'add_match',entry_id:'db:p1:channel:'+'0'.repeat(28),source_line_id:'missing',match_id:match},'valid'),fake);
 assert.equal(missing.status,404);
});
