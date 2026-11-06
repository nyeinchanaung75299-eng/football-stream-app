import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createTelegramHandler} from '../supabase/functions/_shared/nca_telegram_bot.mjs';
import {createViewerFeatures} from '../supabase/functions/_shared/viewer_bot_features.mjs';
import {withTelegramUpdateDedup} from '../supabase/functions/_shared/telegram_update_dedup.mjs';

const id='11111111-1111-4111-8111-111111111111';
const lineId='22222222-2222-4222-8222-222222222222';
const now=new Date('2026-11-06T12:00:00Z');
const fixture={id,home_team:'Today home',away_team:'Today away',kickoff_at:'2026-11-06T13:00:00Z',league:'Test',is_live:false};
const env={SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'fixture',
 TG_VIEWER_BOT_TOKEN:'fixture',TG_VIEWER_WEBHOOK_SECRET:'fixture-secret'};
function request(text, update_id) {
  return new Request('https://edge.example',{method:'POST',headers:{
    'Content-Type':'application/json','X-Telegram-Bot-Api-Secret-Token':'fixture-secret'},
    body:JSON.stringify({update_id,message:{text,from:{id:42},chat:{id:42,type:'private'}}})});
}

test('Today is filtered on the server before LIMIT, even with 100 earlier published matches',async()=>{
 const old=Array.from({length:100},()=>({...fixture,kickoff_at:'2026-10-01T12:00:00Z'}));
 let sent;
 const fetcher=async(input,init={})=>{
  const url=new URL(input);
  if(url.host==='api.telegram.org'){sent=JSON.parse(init.body);return Response.json({ok:true});}
  const filter=url.searchParams.get('and')||'';
  assert.match(filter,/kickoff_at.gte.2026-11-05T17:30:00.000Z/);
  assert.match(filter,/kickoff_at.lt.2026-11-06T17:30:00.000Z/);
  assert.equal(url.searchParams.get('is_finished'),'eq.false');
  const rows=filter?[fixture]:[...old,fixture];
  return Response.json(rows.slice(0,Number(url.searchParams.get('limit'))));
 };
 const bot=createTelegramHandler({mode:'viewer',env,fetcher,clock:()=>now});
 assert.equal((await bot(request('/today'))).status,200);
 assert.match(sent.text,/Today home/);
 assert.match(sent.reply_markup.inline_keyboard[0][0].url,/\?match=/);
});

test('Live is filtered in the database, not hidden behind earlier non-live matches',async()=>{
 const fetcher=async(input)=>{
  const url=new URL(input);
  if(url.host==='api.telegram.org')return Response.json({ok:true});
  assert.equal(url.searchParams.get('is_live'),'eq.true');
  assert.equal(url.searchParams.get('limit'),'10');
  return Response.json([]);
 };
 await createTelegramHandler({mode:'viewer',env,fetcher,clock:()=>now})(request('/live'));
});

function dedupFixture(handler) {
 const rows=new Map();
 const fetcher=async(input,init)=>{
  const url=new URL(input);const body=init.body?JSON.parse(init.body):null;
  if(url.pathname.endsWith('claim_nca_bot_update')){
    const row=rows.get(body.p_update_id);
    if(row)return Response.json(row.completed?'completed':'busy');
    rows.set(body.p_update_id,{completed:false});return Response.json('claimed');
  }
  const key=Number(url.searchParams.get('update_id').slice(3));
  if(init.method==='PATCH')rows.get(key).completed=true;
  if(init.method==='DELETE')rows.delete(key);
  return new Response(null,{status:204});
 };
 return withTelegramUpdateDedup(handler,{mode:'viewer',env,fetcher});
}
test('duplicate Telegram delivery is handled once across independent requests',async()=>{
 let calls=0;
 const bot=dedupFixture(async()=>{calls++;return Response.json({ok:true});});
 assert.equal((await bot(request('/today',77))).status,200);
 assert.equal((await bot(request('/today',77))).status,200);
 assert.equal(calls,1);
});
test('a failed delivery releases its lease so Telegram can retry',async()=>{
 let calls=0;
 const bot=dedupFixture(async()=>{if(++calls===1)throw new Error('network');return Response.json({ok:true});});
 assert.equal((await bot(request('/today',78))).status,503);
 assert.equal((await bot(request('/today',78))).status,200);
 assert.equal(calls,2);
});
test('a concurrent in-flight duplicate is retried instead of prematurely acknowledged',async()=>{
 let release;
 const bot=dedupFixture(()=>new Promise(resolve=>{release=()=>resolve(Response.json({ok:true}));}));
 const first=bot(request('/today',79));
 while(!release)await new Promise(r=>setTimeout(r,0));
 assert.equal((await bot(request('/today',79))).status,503);
 release();assert.equal((await first).status,200);
});

