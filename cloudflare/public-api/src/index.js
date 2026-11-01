const DEFAULT_MIRROR =
  "https://raw.githubusercontent.com/" +
  "nyeinchanaung75299-eng/football-stream-app/" +
  "feed/public/matches.json";

const MATCH_FIELDS = [
  "id", "league", "home_team", "away_team", "home_logo_url",
  "away_logo_url", "kickoff_at", "is_live", "sort_order",
  "status_short", "is_featured", "publish_state", "updated_at",
];

const SOFT_RATE_LIMITS = new Map();
const PLAYBACK_SESSION_AAD = new TextEncoder().encode(
  "nca-playback-session-v1",
);
const METADATA_TIMEOUT_MS = 8000;
const MEDIA_HEADER_TIMEOUT_MS = 10000;
const MANIFEST_BODY_TIMEOUT_MS = 10000;
const MAX_METADATA_BYTES = 2 * 1024 * 1024;
const VIEWER_LOOKUPS = new WeakMap();
// This guide only supplies public programme metadata. It is deliberately kept
// separate from stream discovery and playback: no stream URL, token or DRM
// field is accepted or returned by the route below.
const TV_GUIDE_ORIGIN = "https://my-channels-match-guide.vercel.app";
const TV_GUIDE_MAX_DAYS = 8;

// Alias failover can reach the same Worker several times while a provider is
// still answering. Share only work already in progress, scoped to this env.
// Never retain completed results: removals and successful empty lists stay fresh.
function coalesceViewerLookup(env, key, load) {
  let pending = VIEWER_LOOKUPS.get(env);
  if (!pending) {
    pending = new Map();
    VIEWER_LOOKUPS.set(env, pending);
  }
  const existing = pending.get(key);
  if (existing) return existing;
  if (pending.size >= 64) return load();
  const request = Promise.resolve().then(load).finally(() => {
    if (pending.get(key) === request) pending.delete(key);
  });
  pending.set(key, request);
  return request;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.hostname.startsWith("supabase-api.")) {
      return handleSupabaseRelay(request, env);
    }

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (url.pathname === "/admin/stream-detect-browser" && request.method === "POST") {
      const { handleBrowserStreamScan } =
        await import("./browser_stream_scanner.mjs");
      return handleBrowserStreamScan(request, env, { allowRequest });
    }

    if (url.pathname === "/admin/stream-detect" && request.method === "POST") {
      // Keep this dependency lazy: legacy worker route tests load the main
      // module from a data: URL, where relative imports are not resolvable.
      // Wrangler bundles this literal dynamic import for production.
      const { handleWebsiteStreamScan } =
        await import("./website_stream_scanner.mjs");
      return handleWebsiteStreamScan(request, env, { allowRequest });
    }

    const adminFunctionRoute = url.pathname.match(
      /^\/admin\/functions\/(football-fixtures|stream-health|soco-links|source-match-list|system-monitor)$/,
    );
    if (adminFunctionRoute && request.method === "POST") {
      return handleAdminFunction(request, adminFunctionRoute[1], env);
    }

    const protectedPlaybackRoute = url.pathname.match(
      /^\/p\/([A-Za-z0-9_-]+)(?:\/(.+))?$/,
    );
    if (
      protectedPlaybackRoute &&
      (request.method === "GET" || request.method === "HEAD")
    ) {
      return handleProtectedPlayback(
        request,
        protectedPlaybackRoute[1],
        protectedPlaybackRoute[2] || null,
        env,
      );
    }

    const sourceStreamsRoute = url.pathname.match(
      /^\/sources\/(soco|yyzb|fawa|cola|xoilac|camel)\/streams$/,
    );
    if (sourceStreamsRoute && request.method === "POST") {
      return handleSourceBrowserStreams(
        request,
        sourceStreamsRoute[1],
        env,
        url.origin,
      );
    }

    if (request.method !== "GET") {
      return json({ error: "Method not allowed." }, 405);
    }

    if (url.pathname === "/health") {
      return json({
        ok: true,
        service: "football-public-api",
        supabase_configured:
          Boolean(env.SUPABASE_URL?.trim()) &&
          Boolean(env.SUPABASE_PUBLISHABLE_KEY?.trim()),
        protected_playback:
          Boolean(env.PLAYBACK_BACKEND_SECRET?.trim()),
        admin_function_proxy: true,
        now: new Date().toISOString(),
      });
    }

    if (url.pathname === "/matches") {
      return handleMatches(env);
    }

    if (url.pathname === "/channels") return handleChannels(env);
    const channelRoute = url.pathname.match(/^\/channels\/([0-9a-fA-F-]{36})\/streams$/);
    if (channelRoute) return handleChannelStreams(request, channelRoute[1], env, url.origin);

    if (url.pathname === "/tv-schedule") {
      return handleTvSchedule(request, env, url);
    }

    const sourceMatchesRoute = url.pathname.match(
      /^\/sources\/(soco|yyzb|fawa|cola|xoilac|camel)\/matches$/,
    );
    if (sourceMatchesRoute && request.method === "GET") {
      return handleSourceBrowserMatches(
        request,
        sourceMatchesRoute[1],
        env,
      );
    }

    const streamRoute = url.pathname.match(
      /^\/matches\/([^/]+)\/streams$/,
    );
    if (streamRoute) {
      return handleStreams(
        request,
        decodeURIComponent(streamRoute[1]),
        env,
        url.origin,
      );
    }

    return json({ error: "Not found." }, 404);
  },
};

