import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createTelegramHandler, ADMIN_INLINE_MENU } from "./nca_private_admin_bot.mjs";

const mockApk = new TextEncoder().encode("admin-bot-apk-fixture");
const mockSha = createHash("sha256").update(mockApk).digest("hex");
const releaseBase = "https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/releases/";
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
function createMock({prefs=[],lines=[],channels=[],matches=[],messageFail=false,key="",highlightHtml=null}={}){
  const calls=[];
  const fetcher=async(url,options={})=>{
    const href=String(url);
    const body=options.body instanceof FormData ? options.body
      : options.body ? JSON.parse(options.body) : {};
    calls.push({url:href,method:options.method||"GET",body});
    if(href.startsWith(releaseBase)){
      const isAdmin=href.endsWith("admin-latest.json") || href.endsWith("NCA-admin-arm64-v8a-latest.apk");
      if(href.endsWith(".json")) return Response.json({
        ...(isAdmin?{app:"nca_admin"}:{}),
        version_name:isAdmin?"2.5.3":"9.8.0",build_number:30739,
        abi:"arm64-v8a",sha256:mockSha,size_bytes:mockApk.byteLength,
        apk_url:releaseBase+(isAdmin?"NCA-admin-arm64-v8a-latest.apk":"NCA-arm64-v8a-latest.apk"),
      });
      return new Response(mockApk);
    }
    if(href==="https://dasfootball.com/") {
      return new Response(highlightHtml ?? "",{headers:{"Content-Type":"text/html"}});
    }
    if(href==="https://cdn.example.org/public-clip.mp4" || /^https:\/\/cdn\.example\.org\/public-clip-\d+\.mp4$/.test(href)) {
      // Minimal 24-byte ISO base-media header, sufficient for first-byte probe.
      const bytes=new Uint8Array(24);
      bytes.set([0x00,0x00,0x00,0x18,0x66,0x74,0x79,0x70,0x69,0x73,0x6f,0x6d]);
      return new Response(bytes,{status:206,headers:{"Content-Type":"video/mp4"}});
    }
    if(href==="https://cdn.example.org/broken.mp4") {
      return new Response("Not an MP4",{status:200,headers:{"Content-Type":"text/plain"}});
    }

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
    if(href.includes("nca_bot_delivery_attempts?") &&
       (options.method||"GET")==="GET")
      return Response.json([]);
    if(href.includes("channel_lines?") && (options.method||"GET")==="GET")
      return Response.json(lines);
    if(href.includes("channels?") && (options.method||"GET")==="GET")
      return Response.json(channels);
    if(href.includes("matches?"))
      return Response.json(matches);
    if(href.includes("stream_links?") || href.includes("nca_bot_match_channels?") ||
       href.includes("nca_epg_auto_match_channels?"))
      return Response.json([]);
    if(href.includes("nca_bot_alert_state?") && (options.method||"GET")==="GET")
      return Response.json([]);
    if((options.method||"GET")==="POST" && href.includes("nca_bot_alert_state?"))
      return Response.json([{event_key:body.event_key}],{status:201});
    if(["PATCH","DELETE","POST"].includes(options.method))
      return new Response(null,{status:204});
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

test("unpaired chat can remove old keyboard without accessing private Admin controls",async()=>{
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv("222"),fetcher:mock.fetcher});
  assert.equal((await handler(request("/start"))).status,200);
  const replies=telegramCalls(mock.calls,"sendMessage");
  assert.equal(replies.length,1);
  assert.deepEqual(replies[0].body.reply_markup,{remove_keyboard:true});
  assert.match(replies[0].body.text,/not linked/);
  assert.doesNotMatch(replies[0].body.text,/PRIVATE ADMIN|stream_url/);
  const other=createMock();
  const otherHandler=createTelegramHandler({mode:"admin",env:botEnv("222"),fetcher:other.fetcher});
  assert.equal((await otherHandler(request("/health"))).status,200);
  assert.equal(telegramCalls(other.calls,"sendMessage").length,0);
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
    const patchCall=mock.calls.find(c=>c.method==="PATCH"&&c.url.includes("channel_lines?id="));
    assert.ok(patchCall);
    assert.equal(patchCall.body.telegram_probe_status,"healthy");
    assert.equal(patchCall.body.telegram_probe_failure_streak,0);
    for(const forbidden of ["health_status","health_http_status","last_checked_at",
      "manifest_status","segment_status","playback_status"]){
      assert.equal(patchCall.body[forbidden],undefined);
    }
  } finally{globalThis.fetch=oldFetch;}
});

