import assert from "node:assert/strict";
import test from "node:test";
import { createTelegramHandler } from "../supabase/functions/_shared/nca_telegram_bot.mjs";

const env = {
  TG_VIEWER_BOT_TOKEN: "viewer-fixture-token",
  TG_VIEWER_WEBHOOK_SECRET: "viewer-fixture-secret",
  TG_ADMIN_BOT_TOKEN: "admin-fixture-token",
  TG_ADMIN_WEBHOOK_SECRET: "admin-fixture-secret",
  TG_ADMIN_USER_IDS: "4242",
  SUPABASE_URL: "https://supabase.example",
  SUPABASE_SERVICE_ROLE_KEY: "server-secret-never-send",
};
const viewerMatch = {
  league: "Football League", home_team: "Team A", away_team: "Team B",
  kickoff_at: "2026-11-01T13:00:00Z", is_live: false,
  stream_url: "https://private.invalid/private.mpd",
  key_data: "very-sensitive-drm-key",
};
const channel = {
  id: "11111111-1111-4111-8111-111111111111", name: "beIN SPORTS 2 Australia",
  category: "beIN Sports", epg_id: "beINSports2.au", epg_source: "AU1",
  key_id: "secret-key-id", key_data: "drm-secret",
};
const mkRequest = (mode, text, user = 4242, secret = true, callback = false) => {
  const from = { id: user }, chat = { id: user, type: "private" };
  const update = callback ?
    { callback_query: { id: "callback-fixture", data: text, from, message: { chat } } } :
    { message: { text, from, chat } };
  return new Request("https://edge.example", {
    method: "POST", headers: {
      "Content-Type": "application/json",
      "X-Telegram-Bot-Api-Secret-Token": secret ?
        (mode === "viewer" ? env.TG_VIEWER_WEBHOOK_SECRET : env.TG_ADMIN_WEBHOOK_SECRET) : "wrong",
    }, body: JSON.stringify(update),
  });
};
function fixture(mode) {
  const sent = [], dbPaths = [];
  const fetcher = async (input, options = {}) => {
    const url = new URL(input);
    if (url.host === "api.telegram.org") {
      const body = JSON.parse(options.body);
      sent.push({ method: url.pathname.split("/").at(-1), body });
      return Response.json({ ok: true, result: { message_id: 1 } });
    }
    if (url.host === "api.github.com") {
      return Response.json({ workflow_runs: [{
        name: "Build and Deploy Web Viewer", status: "completed", conclusion: "success",
        html_url: "https://github.com/example/actions/runs/1",
      }] });
    }
    assert.equal(url.host, "supabase.example");
    assert.equal(options.headers.apikey, env.SUPABASE_SERVICE_ROLE_KEY);
    assert.equal(options.headers.Authorization, "Bearer " + env.SUPABASE_SERVICE_ROLE_KEY);
    dbPaths.push(url.pathname + url.search);
    if (url.pathname.endsWith("/matches")) return Response.json([viewerMatch]);
    if (url.pathname.endsWith("/channel_lines")) return Response.json(
      url.searchParams.has("channel_id") ?
        [{ stream_type: "dash", health_status: "healthy", key_data: "drm-secret" }] :
        [{ health_status: "healthy" }, { health_status: "failed" }],
    );
    if (url.pathname.endsWith("/channels")) {
      return Response.json(url.searchParams.has("id") ? [channel] : [channel]);
    }
    throw new Error("Unexpected endpoint " + url.href);
  };
  return { handler: createTelegramHandler({
    mode, env, fetcher, clock: () => new Date("2026-11-01T12:00:00Z"),
  }), sent, dbPaths };
}

test("invalid Telegram webhook secret is rejected before any database or outbound calls", async () => {
  const f = fixture("viewer");
  const response = await f.handler(mkRequest("viewer", "/today", 4242, false));
  assert.equal(response.status, 401);
  assert.equal(f.sent.length, 0);
  assert.equal(f.dbPaths.length, 0);
});

