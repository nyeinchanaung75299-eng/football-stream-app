export interface Env {
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
}

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

    if (request.method !== "GET") {
      return json({ error: "Method not allowed." }, 405);
    }

    if (url.pathname === "/health") {
      return json({
        ok: true,
        service: "football-public-api",
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

  const select = [
    ...MATCH_FIELDS,
    "stream_links(" + LINK_FIELDS.join(",") + ")",
  ].join(",");

  const upstream = restUrl(env, "matches");
  upstream.searchParams.set("select", select);
  upstream.searchParams.set("is_active", "eq.true");
  upstream.searchParams.set("publish_state", "eq.published");
  upstream.searchParams.set("is_featured", "eq.true");
  upstream.searchParams.set(
    "order",
    "kickoff_at.asc,sort_order.asc",
  );

  const response = await supabaseFetch(upstream, env);
  if (!response.ok) return upstreamError(response);

  const rows = await response.json();
  if (!Array.isArray(rows)) {
    return json(
      { error: "Invalid upstream response." },
      502,
    );
  }

  const matches = rows.map((raw) => {
    const match = {
      ...(raw as Record<string, unknown>),
    };

    const links = safeLinks(match.stream_links);
    delete match.stream_links;
    match.stream_count = links.length;
    return match;
  });

  const result = json(
    {
      ok: true,
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
}

async function handleStreams(
  matchId: string,
  env: Env,
  ctx: ExecutionContext,
) {
  if (!/^[0-9a-fA-F-]{16,64}$/.test(matchId)) {
    return json({ error: "Invalid match id." }, 400);
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

  const upstream = restUrl(env, "matches");
  upstream.searchParams.set("select", select);
  upstream.searchParams.set("id", "eq." + matchId);
  upstream.searchParams.set("is_active", "eq.true");
  upstream.searchParams.set("publish_state", "eq.published");
  upstream.searchParams.set("is_featured", "eq.true");
  upstream.searchParams.set("limit", "1");

  const response = await supabaseFetch(upstream, env);
  if (!response.ok) return upstreamError(response);

  const rows = await response.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return json({ error: "Match not found." }, 404);
  }

  const match = rows[0] as Record<string, unknown>;
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

function safeLinks(raw: unknown) {
  const links = Array.isArray(raw) ? raw : [];

  return links
    .filter((item) => {
      const link = item as Record<string, unknown>;

      if (link.is_active !== true) return false;
      if (link.use_webview === true) return false;

      for (const field of [
        "referer",
        "origin",
        "key_id",
        "key_data",
      ]) {
        if (String(link[field] ?? "").trim().length > 0) {
          return false;
        }
      }

      return String(link.stream_url ?? "").trim().length > 0;
    })
    .map((item) => {
      const link = item as Record<string, unknown>;

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

function compareLinks(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
) {
  const health =
    healthRank(a.health_status) -
    healthRank(b.health_status);
  if (health !== 0) return health;

  const format = formatRank(a) - formatRank(b);
  if (format !== 0) return format;

  return (
    Number(a.priority ?? 100) -
    Number(b.priority ?? 100)
  );
}

function healthRank(value: unknown) {
  switch (String(value ?? "unknown")) {
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
  const type = String(
    link.stream_type ?? "auto",
  ).toLowerCase();
  const url = String(
    link.stream_url ?? "",
  ).toLowerCase();

  if (
    type === "hls" ||
    type === "m3u8" ||
    url.includes(".m3u8")
  ) return 0;

  if (
    type === "dash" ||
    type === "mpd" ||
    url.includes(".mpd")
  ) return 1;

  if (type === "mp4" || url.includes(".mp4")) return 2;
  if (type === "auto") return 3;
  if (type === "flv" || url.includes(".flv")) return 4;
  return 5;
}

function restUrl(
  env: Env,
  table: string,
) {
  return new URL(
    env.SUPABASE_URL.replace(/\/+$/, "") +
      "/rest/v1/" +
      table,
  );
}

function supabaseFetch(
  url: URL,
  env: Env,
) {
  return fetch(url, {
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      Accept: "application/json",
    },
  });
}

function upstreamError(
  response: Response,
) {
  return json(
    {
      error: "Upstream unavailable.",
      upstream_status: response.status,
    },
    502,
  );
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function withCors(
  response: Response,
) {
  const headers = new Headers(response.headers);

  for (const [key, value] of Object.entries(corsHeaders())) {
    headers.set(key, value);
  }

  return new Response(response.body, {
    status: response.status,
    headers,
  });
}

function json(
  data: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
      ...extraHeaders,
    },
  });
}
