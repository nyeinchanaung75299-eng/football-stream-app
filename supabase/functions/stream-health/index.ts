import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { probeStreamFirstChunk } from "../_shared/stream_probe.mjs";

type LinkRow = {
  id: string;
  match_id: string;
  stream_url: string | null;
  referer: string | null;
  origin: string | null;
  use_webview: boolean | null;
  webview_url: string | null;
};

type ChannelLineRow = {
  id: string;
  channel_id: string;
  stream_url: string | null;
  referer: string | null;
  origin: string | null;
};

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const cronSecret = Deno.env.get("CRON_SECRET");

    if (!supabaseUrl || !serviceRole) {
      return json({ error: "Supabase server credentials are missing." }, 500);
    }

    const cronAuthorized =
      !!cronSecret &&
      req.headers.get("x-cron-secret") === cronSecret;

    let adminAuthorized = false;

    if (!cronAuthorized && anonKey) {
      const authHeader = req.headers.get("Authorization") ?? "";

      if (authHeader.startsWith("Bearer ")) {
        const userClient = createClient(supabaseUrl, anonKey, {
          global: {
            headers: {
              Authorization: authHeader,
            },
          },
        });

        const {
          data: { user },
          error: userError,
        } = await userClient.auth.getUser();

        if (!userError && user) {
          const { data: profile } = await userClient
            .from("profiles")
            .select("role")
            .eq("id", user.id)
            .single();

          adminAuthorized = profile?.role === "admin";
        }
      }
    }

    if (!cronAuthorized && !adminAuthorized) {
      return json({ error: "Admin or cron access required." }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const linkId = body?.link_id?.toString();
    const matchId = body?.match_id?.toString();
    const channelLineId = body?.channel_line_id?.toString();
    const channelId = body?.channel_id?.toString();
    const checkAll = body?.all === true || cronAuthorized;

    const admin = createClient(supabaseUrl, serviceRole);

    // Channel-line checks are explicitly scoped to one private channel or
    // line. They never return a stream URL, referer, key, or playback token.
    if (channelLineId || channelId) {
      let channelQuery = admin
        .from("channel_lines")
        .select("id,channel_id,stream_url,referer,origin")
        .eq("is_active", true)
        .order("sort_order", { ascending: true })
        .limit(channelLineId ? 1 : 30);

      if (channelLineId) {
        channelQuery = channelQuery.eq("id", channelLineId);
      } else if (channelId) {
        channelQuery = channelQuery.eq("channel_id", channelId);
      }

      const { data, error } = await channelQuery;
      if (error) throw error;
      const lines = (data ?? []) as ChannelLineRow[];
      const results: Record<string, unknown>[] = [];

      for (let offset = 0; offset < lines.length; offset += 4) {
        const chunk = lines.slice(offset, offset + 4);
        const checked = await Promise.all(
          chunk.map((line) => checkChannelLine(admin, line)),
        );
        results.push(...checked);
      }

      if (channelLineId && results.length === 1) {
        return json({ ok: true, ...results[0] });
      }
      return json({
        ok: true,
        checked: results.length,
        summary: healthSummary(results),
        results,
      });
    }

    let query = admin
      .from("stream_links")
      .select(
        "id,match_id,stream_url,referer,origin,use_webview,webview_url",
      )
      .eq("is_active", true)
      .order("priority", { ascending: true })
      .limit(checkAll ? 100 : 30);

    if (linkId) {
      query = query.eq("id", linkId);
    } else if (matchId) {
      query = query.eq("match_id", matchId);
    } else if (!checkAll) {
      return json(
        { error: "link_id, match_id, or all=true is required." },
        400,
      );
    }

    const { data, error } = await query;
    if (error) throw error;

    const links = (data ?? []) as LinkRow[];

    const results: Record<string, unknown>[] = [];

    for (let offset = 0; offset < links.length; offset += 4) {
      const chunk = links.slice(offset, offset + 4);
      const checked = await Promise.all(
        chunk.map((link) => checkLink(admin, link)),
      );
      results.push(...checked);
    }

    if (linkId && results.length === 1) {
      return json({ ok: true, ...results[0] });
    }

    return json({
      ok: true,
      checked: results.length,
      summary: healthSummary(results),
      results,
    });
  } catch (error) {
    console.error(error);
    return json(
      {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});

async function checkLink(
  admin: SupabaseClient,
  link: LinkRow,
) {
  const url = link.use_webview ? link.webview_url : link.stream_url;

  let health = "failed";
  let statusCode = 0;
  let latency = 0;
  let detail = "";

  if (!url) {
    detail = "URL is empty.";
  } else {
    const headers: Record<string, string> = {
      "Accept": "*/*",
      "Range": "bytes=0-4095",
      "User-Agent": "FootballStreamHealth/1.0",
    };

    if (link.referer) headers["Referer"] = link.referer;
    if (link.origin) headers["Origin"] = link.origin;

    const result = await probeStreamFirstChunk(url, { headers });
    health = result.status;
    statusCode = result.httpStatus;
    latency = result.latencyMs;
    detail = result.detail;
  }

  const checkedAt = new Date().toISOString();

  await admin
    .from("stream_links")
    .update({
      health_status: health,
      health_latency_ms: latency,
      last_checked_at: checkedAt,
    })
    .eq("id", link.id);

  return {
    id: link.id,
    match_id: link.match_id,
    health_status: health,
    latency_ms: latency,
    http_status: statusCode,
    checked_at: checkedAt,
    detail,
  };
}

async function checkChannelLine(
  admin: SupabaseClient,
  line: ChannelLineRow,
) {
  const result = await probe(line.stream_url, line.referer, line.origin);
  const checkedAt = new Date().toISOString();

  await admin
    .from("channel_lines")
    .update({
      health_status: result.health,
      health_latency_ms: result.latency,
      last_checked_at: checkedAt,
    })
    .eq("id", line.id);

  return {
    id: line.id,
    channel_id: line.channel_id,
    health_status: result.health,
    latency_ms: result.latency,
    http_status: result.statusCode,
    checked_at: checkedAt,
  };
}

async function probe(
  url: string | null,
  referer: string | null,
  origin: string | null,
) {
  if (!url) {
    return {
      health: "failed",
      statusCode: 0,
      latency: 0,
      detail: "URL is empty.",
    };
  }
  const headers: Record<string, string> = {
    "Accept": "*/*",
    "Range": "bytes=0-4095",
    "User-Agent": "FootballStreamHealth/1.0",
  };
  if (referer) headers["Referer"] = referer;
  if (origin) headers["Origin"] = origin;
  const result = await probeStreamFirstChunk(url, { headers });
  return {
    health: result.status,
    statusCode: result.httpStatus,
    latency: result.latencyMs,
    detail: result.detail,
  };
}

function healthSummary(results: Record<string, unknown>[]) {
  return {
    healthy: results.filter((x) => x.health_status === "healthy").length,
    slow: results.filter((x) => x.health_status === "slow").length,
    failed: results.filter((x) => x.health_status === "failed").length,
    unknown: results.filter((x) => x.health_status === "unknown").length,
  };
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
