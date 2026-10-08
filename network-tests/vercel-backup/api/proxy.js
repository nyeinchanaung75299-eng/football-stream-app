const upstreamOrigin = "https://football-public-api.nyeinchanaung75299-eng.workers.dev";
const backendOrigin = "https://supabase-api.nyeinchanaung.us.ci";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Accept, Range, Content-Type",
  "Access-Control-Expose-Headers": "Content-Range, Accept-Ranges",
  "Cache-Control": "no-store",
};

function failure(message, status) {
  return Response.json({ error: message }, { status, headers: cors });
}

function allowed(path) {
  return ["/health", "/matches", "/backend-health"].includes(path) ||
    /^\/matches\/[A-Za-z0-9_-]+\/streams$/.test(path) ||
    /^\/p\/[A-Za-z0-9_-]+(?:\/.*)?$/.test(path);
}

async function proxy(request) {
  const incoming = new URL(request.url);
  const routes = incoming.searchParams.getAll("route");
  if (routes.length > 1) return failure("Invalid route.", 400);
  const path = routes.length ? "/" + routes[0].replace(/^\/+/, "") : incoming.pathname;
  incoming.searchParams.delete("route");
  if (path === "/" && request.method === "GET") {
    return Response.json({ service: "nca-vercel-network-backup", experimental: true }, { headers: cors });
  }
  if (!allowed(path)) return failure("Not found.", 404);
  if (!["GET", "HEAD", "OPTIONS"].includes(request.method)) return failure("Method not allowed.", 405);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

  const backend = path === "/backend-health";
  const upstream = new URL(backend ? "/health" : path, backend ? backendOrigin : upstreamOrigin);
  if (!backend && !allowed(upstream.pathname)) return failure("Not found.", 404);
  upstream.search = incoming.search;
  const headers = new Headers({
    Accept: request.headers.get("Accept") || "*/*",
    "User-Agent": request.headers.get("User-Agent") || "Dart/3.13.5 (dart:io)",
  });
  if (request.headers.has("Range")) headers.set("Range", request.headers.get("Range"));

  // The deadline also covers JSON/manifest body reads. Binary media remains a
  // stream, and cancellation from the client propagates to the upstream fetch.
  const signal = AbortSignal.any([request.signal, AbortSignal.timeout(20000)]);
  try {
    const response = await fetch(upstream, { method: request.method, headers, signal, redirect: "manual" });
    const outputHeaders = new Headers(cors);
    for (const name of ["Content-Type", "Content-Range", "Accept-Ranges"]) {
      if (response.headers.has(name)) outputHeaders.set(name, response.headers.get(name));
    }
    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel();
      return failure("Unexpected upstream redirect.", 502);
    }
    if (request.method === "HEAD" || [204, 304].includes(response.status)) {
      return new Response(null, { status: response.status, headers: outputHeaders });
    }
    const type = response.headers.get("Content-Type") || "";
    if (/json|mpegurl|dash\+xml/i.test(type) && response.ok) {
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
      const text = new TextDecoder().decode(body).replaceAll(upstreamOrigin + "/p/", incoming.origin + "/p/");
      return new Response(text, { status: response.status, headers: outputHeaders });
    }
    return new Response(response.body, { status: response.status, headers: outputHeaders });
  } catch (error) {
    // Never log the request URL, session token, source URL, or stream key.
    console.error("Network backup upstream failure", { category: error?.name || "Error", media: path.startsWith("/p/") });
    return failure(signal.aborted ? "Upstream timed out or was cancelled." : "Upstream connection failed.", signal.aborted ? 504 : 502);
  }
}

export const GET = proxy;
export const HEAD = proxy;
export const OPTIONS = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
