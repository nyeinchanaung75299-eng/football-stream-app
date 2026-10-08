const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Accept, Range, Content-Type",
  "Cache-Control": "no-store",
};

function error(message, status) {
  return Response.json({ error: message }, { status, headers: cors });
}

// An isolated transport candidate. The existing Worker still validates
// sessions and serves media; its secrets never leave that Worker.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const allowed = url.pathname === "/health" ||
      url.pathname === "/matches" ||
      url.pathname === "/backend-health" ||
      /^\/matches\/[A-Za-z0-9_-]+\/streams$/.test(url.pathname) ||
      /^\/p\/[A-Za-z0-9_-]+(?:\/.*)?$/.test(url.pathname);

    if (url.pathname === "/" && request.method === "GET") {
      return Response.json({
        service: "nca-network-backup",
        experimental: true,
        tests: ["/health", "/matches", "/backend-health"],
      }, { headers: cors });
    }
    if (!allowed) return error("Not found.", 404);
    if (!["GET", "HEAD", "OPTIONS"].includes(request.method)) {
      return error("Method not allowed.", 405);
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (!env.PUBLIC_API) return error("Backup route is not configured.", 503);

    try {
      if (url.pathname === "/backend-health") {
        const upstream = new URL("https://supabase-api.nyeinchanaung.us.ci/health");
        return await env.PUBLIC_API.fetch(new Request(upstream, request));
      }
      // Preserve the Pages request origin, so protected manifests and media
      // URLs all stay on this route rather than returning to a blocked host.
      return await env.PUBLIC_API.fetch(request);
    } catch (_) {
      return error("The backup route could not reach the API.", 502);
    }
  },
};
