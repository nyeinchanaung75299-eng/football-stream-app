const DEFAULT_MIRROR =
  "https://raw.githubusercontent.com/" +
  "nyeinchanaung75299-eng/football-stream-app/" +
  "feed/public/matches.json";

const MATCH_FIELDS = [
  "id", "league", "home_team", "away_team", "home_logo_url",
  "away_logo_url", "kickoff_at", "is_live", "sort_order",
  "home_score", "away_score", "status_short", "status_elapsed",
  "is_finished", "is_featured", "publish_state",
  "last_score_sync_at", "updated_at",
];

const LINK_FIELDS = [
  "id", "label", "resolution", "stream_type", "stream_url",
  "referer", "origin", "key_id", "key_data", "use_webview",
  "webview_url", "is_active", "priority", "available_from",
  "expires_at", "health_status",
];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const adminFunctionRoute = url.pathname.match(
      /^\/admin\/functions\/(football-fixtures|football-score-sync|stream-health|soco-links|source-match-list)$/,
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
        protected_playback: Boolean(env.PLAYBACK_TOKENS),
        admin_function_proxy: true,
        now: new Date().toISOString(),
      });
    }

    if (url.pathname === "/matches") {
      return handleMatches(env);
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

async function handleStreams(request, matchId, env, publicOrigin) {
  if (!/^[0-9a-fA-F-]{16,64}$/.test(matchId)) {
    return json({ error: "Invalid match id." }, 400);
  }

  const base = env.SUPABASE_URL?.trim() || "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() || "";
  const backendSecret = env.PLAYBACK_BACKEND_SECRET?.trim() || "";
  if (!base || !key || !backendSecret || !env.PLAYBACK_TOKENS) {
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
    const blockedStreams = blockedClientLinks(rawStreams);

    return json({
      ok: true,
      match_id: matchId,
      streams,
      blocked_streams: blockedStreams,
      stream_count: streams.length,
      blocked_stream_count: blockedStreams.length,
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

      const matchesResponse = await fetch(matchesUrl, { headers });
      if (matchesResponse.ok) {
        const matches = await matchesResponse.json();

        const countsUrl = new URL(
          base.replace(/\/+$/, "") + "/rest/v1/match_stream_counts",
        );
        countsUrl.searchParams.set("select", "match_id,stream_count");

        const countsResponse = await fetch(countsUrl, { headers });
        const counts = countsResponse.ok ? await countsResponse.json() : [];

        if (Array.isArray(matches)) {
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
  const response = await fetch(mirror, {
    headers: { Accept: "application/json", "Cache-Control": "no-cache" },
  });
  if (!response.ok) throw new Error("Public match mirror unavailable.");
  const rows = await response.json();
  if (!Array.isArray(rows)) throw new Error("Invalid mirror response.");
  return { rows, source: "github" };
}

function sanitizeMatchMetadata(raw) {
  const source = { ...raw };
  const links = Array.isArray(source.stream_links) ? source.stream_links : [];
  const result = {};
  for (const field of MATCH_FIELDS) result[field] = source[field];
  result.stream_count = advertisedLinkCount(
    links.length > 0 ? links : source.stream_count,
  );
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
    if (
      String(link.key_id || "").trim() ||
      String(link.key_data || "").trim()
    ) {
      return false;
    }
    const streamUrl = String(link.stream_url || "").trim();
    return streamUrl.length > 0;
  }).length;
}

function blockedClientLinks(raw) {
  const links = Array.isArray(raw) ? raw : [];
  const now = Date.now();
  return links
    .filter((link) => {
      if (link.is_active !== true || link.use_webview === true) return false;
      const availableFrom = Date.parse(String(link.available_from || ""));
      if (Number.isFinite(availableFrom) && now < availableFrom) return false;
      const expiresAt = Date.parse(String(link.expires_at || ""));
      if (Number.isFinite(expiresAt) && now >= expiresAt) return false;
      return Boolean(
        String(link.key_id || "").trim() ||
        String(link.key_data || "").trim()
      );
    })
    .map((link) => ({
      id: link.id,
      label: link.label,
      resolution: link.resolution,
      stream_type: link.stream_type,
      stream_url: null,
      referer: null,
      origin: null,
      key_id: null,
      key_data: null,
      use_webview: false,
      webview_url: null,
      is_active: true,
      priority: link.priority,
      available_from: link.available_from,
      expires_at: link.expires_at,
      health_status: link.health_status,
      blocked_reason: "keyed_dash_not_exposed",
      viewer_message:
        "Keyed/ClearKey DASH is stored but is not exposed by the public Viewer. Add a non-DRM DASH or HLS/FairPlay-compatible backup.",
    }))
    .sort(compareLinks);
}

async function protectedClientLinks(raw, env, publicOrigin) {
  if (!env.PLAYBACK_TOKENS) return [];
  const links = Array.isArray(raw) ? raw : [];
  const now = Date.now();
  const nowSeconds = Math.floor(now / 1000);
  const idleTtl = 30 * 60;
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
    if (String(link.key_id || "").trim() || String(link.key_data || "").trim()) {
      continue;
    }

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
    const ttl = Math.max(60, Math.min(idleTtl, maxTtl));
    const sessionToken = randomToken();
    const sessionKey = crypto.getRandomValues(new Uint8Array(32));
    const session = {
      u: upstreamUrl,
      r: String(link.referer || "").trim(),
      o: String(link.origin || "").trim(),
      t: streamType,
      k: bytesToBase64Url(sessionKey),
      e: nowSeconds + ttl,
      x: nowSeconds + maxTtl,
    };

    await env.PLAYBACK_TOKENS.put(
      "s:" + sessionToken,
      JSON.stringify(session),
      { expirationTtl: ttl },
    );

    output.push({
      id: link.id,
      label: link.label,
      resolution: link.resolution,
      stream_type: link.stream_type,
      stream_url: publicOrigin.replace(/\/+$/, "") + "/p/" + sessionToken,
      referer: null,
      origin: null,
      key_id: null,
      key_data: null,
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
  if (!env.PLAYBACK_TOKENS) {
    return json({ error: "Protected playback is unavailable." }, 503);
  }

  const raw = await env.PLAYBACK_TOKENS.get("s:" + sessionToken);
  if (!raw) {
    return json({ error: "Playback session expired." }, 410, {
      "Cache-Control": "no-store",
    });
  }

  let session;
  try {
    session = JSON.parse(raw);
  } catch (_) {
    return json({ error: "Invalid playback session." }, 410);
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (
    !session.u || !session.k || !Number.isFinite(session.e) ||
    session.e <= nowSeconds ||
    (Number.isFinite(session.x) && session.x <= nowSeconds)
  ) {
    return json({ error: "Playback session expired." }, 410, {
      "Cache-Control": "no-store",
    });
  }

  if (
    Number.isFinite(session.x) &&
    session.e - nowSeconds < 10 * 60
  ) {
    const nextTtl = Math.max(
      60,
      Math.min(30 * 60, session.x - nowSeconds),
    );
    session.e = nowSeconds + nextTtl;
    await env.PLAYBACK_TOKENS.put(
      "s:" + sessionToken,
      JSON.stringify(session),
      { expirationTtl: nextTtl },
    );
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

  let response;
  try {
    response = await fetch(upstream, {
      method: request.method,
      headers,
      redirect: "follow",
    });
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

  rewritten = await replaceAsync(
    rewritten,
    /<BaseURL(\b[^>]*)>([\s\S]*?)<\/BaseURL>/gi,
    async (match, attributes, rawValue) => {
      const value = decodeXmlText(stripXmlText(rawValue));
      if (!value || value.startsWith("#") || /^urn:/i.test(value)) {
        return match;
      }
      const protectedValue = await protectDashBaseReference(
        value,
        manifestUrl,
        sessionToken,
        sessionKey,
        origin,
      );
      return "<BaseURL" + (attributes || "") + ">" +
        escapeXmlText(protectedValue) + "</BaseURL>";
    },
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
      if (!isAbsoluteHttpReference(value)) return match;
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

function randomToken() {
  return bytesToBase64Url(crypto.getRandomValues(new Uint8Array(24)));
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
  if (!env.PLAYBACK_TOKENS) return true;

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
  const key = "rl:" + scope + ":" + id + ":" + bucket;

  const raw = await env.PLAYBACK_TOKENS.get(key);
  const count = Number.parseInt(raw || "0", 10) || 0;
  if (count >= limit) return false;

  await env.PLAYBACK_TOKENS.put(
    key,
    String(count + 1),
    { expirationTtl: 120 },
  );
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
    "Access-Control-Allow-Methods": "GET,HEAD,OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey, Range",
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
