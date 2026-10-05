export interface Env {
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  GITHUB_MIRROR_URL?: string;
  PLAYBACK_TOKENS?: KVNamespace;
}

const DEFAULT_MIRROR =
  "https://raw.githubusercontent.com/" +
  "nyeinchanaung75299-eng/football-stream-app/" +
  "feed/public/matches.json";

const MATCH_FIELDS = [
  "id",
  "league",
  "home_team",
  "away_team",
  "home_logo_url",
  "away_logo_url",
  "kickoff_at",
  "is_live",
  "sort_order",
  "home_score",
  "away_score",
  "status_short",
  "status_elapsed",
  "is_finished",
  "is_featured",
  "publish_state",
  "last_score_sync_at",
  "updated_at",
];

const LINK_FIELDS = [
  "id",
  "label",
  "resolution",
  "stream_type",
  "stream_url",
  "referer",
  "origin",
  "key_id",
  "key_data",
  "use_webview",
  "webview_url",
  "is_active",
  "priority",
  "available_from",
  "expires_at",
  "health_status",
];


export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }

    const adminFunctionRoute = url.pathname.match(
      /^\/admin\/functions\/(football-fixtures|football-score-sync|stream-health|soco-links|source-match-list)$/,
    );

    if (adminFunctionRoute && request.method === "POST") {
      return handleAdminFunction(
        request,
        adminFunctionRoute[1],
        env,
      );
    }

    const protectedPlaybackRoute = url.pathname.match(
      /^\/p\/([A-Za-z0-9_-]+)(?:\/([A-Za-z0-9_-]+))?$/,
    );

    if (
      protectedPlaybackRoute &&
      (request.method === "GET" || request.method === "HEAD")
    ) {
      return handleProtectedPlayback(
        request,
        protectedPlaybackRoute[1],
        protectedPlaybackRoute[2] ?? null,
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
        admin_function_proxy: true,
        now: new Date().toISOString(),
      });
    }

    if (url.pathname === "/matches") {
      return handleMatches(url, env, ctx);
    }

    const streamRoute = url.pathname.match(
      /^\/matches\/([^/]+)\/streams$/,
    );

    if (streamRoute) {
      return handleStreams(
        decodeURIComponent(streamRoute[1]),
        env,
        ctx,
        url.origin,
      );
    }

    return json({ error: "Not found." }, 404);
  },
};

async function handleAdminFunction(
  request: Request,
  functionName: string,
  env: Env,
) {
  const base = env.SUPABASE_URL?.trim() ?? "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";
  const authorization = request.headers.get("Authorization")?.trim() ?? "";

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

  let upstreamResponse: Response;
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
    return json(
      { error: "Backend function is temporarily unreachable." },
      502,
      { "Cache-Control": "no-store" },
    );
  }

  const headers = new Headers(upstreamResponse.headers);
  for (const [keyName, value] of Object.entries(corsHeaders())) {
    headers.set(keyName, value);
  }
  headers.set("Cache-Control", "no-store");

  return new Response(upstreamResponse.body, {
    status: upstreamResponse.status,
    headers,
  });
}

async function handleMatches(
  requestUrl: URL,
  env: Env,
  ctx: ExecutionContext,
) {
  try {
    // Do not edge-cache match metadata. Separate custom-domain/workers.dev
    // cache keys can otherwise disagree briefly and make WATCH flicker between
    // available and NOT READY when the user refreshes or toggles VPN.
    const loaded = await loadMatchRows(env);

    const matches = loaded.rows
      .map((raw) => sanitizeMatchMetadata(raw))
      .sort(compareMatches);

    return json(
      {
        ok: true,
        source: loaded.source,
        matches,
        generated_at: new Date().toISOString(),
      },
      200,
      {
        "Cache-Control": "no-store, max-age=0",
      },
    );
  } catch (error) {
    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
      502,
      {
        "Cache-Control": "no-store, max-age=0",
      },
    );
  }
}