test("Viewer /today only displays published fixture metadata, never private streams or keys", async () => {
  const f = fixture("viewer");
  const response = await f.handler(mkRequest("viewer", "/today"));
  assert.equal(response.status, 200);
  assert.match(f.sent[0].body.text, /Team A vs Team B/);
  assert.match(f.sent[0].body.text, /01 Nov/);
  assert.doesNotMatch(f.sent[0].body.text, /key_data|drm-secret|private\.mpd|server-secret/i);
  assert.equal(f.dbPaths.length, 1);
  assert.match(f.dbPaths[0], /publish_state=eq\.published/);
});

test("Viewer /start includes linked website and quick actions; no automatic alert promise", async () => {
  const f = fixture("viewer");
  const response = await f.handler(mkRequest("viewer", "/start"));
  assert.equal(response.status, 200);
  assert.equal(f.sent[0].body.reply_markup.inline_keyboard[2][0].url.includes("github.io"), true);
  assert.match(f.sent[0].body.text, /not enabled/);
});

test("Private Admin bot never makes a database call for an unapproved Telegram ID", async () => {
  const f = fixture("admin");
  const response = await f.handler(mkRequest("admin", "/health", 7777));
  assert.equal(response.status, 200);
  assert.equal(f.sent.length, 0);
  assert.equal(f.dbPaths.length, 0);
});

test("Admin health counts active channels and line statuses without private details", async () => {
  const f = fixture("admin");
  const response = await f.handler(mkRequest("admin", "/health"));
  assert.equal(response.status, 200);
  assert.match(f.sent[0].body.text, /Active channels: 1/);
  assert.match(f.sent[0].body.text, /Healthy lines: 1/);
  assert.match(f.sent[0].body.text, /Failed lines: 1/);
  assert.doesNotMatch(f.sent[0].body.text, /server-secret|key_data/i);
});

test("Admin beIN buttons fetch channel metadata, without sending DRM data or raw stream URL", async () => {
  const f = fixture("admin");
  const first = await f.handler(mkRequest("admin", "/bein"));
  assert.equal(first.status, 200);
  assert.equal(f.sent[0].body.reply_markup.inline_keyboard[0][0].text, "beIN SPORTS 2 Australia");
  const second = await f.handler(mkRequest("admin", "channel:" + channel.id, 4242, true, true));
  assert.equal(second.status, 200);
  assert.equal(f.sent[1].method, "answerCallbackQuery");
  assert.match(f.sent[2].body.text, /beIN SPORTS 2 Australia/);
  assert.match(f.sent[2].body.text, /Active lines: 1/);
  assert.doesNotMatch(f.sent[2].body.text, /key_data|drm-secret|private\.mpd|secret-key-id/i);
});

test("Admin /build presents current GitHub build summary", async () => {
  const f = fixture("admin");
  const response = await f.handler(mkRequest("admin", "/build"));
  assert.equal(response.status, 200);
  assert.match(f.sent[0].body.text, /Build and Deploy Web Viewer/);
  assert.match(f.sent[0].body.text, /success/);
});

test("Admin /whoami securely returns only the requester's own ID before allowlisting", async () => {
  const f = fixture("admin");
  const response = await f.handler(mkRequest("admin", "/whoami", 7777));
  assert.equal(response.status, 200);
  assert.match(f.sent[0].body.text, /7777/);
  assert.equal(f.dbPaths.length, 0);
});

test("Private Admin bot cannot be used in a group even by an approved user", async () => {
  const f = fixture("admin");
  const update = { message: { text: "/health", from: { id: 4242 }, chat: { id: -111, type: "group" } } };
  const response = await f.handler(new Request("https://edge.example", {
    method: "POST", headers: {
      "X-Telegram-Bot-Api-Secret-Token": env.TG_ADMIN_WEBHOOK_SECRET,
      "Content-Type": "application/json",
    }, body: JSON.stringify(update),
  }));
  assert.equal(response.status, 200);
  assert.equal(f.sent.length, 0);
  assert.equal(f.dbPaths.length, 0);
});
