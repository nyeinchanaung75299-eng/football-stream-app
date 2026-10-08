const publicOrigin = "https://football-public-api.nyeinchanaung75299-eng.workers.dev";
const backendOrigin = "https://supabase-api.nyeinchanaung.us.ci";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS, POST, PUT, PATCH, DELETE",
  "Access-Control-Allow-Headers": "Accept, Authorization, apikey, Content-Type, Range, Prefer, X-Client-Info, X-Supabase-Api-Version, Accept-Profile, Content-Profile, X-Upsert, Cache-Control, If-Match, If-None-Match",
  "Access-Control-Expose-Headers": "Content-Range, Accept-Ranges, Content-Location, X-Total-Count, Retry-After",
  "Cache-Control": "no-store",
};
const functionNames = "football-fixtures|stream-health|soco-links|source-match-list";

function failure(message, status) {
  return Response.json({ error: message }, { status, headers: cors });
}

function routeKind(path) {
  if (["/health", "/matches", "/backend-health"].includes(path) ||
      /^\/matches\/[A-Za-z0-9_-]+\/streams$/.test(path) ||
      /^\/p\/[A-Za-z0-9_-]+(?:\/.*)?$/.test(path) ||
      /^\/sources\/(soco|yyzb|fawa|cola)\/(matches|streams)$/.test(path)) return "public";
  if (new RegExp("^/admin/functions/(" + functionNames + ")$").test(path)) return "admin";
  if (/^\/(auth|rest|storage)\/v1(?:\/.*)?$/.test(path) ||
      new RegExp("^/functions/v1/(" + functionNames + ")$").test(path)) return "backend";
  return null;
}

async function serviceHealth() {
  const targets = [
    ["viewer-web", "https://nyeinchanaung75299-eng.github.io/football-stream-app/"],
    ["admin-web", "https://nyeinchanaung75299-eng.github.io/football-stream-app/admin/"],
    ["posthog", "https://us.i.posthog.com/i/v0/e/"],
    ["google-drive", "https://www.googleapis.com/drive/v3/about?fields=kind"],
  ];
  const results = await Promise.all(targets.map(async ([service, target]) => {
    const start = Date.now();
    try {
      const response = await fetch(target, { signal: AbortSignal.timeout(6000), redirect: "follow" });
      await response.body?.cancel();
      return { service, reachable: response.status < 500, http: response.status, ms: Date.now() - start };
    } catch (_) { return { service, reachable: false, error: "Connection timed out or failed." }; }
  }));
  // These probes do not inspect ChatGPT plugin credentials or account access.
  return Response.json({ results, scope: "service-reachability-via-vercel" }, { headers: cors });
}

