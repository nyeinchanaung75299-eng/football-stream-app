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

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.hostname.startsWith("supabase-api.")) {
      return handleSupabaseRelay(request, env);
    }

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const adminFunctionRoute = url.pathname.match(
      /^\/admin\/functions\/(football-fixtures|stream-health|soco-links|source-match-list)$/,
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
      /^\/sources\/(soco|yyzb|fawa|cola)\/streams$/,
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

    const sourceMatchesRoute = url.pathname.match(
      /^\/sources\/(soco|yyzb|fawa|cola)\/matches$/,
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
  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  if (!base || !key) {
    throw new Error("Source browser backend is not configured.");
  }

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
    },
  );

  const text = await response.text();
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
      action: "matches",
      source,
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
    return json({ error: "Too many source requests. Try again shortly." }, 429, {
      "Retry-After": "60",
      "Cache-Control": "no-store, max-age=0",
    });
  }

  let input = {};
  try {
    input = await request.json();
  } catch (_) {}

  try {
    const payload = await invokeViewerSourceFunction(env, {
      action: "streams",
      source,
      room_num: input?.room_num ?? null,
      schedule_id: input?.schedule_id ?? null,
      page_url: input?.page_url ?? null,
      source_id: input?.source_id ?? null,
      anchor_name: input?.anchor_name ?? null,
    });

    const rawLines = Array.isArray(payload?.lines) ? payload.lines : [];
    const roomKey = String(input?.room_num || input?.source_id || "room");
    const anchorName = String(input?.anchor_name || "").trim();
    const normalized = rawLines.map((line, index) => ({
      id: String(line?.id || source + ":" +
        String(input?.schedule_id || "match") + ":" + roomKey + ":" + index),
      label: anchorName
        ? anchorName + " • " + String(line?.label || line?.resolution || ("Line " + (index + 1)))
        : line?.label || line?.resolution || ("Line " + (index + 1)),
      resolution: line?.resolution || "Auto",
      stream_type: line?.stream_type || "auto",
      stream_url: line?.url || line?.stream_url || "",
      referer: line?.referer || "",
      origin: line?.origin || "",
      key_id: null,
      key_data: null,
      use_webview: false,
      webview_url: null,
      is_active: true,
      priority: Number(line?.priority || 100),
      available_from: null,
      expires_at: line?.expires_at || null,
      health_status: line?.health_status || "unknown",
    }));

    const streams = await protectedClientLinks(normalized, env, publicOrigin);
    return json({
      ok: true,
      source,
      streams,
      stream_count: streams.length,
      live_status: payload?.live_status ?? null,
      generated_at: new Date().toISOString(),
    }, 200, { "Cache-Control": "no-store, max-age=0" });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : String(error),
    }, Number(error?.status) || 502, {
      "Cache-Control": "no-store, max-age=0",
    });
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

  const commonHeaders = { apikey: key, Accept: "application/json" };
  const matchUrl = new URL(base.replace(/\/+$/, "") + "/rest/v1/matches");
  matchUrl.searchParams.set("select", "id");
  matchUrl.searchParams.set("id", "eq." + matchId);
  matchUrl.searchParams.set("is_active", "eq.true");
  matchUrl.searchParams.set("publish_state", "eq.published");
  matchUrl.searchParams.set("is_featured", "eq.true");
  matchUrl.searchParams.set("limit", "1");

  try {
    const matchResponse = await fetch(matchUrl, { headers: commonHeaders });
    if (!matchResponse.ok) {
      return json({
        error: "Match validation upstream unavailable.",
        upstream_status: matchResponse.status,
      }, 502, { "Cache-Control": "no-store, max-age=0" });
    }
    const matchRows = await matchResponse.json();
    if (!Array.isArray(matchRows) || matchRows.length === 0) {
      return json({ error: "Match not found." }, 404, {
        "Cache-Control": "no-store, max-age=0",
      });
    }

    const streamUrl = new URL(
      base.replace(/\/+$/, "") +
        "/rest/v1/rpc/get_stream_links_for_gateway",
    );

    const streamResponse = await fetch(streamUrl, {
      method: "POST",
      headers: {
        ...commonHeaders,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_match_id: matchId,
        p_secret: backendSecret,
      }),
    });
    if (!streamResponse.ok) {
      return json({
        error: "Stream configuration upstream unavailable.",
        upstream_status: streamResponse.status,
      }, 502, { "Cache-Control": "no-store, max-age=0" });
    }

    const rawStreams = await streamResponse.json();
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

async function loadMatchRows(env) {
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
    return { status: response.status, data: await response.json() };
  } finally {
    clearTimeout(timer);
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
      ? Math.max(60, Math.floor((expiresAt - now) / 1000))
      : maxLifetime;
    const maxTtl = Math.max(60, Math.min(maxLifetime, sourceTtl));
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

  let response;
  try {
    const fetchOptions = {
      method: request.method,
      headers,
      redirect: "follow",
    };
    if (liveManifestRequest) fetchOptions.cache = "no-store";
    response = await fetch(upstream, fetchOptions);
  } catch (_) {
    return json({ error: "Playback upstream unavailable." }, 502, {
      "Cache-Control": "no-store",
    });
  }

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

  if (request.method === "GET" && response.ok && isDash) {
    const manifest = await response.text();
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
    const playlist = await response.text();
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

  return new Response(request.method === "HEAD" ? null : response.body, {
    status: response.status,
    headers: outHeaders,
  });
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
