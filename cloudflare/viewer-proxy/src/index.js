const viewerOrigin = "https://nyeinchanaung75299-eng.github.io";
const viewerBasePath = "/football-stream-app/";

export default {
  async fetch(request) {
    const incoming = new URL(request.url);
    let path = incoming.pathname;
    if (path === "/") {
      path = viewerBasePath;
    } else if (!path.startsWith(viewerBasePath)) {
      path = "/football-stream-app" + (path.startsWith("/") ? path : "/" + path);
    }

    const origin = new URL(viewerOrigin);
    origin.pathname = path;
    origin.search = incoming.search;

    try {
      const upstream = await fetch(new Request(origin, request), {
        redirect: "follow",
        cf: {
          cacheEverything: true,
          cacheTtl: path.endsWith(".html") || path.endsWith("/") ? 60 : 3600,
        },
      });
      const headers = new Headers(upstream.headers);
      headers.set("Access-Control-Allow-Origin", "*");
      headers.set("X-NCA-Viewer-Mirror", "cloudflare");
      if (
        path.endsWith(".html") ||
        path.endsWith("/") ||
        path.endsWith("service_worker.js")
      ) {
        headers.set("Cache-Control", "no-cache, no-store, must-revalidate");
      }
      return new Response(upstream.body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers,
      });
    } catch {
      return new Response("NCA Viewer is temporarily unavailable. Please retry.", {
        status: 503,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }
  },
};
