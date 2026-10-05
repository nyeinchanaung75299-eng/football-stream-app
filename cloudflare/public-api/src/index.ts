export interface Env {
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
}

const SELECT = [
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
  "stream_links(" +
    [
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
    ].join(",") +
    ")",
].join(",");

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

    if (request.method !== "GET" || url.pathname !== "/matches") {
      return json({ error: "Not found." }, 404);
    }

    const cache = caches.default;
    const cacheKey = new Request(url.origin + "/matches");
    const cached = await cache.match(cacheKey);
    if (cached) return withCors(cached);

    const upstream = new URL(
      env.SUPABASE_URL.replace(/\/+$/, "") + "/rest/v1/matches",
    );

    upstream.searchParams.set("select", SELECT);
    upstream.searchParams.set("is_active", "eq.true");
    upstream.searchParams.set("publish_state", "eq.published");
    upstream.searchParams.set("is_featured", "eq.true");
    upstream.searchParams.set("order", "kickoff_at.asc,sort_order.asc");

    const response = await fetch(upstream, {
      headers: {
        apikey: env.SUPABASE_PUBLISHABLE_KEY,
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      return json(
        {
          error: "Upstream unavailable.",
          upstream_status: response.status,
        },
        502,
      );
    }

    const rows = await response.json<unknown>();
    if (!Array.isArray(rows)) {
      return json({ error: "Invalid upstream response." }, 502);
    }

    const matches = rows.map(sanitizeMatch);

    const result = json(
      {
        ok: true,
        matches,
        generated_at: new Date().toISOString(),
      },
      200,
      {
        "Cache-Control": "public, max-age=30, s-maxage=60",
      },
    );

    ctx.waitUntil(cache.put(cacheKey, result.clone()));
    return result;
  },
};

function sanitizeMatch(raw: unknown) {
  const match = {
    ...(raw as Record<string, unknown>),
  };

  const links = Array.isArray(match.stream_links)
    ? match.stream_links
    : [];

  match.stream_links = links
    .filter((item) => {
      const link = item as Record<string, unknown>;

      if (link.is_active !== true) return false;
      if (link.use_webview === true) return false;

      const protectedFields = [
        "referer",
        "origin",
        "key_id",
        "key_data",
      ];

      if (
        protectedFields.some(
          (field) => String(link[field] ?? "").trim().length > 0,
        )
      ) {
        return false;
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
        use_webview: false,
        webview_url: null,
        is_active: true,
        priority: link.priority,
        available_from: link.available_from,
        expires_at: link.expires_at,
        health_status: link.health_status,
      };
    });

  return match;
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function withCors(response: Response) {
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
