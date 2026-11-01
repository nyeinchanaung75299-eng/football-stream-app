// Register only after deploying both Supabase Edge Functions.
// Set tokens and webhook secrets via your PRIVATE shell environment.
// Never commit bot tokens, webhook secrets or the Telegram API URL with token.
const host = "https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/";
const settings = [
  ["Viewer", "telegram-viewer", "TG_VIEWER_BOT_TOKEN", "TG_VIEWER_WEBHOOK_SECRET"],
  ["Admin", "telegram-admin", "TG_ADMIN_BOT_TOKEN", "TG_ADMIN_WEBHOOK_SECRET"],
];
for (const [label, path, tokenKey, secretKey] of settings) {
  const token = process.env[tokenKey], secret = process.env[secretKey];
  if (!token || !secret || !/^[a-zA-Z0-9_-]{1,256}$/.test(secret)) {
    console.error(label + ": missing token or invalid webhook secret. Nothing registered.");
    process.exitCode = 1;
    continue;
  }
  try {
    const response = await fetch("https://api.telegram.org/bot" + token + "/setWebhook", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        url: host + path, secret_token: secret,
        allowed_updates: ["message", "callback_query"],
        max_connections: 4, drop_pending_updates: false,
      }),
    });
    const result = await response.json();
    if (!response.ok || result.ok !== true || result.result !== true) {
      console.error(label + ": webhook registration failed (no secrets printed).");
      process.exitCode = 1;
      continue;
    }
    console.log(label + ": Telegram webhook registered for " + host + path);
  } catch {
    console.error(label + ": Telegram API connection failed.");
    process.exitCode = 1;
  }
}
