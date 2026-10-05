import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type LinkRow = {
  id: string;
  match_id: string;
  stream_url: string | null;
  referer: string | null;
  origin: string | null;
  use_webview: boolean | null;
  webview_url: string | null;
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
    const checkAll = body?.all === true || cronAuthorized;

    const admin = createClient(supabaseUrl, serviceRole);

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

    if (links.length === 0) {
      return json({
        ok: true,
        checked: 0,
        summary: { healthy: 0, slow: 0, failed: 0 },
        results: [],
      });
    }

    const results: Record<string, unknown>[] = [];

    for (let offset = 0; offset < links.length; offset += 4) {
      const chunk = links.slice(offset, offset + 4);
      const checked = await Promise.all(
        chunk.map((link) => checkLink(admin, link)),
      );
      results.push(...checked);
    }

    const summary = {
      healthy: results.filter((x) => x.health_status === "healthy").length,
      slow: results.filter((x) => x.health_status === "slow").length,
      failed: results.filter((x) => x.health_status === "failed").length,
      unknown: results.filter((x) => x.health_status === "unknown").length,
    };

    if (linkId && results.length === 1) {
      return json({ ok: true, ...results[0] });
    }

    return json({
      ok: true,
      checked: results.length,
      summary,
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
  admin: ReturnType<typeof createClient>,
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

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    const started = Date.now();

    try {
      const response = await fetch(url, {
        method: "GET",
        headers,
        redirect: "follow",
        signal: controller.signal,
      });

      statusCode = response.status;
      latency = Date.now() - started;

      const reachable =
        response.ok ||
        response.status === 206 ||
        (response.status >= 300 && response.status < 400);

      if (reachable) {
        health = latency > 3000 ? "slow" : "healthy";
      } else if (
        response.status === 401 ||
        response.status === 403 ||
        response.status === 405 ||
        response.status === 429
      ) {
        health = "unknown";
      } else {
        health = "failed";
      }

      detail = reachable ? "reachable" : `HTTP ${response.status}`;

      try {
        const reader = response.body?.getReader();
        if (reader) {
          await reader.read();
          await reader.cancel();
        }
      } catch (_) {}
    } catch (error) {
      latency = Date.now() - started;
      detail = error instanceof Error ? error.message : String(error);
      health = "failed";
    } finally {
      clearTimeout(timeout);
    }
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

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