test("failed Telegram delivery releases alert dedupe claim for a later retry",async()=>{
  const key="a".repeat(64);
  const mock=createMock({
    key,prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false}],
    lines:[{id:"line-a",channel_id:"channel-a",stream_url:"https://stream.test/master.m3u8",
      telegram_probe_status:"failed",telegram_probe_failure_streak:1,
      telegram_probe_checked_at:new Date().toISOString()}],
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
    const audit=mock.calls.find(c=>c.method==="POST" &&
      c.url.endsWith("/nca_bot_delivery_attempts"));
    assert.equal(audit?.body.outcome,"failed");
    assert.equal(audit?.body.error_code,"telegram_http_429");
    assert.equal(audit?.body.kind,"health");
    assert.doesNotMatch(JSON.stringify(audit.body),/stream\.test|test-admin-token|test-service-key/);
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


test("upcoming featured match produces a one-time private readiness alert",async()=>{
  const key="b".repeat(64);
  const id="22222222-2222-4222-8222-222222222222";
  const kickoff=new Date(Date.now()+30*60000).toISOString();
  const mock=createMock({
    key,
    prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:false,football_enabled:true}],
    lines:[],channels:[],
    matches:[{
      id,home_team:"Arsenal",away_team:"Chelsea",league:"Premier League",
      kickoff_at:kickoff,is_finished:false,is_featured:true,is_live:false,is_active:true,
    }],
  });
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  const response=await handler(pulseRequest(key));
  assert.equal(response.status,200);
  const sent=telegramCalls(mock.calls,"sendMessage");
  assert.equal(sent.length,1);
  assert.match(sent[0].body.text,/FEATURED MATCH READINESS/);
  assert.match(sent[0].body.text,/No channel assignment/);
  assert.doesNotMatch(sent[0].body.text,/stream_url|Bearer /);
  assert.ok(mock.calls.some(c=>c.method==="POST" && c.url.includes("nca_bot_alert_state?")));
});

test("ordinary upcoming matches do not trigger featured-only preflight",async()=>{
  const key="b".repeat(64);
  const mock=createMock({
    key,
    prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:false,football_enabled:true}],
    lines:[],channels:[],
    matches:[{
      id:"33333333-3333-4333-8333-333333333333",
      home_team:"Home",away_team:"Away",league:"Friendly",
      kickoff_at:new Date(Date.now()+30*60000).toISOString(),
      is_finished:false,is_featured:false,is_live:false,is_active:true,
    }],
  });
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(pulseRequest(key))).status,200);
  assert.equal(telegramCalls(mock.calls,"sendMessage").length,0);
});

test("/monitor on automatically enables alerts, while /alerts off remains a master pause",async()=>{
  const mock=createMock({prefs:[{
    chat_id:111,alert_enabled:false,monitor_enabled:false,football_enabled:false,
  }]});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/monitor on"))).status,200);
  const setMonitor=mock.calls.find(c=>c.method==="POST" &&
    c.url.includes("nca_bot_preferences?"));
  assert.equal(setMonitor.body.monitor_enabled,true);
  assert.equal(setMonitor.body.alert_enabled,true);
  assert.equal((await handler(request("/football on"))).status,200);
  const actions=mock.calls.filter(c=>c.method==="POST" &&
    c.url.includes("nca_bot_preferences?"));
  assert.equal(actions[1].body.football_enabled,true);
  assert.equal(actions[1].body.alert_enabled,true);
  assert.equal((await handler(request("/alerts off"))).status,200);
  const off=mock.calls.filter(c=>c.method==="POST" &&
    c.url.includes("nca_bot_preferences?")).at(-1);
  assert.equal(off.body.alert_enabled,false);
});