async function handleSupabaseRelay(request, env) {
  const base = env.SUPABASE_URL?.trim() || "";
  const publishableKey = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  const incoming = new URL(request.url);

  if (!base) {
    return json({ error: "Supabase relay is not configured." }, 503, {
      "Cache-Control": "no-store",
    });
  }

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: supabaseCorsHeaders(request),
    });
  }

  if (incoming.pathname === "/health") {
    if (!publishableKey) {
      return json({ error: "Supabase publishable key is not configured." }, 503, {
        "Cache-Control": "no-store",
      });
    }

    try {
      // The REST root is an OpenAPI endpoint and can return 401 for a valid
      // publishable key. Probe Auth health instead of declaring that healthy.
      const upstream = new URL(base.replace(/\/+$/, "") + "/auth/v1/health");
      const { status } = await fetchJsonWithTimeout(upstream, {
        method: "GET",
        headers: {
          apikey: publishableKey,
          Accept: "application/json",
        },
        redirect: "follow",
      }, 2500);
      return json({
        ok: true,
        service: "supabase-relay",
        upstream_status: status,
        now: new Date().toISOString(),
      }, 200, {
        "Cache-Control": "no-store",
      });
    } catch (error) {
      return json({
        ok: false,
        service: "supabase-relay",
        error: error instanceof Error ? error.message : String(error),
      }, 502, { "Cache-Control": "no-store" });
    }
  }

  const allowed =
    incoming.pathname.startsWith("/auth/v1/") ||
    incoming.pathname === "/auth/v1" ||
    incoming.pathname.startsWith("/rest/v1/") ||
    incoming.pathname === "/rest/v1" ||
    incoming.pathname.startsWith("/functions/v1/") ||
    incoming.pathname === "/functions/v1" ||
    incoming.pathname.startsWith("/realtime/v1/") ||
    incoming.pathname === "/realtime/v1" ||
    incoming.pathname.startsWith("/storage/v1/") ||
    incoming.pathname === "/storage/v1";

  if (!allowed) {
    return json({ error: "Supabase relay route not found." }, 404, {
      "Cache-Control": "no-store",
    });
  }

  const upstream = new URL(
    base.replace(/\/+$/, "") + incoming.pathname + incoming.search,
  );

  const headers = new Headers(request.headers);
  headers.delete("host");
  headers.delete("cf-connecting-ip");
  headers.delete("cf-ipcountry");
  headers.delete("cf-ray");
  headers.delete("x-forwarded-proto");
  headers.set("X-Forwarded-Host", incoming.host);
  headers.set("X-Forwarded-Proto", "https");

  let upstreamResponse;
  try {
    const isWebSocket =
      request.headers.get("Upgrade")?.toLowerCase() === "websocket";

    if (isWebSocket) {
      upstreamResponse = await fetch(
        new Request(upstream.toString(), request),
      );
    } else {
      const init = {
        method: request.method,
        headers,
        redirect: "manual",
      };
      if (request.method !== "GET" && request.method !== "HEAD") {
        init.body = request.body;
      }
      upstreamResponse = await fetch(new Request(upstream.toString(), init));
    }
  } catch (error) {
    return json({
      error: "Supabase relay upstream is unreachable.",
      detail: error instanceof Error ? error.message : String(error),
    }, 502, { "Cache-Control": "no-store" });
  }

  // WebSocket upgrade responses must pass through untouched.
  if (upstreamResponse.status === 101) {
    return upstreamResponse;
  }

  const outHeaders = new Headers(upstreamResponse.headers);
  for (const [name, value] of Object.entries(
    supabaseCorsHeaders(request),
  )) {
    outHeaders.set(name, value);
  }

  const location = outHeaders.get("Location");
  if (location) {
    try {
      const parsed = new URL(location);
      const upstreamOrigin = new URL(base).origin;
      if (parsed.origin === upstreamOrigin) {
        parsed.protocol = incoming.protocol;
        parsed.host = incoming.host;
        outHeaders.set("Location", parsed.toString());
      }
    } catch (_) {}
  }

  outHeaders.set("Cache-Control", "no-store");

  return new Response(
    request.method === "HEAD" ? null : upstreamResponse.body,
    {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers: outHeaders,
    },
  );
}

function supabaseCorsHeaders(request) {
  const origin = request.headers.get("Origin") || "*";
  const requestedHeaders =
    request.headers.get("Access-Control-Request-Headers") ||
    "Authorization, Content-Type, apikey, x-client-info, x-supabase-api-version, Prefer, Range, Content-Profile, Accept-Profile";
  return {
    "Access-Control-Allow-Origin": origin === "null" ? "*" : origin,
    "Access-Control-Allow-Methods":
      "GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": requestedHeaders,
    "Access-Control-Expose-Headers":
      "Content-Length, Content-Range, Accept-Ranges, Location, Preference-Applied, X-Supabase-Api-Version",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  };
}

async function handleAdminFunction(request, functionName, env) {
  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  const authorization = request.headers.get("Authorization")?.trim() || "";

  if (!base || !key) {
    return json({ error: "Backend gateway is not configured." }, 503);
  }
  if (!authorization.startsWith("Bearer ")) {
    return json({ error: "Authentication required." }, 401, {
      "Cache-Control": "no-store",
    });
  }

  const upstream = new URL(
    base.replace(/\/+$/, "") + "/functions/v1/" + functionName,
  );

  let upstreamResponse;
  try {
    upstreamResponse = await fetch(upstream, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: authorization,
        "Content-Type": request.headers.get("Content-Type") || "application/json",
        Accept: "application/json",
      },
      body: await request.text(),
    });
  } catch (_) {
    return json({ error: "Backend function is temporarily unreachable." }, 502, {
      "Cache-Control": "no-store",
    });
  }

  const headers = new Headers(upstreamResponse.headers);
  for (const [name, value] of Object.entries(corsHeaders())) headers.set(name, value);
  headers.set("Cache-Control", "no-store");
  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    headers,
  });
}

async function handleMatches(env) {
  try {
    const loaded = await loadMatchRows(env);
    const matches = loaded.rows
      .map((raw) => sanitizeMatchMetadata(raw))
      .sort(compareMatches);

    return json({
      ok: true,
      source: loaded.source,
      matches,
      generated_at: new Date().toISOString(),
    }, 200, { "Cache-Control": "no-store, max-age=0" });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : String(error),
    }, 502, { "Cache-Control": "no-store, max-age=0" });
  }
}

async function invokeViewerSourceFunction(env, body) {
  return coalesceViewerLookup(env, 'source:' + JSON.stringify(body),
    () => invokeViewerSourceFunctionOnce(env, body));
}

async function invokeViewerSourceFunctionOnce(env, body) {
  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  if (!base || !key) {
    throw new Error("Source browser backend is not configured.");
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 16000);
  try {
    const response = await fetch(
      base.replace(/\/+$/, "") + "/functions/v1/soco-links",
      {
        method: "POST",
        headers: {
          apikey: key,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          ...body,
          viewer_public: true,
        }),
        signal: controller.signal,
      },
    );

    const text = await readBoundedText(response, MAX_METADATA_BYTES);
    let payload = null;
    try {
      payload = text ? JSON.parse(text) : null;
    } catch (_) {
      payload = { error: text || "Invalid source browser response." };
    }

    if (!response.ok) {
      const detail =
        payload && typeof payload === "object" && payload.error
          ? String(payload.error)
          : "Source browser upstream unavailable.";
      const error = new Error(detail);
      error.status = response.status;
      throw error;
    }
    return payload;
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
}

async function handleSourceBrowserMatches(request, source, env) {
  if (!(await allowRequest(request, env, "source-matches-" + source, 20))) {
    return json({ error: "Too many source requests. Try again shortly." }, 429, {
      "Retry-After": "60",
      "Cache-Control": "no-store, max-age=0",
    });
  }

  try {
    const payload = await invokeViewerSourceFunction(env, {
      action: "matches", source,
    });
    const matches = Array.isArray(payload?.matches) ? payload.matches : [];
    return json({
      ok: true,
      source,
      matches,
      results: matches.length,
      generated_at: payload?.generated_at || new Date().toISOString(),
    }, 200, { "Cache-Control": "no-store, max-age=0" });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : String(error),
    }, Number(error?.status) || 502, {
      "Cache-Control": "no-store, max-age=0",
    });
  }
}