function featuresFixture({missing=false,due=[]}={}) {
 const calls=[];
 const key='a'.repeat(64);
 const fetcher=async(input,init={})=>{
  const url=new URL(input),body=init.body?JSON.parse(init.body):null;
  calls.push({url,method:init.method||'GET',body});
  if(url.host==='api.telegram.org')return Response.json({ok:true});
  const table=url.pathname.split('/').pop();
  if(table==='nca_viewer_scheduler')return Response.json([{secret_sha256:createHash('sha256').update(key).digest('hex')}]);
  if(init.method==='PATCH')return Response.json([{chat_id:42,match_id:id}]);
  if(init.method==='DELETE'||init.method==='POST')return Response.json([]);
  if(table==='matches')return Response.json(missing?[]:[fixture]);
  if(table==='nca_viewer_reminders')return Response.json(due);
  if(table==='nca_viewer_reports')return Response.json([]);
  if(table==='channel_lines')return Response.json([{id:lineId,channel_id:id,label:'HD'}]);
  if(table==='channels')return Response.json([{id,name:'Fixture TV'}]);
  throw new Error('Unexpected table '+table);
 };
 return {calls,key,features:createViewerFeatures({env,fetcher,clock:()=>now,site:'https://viewer.example/'})};
}
test('reminders require an explicit action and persist only identifiers and time',async()=>{
 const {calls,features}=featuresFixture();
 assert.equal(await features.handle('/start',42),null);assert.equal(calls.length,0);
 const reply=await features.handle('remind:'+id,42);
 const saved=calls.find(c=>c.method==='POST');
 assert.deepEqual(Object.keys(saved.body).sort(),['chat_id','due_at','match_id']);
 assert.equal(saved.body.due_at,'2026-11-06T12:50:00.000Z');
 assert.match(reply.text,/Reminder set/);
 assert.doesNotMatch(JSON.stringify(reply),/fixture-secret|service_role|stream_url/);
});
test('unpublished/missing matches cannot get reminders; cancellation is scoped to the requesting chat',async()=>{
 const {calls,features}=featuresFixture({missing:true});
 assert.match((await features.handle('remind:'+id,42)).text,/no longer available/);
 assert.equal(calls.some(c=>c.method==='POST'),false);
 await features.handle('/unsubscribe',42);
 assert.equal(calls.at(-1).url.searchParams.get('chat_id'),'eq.42');
 assert.equal(calls.at(-1).method,'DELETE');
});
test('broken line reports validate the active line/channel and do not store playback credentials',async()=>{
 const {calls,features}=featuresFixture();
 const reply=await features.handle('broken:'+lineId,42);
 assert.match(reply.text,/Report saved/);
 const body=calls.find(c=>c.method==='POST').body;
 assert.deepEqual(body,{chat_id:42,channel_id:id,line_id:lineId});
});
test('scheduler rejects unauthorized requests before sending any reminder',async()=>{
 const {features,calls}=featuresFixture();
 assert.equal((await features.pulse(new Request('https://edge.example'))).status,401);
 assert.equal(calls.length,0);
});
test('scheduler claims a due reminder, sends a match link, then records delivery',async()=>{
 const {features,calls,key}=featuresFixture({due:[{chat_id:42,match_id:id}]});
 const response=await features.pulse(new Request('https://edge.example',{headers:{'x-nca-viewer-pulse-key':key}}));
 assert.deepEqual(await response.json(),{ok:true,delivered:1});
 const sent=calls.find(c=>c.url.host==='api.telegram.org');
 assert.equal(sent.body.reply_markup.inline_keyboard[0][0].url,'https://viewer.example/?match='+id);
 assert.ok(calls.some(c=>c.method==='PATCH'&&c.body.delivered_at));
});