test("same-day failed/recovered/failed transitions generate distinct dedupe keys",async()=>{
  const key="b".repeat(64);
  const times=[
    "2026-11-09T02:00:00.000Z",
    "2026-11-09T02:02:00.000Z",
    "2026-11-09T02:04:00.000Z",
  ];
  const cases=[
    {before:1,probe:500,now:times[0]},
    {before:2,probe:200,now:times[1]},
    {before:1,probe:500,now:times[2]},
  ];
  const keys=[];
  const oldFetch=globalThis.fetch;
  try{
    for(const entry of cases){
      const mock=createMock({
        key,prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false}],
        lines:[{id:"line-x",channel_id:"channel-x",
          stream_url:"https://stream.test/master.m3u8",
          telegram_probe_status:entry.before===2?"failed":"healthy",
          telegram_probe_failure_streak:entry.before,
          telegram_probe_checked_at:entry.now}],
        channels:[{id:"channel-x",name:"Test channel",is_active:true}],
      });
      globalThis.fetch=async()=>new Response(
        entry.probe===200 ? "#EXTM3U\n" : "unavailable",
        {status:entry.probe},
      );
      const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
      const response=await handler(pulseRequest(key));
      assert.equal(response.status,200);
      const state=mock.calls.find(c=>c.method==="POST"&&
        c.url.includes("nca_bot_alert_state?"));
      assert.ok(state,"each real health transition should attempt an alert");
      keys.push(state.body.event_key);
      const audit=mock.calls.find(c=>c.method==="POST"&&
        c.url.endsWith("/nca_bot_delivery_attempts"));
      assert.equal(audit?.body.outcome,"sent");
      assert.equal(audit?.body.kind,"health");
    }
    assert.equal(new Set(keys).size,3);
    assert.match(keys[0],/failed/);
    assert.match(keys[1],/recovered/);
    assert.match(keys[2],/failed/);
  }finally{globalThis.fetch=oldFetch;}
});

test("the Admin health probe batch is bounded to 12 oldest lines",async()=>{
  const key="a".repeat(64),mock=createMock({key});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  const response=await handler(pulseRequest(key));
  assert.equal(response.status,200);
  assert.equal((await response.json()).probe_errors,0);
  const query=mock.calls.find(c=>c.url.includes("/channel_lines?") &&
    c.method==="GET");
  assert.match(query?.url||"",/limit=12/);
});

test("diagnostics shows last-24h delivery attempts without exposing private secrets",async()=>{
  const mock=createMock({prefs:[{
    chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false,
  }]});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/diagnostics"))).status,200);
  const reply=telegramCalls(mock.calls,"sendMessage")[0].body.text;
  assert.match(reply,/delivery attempts \(24h\): 0 sent, 0 failed/i);
  assert.doesNotMatch(reply,/test-admin-token|test-service-key|stream_url/);
});

test("server timeout or inaccessible network is inconclusive, not a video FAIL",async()=>{
  const key="c".repeat(64);
  const mock=createMock({
    key,prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false}],
    lines:[{id:"line-v",channel_id:"channel-v",stream_url:"https://stream.test/master.m3u8",
      health_status:"healthy",playback_status:"verified",
      telegram_probe_failure_streak:0,telegram_probe_status:"unknown"}],
    channels:[{id:"channel-v",name:"Verified device stream",is_active:true}],
  });
  const oldFetch=globalThis.fetch;
  globalThis.fetch=async()=>{throw new Error("simulated network timeout");};
  try{
    const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
    const response=await handler(pulseRequest(key));
    assert.equal(response.status,200);
    const patch=mock.calls.find(c=>c.method==="PATCH"&&c.url.includes("channel_lines?id="));
    assert.equal(patch.body.telegram_probe_status,"unknown");
    assert.equal(patch.body.telegram_probe_http_status,0);
    assert.equal(patch.body.telegram_probe_failure_streak,0);
    assert.equal(patch.body.health_status,undefined);
    assert.equal(patch.body.playback_status,undefined);
    assert.equal(telegramCalls(mock.calls,"sendMessage").length,0);
  }finally{globalThis.fetch=oldFetch;}
});

test("one HTTP 500 does not send a video failure alert; next consecutive failure may warn",async()=>{
  const key="c".repeat(64);
  const mock=createMock({
    key,prefs:[{chat_id:111,alert_enabled:true,monitor_enabled:true,football_enabled:false}],
    lines:[{id:"line-v",channel_id:"channel-v",stream_url:"https://stream.test/master.m3u8",
      health_status:"healthy",playback_status:"verified",
      telegram_probe_failure_streak:0,telegram_probe_status:"healthy"}],
    channels:[{id:"channel-v",name:"Verified device stream",is_active:true}],
  });
  const oldFetch=globalThis.fetch;
  globalThis.fetch=async()=>new Response("temporary upstream 500",{status:500});
  try{
    const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
    assert.equal((await handler(pulseRequest(key))).status,200);
    const patch=mock.calls.find(c=>c.method==="PATCH"&&c.url.includes("channel_lines?id="));
    assert.equal(patch.body.telegram_probe_status,"failed");
    assert.equal(patch.body.telegram_probe_failure_streak,1);
    assert.equal(patch.body.health_status,undefined);
    assert.equal(patch.body.playback_status,undefined);
    assert.equal(telegramCalls(mock.calls,"sendMessage").length,0);
  }finally{globalThis.fetch=oldFetch;}
});

