// NCA Telegram bots: private webhook commands backed by safe Supabase metadata.
// NO stream URLs, key IDs, key data, DRM, service keys or session tokens in replies.
export const VIEWER_SITE = "https://nyeinchanaung75299-eng.github.io/football-stream-app/";
export const ADMIN_SITE = VIEWER_SITE + "admin/";

const reply = (body, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const text = (value, limit = 100) => String(value ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, limit);
const dateInMyanmar = (iso) => {
  const date = new Date(iso);
  return Number.isNaN(date.valueOf()) ? "Time unavailable" :
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Asia/Yangon", day: "2-digit", month: "short",
      hour: "2-digit", minute: "2-digit", hour12: true,
    }).format(date) + " MMT";
};
const myanmarDay = (date) => new Date(date.getTime() + 390 * 60000).toISOString().slice(0, 10);

async function sameSecret(provided, expected) {
  if (!provided || !expected) return false;
  const encoder = new TextEncoder();
  const digests = await Promise.all([provided, expected].map(v => crypto.subtle.digest("SHA-256", encoder.encode(v))));
  const a = new Uint8Array(digests[0]), b = new Uint8Array(digests[1]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function createTelegramHandler({ mode, env, fetcher = fetch, clock = () => new Date() }) {
  if (mode !== "viewer" && mode !== "admin") throw new Error("Unknown bot mode");
  const prefix = mode === "viewer" ? "TG_VIEWER" : "TG_ADMIN";

  async function telegram(method, token, body) {
    const response = await fetcher("https://api.telegram.org/bot" + token + "/" + method, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error("Telegram API unavailable");
    const data = await response.json();
    if (data.ok !== true) throw new Error("Telegram rejected message");
  }
  async function database(path, env) {
    const url = (env.SUPABASE_URL || "").replace(/\/+$/, "") + "/rest/v1/" + path;
    const response = await fetcher(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: "Bearer " + env.SUPABASE_SERVICE_ROLE_KEY,
        Accept: "application/json",
      },
    });
    if (!response.ok) throw new Error("Database metadata unavailable");
    const rows = await response.json();
    if (!Array.isArray(rows)) throw new Error("Invalid database metadata");
    return rows;
  }
  async function matches(command, env) {
    const data = await database("matches?select=league,home_team,away_team,kickoff_at,is_live" +
      "&is_active=eq.true&publish_state=eq.published&deleted_at=is.null" +
      "&order=kickoff_at.asc&limit=100", env);
    const today = myanmarDay(clock()), now = clock().valueOf();
    const items = data.filter(m => {
      const t = new Date(m.kickoff_at).valueOf();
      if (!Number.isFinite(t)) return false;
      if (command === "/live") return m.is_live === true;
      if (command === "/today") return myanmarDay(new Date(t)) === today;
      return t >= now && t <= now + 7 * 86400000;
    }).slice(0, 9);
    if (!items.length) return command === "/live" ?
      "No verified live football matches right now." : "No published football matches for this selection.";
    return (command === "/live" ? "🔴 LIVE FOOTBALL" : command === "/today" ? "⚽ TODAY'S FOOTBALL" : "📅 UPCOMING FOOTBALL") +
      "\n" + items.map(m => text(m.home_team, 50) + " vs " + text(m.away_team, 50) +
        "\n" + text(m.league, 70) + " • " + dateInMyanmar(m.kickoff_at)).join("\n\n") +
      "\n\nWatch on NCA: " + VIEWER_SITE;
  }
  async function channelList(env, onlyBein) {
    const rows = await database("channels?select=id,name,category,epg_id,epg_source" +
      "&is_active=eq.true&order=name.asc&limit=250", env);
    return onlyBein ? rows.filter(r => /bein/i.test(r.name || "") || /bein/i.test(r.category || "")) : rows;
  }
  async function channelDetails(id, env) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return "Invalid channel selection.";
    const rows = await database("channels?select=id,name,category,epg_id,epg_source" +
      "&is_active=eq.true&id=eq." + encodeURIComponent(id) + "&limit=1", env);
    if (!rows.length) return "Channel not found.";
    const lines = await database("channel_lines?select=stream_type,health_status,last_checked_at" +
      "&is_active=eq.true&channel_id=eq." + encodeURIComponent(id) + "&limit=20", env);
    const channel = rows[0];
    const statuses = lines.map((line, n) => "Line " + (n + 1) + ": " +
      text(line.stream_type, 20) + " • " + text(line.health_status || "unknown", 30));
    return "📺 " + text(channel.name, 110) + "\nCategory: " +
      text(channel.category, 65) + "\nEPG: " +
      text(channel.epg_id || "Not linked", 80) +
      "\nActive lines: " + lines.length + "\n" + statuses.join("\n") +
      "\n\nManage protected stream details in NCA Admin:\n" + ADMIN_SITE;
  }
  async function health(env) {
    const [channels, lines] = await Promise.all([
      database("channels?select=id&is_active=eq.true&limit=250", env),
      database("channel_lines?select=health_status&is_active=eq.true&limit=500", env),
    ]);
    const counts = { healthy: 0, slow: 0, failed: 0, unknown: 0 };
    for (const row of lines) {
      const status = String(row.health_status || "unknown").toLowerCase();
      counts[status in counts ? status : "unknown"]++;
    }
    return "📊 NCA CHANNEL HEALTH\nActive channels: " + channels.length +
      "\nActive lines: " + lines.length + "\n🟢 Healthy lines: " + counts.healthy +
      "\n🟡 Slow lines: " + counts.slow + "\n🔴 Failed lines: " + counts.failed +
      "\n⚪ Unknown lines: " + counts.unknown +
      "\n\nHealth indicates reachability, not guaranteed playback.";
  }
  async function builds() {
    const response = await fetcher("https://api.github.com/repos/nyeinchanaung75299-eng/football-stream-app/actions/runs?branch=main&per_page=20", {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "NCA-Telegram-Admin" },
    });
    if (!response.ok) throw new Error("GitHub build status unavailable");
    const json = await response.json();
    const recent = (json.workflow_runs || []).filter(r =>
      ["Build and Deploy Web Viewer", "Build Android V9.8 APKs"].includes(r.name)).slice(0, 2);
    if (!recent.length) return "No recent tracked Web/APK runs.";
    return "🛠️ NCA BUILDS\n" + recent.map(r => text(r.name, 55) + ": " +
      text(r.conclusion || r.status, 25) + "\n" + text(r.html_url, 190)).join("\n\n");
  }
  async function handle(req) {
    if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
    const token = env[prefix + "_BOT_TOKEN"];
    const secret = env[prefix + "_WEBHOOK_SECRET"];
    if (!token || !secret || !env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      return reply({ error: "Bot not configured" }, 503);
    }
    if (!await sameSecret(req.headers.get("X-Telegram-Bot-Api-Secret-Token"), secret)) {
      return reply({ error: "Invalid webhook" }, 401);
    }
    const update = await req.json().catch(() => null);
    if (!update || typeof update !== "object") return reply({ error: "Bad update" }, 400);
    const callback = update.callback_query;
    const message = callback?.message || update.message;
    const from = callback?.from || update.message?.from;
    const chat = message?.chat;
    if (!chat || !from || !Number.isSafeInteger(chat.id) || !Number.isSafeInteger(from.id)) return reply({ ok: true });
    const raw = String(callback ? callback.data || "" : message.text || "").trim();
    const cmd = raw.split(/\s+/)[0].split("@")[0].toLowerCase();
    // The pairing command returns only the requesting user's OWN ID.
    // All Admin data remains inaccessible until that ID is explicitly allowlisted.
    if (mode === "admin") {
      if (chat.type !== "private" || String(chat.id) !== String(from.id)) return reply({ ok: true });
      if (cmd === "/whoami") {
        await telegram("sendMessage", token, {
          chat_id: chat.id, text: "Your Telegram User ID: " + String(from.id) +
            "\nAdd this ID to the private Supabase secret TG_ADMIN_USER_IDS to enable Admin commands.",
        });
        return reply({ ok: true });
      }
      const allowed = new Set((env.TG_ADMIN_USER_IDS || "").split(",").map(s => s.trim()).filter(Boolean));
      if (!allowed.has(String(from.id))) return reply({ ok: true });
    }
    if (callback && callback.id) await telegram("answerCallbackQuery", token, { callback_query_id: callback.id });
    let responseText, keyboard;
    try {
      if (mode === "viewer") {
        if (["/today", "/live", "/schedule"].includes(cmd)) {
          responseText = await matches(cmd, env);
        } else if (cmd === "/channels") {
          const rows = await channelList(env, false);
          responseText = "📺 NCA active channels: " + rows.length +
            "\nView EPG and authorized playback in the NCA website:\n" + VIEWER_SITE;
        } else {
          responseText = "⚽ NCA Football Viewer\nUse /today /live /schedule /channels.\n" +
            "Automatic match alerts are not enabled until subscriptions are configured.";
          keyboard = { inline_keyboard: [
            [{ text: "⚽ Today", callback_data: "/today" }, { text: "🔴 Live", callback_data: "/live" }],
            [{ text: "📅 Schedule", callback_data: "/schedule" }],
            [{ text: "Open Viewer", url: VIEWER_SITE }],
          ] };
        }
      } else if (cmd === "/health" || cmd === "/status") {
        responseText = await health(env);
      } else if (cmd === "/build") {
        responseText = await builds();
      } else if (cmd === "/bein") {
        const rows = (await channelList(env, true)).slice(0, 30);
        responseText = "📺 beIN Sports (" + rows.length + ")\nSelect a channel for metadata:";
        keyboard = { inline_keyboard: rows.map(r => [{
          text: text(r.name, 55), callback_data: "channel:" + r.id,
        }]) };
        if (!rows.length) responseText = "No active beIN Sports channel found.";
      } else if (raw.startsWith("channel:")) {
        responseText = await channelDetails(raw.slice("channel:".length), env);
      } else {
        responseText = "🛡️ NCA Private Admin\nRead-only commands: /health /bein /build /whoami.\n" +
          "Protected stream data and keys stay in the authenticated Admin website.";
        keyboard = { inline_keyboard: [
          [{ text: "📺 beIN Sports", callback_data: "/bein" }],
          [{ text: "🟢 Channel Health", callback_data: "/health" }, { text: "🛠️ Builds", callback_data: "/build" }],
          [{ text: "Open Admin", url: ADMIN_SITE }],
        ] };
      }
    } catch {
      responseText = "NCA data is temporarily unavailable. Try again later.";
    }
    await telegram("sendMessage", token, {
      chat_id: chat.id, text: responseText.slice(0, 3900),
      disable_web_page_preview: true,
      ...(keyboard ? { reply_markup: keyboard } : {}),
    });
    return reply({ ok: true });
  }
  return handle;
}