async function proxy(request) {
  const incoming = new URL(request.url);
  const routes = incoming.searchParams.getAll("route");
  if (routes.length > 1) return failure("Invalid route.", 400);
  const path = routes.length ? "/" + routes[0].replace(/^\/+/, "") : incoming.pathname;
  incoming.searchParams.delete("route");
  // Vercel includes rewrite captures as query parameters. Keep them in a
  // reserved namespace and strip them so PostgREST does not parse them as
  // table-column filters. Real filters such as id/eq and path/eq stay intact.
  for (const name of ["ncaPath", "ncaId", "ncaSource", "ncaAction", "ncaFunction"]) {
    incoming.searchParams.delete(name);
  }
  if (path === "/" && ["GET", "HEAD"].includes(request.method)) {
    const reply = Response.json({ service: "nca-vercel-network-backup", experimental: false }, { headers: cors });
    return request.method === "HEAD" ? new Response(null, { headers: reply.headers }) : reply;
  }
  if (path === "/service-health") {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method !== "GET") return failure("Method not allowed.", 405);
    return serviceHealth();
  }
  const kind = routeKind(path);
  if (!kind) return failure("Not found.", 404);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  const sourcePost = /^\/sources\/(soco|yyzb|fawa|cola)\/streams$/.test(path);
  const methods = kind === "backend" ? ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"] :
    (kind === "admin" || sourcePost ? ["POST"] : ["GET", "HEAD"]);
  if (!methods.includes(request.method)) return failure("Method not allowed.", 405);
  if (kind === "admin" && !/^Bearer \S+$/i.test(request.headers.get("Authorization") || "")) {
    return failure("Admin session is required.", 401);
  }

  const backend = kind === "backend" || path === "/backend-health";
  const upstream = new URL(path === "/backend-health" ? "/health" : path, backend ? backendOrigin : publicOrigin);
  if (path !== "/backend-health" && routeKind(upstream.pathname) !== kind) return failure("Not found.", 404);
  upstream.search = incoming.search;
  const headers = new Headers({
    Accept: request.headers.get("Accept") || "*/*",
    "User-Agent": request.headers.get("User-Agent") || "Dart/3.13.5 (dart:io)",
  });
  for (const name of ["Range", "Content-Type", "Authorization", "apikey", "Prefer", "X-Client-Info",
    "X-Supabase-Api-Version", "Accept-Profile", "Content-Profile", "X-Upsert", "If-Match", "If-None-Match"]) {
    if (["Authorization", "apikey"].includes(name) && !backend && kind !== "admin") continue;
    if (request.headers.has(name)) headers.set(name, request.headers.get(name));
  }
  // JWTs and publishable keys pass through unchanged. The original backend
  // enforces authentication, Admin roles, and RLS; no privileged key is added.
  const controller = new AbortController();
  const signal = AbortSignal.any([request.signal, controller.signal]);
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const method = request.method === "HEAD" && !path.startsWith("/p/") ? "GET" : request.method;
    const init = { method, headers, signal, redirect: "manual" };
    if (!["GET", "HEAD"].includes(method) && request.body) {
      init.body = request.body;
      init.duplex = "half";
    }
    const response = await fetch(upstream, init);
    const outputHeaders = new Headers(cors);
    for (const name of ["Content-Type", "Content-Range", "Accept-Ranges", "Content-Location", "Retry-After"]) {
      if (response.headers.has(name)) outputHeaders.set(name, response.headers.get(name));
    }
    if (response.status >= 300 && response.status < 400) {
      if (!backend) { await response.body?.cancel(); return failure("Unexpected upstream redirect.", 502); }
      const location = response.headers.get("Location");
      if (location) {
        const redirect = new URL(location, upstream);
        outputHeaders.set("Location", redirect.origin === backendOrigin ? incoming.origin + redirect.pathname + redirect.search : redirect.href);
      }
    }
    if (request.method === "HEAD" || [204, 304].includes(response.status)) {
      await response.body?.cancel();
      return new Response(null, { status: response.status, headers: outputHeaders });
    }
    const type = response.headers.get("Content-Type") || "";
    if (response.body && (/json/i.test(type) || (!backend && /mpegurl|dash\+xml/i.test(type) && response.ok))) {
      const reader = response.body.getReader();
      const parts = []; let size = 0;
      try {
        for (;;) {
          const part = await reader.read();
          if (part.done) break;
          size += part.value.byteLength;
          if (size > 2 * 1024 * 1024) throw new Error("Metadata response too large");
          parts.push(part.value);
        }
      } finally { await reader.cancel().catch(() => {}); }
      const body = new Uint8Array(size); let offset = 0;
      for (const part of parts) { body.set(part, offset); offset += part.byteLength; }
      let text = new TextDecoder().decode(body);
      if (!backend && response.ok) text = text.replaceAll(publicOrigin + "/p/", incoming.origin + "/p/");
      return new Response(text, { status: response.status, headers: outputHeaders });
    }
    // A media response can remain open after its headers arrive. A header
    // timeout must not terminate an otherwise healthy continuous FLV stream.
    clearTimeout(timer);
    return new Response(response.body, { status: response.status, headers: outputHeaders });
  } catch (error) {
    console.error("Network backup upstream failure", { category: error?.name || "Error", kind });
    return failure(signal.aborted ? "Upstream timed out or was cancelled." : "Upstream connection failed.", signal.aborted ? 504 : 502);
  } finally { clearTimeout(timer); }
}

export const GET = proxy;
export const HEAD = proxy;
export const OPTIONS = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
