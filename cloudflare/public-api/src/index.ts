export interface Env {
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  GITHUB_MIRROR_URL?: string;
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

const SENSITIVE_QUERY_PARTS = [
  "token",
  "auth",
  "signature",
  "sig",
  "key",
  "expires",
  "expire",
  "policy",
  "jwt",
  "hdnts",
  "hdnea",
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
      /^\/admin\/functions\/(football-fixtures|football-score-sync|stream-health)$/,
    );

    if (adminFunctionRoute && request.method === "POST") {
      return handleAdminFunction(
        request,
        adminFunctionRoute[1],
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
  const cache = caches.default;
  const cacheKey = new Request(
    requestUrl.origin + "/matches",
  );

  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached);

  try {
    const loaded = await loadMatchRows(env);

    const matches = loaded.rows
      .map((raw) => sanitizeMatchMetadata(raw))
      .sort(compareMatches);

    const result = json(
      {
        ok: true,
        source: loaded.source,
        matches,
        generated_at: new Date().toISOString(),
      },
      200,
      {
        "Cache-Control": "public, max-age=20, s-maxage=45",
      },
    );

    ctx.waitUntil(cache.put(cacheKey, result.clone()));
    return result;
  } catch (error) {
    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
      502,
    );
  }
}

async function handleStreams(
  matchId: string,
  env: Env,
  ctx: ExecutionContext,
) {
  if (!/^[0-9a-fA-F-]{16,64}$/.test(matchId)) {
    return json({ error: "Invalid match id." }, 400);
  }

  const base = env.SUPABASE_URL?.trim() ?? "";
  const key =
    env.SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";

  if (!base || !key) {
    return json(
      {
        error:
          "Fresh stream configuration is not available.",
      },
      503,
    );
  }

  const cache = caches.default;
  const cacheKey = new Request(
    "https://cache.local/matches/" +
      encodeURIComponent(matchId) +
      "/streams",
  );

  const cached = await cache.match(cacheKey);
  if (cached) return withCors(cached);

  const select = [
    ...MATCH_FIELDS,
    "stream_links(" + LINK_FIELDS.join(",") + ")",
  ].join(",");

  const upstream = new URL(
    base.replace(/\/+$/, "") +
      "/rest/v1/matches",
  );

  upstream.searchParams.set("select", select);
  upstream.searchParams.set("id", "eq." + matchId);
  upstream.searchParams.set("is_active", "eq.true");
  upstream.searchParams.set(
    "publish_state",
    "eq.published",
  );
  upstream.searchParams.set("is_featured", "eq.true");
  upstream.searchParams.set("limit", "1");

  let response: Response;
  try {
    response = await fetch(upstream, {
      headers: {
        apikey: key,
        Accept: "application/json",
      },
    });
  } catch (_) {
    return json(
      { error: "Stream configuration upstream unavailable." },
      502,
    );
  }

  if (!response.ok) {
    return json(
      {
        error: "Stream configuration upstream unavailable.",
        upstream_status: response.status,
      },
      502,
    );
  }

  const rows = await response.json<unknown>();
  if (!Array.isArray(rows) || rows.length === 0) {
    return json({ error: "Match not found." }, 404);
  }

  const match =
    rows[0] as Record<string, unknown>;

  const streams = safeLinks(match.stream_links);

  const result = json(
    {
      ok: true,
      match_id: matchId,
      streams,
      generated_at: new Date().toISOString(),
    },
    200,
    {
      "Cache-Control": "public, max-age=8, s-maxage=15",
    },
  );

  ctx.waitUntil(cache.put(cacheKey, result.clone()));
  return result;
}

async function loadMatchRows(
  env: Env,
): Promise<{
  rows: unknown[];
  source: "supabase" | "github";
}> {
  const base = env.SUPABASE_URL?.trim() ?? "";
  const key =
    env.SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";

  if (base && key) {
    try {
      const select = [
        ...MATCH_FIELDS,
        "stream_links(" + LINK_FIELDS.join(",") + ")",
      ].join(",");

      const upstream = new URL(
        base.replace(/\/+$/, "") +
          "/rest/v1/matches",
      );

      upstream.searchParams.set("select", select);
      upstream.searchParams.set("is_active", "eq.true");
      upstream.searchParams.set(
        "publish_state",
        "eq.published",
      );
      upstream.searchParams.set("is_featured", "eq.true");
      upstream.searchParams.set(
        "order",
        "kickoff_at.asc,sort_order.asc",
      );

      const response = await fetch(upstream, {
        headers: {
          apikey: key,
          Accept: "application/json",
        },
      });

      if (response.ok) {
        const rows = await response.json<unknown>();
        if (Array.isArray(rows)) {
          return {
            rows,
            source: "supabase",
          };
        }
      }
    } catch (_) {
      // Use metadata-only mirror below.
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
  result.public_stream_count = safeLinks(links).length;

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

function safeLinks(raw: unknown) {
  const links = Array.isArray(raw) ? raw : [];

  return links
    .filter((item) =>
      isSafePublicLink(
        item as Record<string, unknown>,
      ),
    )
    .map((item) => {
      const link =
        item as Record<string, unknown>;

      return {
        id: link.id,
        label: link.label,
        resolution: link.resolution,
        stream_type: link.stream_type,
        stream_url: link.stream_url,
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
      };
    })
    .sort(compareLinks);
}

function isSafePublicLink(
  link: Record<string, unknown>,
) {
  if (link.is_active !== true) return false;
  if (link.use_webview === true) return false;

  for (const field of [
    "referer",
    "origin",
    "key_id",
    "key_data",
  ]) {
    if (
      String(link[field] ?? "")
        .trim()
        .length > 0
    ) {
      return false;
    }
  }

  const streamUrl =
    String(link.stream_url ?? "").trim();

  if (!streamUrl) return false;

  try {
    const url = new URL(streamUrl);

    for (
      const queryKey of
      url.searchParams.keys()
    ) {
      const lower =
        queryKey.toLowerCase();

      if (
        SENSITIVE_QUERY_PARTS.some(
          (part) =>
            lower.includes(part),
        )
      ) {
        return false;
      }
    }
  } catch (_) {
    return false;
  }

  return true;
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
      "Authorization, Content-Type, apikey",
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