async function handleSourceBrowserStreams(request, source, env, publicOrigin) {
  if (!(await allowRequest(request, env, "source-streams-" + source, 30))) {
    return json({error: "Too many source requests."}, 429,
      {"Retry-After": "60", "Cache-Control": "no-store"});
  }
  let input = {};
  try { input = await request.json(); } catch (_) {}
  try {
    const payload = await invokeViewerSourceFunction(env, {
      action: "streams", source,
      room_num: input?.room_num ?? null,
      schedule_id: input?.schedule_id ?? null,
      page_url: input?.page_url ?? null,
      source_id: input?.source_id ?? null,
      anchor_name: input?.anchor_name ?? null,
      skip_probe: true,
    });
    if (payload?.requires_login) return json({ok:false, requires_login:true,
      error:"Camel1 requires sign-in on its own website."},403,{"Cache-Control":"no-store"});
    const candidates = Array.isArray(payload?.lines) ? payload.lines : [];
    const room = String(input?.room_num || "room");
    const anchor = String(input?.anchor_name || "").trim();
    const normalized = candidates.map((line, index) => ({
      id: String(line?.id || source + ":" +
        String(input?.schedule_id || "match") + ":" + room + ":" + index),
      label: anchor ? anchor + " • " + String(line?.label || ("Line " + (index + 1)))
        : line?.label || ("Line " + (index + 1)),
      resolution: line?.resolution || "Auto",
      stream_type: line?.stream_type || "auto",
      stream_url: line?.url || line?.stream_url || "",
      referer: line?.referer || "", origin: line?.origin || "",
      key_id: null, key_data: null, use_webview: false,
      is_active: true, priority: Number(line?.priority || 100),
      available_from: null, expires_at: line?.expires_at || null,
      health_status: line?.health_status || "unknown",
    }));
    const streams = await protectedClientLinks(normalized, env, publicOrigin);
    return json({ok: true, source, streams, stream_count: streams.length,
      live_status: payload?.live_status ?? null,
      generated_at: new Date().toISOString()}, 200,
      {"Cache-Control": "no-store, max-age=0"});
  } catch (error) {
    return json({error: error instanceof Error ? error.message : String(error)},
      Number(error?.status) || 502, {"Cache-Control": "no-store, max-age=0"});
  }
}

async function handleStreams(request, matchId, env, publicOrigin) {
  if (!/^[0-9a-fA-F-]{16,64}$/.test(matchId)) {
    return json({ error: "Invalid match id." }, 400);
  }

  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  const backendSecret = env.PLAYBACK_BACKEND_SECRET?.trim() || "";
  if (!base || !key || !backendSecret) {
    return json({ error: "Protected playback is not configured." }, 503, {
      "Cache-Control": "no-store, max-age=0",
    });
  }

  if (!(await allowRequest(request, env, "stream-list", 30))) {
    return json(
      { error: "Too many stream requests. Please try again shortly." },
      429,
      {
        "Cache-Control": "no-store, max-age=0",
        "Retry-After": "60",
      },
    );
  }

  try {
    const metadata = await loadStreamMetadata(env, matchId);
    if (!metadata.match_valid) {
      return json({ error: "Match not found." }, 404, {
        "Cache-Control": "no-store, max-age=0",
      });
    }
    const rawStreams = metadata.streams;
    const streams = await protectedClientLinks(rawStreams, env, publicOrigin);

    return json({
      ok: true,
      match_id: matchId,
      streams,
      blocked_streams: [],
      stream_count: streams.length,
      playable_stream_count: streams.length,
      blocked_stream_count: 0,
      // ClearKey lines configured by Admin are playable through the protected proxy.
      protected_playback: true,
      generated_at: new Date().toISOString(),
    }, 200, { "Cache-Control": "no-store, max-age=0" });
  } catch (_) {
    return json({ error: "Stream configuration upstream unavailable." }, 502, {
      "Cache-Control": "no-store, max-age=0",
    });
  }
}

async function handleChannels(env) {
  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  if (!base || !key) return json({error: "Channel catalog is not configured."}, 503);
  try {
    const url = new URL(base.replace(/\/+$/, "") + "/rest/v1/channels");
    url.searchParams.set("select", "id,name,category,image_url,sort_order");
    url.searchParams.set("is_active", "eq.true");
    url.searchParams.set("order", "category.asc,sort_order.asc,name.asc");
    url.searchParams.set("limit", "250");
    const {data} = await fetchJsonWithTimeout(url, {
      headers: {apikey: key, Accept: "application/json"},
    }, METADATA_TIMEOUT_MS);
    if (!Array.isArray(data)) throw new Error("Invalid channel catalog.");
    return json({ok: true, channels: data}, 200,
      {"Cache-Control": "public, max-age=15"});
  } catch (_) {
    return json({error: "Channel catalog is unavailable."}, 502);
  }
}

async function handleTvSchedule(request, env, incoming) {
  if (!(await allowRequest(request, env, "tv-schedule", 20))) {
    return json({ error: "Too many TV schedule requests. Try again shortly." }, 429, {
      "Retry-After": "60",
      "Cache-Control": "no-store",
    });
  }

  const requestedDate = String(incoming.searchParams.get("date") || "");
  const date = /^\d{4}-\d{2}-\d{2}$/.test(requestedDate)
    ? requestedDate
    : new Date().toISOString().slice(0, 10);
  const requestedDays = Number(incoming.searchParams.get("days") || TV_GUIDE_MAX_DAYS);
  const days = Number.isFinite(requestedDays)
    ? Math.min(TV_GUIDE_MAX_DAYS, Math.max(1, Math.floor(requestedDays)))
    : TV_GUIDE_MAX_DAYS;

  try {
    const upstream = new URL("/api/schedule", TV_GUIDE_ORIGIN);
    upstream.searchParams.set("date", date);
    upstream.searchParams.set("days", String(days));
    // Read the primary guide BEFORE launching optional region fan-out.
    // Cloudflare may limit concurrent connections to a single upstream host:
    // starting 18 optional lookups first previously starved this required
    // request and produced a 502 even though the primary guide was healthy.
    const { data } = await fetchJsonWithTimeout(upstream, {
      headers: { Accept: "application/json" },
    }, METADATA_TIMEOUT_MS);
    let schedule = sanitizeTvSchedule(data, date, days);
    // Missing optional feeds must never make the baseline schedule unavailable.
    try {
      const supplements = await loadExtendedTvGuide(date, days);
      schedule = sanitizeTvSchedule(
        mergeTvScheduleSources(data, supplements), date, days);
    } catch (_) {
      // Preserve the verified baseline if an optional provider fails.
    }
    return json(schedule, 200, {
      // Schedule data is public metadata and may be briefly cached by
      // clients. The upstream can still refresh it independently.
      "Cache-Control": "public, max-age=120",
    });
  } catch (_) {
    return json({ error: "TV schedule is temporarily unavailable." }, 502, {
      "Cache-Control": "no-store",
    });
  }
}

// Every route is fixed and owned by the user's public match-guide deployment.
// No arbitrary client URL is accepted, and partial provider outages simply
// leave their rows unmatched. Limit enrichment time so Vercel-first remains
// usable on slow Myanmar mobile networks.
const EXTENDED_TV_GUIDES = [
  ...["UK1", "US2", "CZ1", "AU1", "SK1", "MY1"]
    .map((source) => ({ path: "/api/epg-match", source })),
  ...["IC_BR", "IC_CA", "IC_UY", "IC_ID", "IC_PH", "IC_DE", "IC_TH", "IC_US"]
    .map((source) => ({ path: "/api/epg-country", source })),
  { path: "/api/epg-mx", source: "MX1" },
  { path: "/api/epg-ca", source: "CA1" },
  { path: "/api/regional", source: "regional" },
  { path: "/api/uk-extended", source: "uk-extended" },
];
let tvGuideCache = null;

async function loadExtendedTvGuide(date, days) {
  const key = `${date}:${days}`;
  if (tvGuideCache?.key === key && Date.now() - tvGuideCache.at < 90000) {
    return tvGuideCache.results;
  }
  const results = await Promise.all(EXTENDED_TV_GUIDES.map(async ({ path, source }) => {
    const url = new URL(path, TV_GUIDE_ORIGIN);
    url.searchParams.set("date", date);
    url.searchParams.set("days", String(days));
    if (path === "/api/epg-match" || path === "/api/epg-country") {
      url.searchParams.set("source", source);
    }
    try {
      const { data } = await fetchJsonWithTimeout(url, {
        headers: { Accept: "application/json" },
      }, 8500);
      if (!Array.isArray(data?.channels)) throw Error("Guide had no channels");
      return { source, data, ok: true };
    } catch (_) {
      return { source, data: null, ok: false };
    }
  }));
  tvGuideCache = { key, at: Date.now(), results };
  return results;
}

