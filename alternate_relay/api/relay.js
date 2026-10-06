import { Readable } from "node:stream";

const ADMIN_FUNCTIONS = new Set([
  "football-fixtures",
  "football-score-sync",
  "stream-health",
  "soco-links",
  "source-match-list",
]);

const PRIMARY_API_BASE = (
  process.env.PRIMARY_API_BASE ||
  "https://football-api.nyeinchanaung.us.ci"
).replace(/\/+$/, "");

const SUPABASE_URL = (process.env.SUPABASE_URL || "").replace(/\/+$/, "");
const SUPABASE_PUBLISHABLE_KEY =
  process.env.SUPABASE_PUBLISHABLE_KEY || "";

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,HEAD,POST,OPTIONS",
    "Access-Control-Allow-Headers":
      "Authorization, Content-Type, apikey, Range, Cache-Control",
    "Access-Control-Expose-Headers":
      "Content-Length, Content-Range, Accept-Ranges, Location",
    "Cache-Control": "no-store",
  };
}

function applyCors(res) {
  for (const [name, value] of Object.entries(corsHeaders())) {
    res.setHeader(name, value);
  }
}

function cleanPath(value) {
  const text = String(value || "").replace(/^\/+/, "");
  if (!text || text.includes("..")) return null;
  return text;
}

function forwardedHeaders(req) {
  const headers = new Headers();
  for (const name of [
    "authorization",
    "accept",
    "content-type",
    "cache-control",
    "range",
    "user-agent",
  ]) {
    const value = req.headers[name];
    if (typeof value === "string" && value) headers.set(name, value);
  }
  return headers;
}

function requestBody(req) {
  if (req.method === "GET" || req.method === "HEAD") return undefined;
  if (req.body == null) return undefined;
  if (typeof req.body === "string" || Buffer.isBuffer(req.body)) {
    return req.body;
  }
  return JSON.stringify(req.body);
}

async function sendFetchResponse(req, res, upstream) {
  applyCors(res);
  res.statusCode = upstream.status;

  for (const [name, value] of upstream.headers.entries()) {
    const lower = name.toLowerCase();
    if (
      lower === "connection" ||
      lower === "transfer-encoding" ||
      lower === "content-length" ||
      lower === "content-encoding" ||
      lower === "access-control-allow-origin" ||
      lower === "access-control-allow-methods" ||
      lower === "access-control-allow-headers" ||
      lower === "access-control-expose-headers" ||
      lower === "cache-control"
    ) {
      continue;
    }
    res.setHeader(name, value);
  }

  if (req.method === "HEAD" || upstream.body == null) {
    res.end();
    return;
  }

  Readable.fromWeb(upstream.body).pipe(res);
}

async function proxyAdminFunction(req, res, functionName) {
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
    applyCors(res);
    res.status(503).json({ error: "Alternate admin relay is not configured." });
    return;
  }

  const authorization = req.headers.authorization || "";
  if (!String(authorization).startsWith("Bearer ")) {
    applyCors(res);
    res.status(401).json({ error: "Authentication required." });
    return;
  }

  const headers = forwardedHeaders(req);
  headers.set("apikey", SUPABASE_PUBLISHABLE_KEY);
  headers.set("Authorization", String(authorization));
  headers.set("Accept", "application/json");
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const upstream = await fetch(
    `${SUPABASE_URL}/functions/v1/${encodeURIComponent(functionName)}`,
    {
      method: req.method,
      headers,
      body: requestBody(req),
      redirect: "manual",
    },
  );

  await sendFetchResponse(req, res, upstream);
}

async function proxyPublicApi(req, res, path) {
  const query = new URLSearchParams();
  for (const [key, raw] of Object.entries(req.query || {})) {
    if (key === "path") continue;
    if (Array.isArray(raw)) {
      for (const value of raw) query.append(key, String(value));
    } else if (raw != null) {
      query.append(key, String(raw));
    }
  }

  const target =
    `${PRIMARY_API_BASE}/${path}` +
    (query.toString() ? `?${query.toString()}` : "");

  const upstream = await fetch(target, {
    method: req.method,
    headers: forwardedHeaders(req),
    body: requestBody(req),
    redirect: "manual",
  });

  await sendFetchResponse(req, res, upstream);
}

export default async function handler(req, res) {
  if (req.method === "OPTIONS") {
    applyCors(res);
    res.statusCode = 204;
    res.end();
    return;
  }

  const path = cleanPath(req.query.path);
  if (!path) {
    applyCors(res);
    res.status(400).json({ error: "Invalid relay path." });
    return;
  }

  if (path === "health") {
    applyCors(res);
    res.status(200).json({
      ok: true,
      service: "nca-alternate-relay",
      provider: "vercel",
      admin_direct_to_supabase:
        Boolean(SUPABASE_URL) && Boolean(SUPABASE_PUBLISHABLE_KEY),
      public_api_proxy: PRIMARY_API_BASE,
      now: new Date().toISOString(),
    });
    return;
  }

  const adminMatch = path.match(/^admin\/functions\/([a-z0-9-]+)$/i);
  if (adminMatch) {
    if (req.method !== "POST") {
      applyCors(res);
      res.status(405).json({ error: "Method not allowed." });
      return;
    }
    if (!ADMIN_FUNCTIONS.has(adminMatch[1])) {
      applyCors(res);
      res.status(404).json({ error: "Unknown admin function." });
      return;
    }
    try {
      await proxyAdminFunction(req, res, adminMatch[1]);
    } catch (error) {
      applyCors(res);
      res.status(502).json({
        error: "Alternate admin relay upstream unavailable.",
        detail: error instanceof Error ? error.message : String(error),
      });
    }
    return;
  }

  if (
    req.method !== "GET" &&
    req.method !== "HEAD" &&
    req.method !== "POST"
  ) {
    applyCors(res);
    res.status(405).json({ error: "Method not allowed." });
    return;
  }

  try {
    await proxyPublicApi(req, res, path);
  } catch (error) {
    applyCors(res);
    res.status(502).json({
      error: "Alternate public relay upstream unavailable.",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