test("admin /health reports server HTTP status independently of verified device video",async()=>{
  const mock=createMock({lines:[{health_status:"failed",
    telegram_probe_status:"unknown",playback_status:"verified",is_active:true}]});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/health"))).status,200);
  const text=telegramCalls(mock.calls,"sendMessage")[0].body.text;
  assert.match(text,/Media probe FAILED: 1/);
  assert.match(text,/Server HTTP probe UNKNOWN: 1/);
  assert.match(text,/Device video VERIFIED: 1/);
  assert.doesNotMatch(text,/stream_url|test-service-key/);
});

test("Admin /apk shows Viewer and Admin download choices", async () => {
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/apk"))).status,200);
  const options=telegramCalls(mock.calls,"sendMessage").at(-1).body.reply_markup.inline_keyboard.flat();
  assert.ok(options.some(b=>b.callback_data==="/apk_viewer"));
  assert.ok(options.some(b=>b.callback_data==="/apk_admin"));
});

test("Allowlisted Admin can send both real APK file types; callback does not edit after upload", async () => {
  for(const [command,name] of [["/apk_viewer","NCA-Viewer-arm64.apk"],["/apk_admin","NCA-Admin-arm64.apk"]]){
    const mock=createMock();
    const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
    assert.equal((await handler(request(command,true))).status,200);
    assert.equal(telegramCalls(mock.calls,"answerCallbackQuery").length,1);
    assert.equal(telegramCalls(mock.calls,"editMessageText").length,0);
    const files=telegramCalls(mock.calls,"sendDocument");
    assert.equal(files.length,1);
    assert.equal(files[0].body.get("document").name,name);
    assert.equal(files[0].body.get("chat_id"),"111");
  }
});

test("Unpaired user cannot access any private Admin APK, and no release is fetched", async () => {
  const mock=createMock();
  const handler=createTelegramHandler({mode:"admin",env:botEnv("222"),fetcher:mock.fetcher});
  assert.equal((await handler(request("/apk_admin"))).status,200);
  assert.equal(telegramCalls(mock.calls,"sendDocument").length,0);
  assert.equal(mock.calls.some(c=>c.url.startsWith(releaseBase)),false);
});



test("Private Admin /highlights returns verified public MP4 links, never web pages or HLS",async()=>{
  const page="https://dasfootball.com/team-a-team-b-highlights-2026-11-14/";
  const html='<script type="application/ld+json">'+JSON.stringify({
    '@type':'VideoObject', name:'Team A vs Team B Highlights',
    url:page, contentUrl:'https://cdn.example.org/public-clip.mp4',
    embedUrl:'https://cdn.example.org/stream.m3u8',
  })+'</script>';
  const mock=createMock({highlightHtml:html});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/highlights"))).status,200);
  const result=telegramCalls(mock.calls,"sendMessage")[0].body.text;
  assert.match(result,/FOOTBALL HIGHLIGHTS — DIRECT MP4/);
  assert.match(result,/https:\/\/cdn\.example\.org\/public-clip\.mp4/);
  assert.doesNotMatch(result,/dasfootball\.com\/team-a|\.m3u8|key_data|stream_url|test-service-key/);
  assert.ok(mock.calls.some(c=>c.url==="https://cdn.example.org/public-clip.mp4"));
  assert.equal(mock.calls.filter(c=>c.url==="https://dasfootball.com/").length,1);
});