function mergeTvScheduleSources(base, supplements) {
  const safeBase = base && typeof base === "object" ? base : {};
  const existing = Array.isArray(safeBase.channels) ? safeBase.channels : [];
  const rows = existing.map((channel) => ({
    ...channel,
    programmes: Array.isArray(channel.programmes) ? [...channel.programmes] : [],
  }));
  const byId = new Map(rows.map((channel) => [String(channel.id), channel]));
  const sourceRows = Array.isArray(safeBase.sources) ? [...safeBase.sources] : [];
  for (const supplement of supplements) {
    const { source, data, ok } = supplement;
    // A regional API can report several distinct EPG feed health statuses.
    if (ok && Array.isArray(data?.sources) && data.sources.length) {
      for (const feed of data.sources) {
        sourceRows.push({
          name: source === "regional"
            ? `regional:${String(feed.name || "unknown")}` : source,
          ok: feed.ok === true,
        });
      }
    } else if (source !== "uk-extended") {
      sourceRows.push({ name: source, ok: false });
    }
    if (!ok) continue;
    for (const found of data.channels) {
      const channel = byId.get(String(found?.id || ""));
      if (!channel || found?.matchedEPG !== true) continue;
      const programmes = Array.isArray(found.programmes)
        ? found.programmes.filter((p) => p && Number(p.start) > 0)
        : [];
      if (!programmes.length) continue;
      channel.matchedEPG = true;
      if (!channel.region) channel.region = found.region;
      if (!channel.guide_candidate) channel.guide_candidate = found.guide_candidate === true;
      channel.programmes.push(...programmes);
    }
  }
  for (const channel of rows) {
    const unique = new Map();
    for (const programme of channel.programmes) {
      const key = `${programme.start}:${programme.title || ""}:${programme.subtitle || ""}`;
      if (!unique.has(key)) unique.set(key, programme);
    }
    channel.programmes = [...unique.values()]
      .sort((a, b) => Number(a.start) - Number(b.start))
      .slice(0, 60);
  }
  return { ...safeBase, sources: sourceRows, channels: rows };
}

function sanitizeTvSchedule(raw, date, days) {
  const source = raw && typeof raw === "object" ? raw : {};
  const text = (value, limit = 240) =>
    typeof value === "string" ? value.trim().slice(0, limit) : "";
  const timestamp = (value) => {
    const number = Number(value);
    return Number.isFinite(number) && number > 0 ? Math.floor(number) : null;
  };
  const programmes = (rows) => Array.isArray(rows) ? rows.slice(0, 60)
    .map((row) => {
      const start = timestamp(row?.start);
      if (start == null) return null;
      return {
        start,
        end: timestamp(row?.end),
        title: text(row?.title),
        subtitle: text(row?.subtitle, 260),
        description: text(row?.description, 360),
        // Public EPG confidence flags, never credentials or video URLs.
        stream_ambiguous: row?.stream_ambiguous === true,
        stream_confirmed: row?.stream_confirmed === true,
      };
    })
    .filter(Boolean) : [];

  return {
    ok: true,
    date,
    days,
    timezone: text(source.timezone, 80) || "Asia/Yangon",
    updated_at: text(source.updated_at, 80) || new Date().toISOString(),
    sources: Array.isArray(source.sources) ? source.sources.slice(0, 32)
      .map((row) => ({ name: text(row?.name, 80), ok: row?.ok === true }))
      .filter((row) => row.name) : [],
    matched_channels: Array.isArray(source.channels)
      ? source.channels.filter((c) => c?.matchedEPG === true && c?.programmes?.length).length : 0,
    channels: Array.isArray(source.channels) ? source.channels.slice(0, 300)
      .map((row) => ({
        id: text(row?.id, 100),
        name: text(row?.name),
        image_url: text(row?.image_url, 2000),
        category: text(row?.category, 100),
        matchedEPG: row?.matchedEPG === true,
        guide_candidate: row?.guide_candidate === true,
        region: text(row?.region, 40),
        programmes: programmes(row?.programmes),
      }))
      .filter((row) => row.id && row.name) : [],
  };
}

async function handleChannelStreams(request, channelId, env, publicOrigin) {
  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  const secret = env.PLAYBACK_BACKEND_SECRET?.trim() || "";
  if (!base || !key || !secret) {
    return json({error: "Channel playback is not configured."}, 503);
  }
  if (!(await allowRequest(request, env, "stream-list", 30))) {
    return json({error: "Too many stream requests."}, 429,
      {"Retry-After": "60", "Cache-Control": "no-store"});
  }
  try {
    const {data} = await fetchJsonWithTimeout(
      base.replace(/\/+$/, "") + "/rest/v1/rpc/get_channel_metadata_for_gateway",
      {method: "POST", headers: {
        apikey: key, Accept: "application/json", "Content-Type": "application/json",
      }, body: JSON.stringify({p_channel_id: channelId, p_secret: secret})},
      METADATA_TIMEOUT_MS,
    );
    if (typeof data?.channel_valid !== "boolean" || !Array.isArray(data.streams)) {
      throw new Error("Invalid channel metadata.");
    }
    if (!data.channel_valid) return json({error: "Channel not found."}, 404);
    const streams = await protectedClientLinks(data.streams, env, publicOrigin);
    return json({ok: true, channel_id: channelId, streams,
      stream_count: streams.length}, 200, {"Cache-Control": "no-store"});
  } catch (_) {
    return json({error: "Channel lines are unavailable."}, 502,
      {"Cache-Control": "no-store"});
  }
}

async function loadStreamMetadata(env, matchId) {
  const base = env.SUPABASE_URL.trim().replace(/\/+$/, "");
  const headers = {
    apikey: env.SUPABASE_PUBLISHABLE_KEY.trim(), Accept: "application/json",
    "Content-Type": "application/json",
  };
  const body = JSON.stringify({
    p_match_id: matchId, p_secret: env.PLAYBACK_BACKEND_SECRET.trim(),
  });
  try {
    const { data } = await fetchJsonWithTimeout(
      base + "/rest/v1/rpc/get_stream_metadata_for_gateway",
      { method: "POST", headers, body }, METADATA_TIMEOUT_MS,
    );
    if (typeof data?.match_valid !== "boolean" || !Array.isArray(data.streams)) {
      throw new Error("Invalid gateway metadata response.");
    }
    return data;
  } catch (error) {
    // An older database can continue serving during the Worker/RPC rollout.
    // Other HTTP failures and timeouts must not trigger duplicate DB work.
    if (error.status !== 404) throw error;
  }

  const matchUrl = new URL(base + "/rest/v1/matches");
  matchUrl.searchParams.set("select", "id");
  matchUrl.searchParams.set("id", "eq." + matchId);
  matchUrl.searchParams.set("is_active", "eq.true");
  matchUrl.searchParams.set("publish_state", "eq.published");
  matchUrl.searchParams.set("is_featured", "eq.true");
  matchUrl.searchParams.set("limit", "1");
  const { data: matches } = await fetchJsonWithTimeout(
    matchUrl, { headers }, METADATA_TIMEOUT_MS,
  );
  if (!Array.isArray(matches)) throw new Error("Invalid match response.");
  if (!matches.length) return { match_valid: false, streams: [] };
  const { data: streams } = await fetchJsonWithTimeout(
    base + "/rest/v1/rpc/get_stream_links_for_gateway",
    { method: "POST", headers, body }, METADATA_TIMEOUT_MS,
  );
  if (!Array.isArray(streams)) throw new Error("Invalid stream response.");
  return { match_valid: true, streams };
}