async function handleStreams(
  matchId: string,
  env: Env,
  ctx: ExecutionContext,
  publicOrigin: string,
) {
  if (!/^[0-9a-fA-F-]{16,64}$/.test(matchId)) {
    return json({ error: "Invalid match id." }, 400);
  }

  const base = env.SUPABASE_URL?.trim() ?? "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";

  if (!base || !key || !env.PLAYBACK_TOKENS) {
    return json(
      { error: "Protected playback is not configured." },
      503,
      { "Cache-Control": "no-store, max-age=0" },
    );
  }

  const commonHeaders = {
    apikey: key,
    Accept: "application/json",
  };

  const matchUrl = new URL(
    base.replace(/\/+$/, "") + "/rest/v1/matches",
  );
  matchUrl.searchParams.set("select", "id");
  matchUrl.searchParams.set("id", "eq." + matchId);
  matchUrl.searchParams.set("is_active", "eq.true");
  matchUrl.searchParams.set("publish_state", "eq.published");
  matchUrl.searchParams.set("is_featured", "eq.true");
  matchUrl.searchParams.set("limit", "1");

  try {
    const matchResponse = await fetch(matchUrl, { headers: commonHeaders });
    if (!matchResponse.ok) {
      return json(
        {
          error: "Match validation upstream unavailable.",
          upstream_status: matchResponse.status,
        },
        502,
        { "Cache-Control": "no-store, max-age=0" },
      );
    }

    const matchRows = await matchResponse.json<unknown>();
    if (!Array.isArray(matchRows) || matchRows.length === 0) {
      return json(
        { error: "Match not found." },
        404,
        { "Cache-Control": "no-store, max-age=0" },
      );
    }

    const streamUrl = new URL(
      base.replace(/\/+$/, "") + "/rest/v1/stream_links",
    );
    streamUrl.searchParams.set("select", LINK_FIELDS.join(","));
    streamUrl.searchParams.set("match_id", "eq." + matchId);
    streamUrl.searchParams.set("is_active", "eq.true");
    streamUrl.searchParams.set("order", "priority.asc,sort_order.asc");

    const streamResponse = await fetch(streamUrl, {
      headers: commonHeaders,
    });

    if (!streamResponse.ok) {
      return json(
        {
          error: "Stream configuration upstream unavailable.",
          upstream_status: streamResponse.status,
        },
        502,
        { "Cache-Control": "no-store, max-age=0" },
      );
    }

    const rawStreams = await streamResponse.json<unknown>();
    const streams = await protectedClientLinks(
      rawStreams,
      env,
      publicOrigin,
    );

    return json(
      {
        ok: true,
        match_id: matchId,
        streams,
        stream_count: streams.length,
        protected_playback: true,
        generated_at: new Date().toISOString(),
      },
      200,
      {
        "Cache-Control": "no-store, max-age=0",
      },
    );
  } catch (_) {
    return json(
      { error: "Stream configuration upstream unavailable." },
      502,
      { "Cache-Control": "no-store, max-age=0" },
    );
  }
}

async function loadMatchRows(
  env: Env,
): Promise<{
  rows: unknown[];
  source: "supabase" | "github";
}> {
  const base = env.SUPABASE_URL?.trim() ?? "";
  const key = env.SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";

  if (base && key) {
    try {
      const headers = {
        apikey: key,
        Accept: "application/json",
      };

      const matchesUrl = new URL(
        base.replace(/\/+$/, "") + "/rest/v1/matches",
      );
      matchesUrl.searchParams.set("select", MATCH_FIELDS.join(","));
      matchesUrl.searchParams.set("is_active", "eq.true");
      matchesUrl.searchParams.set("publish_state", "eq.published");
      matchesUrl.searchParams.set("is_featured", "eq.true");
      matchesUrl.searchParams.set("order", "kickoff_at.asc,sort_order.asc");

      const matchesResponse = await fetch(matchesUrl, { headers });
      if (matchesResponse.ok) {
        const matches = await matchesResponse.json<unknown>();

        const linksUrl = new URL(
          base.replace(/\/+$/, "") + "/rest/v1/stream_links",
        );
        linksUrl.searchParams.set(
          "select",
          ["match_id", ...LINK_FIELDS, "sort_order"].join(","),
        );
        linksUrl.searchParams.set("is_active", "eq.true");
        linksUrl.searchParams.set("order", "priority.asc,sort_order.asc");

        const linksResponse = await fetch(linksUrl, { headers });
        const links = linksResponse.ok
          ? await linksResponse.json<unknown>()
          : [];

        if (Array.isArray(matches)) {
          const grouped = new Map<string, unknown[]>();
          if (Array.isArray(links)) {
            for (const raw of links) {
              const link = raw as Record<string, unknown>;
              const matchId = String(link.match_id ?? "");
              if (!matchId) continue;
              const list = grouped.get(matchId) ?? [];
              list.push(link);
              grouped.set(matchId, list);
            }
          }

          return {
            source: "supabase",
            rows: matches.map((raw) => {
              const match = raw as Record<string, unknown>;
              return {
                ...match,
                stream_links: grouped.get(String(match.id ?? "")) ?? [],
              };
            }),
          };
        }
      }
    } catch (_) {
      // Use GitHub fallback below.
    }
  }

  const mirror =
    env.GITHUB_MIRROR_URL?.trim() ||
    DEFAULT_MIRROR;

  const response = await fetch(mirror, {
    headers: {
      Accept: "application/json",
      "Cache-Control": "no-cache",
    },
  });

  if (!response.ok) {
    throw new Error("Public match mirror unavailable.");
  }

  const rows = await response.json<unknown>();
  if (!Array.isArray(rows)) {
    throw new Error("Invalid mirror response.");
  }

  return {
    rows,
    source: "github",
  };
}

