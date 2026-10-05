export interface Env {
  SUPABASE_URL?: string;
  SUPABASE_PUBLISHABLE_KEY?: string;
  GITHUB_MIRROR_URL?: string;
}

const DEFAULT_MIRROR =
  "https://raw.githubusercontent.com/" +
  "nyeinchanaung75299-eng/football-stream-app/" +
  "feed/public/matches.json";

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

    if (url.pathname !== "/matches") {
      return json({ error: "Not found." }, 404);
    }

    const cache = caches.default;
    const cacheKey = new Request(url.origin + "/matches");
    const cached = await cache.match(cacheKey);
    if (cached) return withCors(cached);

    try {
      const loaded = await loadRows(env);
      const matches = loaded.rows.map(sanitizeMatch);

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
          error: error instanceof Error ? error.message : String(error),
        },
        502,
      );
    }
  },
};

async function loadRows(
  env: Env,
): Promise<{ rows: unknown[]; source: "supabase" | "github" }> {
  const base = (env.SUPABASE_URL ?? "").trim();
  const key = (env.SUPABASE_PUBLISHABLE_KEY ?? "").trim();

  if (base && key) {
    try {
      const upstream = new URL(
        base.replace(/\/+$/, "") + "/rest/v1/matches",
      );

      upstream.searchParams.set("select", SELECT);
      upstream.searchParams.set("is_active", "eq.true");
      upstream.searchParams.set("publish_state", "eq.published");
      upstream.searchParams.set("is_featured", "eq.true");
      upstream.searchParams.set("order", "kickoff_at.asc,sort_order.asc");

      const response = await fetch(upstream, {
        headers: {
          apikey: key,
          Accept: "application/json",
        },
      });

      if (response.ok) {
        const rows = await response.json<unknown>();
        if (Array.isArray(rows)) {
          return { rows, source: "supabase" };
        }
      }
    } catch (_) {
      // Use safe mirror below.
    }
  }

  const mirror = env.GITHUB_MIRROR_URL?.trim() || DEFAULT_MIRROR;
  const response = await fetch(mirror, {
    headers: { Accept: "application/json" },
  });

  if (!response.ok) {
    throw new Error("Public mirror unavailable.");
  }

  const rows = await response.json<unknown>();
  if (!Array.isArray(rows)) {
    throw new Error("Invalid mirror response.");
  }

  return { rows, source: "github" };
}

function sanitizeMatch(raw: unknown) {
  const match = {
    ...(raw as Record<string, unknown>),
  };

  const links = Array.isArray(match.stream_links)
    ? match.stream_links
    : [];

  match.stream_links = links
    .filter((item) => isSafePublicLink(item as Record<string, unknown>))
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

function isSafePublicLink(link: Record<string, unknown>) {
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

  const streamUrl = String(link.stream_url ?? "").trim();
  if (!streamUrl) return false;

  try {
    const url = new URL(streamUrl);
    const sensitiveParts = [
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

    for (const queryKey of url.searchParams.keys()) {
      const lower = queryKey.toLowerCase();
      if (sensitiveParts.some((part) => lower.includes(part))) {
        return false;
      }
    }
  } catch (_) {
    return false;
  }

  return true;
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