async function loadMatchRows(env) {
  return coalesceViewerLookup(env, 'published-matches', () => loadMatchRowsOnce(env));
}

async function loadMatchRowsOnce(env) {
  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";

  if (base && key) {
    try {
      const headers = { apikey: key, Accept: "application/json" };
      const matchesUrl = new URL(base.replace(/\/+$/, "") + "/rest/v1/matches");
      matchesUrl.searchParams.set("select", MATCH_FIELDS.join(","));
      matchesUrl.searchParams.set("is_active", "eq.true");
      matchesUrl.searchParams.set("publish_state", "eq.published");
      matchesUrl.searchParams.set("is_featured", "eq.true");
      matchesUrl.searchParams.set("order", "kickoff_at.asc,sort_order.asc");

      const countsUrl = new URL(
        base.replace(/\/+$/, "") + "/rest/v1/match_stream_counts",
      );
      countsUrl.searchParams.set("select", "match_id,stream_count");

      const [matchResult, countResult] = await Promise.allSettled([
        fetchJsonWithTimeout(matchesUrl, { headers }),
        fetchJsonWithTimeout(countsUrl, { headers }),
      ]);
      if (matchResult.status === "fulfilled") {
        const matches = matchResult.value.data;
        if (Array.isArray(matches)) {
          // No matches remains authoritative even if counts are unavailable.
          if (matches.length === 0) return { source: "supabase", rows: [] };
          if (countResult.status !== "fulfilled" ||
              !Array.isArray(countResult.value.data)) {
            throw new Error("Match availability counts are unavailable.");
          }
          const counts = countResult.value.data;
          const byMatch = new Map();
          if (Array.isArray(counts)) {
            for (const raw of counts) {
              const matchId = String(raw.match_id || "");
              if (!matchId) continue;
              byMatch.set(
                matchId,
                Math.max(0, Number(raw.stream_count || 0)),
              );
            }
          }
          return {
            source: "supabase",
            rows: matches.map((raw) => ({
              ...raw,
              stream_count: byMatch.get(String(raw.id || "")) || 0,
            })),
          };
        }
      }
    } catch (_) {}
  }

  const mirror = env.GITHUB_MIRROR_URL?.trim() || DEFAULT_MIRROR;
  const { data: rows } = await fetchJsonWithTimeout(mirror, {
    headers: { Accept: "application/json", "Cache-Control": "no-cache" },
  });
  if (!Array.isArray(rows)) throw new Error("Invalid mirror response.");
  return { rows, source: "github" };
}

// Keep JSON metadata deadlines active through response-body parsing, rather
// than only until headers arrive. Media segment streaming uses its own path.
async function fetchJsonWithTimeout(url, options = {}, timeoutMs = 4000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    if (!response.ok) {
      const error = new Error("Backend returned HTTP " + response.status);
      error.status = response.status;
      controller.abort();
      throw error;
    }
    return {
      status: response.status,
      data: JSON.parse(await readBoundedText(response, MAX_METADATA_BYTES)),
    };
  } finally {
    clearTimeout(timer);
  }
}

// Only bounded metadata/manifest bodies are buffered. Media is streamed.
async function readBoundedText(response, maxBytes) {
  const reader = response.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder();
  let text = "";
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) throw new Error("Metadata response too large.");
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    await reader.cancel().catch(() => {});
  }
}

function sanitizeMatchMetadata(raw) {
  const source = { ...raw };
  const links = Array.isArray(source.stream_links) ? source.stream_links : [];
  const result = {};
  for (const field of MATCH_FIELDS) result[field] = source[field];
  const embeddedCount = advertisedLinkCount(links);
  const authoritativeCount = advertisedLinkCount(source.stream_count);
  result.stream_count = Math.max(embeddedCount, authoritativeCount);
  result.public_stream_count = 0;
  return result;
}

function advertisedLinkCount(raw) {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.max(0, Math.floor(raw));
  }
  const links = Array.isArray(raw) ? raw : [];
  const now = Date.now();
  return links.filter((link) => {
    if (link.is_active !== true) return false;
    const availableFrom = Date.parse(String(link.available_from || ""));
    if (Number.isFinite(availableFrom) && now < availableFrom) return false;
    const expiresAt = Date.parse(String(link.expires_at || ""));
    if (Number.isFinite(expiresAt) && now >= expiresAt) return false;
    if (link.use_webview === true) return false;
    const streamUrl = String(link.stream_url || "").trim();
    return streamUrl.length > 0;
  }).length;
}

async function protectedClientLinks(raw, env, publicOrigin) {
  const backendSecret = env.PLAYBACK_BACKEND_SECRET?.trim() || "";
  if (!backendSecret) return [];

  const links = Array.isArray(raw) ? raw : [];
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);
  const maxLifetime = 3 * 60 * 60;
  const output = [];

  for (const link of links) {
    if (link.is_active !== true || link.use_webview === true) continue;
    const availableFrom = Date.parse(String(link.available_from || ""));
    if (Number.isFinite(availableFrom) && now < availableFrom) continue;
    const expiresAt = Date.parse(String(link.expires_at || ""));
    if (Number.isFinite(expiresAt) && now >= expiresAt) continue;
    if (Number.isFinite(expiresAt) && expiresAt - now <= 30000) continue;

    const upstreamUrl = String(link.stream_url || "").trim();
    if (!upstreamUrl) continue;

    const keyId = String(link.key_id || "").trim();
    const keyData = String(link.key_data || "").trim();
    // A ClearKey source is playable only when Admin supplied the complete
    // Key ID + Key Data pair. Incomplete key configuration is skipped.
    if ((keyId && !keyData) || (!keyId && keyData)) continue;

    const declaredType = String(link.stream_type || "auto").toLowerCase();
    const streamType =
      declaredType === "mpd"
        ? "dash"
        : declaredType === "m3u8"
          ? "hls"
          : declaredType;

    const sourceTtl = Number.isFinite(expiresAt)
      ? Math.floor((expiresAt - now) / 1000)
      : maxLifetime;
    if (sourceTtl <= 0) continue;
    const maxTtl = Math.min(maxLifetime, sourceTtl);
    const sessionKey = crypto.getRandomValues(new Uint8Array(32));
    const session = {
      u: upstreamUrl,
      r: String(link.referer || "").trim(),
      o: String(link.origin || "").trim(),
      t: streamType,
      k: bytesToBase64Url(sessionKey),
      e: nowSeconds + maxTtl,
    };

    // Stateless encrypted session: every playback request can validate and
    // decrypt the token locally, so HLS/DASH segment requests no longer read
    // or write Workers KV.
    const sessionToken = await encryptPlaybackSession(session, backendSecret);

    output.push({
      id: link.id,
      label: link.label,
      resolution: link.resolution,
      stream_type: link.stream_type,
      stream_url: publicOrigin.replace(/\/+$/, "") + "/p/" + sessionToken,
      referer: null,
      origin: null,
      // The upstream URL remains inside an authenticated encrypted token.
      // The Viewer receives only the ClearKey pair that Admin explicitly
      // configured for authorized ClearKey playback.
      key_id: keyId || null,
      key_data: keyData || null,
      use_webview: false,
      webview_url: null,
      is_active: true,
      priority: link.priority,
      available_from: link.available_from,
      expires_at: new Date(session.e * 1000).toISOString(),
      health_status: link.health_status,
      protected_proxy: true,
    });
  }

  return output.sort(compareLinks);
}

