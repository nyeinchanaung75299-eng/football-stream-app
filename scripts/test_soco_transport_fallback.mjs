import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {socoCatalog} from '../cloudflare/public-api/src/soco_catalog.mjs';
const now=Date.now();
const data={code:200,data:{normal:[{scheduleId:'fixture',categoryId:1,hostName:'Arsenal',guestName:'Everton',
 matchTime:now,anchors:[{roomNum:'room-one',stream_url:'private-video',key_data:'private-key'}],stream_url:'private-video'}],
 hot:[{scheduleId:'fixture',categoryId:1,hostName:'Arsenal',guestName:'Everton',matchTime:now,anchors:[{roomNum:'room-two'}]}],
 other:[{scheduleId:'basketball',categoryId:2,hostName:'Other',guestName:'Sport'}]}};
test('Worker Soco fallback merges football rooms and exposes metadata only',()=>{
 const result=socoCatalog('matches('+JSON.stringify(data)+');',{now});
 assert.equal(result.matches.length,1);assert.equal(result.matches[0].anchors.length,2);
 assert.equal(result.matches[0].hot,true);assert(!JSON.stringify(result).includes('private-'));
});
test('invalid/error Soco catalog is not interpreted as an authoritative empty list',()=>{
 assert.throws(()=>socoCatalog('<html>Unavailable</html>'));
 assert.throws(()=>socoCatalog('{"code":503,"data":[]}'));
 assert.equal(socoCatalog('{"code":200,"data":[]}',{now}).matches.length,0);
});
test('a Supabase provider failure recovers via the fixed public Worker fetch without private credentials',async()=>{
 let source=readFileSync(new URL('../cloudflare/public-api/src/index.js',import.meta.url),'utf8');
 source=source.replace("import('./soco_catalog.mjs')",`import('${new URL('../cloudflare/public-api/src/soco_catalog.mjs',import.meta.url).href}')`);
 const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 const before=globalThis.fetch;let provider=0;
 globalThis.fetch=async(target,init)=>{
  const u=new URL(target);
  if(u.hostname==='database.example')return Response.json({error:'Source unavailable'},{status:502});
  assert.equal(u.href,'https://json.vnres.co/matches.json');provider++;
  assert.equal(new Headers(init.headers).get('Authorization'),null);assert.equal(new Headers(init.headers).get('apikey'),null);
  assert.equal(init.redirect,'manual');return new Response('matches('+JSON.stringify(data)+')');
 };
 try{
  const r=await worker.fetch(new Request('https://worker.example/sources/soco/matches'),{
   SUPABASE_URL:'https://database.example',SUPABASE_PUBLISHABLE_KEY:'public-test-key'},{});
  assert.equal(r.status,200);assert.equal((await r.json()).matches.length,1);assert.equal(provider,1);
 }finally{globalThis.fetch=before;}
});
