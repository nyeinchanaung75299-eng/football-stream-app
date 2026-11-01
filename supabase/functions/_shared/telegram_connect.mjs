// Telegram webhook registration. Only a verified NCA Supabase Admin can trigger it.
// Secrets are read from the Edge Function's private environment, never from the client.
const WEB_ORIGIN = "https://nyeinchanaung75299-eng.github.io";
const PROJECT = "woggzixprvyjnfjzsglz";
const targets = [
  { label: "Viewer", name: "NCAFootballViewer_bot", slug: "telegram-viewer", token: "TG_VIEWER_BOT_TOKEN", secret: "TG_VIEWER_WEBHOOK_SECRET" },
  { label: "Admin", name: "NCAPrivate_bot", slug: "telegram-admin", token: "TG_ADMIN_BOT_TOKEN", secret: "TG_ADMIN_WEBHOOK_SECRET" },
];
const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": WEB_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const output = (value, status = 200) => Response.json(value, { status, headers });
const validWebhookSecret = v => typeof v === "string" && /^[A-Za-z0-9_-]{32,128}$/.test(v);
const safeFetch = async (fetcher, url, options = {}) =>
  fetcher(url, { ...options, signal: AbortSignal.timeout(12000) });

export function createTelegramConnect(env, fetcher = fetch) {
  async function telegram(token, method, body) {
    // Never print request URLs: Telegram's bot token is part of this URL.
    const url = "https://api.telegram.org/bot" + token + "/" + method;
    const response = await safeFetch(fetcher, url, {
      method: body ? "POST" : "GET",
      ...(body ? { headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) throw new Error("Telegram API request failed");
    const result = await response.json();
    if (result?.ok !== true) throw new Error("Telegram API rejected request");
    return result.result;
  }
  return async function handle(req) {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return output({ error: "Method not allowed" }, 405);

    const backend = (env.SUPABASE_URL || "").replace(/\/+$/, "");
    const apiKey = env.SUPABASE_ANON_KEY || env.SUPABASE_PUBLISHABLE_KEY;
    if (!backend || !apiKey) return output({ error: "Supabase Auth not configured" }, 503);
    const auth = req.headers.get("Authorization") || "";
    if (!/^Bearer \S+$/.test(auth)) return output({ error: "Admin session required" }, 401);

    let user;
    try {
      const who = await safeFetch(fetcher, backend + "/auth/v1/user", {
        headers: { "apikey": apiKey, "Authorization": auth, "Accept": "application/json" },
      });
      if (!who.ok) return output({ error: "Invalid Admin session" }, 401);
      user = await who.json();
      if (!/^[0-9a-f-]{36}$/i.test(user?.id || "")) return output({ error: "Invalid Admin session" }, 401);
      // Role comes from protected DB, not user-supplied Telegram ID or JWT metadata.
      const roles = await safeFetch(fetcher, backend + "/rest/v1/profiles?select=role&id=eq." +
        encodeURIComponent(user.id) + "&limit=1", {
        headers: { "apikey": apiKey, "Authorization": auth, "Accept": "application/json" },
      });
      if (!roles.ok) return output({ error: "Could not verify Admin access" }, 503);
      const rows = await roles.json();
      if (!Array.isArray(rows) || rows[0]?.role !== "admin") {
        return output({ error: "Admin role required" }, 403);
      }
    } catch {
      return output({ error: "Could not verify Admin access" }, 503);
    }

    const missing = targets.filter(t => !env[t.token] || !validWebhookSecret(env[t.secret]));
    if (missing.length) {
      return output({
        error: "Missing bot tokens or invalid webhook secrets (use 32–128 random letters/digits/_/-).",
        bots: missing.map(t => t.label),
      }, 409);
    }
    if (env.TG_VIEWER_WEBHOOK_SECRET === env.TG_ADMIN_WEBHOOK_SECRET) {
      return output({ error: "Viewer and Admin webhook secrets must be different." }, 409);
    }

    const verified = [];
    try {
      for (const target of targets) {
        const who = await telegram(env[target.token], "getMe");
        if (who?.username?.toLowerCase() !== target.name.toLowerCase()) {
          return output({ error: target.label + " token belongs to a different Telegram bot." }, 409);
        }
        verified.push(target);
      }
    } catch {
      return output({ error: "Could not verify BotFather tokens with Telegram." }, 502);
    }

    const results = [];
    for (const target of verified) {
      const url = "https://" + PROJECT + ".supabase.co/functions/v1/" + target.slug;
      try {
        await telegram(env[target.token], "setWebhook", {
          url, secret_token: env[target.secret],
          allowed_updates: ["message", "callback_query"],
          drop_pending_updates: false, max_connections: 4,
        });
        const status = await telegram(env[target.token], "getWebhookInfo");
        results.push({ bot: target.label, connected: status?.url === url });
      } catch {
        results.push({ bot: target.label, connected: false });
      }
    }
    return output({ bots: results, connected: results.every(r => r.connected) },
      results.every(r => r.connected) ? 200 : 502);
  };
}