const WORKER_IP_HOST_ALIASES = Object.freeze({
  "193.47.62.41": "fawa41-origin.nyeinchanaung.us.ci",
  "193.47.62.44": "fawa44-origin.nyeinchanaung.us.ci",
  "193.47.62.55": "fawa55-origin.nyeinchanaung.us.ci",
  "193.47.62.59": "fawa59-origin.nyeinchanaung.us.ci",
});

function workerFetchUrl(value) {
  const url = value instanceof URL ? new URL(value.toString()) : new URL(value);
  const alias = WORKER_IP_HOST_ALIASES[url.hostname];
  if (alias) url.hostname = alias;
  return url;
}

function isFawaSession(session) {
  const referer = String(session?.r || "").toLowerCase();
  const origin = String(session?.o || "").toLowerCase();
  return referer.includes("fawanews.") || origin.includes("fawanews.");
}

async function handleProtectedPlayback(request, sessionToken, childPath, env) {
  const backendSecret = env.PLAYBACK_BACKEND_SECRET?.trim() || "";
  if (!backendSecret) {
    return json({ error: "Protected playback is unavailable." }, 503);
  }

  let session;
  try {
    session = await decryptPlaybackSession(sessionToken, backendSecret);
  } catch (_) {
    return json({ error: "Invalid or expired playback session." }, 410, {
      "Cache-Control": "no-store",
    });
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (
    !session.u || !session.k || !Number.isFinite(session.e) ||
    session.e <= nowSeconds
  ) {
    return json({ error: "Playback session expired." }, 410, {
      "Cache-Control": "no-store",
    });
  }

  let upstreamUrl;
  try {
    upstreamUrl = await resolveProtectedTarget(
      childPath,
      session,
      request.url,
    );
  } catch (_) {
    return json({ error: "Invalid protected media URL." }, 400);
  }

  let upstream;
  try {
    // Cloudflare Workers cannot subrequest raw IP-literal URLs. Known Fawa
    // origins are routed through DNS-only A-record aliases in our zone while
    // the protected session keeps the original URL private.
    upstream = workerFetchUrl(upstreamUrl);
  } catch (_) {
    return json({ error: "Invalid upstream URL." }, 400);
  }
  if (upstream.protocol !== "http:" && upstream.protocol !== "https:") {
    return json({ error: "Unsupported upstream protocol." }, 400);
  }

  const headers = new Headers();
  const fawa = isFawaSession(session);
  headers.set(
    "Accept",
    fawa
      ? "application/vnd.apple.mpegurl,application/x-mpegURL,video/*,*/*;q=0.8"
      : request.headers.get("Accept") || "*/*",
  );
  headers.set(
    "User-Agent",
    fawa
      ? "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36"
      : request.headers.get("User-Agent") ||
          "Mozilla/5.0 NCA-Protected-Playback",
  );
  const range = request.headers.get("Range");
  if (range) headers.set("Range", range);
  if (session.r) headers.set("Referer", session.r);
  if (session.o) headers.set("Origin", session.o);

  const requestedPath = upstream.pathname.toLowerCase();
  const requestedSessionType = String(session.t || "auto").toLowerCase();
  const liveManifestRequest =
    requestedPath.endsWith(".m3u8") ||
    requestedPath.endsWith(".mpd") ||
    (!childPath &&
      ["hls", "m3u8", "dash", "mpd"].includes(requestedSessionType));

  if (liveManifestRequest) {
    headers.set("Cache-Control", "no-cache");
    headers.set("Pragma", "no-cache");
  }

  const controller = new AbortController();
  const signal = AbortSignal.any([request.signal, controller.signal]);
  let timer = setTimeout(() => controller.abort(), MEDIA_HEADER_TIMEOUT_MS);
  let mediaStreaming = false;
  try {
    const fetchOptions = {
      method: request.method, headers, redirect: "follow", signal,
    };
    if (liveManifestRequest) fetchOptions.cache = "no-store";
    const response = await fetch(upstream, fetchOptions);
    clearTimeout(timer);
    const contentType = (response.headers.get("Content-Type") || "").toLowerCase();
    const finalUrl = response.url || upstream.toString();
    const path = new URL(finalUrl).pathname.toLowerCase();
    const isRootRequest = !childPath;
    const sessionType = String(session.t || "auto").toLowerCase();
    const isHls =
      contentType.includes("mpegurl") ||
      path.endsWith(".m3u8") ||
      (isRootRequest && (sessionType === "hls" || sessionType === "m3u8"));
    const isDash =
      contentType.includes("dash+xml") ||
      path.endsWith(".mpd") ||
      (isRootRequest && (sessionType === "dash" || sessionType === "mpd"));

    if (request.method === "GET" && response.ok && (isDash || isHls)) {
      timer = setTimeout(() => controller.abort(), MANIFEST_BODY_TIMEOUT_MS);
    }

    if (request.method === "GET" && response.ok && isDash) {
      const manifest = await readBoundedText(response, MAX_METADATA_BYTES);
      const rewritten = await rewriteDashManifest(
        manifest,
        finalUrl,
        sessionToken,
        session.k,
        new URL(request.url).origin,
      );
      return new Response(rewritten, {
        status: response.status,
        headers: {
          ...corsHeaders(),
          "Content-Type": "application/dash+xml",
          "Cache-Control": "no-store, max-age=0",
        },
      });
    }

    if (request.method === "GET" && response.ok && isHls) {
      const playlist = await readBoundedText(response, MAX_METADATA_BYTES);
      const rewritten = await rewriteHlsPlaylist(
        playlist,
        finalUrl,
        sessionToken,
        session.k,
        new URL(request.url).origin,
      );
      return new Response(rewritten, {
        status: response.status,
        headers: {
          ...corsHeaders(),
          "Content-Type": "application/vnd.apple.mpegurl",
          "Cache-Control": "no-store, max-age=0",
        },
      });
    }

    const outHeaders = new Headers(corsHeaders());
    outHeaders.set("Cache-Control", "no-store, max-age=0");
    for (const name of [
      "Content-Type", "Content-Length", "Content-Range", "Accept-Ranges",
      "ETag", "Last-Modified",
    ]) {
      const value = response.headers.get(name);
      if (value) outHeaders.set(name, value);
    }

    // Header timeout ends when headers arrive. Continuous FLV and segment
    // bodies retain client cancellation but have no fixed lifetime deadline.
    mediaStreaming = request.method !== "HEAD";
    return new Response(request.method === "HEAD" ? null : response.body, {
      status: response.status,
      headers: outHeaders,
    });
  } catch (_) {
    return json({ error: signal.aborted
      ? "Playback upstream timed out or was cancelled."
      : "Playback upstream unavailable." }, signal.aborted ? 504 : 502, {
      "Cache-Control": "no-store",
    });
  } finally {
    clearTimeout(timer);
    if (!mediaStreaming) controller.abort();
  }
}

async function resolveProtectedTarget(childPath, session, requestUrl) {
  if (!childPath) return session.u;

  const direct = childPath.match(/^([A-Za-z0-9_-]+)$/);
  if (direct) {
    return decryptTarget(direct[1], session.k);
  }

  const base = childPath.match(
    /^b\/([A-Za-z0-9_-]+)(?:\/(.*))?$/,
  );
  if (!base) throw new Error("Unsupported protected media path.");

  const rawBase = await decryptTarget(base[1], session.k);
  const anchor = new URL(rawBase);
  if (anchor.protocol !== "http:" && anchor.protocol !== "https:") {
    throw new Error("Unsupported protected base URL.");
  }

  const tail = base[2] || "";
  if (!tail) return anchor.toString();

  const target = new URL(tail, anchor);
  if (target.origin !== anchor.origin) {
    throw new Error("Protected media origin mismatch.");
  }

  const allowedPath = anchor.pathname.endsWith("/")
    ? anchor.pathname
    : anchor.pathname.slice(0, anchor.pathname.lastIndexOf("/") + 1);
  if (allowedPath && !target.pathname.startsWith(allowedPath)) {
    throw new Error("Protected media path escaped its base.");
  }

  const incoming = new URL(requestUrl);
  if (incoming.search) target.search = incoming.search;
  return target.toString();
}

async function rewriteHlsPlaylist(
  text,
  baseUrl,
  sessionToken,
  sessionKey,
  publicOrigin,
) {
  const output = [];
  for (const original of text.split(/\r?\n/)) {
    const line = original.trim();
    if (!line) {
      output.push(original);
      continue;
    }
    if (line.startsWith("#")) {
      output.push(await rewriteHlsTagUris(
        original, baseUrl, sessionToken, sessionKey, publicOrigin,
      ));
      continue;
    }
    const absolute = new URL(line, baseUrl).toString();
    const sealed = await encryptTarget(absolute, sessionKey);
    output.push(
      publicOrigin.replace(/\/+$/, "") + "/p/" + sessionToken + "/" + sealed,
    );
  }
  return output.join("\n");
}

async function rewriteHlsTagUris(
  line,
  baseUrl,
  sessionToken,
  sessionKey,
  publicOrigin,
) {
  const regex = /URI="([^"]+)"/g;
  let match;
  let cursor = 0;
  let result = "";
  while ((match = regex.exec(line)) !== null) {
    result += line.slice(cursor, match.index);
    const absolute = new URL(match[1], baseUrl).toString();
    const sealed = await encryptTarget(absolute, sessionKey);
    result += 'URI="' + publicOrigin.replace(/\/+$/, "") +
      "/p/" + sessionToken + "/" + sealed + '"';
    cursor = match.index + match[0].length;
  }
  return result + line.slice(cursor);
}