function sanitizeMatchMetadata(
  raw: unknown,
) {
  const source = {
    ...(raw as Record<string, unknown>),
  };

  const links = Array.isArray(source.stream_links)
    ? source.stream_links
    : [];

  const result:
    Record<string, unknown> = {};

  for (const field of MATCH_FIELDS) {
    result[field] = source[field];
  }

  // WATCH availability must not depend on whether the viewer can reach
  // Supabase directly. Advertise the number of active configured lines using
  // metadata only; the /streams endpoint still returns only safe public URLs.
  // This keeps the WATCH button stable on VPN-off/restricted networks without
  // exposing protected playback credentials.
  result.stream_count = advertisedLinkCount(
    links.length > 0 ? links : source.stream_count,
  );
  result.public_stream_count = 0;

  return result;
}

function advertisedLinkCount(raw: unknown) {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.max(0, Math.floor(raw));
  }

  const links = Array.isArray(raw) ? raw : [];
  const now = Date.now();

  return links.filter((item) => {
    const link = item as Record<string, unknown>;
    if (link.is_active !== true) return false;

    const availableFrom = Date.parse(
      String(link.available_from ?? ""),
    );
    if (Number.isFinite(availableFrom) && now < availableFrom) {
      return false;
    }

    const expiresAt = Date.parse(
      String(link.expires_at ?? ""),
    );
    if (Number.isFinite(expiresAt) && now >= expiresAt) {
      return false;
    }

    // Home WATCH currently opens the native stream picker. WebView-only
    // entries are managed separately and should not inflate its line count.
    if (link.use_webview === true) return false;

    return String(link.stream_url ?? "").trim().length > 0;
  }).length;
}