test("Telegram Highlights Next returns subsequent five matches and final page",async()=>{
  const videos=Array.from({length:12},(_,i)=>({
    '@type':'VideoObject', name:'Football Match '+i+' Highlights',
    url:'https://dasfootball.com/football-match-'+i+'-highlights/',
    contentUrl:'https://cdn.example.org/public-clip-'+i+'.mp4',
  }));
  const html='<script type="application/ld+json">'+JSON.stringify({'@graph':videos})+'</script>';
  const mock=createMock({highlightHtml:html});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});

  assert.equal((await handler(request("/highlights"))).status,200);
  const first=telegramCalls(mock.calls,"sendMessage").at(-1).body;
  assert.match(first.text,/Football Match 0 Highlights/);
  assert.match(first.text,/Football Match 4 Highlights/);
  assert.doesNotMatch(first.text,/Football Match 5 Highlights/);
  assert.equal(first.reply_markup.inline_keyboard[0][0].callback_data,'hl:5');

  assert.equal((await handler(request("hl:5",true))).status,200);
  const second=telegramCalls(mock.calls,"editMessageText").at(-1).body;
  assert.match(second.text,/Football Match 5 Highlights/);
  assert.match(second.text,/Football Match 9 Highlights/);
  assert.doesNotMatch(second.text,/Football Match 0 Highlights/);
  assert.equal(second.reply_markup.inline_keyboard[0][0].callback_data,'hl:10');

  assert.equal((await handler(request("hl:10",true))).status,200);
  const third=telegramCalls(mock.calls,"editMessageText").at(-1).body;
  assert.match(third.text,/Football Match 10 Highlights/);
  assert.match(third.text,/Football Match 11 Highlights/);
  assert.doesNotMatch(third.text,/Football Match 9 Highlights/);
  assert.ok(third.reply_markup.inline_keyboard.flat().every(b=>!b.callback_data.startsWith('hl:')));
});

test("Telegram Highlights skips unreachable candidates without skipping subsequent matches",async()=>{
  const videos=Array.from({length:9},(_,i)=>({
    '@type':'VideoObject',name:'Fixture '+i+' Highlights',
    url:'https://dasfootball.com/fixture-'+i+'-highlights/',
    contentUrl:i<2?'https://cdn.example.org/broken.mp4':
      'https://cdn.example.org/public-clip-'+i+'.mp4',
  }));
  const mock=createMock({highlightHtml:'<script type="application/ld+json">'+
    JSON.stringify({'@graph':videos})+'</script>'});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/highlights"))).status,200);
  const first=telegramCalls(mock.calls,"sendMessage").at(-1).body;
  assert.doesNotMatch(first.text,/Fixture 0 Highlights|Fixture 1 Highlights/);
  assert.match(first.text,/Fixture 2 Highlights/);
  assert.match(first.text,/Fixture 6 Highlights/);
  assert.equal(first.reply_markup.inline_keyboard[0][0].callback_data,'hl:7');
});

test("Telegram Highlights never sends protected, tokenized or invalid MP4 URLs",async()=>{
  const videos=[
    {name:"A vs B Highlights",url:"https://dasfootball.com/a-b-highlights/",
     contentUrl:"https://cdn.example.org/secured.mp4?token=private"},
    {name:"C vs D Highlights",url:"https://dasfootball.com/c-d-highlights/",
     contentUrl:"https://cdn.example.org/broken.mp4"},
    {name:"E vs F Highlights",url:"https://dasfootball.com/e-f-highlights/",
     contentUrl:"https://cdn.example.org/stream.m3u8"},
    {name:"G vs H Highlights",url:"https://dasfootball.com/g-h-highlights/",
     contentUrl:"https://cdn.example.org/private.mp4",
     // A published referer requirement means it is not a standalone URL.
     referer:"https://dasfootball.com/"},
  ];
  const html='<script type="application/ld+json">'+JSON.stringify({
    "@graph":videos.map(video=>({"@type":"VideoObject",...video})),
  })+'</script>';
  const mock=createMock({highlightHtml:html});
  const handler=createTelegramHandler({mode:"admin",env:botEnv(),fetcher:mock.fetcher});
  assert.equal((await handler(request("/highlights"))).status,200);
  const result=telegramCalls(mock.calls,"sendMessage")[0].body.text;
  assert.match(result,/No verified public direct MP4 video URL/);
  assert.doesNotMatch(result,/token=private|secured\.mp4|broken\.mp4|stream\.m3u8/);
});

test("Unpaired Telegram admin cannot fetch public highlight feed or see private highlights menu",async()=>{
  const mock=createMock({highlightHtml:'<html></html>'});
  const handler=createTelegramHandler({mode:"admin",env:botEnv("999"),fetcher:mock.fetcher});
  assert.equal((await handler(request("/highlights"))).status,200);
  assert.equal(mock.calls.length,0);
});