async function rewriteDashManifest(
  text,
  manifestUrl,
  sessionToken,
  sessionKey,
  publicOrigin,
) {
  const origin = publicOrigin.replace(/\/+$/, "");
  let rewritten = text;
  const hadRootBaseUrl = hasRootDashBaseUrl(text);

  rewritten = await rewriteDashBaseUrls(
    rewritten,
    manifestUrl,
    sessionToken,
    sessionKey,
    origin,
  );

  // A manifest can have BaseURL only inside one Representation/AdaptationSet.
  // Other siblings would then resolve relative media directly against the
  // protected manifest URL and miss the session route. Inject a protected
  // MPD-level base whenever the original manifest had no root-level BaseURL.
  if (!hadRootBaseUrl) {
    const manifestDirectory = new URL(".", manifestUrl).toString();
    const protectedBase = await protectDashBaseReference(
      manifestDirectory,
      manifestUrl,
      sessionToken,
      sessionKey,
      origin,
    );
    rewritten = rewritten.replace(
      /<MPD\b[^>]*>/i,
      (rootTag) =>
        rootTag + "<BaseURL>" + escapeXmlText(protectedBase) + "</BaseURL>",
    );
  }

  rewritten = await replaceAsync(
    rewritten,
    /\b(media|initialization|sourceURL|index|href|xlink:href|value)\s*=\s*(["'])([^"']+)\2/gi,
    async (match, name, quote, rawValue) => {
      const value = decodeXmlText(rawValue.trim());
      if (!isDashExternalReference(value)) return match;
      const protectedValue = await protectDashReference(
        value,
        manifestUrl,
        sessionToken,
        sessionKey,
        origin,
      );
      return name + "=" + quote + escapeXmlAttribute(protectedValue, quote) + quote;
    },
  );

  rewritten = await replaceAsync(
    rewritten,
    /<(Location|PatchLocation)(\b[^>]*)>([\s\S]*?)<\/\1>/gi,
    async (match, tagName, attributes, rawValue) => {
      const value = decodeXmlText(stripXmlText(rawValue));
      if (!value || value.startsWith("#") || /^urn:/i.test(value)) {
        return match;
      }
      const protectedValue = await protectDashReference(
        value,
        manifestUrl,
        sessionToken,
        sessionKey,
        origin,
      );
      return "<" + tagName + (attributes || "") + ">" +
        escapeXmlText(protectedValue) + "</" + tagName + ">";
    },
  );

  return rewritten;
}

async function rewriteDashBaseUrls(
  text,
  manifestUrl,
  sessionToken,
  sessionKey,
  publicOrigin,
) {
  const source = String(text || "");
  const root = /<MPD\b[^>]*>/i.exec(source);
  const rootEnd = root ? (root.index || 0) + root[0].length : -1;
  const afterRoot = rootEnd >= 0 ? source.slice(rootEnd) : "";
  const firstPeriod = /<Period\b/i.exec(afterRoot);
  const firstPeriodIndex = firstPeriod
    ? rootEnd + firstPeriod.index
    : source.length;

  const regex = /<BaseURL(\b[^>]*)>([\s\S]*?)<\/BaseURL>/gi;
  let result = "";
  let cursor = 0;
  let match;

  while ((match = regex.exec(source)) !== null) {
    result += source.slice(cursor, match.index);
    const attributes = match[1] || "";
    const rawValue = match[2];
    const value = decodeXmlText(stripXmlText(rawValue));
    const isRootLevel =
      rootEnd >= 0 &&
      match.index >= rootEnd &&
      match.index < firstPeriodIndex;

    if (!value || value.startsWith("#") || /^urn:/i.test(value)) {
      result += match[0];
    } else if (
      isRootLevel ||
      isDashExternalReference(value)
    ) {
      const protectedValue = await protectDashBaseReference(
        value,
        manifestUrl,
        sessionToken,
        sessionKey,
        publicOrigin,
      );
      result += "<BaseURL" + attributes + ">" +
        escapeXmlText(protectedValue) + "</BaseURL>";
    } else {
      // Nested relative BaseURL values must stay relative to their protected
      // parent. Resolving each one against manifestUrl discards hierarchy.
      result += match[0];
    }

    cursor = match.index + match[0].length;
  }

  return result + source.slice(cursor);
}

function isDashExternalReference(value) {
  return isAbsoluteHttpReference(value) || /^\//.test(String(value || ""));
}

async function protectDashBaseReference(
  value,
  manifestUrl,
  sessionToken,
  sessionKey,
  publicOrigin,
) {
  const absolute = new URL(value, manifestUrl).toString();
  const parts = splitDashTemplateBase(absolute);
  const sealed = await encryptTarget(parts.base, sessionKey);
  return publicOrigin + "/p/" + sessionToken + "/b/" + sealed + "/" + parts.tail;
}

async function protectDashReference(
  value,
  manifestUrl,
  sessionToken,
  sessionKey,
  publicOrigin,
) {
  const absolute = new URL(value, manifestUrl).toString();
  if (absolute.includes("$")) {
    const parts = splitDashTemplateBase(absolute);
    const sealedBase = await encryptTarget(parts.base, sessionKey);
    return publicOrigin + "/p/" + sessionToken + "/b/" +
      sealedBase + "/" + parts.tail;
  }

  const sealed = await encryptTarget(absolute, sessionKey);
  return publicOrigin + "/p/" + sessionToken + "/" + sealed;
}

function splitDashTemplateBase(absolute) {
  const marker = absolute.indexOf("$");
  if (marker < 0) {
    return { base: absolute, tail: "" };
  }

  const parsed = new URL(absolute);
  const prefix = absolute.slice(0, marker);
  const slash = prefix.lastIndexOf("/");
  const minimum = parsed.origin.length;
  if (slash < minimum) {
    throw new Error("Unsupported DASH template URL.");
  }

  return {
    base: absolute.slice(0, slash + 1),
    tail: absolute.slice(slash + 1),
  };
}

function hasRootDashBaseUrl(text) {
  const source = String(text || "");
  const root = /<MPD\b[^>]*>/i.exec(source);
  if (!root) return false;

  const start = (root.index || 0) + root[0].length;
  const remainder = source.slice(start);
  const firstPeriod = /<Period\b/i.exec(remainder);
  const rootChildren = firstPeriod
    ? remainder.slice(0, firstPeriod.index)
    : remainder;

  return /<BaseURL\b/i.test(rootChildren);
}

function isAbsoluteHttpReference(value) {
  return /^https?:\/\//i.test(value) || /^\/\//.test(value);
}

function stripXmlText(value) {
  return String(value || "").replace(/<[^>]*>/g, "").trim();
}

function decodeXmlText(value) {
  return String(value || "")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

function escapeXmlText(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function escapeXmlAttribute(value, quote) {
  let result = escapeXmlText(value);
  if (quote === '"') result = result.replace(/"/g, "&quot;");
  if (quote === "'") result = result.replace(/'/g, "&apos;");
  return result;
}

async function replaceAsync(input, regex, replacer) {
  let result = "";
  let cursor = 0;
  regex.lastIndex = 0;
  let match;

  while ((match = regex.exec(input)) !== null) {
    result += input.slice(cursor, match.index);
    result += await replacer(...match);
    cursor = match.index + match[0].length;
    if (match[0].length === 0) regex.lastIndex += 1;
  }

  return result + input.slice(cursor);
}

async function playbackSessionKey(secret) {
  const material = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(
      "nca-playback-key-v1:" + String(secret || ""),
    ),
  );
  return crypto.subtle.importKey(
    "raw",
    material,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

async function encryptPlaybackSession(session, secret) {
  const key = await playbackSessionKey(secret);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(JSON.stringify(session));
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: PLAYBACK_SESSION_AAD,
      tagLength: 128,
    },
    key,
    plain,
  ));
  const combined = new Uint8Array(iv.length + ciphertext.length);
  combined.set(iv, 0);
  combined.set(ciphertext, iv.length);
  return bytesToBase64Url(combined);
}

async function decryptPlaybackSession(token, secret) {
  const combined = base64UrlToBytes(token);
  if (combined.length <= 28) throw new Error("Invalid playback token.");
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const key = await playbackSessionKey(secret);
  const plain = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv,
      additionalData: PLAYBACK_SESSION_AAD,
      tagLength: 128,
    },
    key,
    ciphertext,
  );
  const session = JSON.parse(new TextDecoder().decode(plain));
  if (!session || typeof session !== "object") {
    throw new Error("Invalid playback session.");
  }
  return session;
}

async function encryptTarget(targetUrl, sessionKey) {
  const rawKey = base64UrlToBytes(sessionKey);
  const key = await crypto.subtle.importKey(
    "raw", rawKey, { name: "AES-GCM" }, false, ["encrypt"],
  );
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(targetUrl);
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv }, key, encoded,
  ));
  const combined = new Uint8Array(iv.length + ciphertext.length);
  combined.set(iv, 0);
  combined.set(ciphertext, iv.length);
  return bytesToBase64Url(combined);
}