async function protectedClientLinks(
  raw: unknown,
  env: Env,
  publicOrigin: string,
) {
  if (!env.PLAYBACK_TOKENS) return [];

  const links = Array.isArray(raw) ? raw : [];
  const now = Date.now();
  const ttlSeconds = 4 * 60 * 60;
  const output: Record<string, unknown>[] = [];

  for (const item of links) {
    const link = item as Record<string, unknown>;
    if (link.is_active !== true) continue;

    const availableFrom = Date.parse(String(link.available_from ?? ""));
    if (Number.isFinite(availableFrom) && now < availableFrom) continue;

    const expiresAt = Date.parse(String(link.expires_at ?? ""));
    if (Number.isFinite(expiresAt) && now >= expiresAt) continue;

    if (link.use_webview === true) continue;

    const upstreamUrl = String(link.stream_url ?? "").trim();
    if (!upstreamUrl) continue;

    // ClearKey material must never be sent to a public client. Encrypted DASH
    // needs a dedicated license flow, so skip those entries here.
    if (
      String(link.key_id ?? "").trim() ||
      String(link.key_data ?? "").trim()
    ) {
      continue;
    }

    const sourceExpirySeconds = Number.isFinite(expiresAt)
      ? Math.max(60, Math.floor((expiresAt - now) / 1000))
      : ttlSeconds;
    const sessionTtl = Math.max(
      60,
      Math.min(ttlSeconds, sourceExpirySeconds),
    );

    const token = randomToken();
    const secretBytes = crypto.getRandomValues(new Uint8Array(32));
    const session = {
      u: upstreamUrl,
      r: String(link.referer ?? "").trim(),
      o: String(link.origin ?? "").trim(),
      k: bytesToBase64Url(secretBytes),
      e: Math.floor(Date.now() / 1000) + sessionTtl,
    };

    await env.PLAYBACK_TOKENS.put(
      "s:" + token,
      JSON.stringify(session),
      { expirationTtl: sessionTtl },
    );

    output.push({
      id: link.id,
      label: link.label,
      resolution: link.resolution,
      stream_type: link.stream_type,
      stream_url:
        publicOrigin.replace(/\/+$/, "") + "/p/" + token,
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

async function handleProtectedPlayback(
  request: Request,
  sessionToken: string,
  encryptedTarget: string | null,
  env: Env,
) {
  if (!env.PLAYBACK_TOKENS) {
    return json({ error: "Protected playback is unavailable." }, 503);
  }

  const raw = await env.PLAYBACK_TOKENS.get("s:" + sessionToken);
  if (!raw) {
    return json(
      { error: "Playback session expired." },
      410,
      { "Cache-Control": "no-store" },
    );
  }

  let session: {
    u: string;
    r?: string;
    o?: string;
    k: string;
    e: number;
  };

  try {
    session = JSON.parse(raw);
  } catch (_) {
    return json({ error: "Invalid playback session." }, 410);
  }

  if (
    !session.u ||
    !session.k ||
    !Number.isFinite(session.e) ||
    session.e <= Math.floor(Date.now() / 1000)
  ) {
    return json(
      { error: "Playback session expired." },
      410,
      { "Cache-Control": "no-store" },
    );
  }

  let upstreamUrl = session.u;
  if (encryptedTarget) {
    try {
      upstreamUrl = await decryptTarget(
        encryptedTarget,
        session.k,
      );
    } catch (_) {
      return json({ error: "Invalid protected media URL." }, 400);
    }
  }

  let upstream: URL;
  try {
    upstream = new URL(upstreamUrl);
  } catch (_) {
    return json({ error: "Invalid upstream URL." }, 400);
  }

  if (upstream.protocol !== "http:" && upstream.protocol !== "https:") {
    return json({ error: "Unsupported upstream protocol." }, 400);
  }

  const headers = new Headers();
  headers.set("Accept", request.headers.get("Accept") || "*/*");
  headers.set(
    "User-Agent",
    request.headers.get("User-Agent") ||
      "Mozilla/5.0 NCA-Protected-Playback",
  );

  const range = request.headers.get("Range");
  if (range) headers.set("Range", range);
  if (session.r) headers.set("Referer", session.r);
  if (session.o) headers.set("Origin", session.o);

  let response: Response;
  try {
    response = await fetch(upstream, {
      method: request.method,
      headers,
      redirect: "follow",
    });
  } catch (_) {
    return json(
      { error: "Playback upstream unavailable." },
      502,
      { "Cache-Control": "no-store" },
    );
  }

  const contentType =
    response.headers.get("Content-Type")?.toLowerCase() ?? "";
  const finalUrl = response.url || upstream.toString();
  const path = new URL(finalUrl).pathname.toLowerCase();
  const isHls =
    contentType.includes("mpegurl") ||
    path.endsWith(".m3u8");

  if (
    request.method === "GET" &&
    response.ok &&
    isHls
  ) {
    const playlist = await response.text();
    const protectedPlaylist = await rewriteHlsPlaylist(
      playlist,
      finalUrl,
      sessionToken,
      session.k,
      new URL(request.url).origin,
    );

    return new Response(protectedPlaylist, {
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
    "Content-Type",
    "Content-Length",
    "Content-Range",
    "Accept-Ranges",
    "ETag",
    "Last-Modified",
  ]) {
    const value = response.headers.get(name);
    if (value) outHeaders.set(name, value);
  }

  return new Response(
    request.method === "HEAD" ? null : response.body,
    {
      status: response.status,
      headers: outHeaders,
    },
  );
}

async function rewriteHlsPlaylist(
  text: string,
  baseUrl: string,
  sessionToken: string,
  sessionKey: string,
  publicOrigin: string,
) {
  const lines = text.split(/\r?\n/);
  const output: string[] = [];

  for (const original of lines) {
    const line = original.trim();

    if (!line) {
      output.push(original);
      continue;
    }

    if (line.startsWith("#")) {
      output.push(
        await rewriteHlsTagUris(
          original,
          baseUrl,
          sessionToken,
          sessionKey,
          publicOrigin,
        ),
      );
      continue;
    }

    const absolute = new URL(line, baseUrl).toString();
    const sealed = await encryptTarget(absolute, sessionKey);
    output.push(
      publicOrigin.replace(/\/+$/, "") +
        "/p/" +
        sessionToken +
        "/" +
        sealed,
    );
  }

  return output.join("\n");
}

async function rewriteHlsTagUris(
  line: string,
  baseUrl: string,
  sessionToken: string,
  sessionKey: string,
  publicOrigin: string,
) {
  const regex = /URI="([^"]+)"/g;
  let match: RegExpExecArray | null;
  let cursor = 0;
  let result = "";

  while ((match = regex.exec(line)) !== null) {
    result += line.slice(cursor, match.index);
    const absolute = new URL(match[1], baseUrl).toString();
    const sealed = await encryptTarget(absolute, sessionKey);
    result +=
      'URI="' +
      publicOrigin.replace(/\/+$/, "") +
      "/p/" +
      sessionToken +
      "/" +
      sealed +
      '"';
    cursor = match.index + match[0].length;
  }

  return result + line.slice(cursor);
}

async function encryptTarget(
  targetUrl: string,
  sessionKey: string,
) {
  const rawKey = base64UrlToBytes(sessionKey);
  const key = await crypto.subtle.importKey(
    "raw",
    rawKey,
    { name: "AES-GCM" },
    false,
    ["encrypt"],
  );
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(targetUrl);
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      key,
      encoded,
    ),
  );
  const combined = new Uint8Array(iv.length + ciphertext.length);
  combined.set(iv, 0);
  combined.set(ciphertext, iv.length);
  return bytesToBase64Url(combined);
}

async function decryptTarget(
  token: string,
  sessionKey: string,
) {
  const combined = base64UrlToBytes(token);
  if (combined.length <= 12) throw new Error("Invalid token.");

  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const key = await crypto.subtle.importKey(
    "raw",
    base64UrlToBytes(sessionKey),
    { name: "AES-GCM" },
    false,
    ["decrypt"],
  );

  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(plain);
}

function randomToken() {
  return bytesToBase64Url(
    crypto.getRandomValues(new Uint8Array(24)),
  );
}

function bytesToBase64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64UrlToBytes(value: string) {
  const normalized =
    value.replace(/-/g, "+").replace(/_/g, "/");
  const padding =
    normalized.length % 4 === 0
      ? ""
      : "=".repeat(4 - (normalized.length % 4));
  const binary = atob(normalized + padding);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function compareMatches(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
) {
  const aTime =
    Date.parse(String(a.kickoff_at ?? ""));
  const bTime =
    Date.parse(String(b.kickoff_at ?? ""));

  if (
    Number.isFinite(aTime) &&
    Number.isFinite(bTime) &&
    aTime !== bTime
  ) {
    return aTime - bTime;
  }

  return (
    Number(a.sort_order ?? 0) -
    Number(b.sort_order ?? 0)
  );
}

function compareLinks(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
) {
  const health =
    healthRank(a.health_status) -
    healthRank(b.health_status);

  if (health !== 0) return health;

  const format =
    formatRank(a) -
    formatRank(b);

  if (format !== 0) return format;

  return (
    Number(a.priority ?? 100) -
    Number(b.priority ?? 100)
  );
}

function healthRank(value: unknown) {
  switch (
    String(value ?? "unknown")
  ) {
    case "healthy":
      return 0;
    case "unknown":
      return 1;
    case "slow":
      return 2;
    default:
      return 3;
  }
}

function formatRank(
  link: Record<string, unknown>,
) {
  const type =
    String(
      link.stream_type ?? "auto",
    ).toLowerCase();

  const url =
    String(
      link.stream_url ?? "",
    ).toLowerCase();

  if (
    type === "hls" ||
    type === "m3u8" ||
    url.includes(".m3u8")
  ) {
    return 0;
  }

  if (
    type === "dash" ||
    type === "mpd" ||
    url.includes(".mpd")
  ) {
    return 1;
  }

  if (
    type === "mp4" ||
    url.includes(".mp4")
  ) {
    return 2;
  }

  if (type === "auto") return 3;

  if (
    type === "flv" ||
    url.includes(".flv")
  ) {
    return 4;
  }

  return 5;
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods":
      "GET,OPTIONS",
    "Access-Control-Allow-Headers":
      "Authorization, Content-Type, apikey, Range",
    "Access-Control-Expose-Headers":
      "Content-Length, Content-Range, Accept-Ranges",
  };
}

function withCors(
  response: Response,
) {
  const headers =
    new Headers(response.headers);

  for (
    const [key, value] of
    Object.entries(corsHeaders())
  ) {
    headers.set(key, value);
  }

  return new Response(
    response.body,
    {
      status: response.status,
      headers,
    },
  );
}

function json(
  data: unknown,
  status = 200,
  extraHeaders:
    Record<string, string> = {},
) {
  return new Response(
    JSON.stringify(data),
    {
      status,
      headers: {
        "Content-Type":
          "application/json",
        ...corsHeaders(),
        ...extraHeaders,
      },
    },
  );
}
