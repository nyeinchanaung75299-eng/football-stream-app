import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createTelegramHandler, ADMIN_INLINE_MENU } from "./nca_private_admin_bot.mjs";

const botEnv = (allowlist = "111") => ({
  TG_ADMIN_BOT_TOKEN: "test-admin-token",
  TG_ADMIN_WEBHOOK_SECRET: "test-secret",
  TG_ADMIN_USER_IDS: allowlist,
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
});
const request = (cmd, callback = false) =>
  new Request("https://example.supabase.co/functions/v1/telegram-admin", {
    method: "POST",
    headers: {"X-Telegram-Bot-Api-Secret-Token":"test-secret","Content-Type":"application/json"},
    body: JSON.stringify(callback
      ? {callback_query:{id:"callback-1",from:{id:111},data:cmd,message:{message_id:50,chat:{id:111,type:"private"}}}}
      : {message:{message_id:50,text:cmd,from:{id:111},chat:{id:111,type:"private"}}}),
  });
const pulseRequest = (key) => new Request("https://example.supabase.co/functions/v1/telegram-admin",{
  method:"POST",headers:{"x-nca-pulse-key":key,"Content-Type":"application/json"},body:"{}",
});
function createMock({prefs=[],lines=[],channels=[],matches=[],messageFail=false,key=""}={}){
  const calls=[];
  const fetcher=async(url,options={})=>{
    const href=String(url);
    const body=options.body?JSON.parse(options.body):{};
    calls.push({url:href,method:options.method||"GET",body});
    if(href.includes("api.telegram.org/bot")){
      const method=href.split("/").pop();
      if(method==="sendMessage" && messageFail)
        return Response.json({ok:false,description:"rate limited"},{status:429});
      return Response.json({ok:true,result:method==="getMe"
        ? {is_bot:true,username:"NCAPrivate_bot"}
        : method==="getWebhookInfo"
          ? {url:"https://example.supabase.co/functions/v1/telegram-admin",pending_update_count:0}
          : {message_id:70}});
    }
    if(href.includes("nca_bot_scheduler?"))
      return Response.json([{secret_sha256:createHash("sha256").update(key).digest("hex")}]);
    if(href.includes("nca_bot_preferences?"))
      return Response.json(prefs);
    if(href.includes("channel_lines?") && (options.method||"GET")==="GET")
      return Response.json(lines);
    if(href.includes("channels?") && (options.method||"GET")==="GET")
      return Response.json(channels);
    if(href.includes("matches?"))
      return Response.json(matches);
    if(href.includes("nca_bot_alert_state?") && (options.method||"GET")==="GET")
      return Response.json([]);
    if((options.method||"GET")==="POST" && href.includes("nca_bot_alert_state?"))
      return Response.json([{event_key:body.event_key}],{status:201});
    if(["PATCH","DELETE","POST"].includes(options.method))
      return new Response("",{status:204});
    throw new Error("Unexpected request in test: "+href);
  };
  return {calls,fetcher};
}
const telegramCalls=(calls,method)=>calls.filter(c=>c.url.endsWith("/"+method));

test("/start clears legacy 14-button keyboard and opens inline menu",async()=>{
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/start"))).status,200);
  const replies=telegramCalls(mock.calls,"sendMessage");
  assert.equal(replies.length,2);
  assert.deepEqual(replies[0].body.reply_markup,{remove_keyboard:true});
  assert.deepEqual(replies[1].body.reply_markup,ADMIN_INLINE_MENU);
  assert.ok(!JSON.stringify(replies).includes("is_persistent"));
});

test("inline callback edits the existing menu instead of piling up new bot messages",async()=>{
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/tools",true))).status,200);
  assert.equal(telegramCalls(mock.calls,"editMessageText").length,1);
  assert.equal(telegramCalls(mock.calls,"sendMessage").length,0);
  assert.equal(telegramCalls(mock.calls,"answerCallbackQuery").length,1);
});

test("/testbot checks Telegram getMe and webhook status before replying",async()=>{
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/testbot"))).status,200);
  assert.equal(telegramCalls(mock.calls,"getMe").length,1);
  assert.equal(telegramCalls(mock.calls,"getWebhookInfo").length,1);
  assert.match(telegramCalls(mock.calls,"sendMessage")[0].body.text,/Token verified: Yes/);
});

test("private admin refuses IDs that were not explicitly allowlisted",async()=>{
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv("222"),fetcher:mock.fetcher});
  assert.equal((await handler(request("/start"))).status,200);
  assert.equal(telegramCalls(mock.calls,"sendMessage").length,0);
});

test("cron keeps monitoring even if all stored subscribers are unauthorized",async()=>{
  const key="a".repeat(64);
  const now=new Date().toISOString();
  const mock=createMock({
    key,prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false}],
    lines:[{id:"line-a",channel_id:"channel-a",stream_url:"https://stream.test/master.m3u8",health_status:"healthy",last_checked_at:now}],
    channels:[{id:"channel-a",name:"Sports",is_active:true}],
  });
  const oldFetch=globalThis.fetch;
  globalThis.fetch=async()=>new Response("#EXTM3U\n",{status:200});
  try{
    const handler=createTelegramHandler({mode:"admin",env:botEnv("222"),fetcher:mock.fetcher});
    const result=await handler(pulseRequest(key));
    assert.equal(result.status,200);
    const body=await result.json();
    assert.equal(body.configured_subscribers,1);
    assert.equal(body.subscribers,0);
    assert.equal(body.skipped_subscribers,1);
    assert.equal(body.checked,1);
    assert.ok(mock.calls.some(c=>c.method==="PATCH"&&c.url.includes("channel_lines?id=")));
  } finally{globalThis.fetch=oldFetch;}
});

test("failed Telegram delivery releases alert dedupe claim for a later retry",async()=>{
  const key="a".repeat(64);
  const mock=createMock({
    key,prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false}],
    lines:[{id:"line-a",channel_id:"channel-a",stream_url:"https://stream.test/master.m3u8",health_status:"healthy",last_checked_at:new Date().toISOString()}],
    channels:[{id:"channel-a",name:"Sports",is_active:true}],
    messageFail:true,
  });
  const oldFetch=globalThis.fetch;
  globalThis.fetch=async()=>new Response("Upstream error",{status:500});
  try{
    const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
    const result=await handler(pulseRequest(key));
    assert.equal(result.status,200);
    assert.ok(mock.calls.some(c=>c.method==="POST"&&c.url.includes("nca_bot_alert_state?")));
    assert.ok(mock.calls.some(c=>c.method==="DELETE"&&c.url.includes("nca_bot_alert_state?")));
  } finally{globalThis.fetch=oldFetch;}
});

test("/readiness provides channel readiness without leaking stream URLs",async()=>{
  const now=Date.now();
  const uuid="11111111-1111-4111-8111-111111111111";
  const mock=createMock({matches:[{id:uuid,home_team:"City",away_team:"United",league:"PL",kickoff_at:new Date(now+3600000).toISOString(),is_finished:false,is_active:true}]});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/readiness"))).status,200);
  const sent=telegramCalls(mock.calls,"sendMessage")[0].body.text;
  assert.match(sent,/No mapped channel/);
  assert.doesNotMatch(sent,/https:\/\/stream/);
});