async function decryptTarget(token, sessionKey) {
  const combined = base64UrlToBytes(token);
  if (combined.length <= 12) throw new Error("Invalid token.");
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const key = await crypto.subtle.importKey(
    "raw", base64UrlToBytes(sessionKey), { name: "AES-GCM" }, false, ["decrypt"],
  );
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv }, key, ciphertext,
  );
  return new TextDecoder().decode(plain);
}

function bytesToBase64Url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlToBytes(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = normalized.length % 4 === 0 ? "" : "=".repeat(4 - normalized.length % 4);
  const binary = atob(normalized + padding);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function allowRequest(request, env, scope, limit) {
  // Soft per-isolate limiter. This intentionally avoids Workers KV so rate
  // limiting cannot consume the account's daily KV operation allowance.
  const address =
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For") ||
    "unknown";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(address),
  );
  const id = bytesToBase64Url(new Uint8Array(digest)).slice(0, 22);
  const bucket = Math.floor(Date.now() / 60000);
  const key = scope + ":" + id + ":" + bucket;
  const now = Date.now();

  if (SOFT_RATE_LIMITS.size > 2048) {
    for (const [candidate, value] of SOFT_RATE_LIMITS.entries()) {
      if (!value || value.expiresAt <= now) {
        SOFT_RATE_LIMITS.delete(candidate);
      }
    }
  }

  const current = SOFT_RATE_LIMITS.get(key);
  const count = current?.count || 0;
  if (count >= limit) return false;

  SOFT_RATE_LIMITS.set(key, {
    count: count + 1,
    expiresAt: now + 2 * 60 * 1000,
  });
  return true;
}

function compareMatches(a, b) {
  const aTime = Date.parse(String(a.kickoff_at || ""));
  const bTime = Date.parse(String(b.kickoff_at || ""));
  if (Number.isFinite(aTime) && Number.isFinite(bTime) && aTime !== bTime) {
    return aTime - bTime;
  }
  return Number(a.sort_order || 0) - Number(b.sort_order || 0);
}

function compareLinks(a, b) {
  const health = healthRank(a.health_status) - healthRank(b.health_status);
  if (health !== 0) return health;
  const format = formatRank(a) - formatRank(b);
  if (format !== 0) return format;
  return Number(a.priority || 100) - Number(b.priority || 100);
}

function healthRank(value) {
  switch (String(value || "unknown")) {
    case "healthy": return 0;
    case "unknown": return 1;
    case "slow": return 2;
    default: return 3;
  }
}

function formatRank(link) {
  const type = String(link.stream_type || "auto").toLowerCase();
  const url = String(link.stream_url || "").toLowerCase();
  if (type === "hls" || type === "m3u8" || url.includes(".m3u8")) return 0;
  if (type === "dash" || type === "mpd" || url.includes(".mpd")) return 1;
  if (type === "mp4" || url.includes(".mp4")) return 2;
  if (type === "auto") return 3;
  if (type === "flv" || url.includes(".flv")) return 4;
  return 5;
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,HEAD,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey, Range, Cache-Control",
    "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  };
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
      ...extraHeaders,
    },
  });
}
