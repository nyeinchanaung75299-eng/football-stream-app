import assert from "node:assert/strict";
import test from "node:test";
import { createTelegramConnect } from "../supabase/functions/_shared/telegram_connect.mjs";

const userId = "11111111-1111-4111-8111-111111111111";
const env = {
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_ANON_KEY: "test-public-key",
  TG_VIEWER_BOT_TOKEN: "viewer-token-fixture",
  TG_ADMIN_BOT_TOKEN: "admin-token-fixture",
  TG_VIEWER_WEBHOOK_SECRET: "viewer_secret_123456789012345678901234",
  TG_ADMIN_WEBHOOK_SECRET: "admin_secret_1234567890123456789012345",
};
function fixture({role="admin", tokenValid=true, botMatch=true, envOverrides={}} = {}) {
  const calls = [];
  const fetcher = async (url, options={}) => {
    calls.push({url:String(url),headers:options.headers || {},method:options.method || "GET",body:options.body});
    if (url === env.SUPABASE_URL + "/auth/v1/user") {
      if (!tokenValid) return Response.json({error:"no user"},{status:401});
      return Response.json({id:userId});
    }
    if (String(url).includes("/rest/v1/profiles?")) return Response.json([{role}]);
    const method = String(url).split("/").at(-1);
    if (method === "getMe") {
      const isViewer = String(url).includes("viewer-token-fixture");
      return Response.json({ok:true,result:{username:botMatch?(isViewer?"NCAFootballViewer_bot":"NCAPrivate_bot"):"Unrelated_bot"}});
    }
    if (method === "setWebhook") return Response.json({ok:true,result:true});
    if (method === "getWebhookInfo") return Response.json({ok:true,result:{url:
      "https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/" +
      (String(url).includes("viewer-token-fixture") ? "telegram-viewer" : "telegram-admin")}});
    throw new Error("Unexpected request");
  };
  const handler=createTelegramConnect({...env,...envOverrides},fetcher);
  function request(auth="Bearer valid-admin-session") {
    return new Request("https://endpoint.invalid/connect",{
      method:"POST",headers:auth?{Authorization:auth}:{},body:"{}",
    });
  }
  return {calls,handler,request};
}

test("registers both BotFather usernames and webhook endpoints under verified Admin",async()=>{
  const f=fixture();
  const response=await f.handler(f.request());
  assert.equal(response.status,200);
  assert.deepEqual((await response.json()).bots,[
    {bot:"Viewer",connected:true},{bot:"Admin",connected:true},
  ]);
  const webhooks=f.calls.filter(c=>c.url.endsWith("/setWebhook"));
  assert.equal(webhooks.length,2);
  const submitted=webhooks.map(c=>JSON.parse(c.body));
  assert.notEqual(submitted[0].secret_token,submitted[1].secret_token);
  assert.ok(webhooks.every(c=>c.method==="POST"));
  assert.equal(f.calls.filter(c=>c.url.includes("/rest/v1/profiles")).length,1);
});

test("no BotFather token is accessed without a valid Supabase bearer token",async()=>{
  const f=fixture();
  const response=await f.handler(f.request(""));
  assert.equal(response.status,401);
  assert.equal(f.calls.length,0);
});

test("a signed-in non-Admin cannot register Telegram webhooks",async()=>{
  const f=fixture({role:"viewer"});
  const response=await f.handler(f.request());
  assert.equal(response.status,403);
  assert.equal(f.calls.filter(c=>c.url.includes("telegram.org")).length,0);
});

test("a forged/expired session cannot register webhooks",async()=>{
  const f=fixture({tokenValid:false});
  const response=await f.handler(f.request());
  assert.equal(response.status,401);
  assert.equal(f.calls.filter(c=>c.url.includes("telegram.org")).length,0);
});

test("missing/short/private duplicate webhook secrets are rejected before Telegram calls",async()=>{
  for(const overrides of [
    {TG_VIEWER_BOT_TOKEN:""},
    {TG_ADMIN_WEBHOOK_SECRET:"short"},
    {TG_ADMIN_WEBHOOK_SECRET:env.TG_VIEWER_WEBHOOK_SECRET},
  ]){
    const f=fixture({envOverrides:overrides});
    const response=await f.handler(f.request());
    assert.equal(response.status,409);
    assert.equal(f.calls.filter(c=>c.url.includes("telegram.org")).length,0);
  }
});

test("wrong BotFather token identity is rejected without registering webhooks",async()=>{
  const f=fixture({botMatch:false});
  const response=await f.handler(f.request());
  assert.equal(response.status,409);
  assert.equal(f.calls.filter(c=>c.url.endsWith("/setWebhook")).length,0);
  const text=JSON.stringify(await response.json());
  assert.doesNotMatch(text,/viewer-token-fixture|admin-token-fixture/);
});

test("only POST can register; OPTIONS has no side effects",async()=>{
  const f=fixture();
  const preflight=await f.handler(new Request("https://endpoint.invalid/connect",{method:"OPTIONS"}));
  assert.equal(preflight.status,204);
  assert.equal(preflight.headers.get("Access-Control-Allow-Origin"),"https://nyeinchanaung75299-eng.github.io");
  const get=await f.handler(new Request("https://endpoint.invalid/connect",{method:"GET"}));
  assert.equal(get.status,405);
  assert.equal(f.calls.length,0);
});
