import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const cronSecret = Deno.env.get("CRON_SECRET");

    if (!supabaseUrl || !serviceRole) {
      return json({ error: "Supabase server credentials are missing." }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const cronAuthorized =
      !!cronSecret && req.headers.get("x-cron-secret") === cronSecret;

    let adminAuthorized = false;
    if (!cronAuthorized && anonKey && authHeader.startsWith("Bearer ")) {
      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
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

    if (!cronAuthorized && !adminAuthorized) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const force = adminAuthorized && body?.force === true;

    const client = createClient(supabaseUrl, serviceRole);
    const now = new Date();

    const staleCleanup = await hideStaleMatches(client, now);
    const expiredStreamCleanup = await disableExpiredStreams(client, now);
    const healthSummary = await syncStreamHealth(client, now, force);

    return json({
      ok: true,
      maintenance_only: true,
      stale_cleanup: staleCleanup,
      expired_stream_cleanup: expiredStreamCleanup,
      stream_health: healthSummary,
      forced: force,
      checked_at: now.toISOString(),
    });
  } catch (error) {
    console.error("football maintenance failed:", error);
    return json(
      {
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});

async function hideStaleMatches(client: any, now: Date) {
  const cutoff = new Date(now.getTime() - 5 * 60 * 60 * 1000).toISOString();
  const { data: rows, error } = await client
    .from("matches")
    .select("id")
    .eq("is_active", true)
    .eq("publish_state", "published")
    .eq("is_featured", true)
    .eq("is_live", false)
    .lt("kickoff_at", cutoff);

  if (error) {
    console.error("Stale-match cleanup query failed:", error);
    return { hidden: 0, grace_hours: 5 };
  }

  const ids = (rows ?? []).map((row: any) => row.id).filter(Boolean);
  if (ids.length === 0) {
    return { hidden: 0, grace_hours: 5 };
  }

  const { error: updateError } = await client
    .from("matches")
    .update({
      is_featured: false,
      is_live: false,
    })
    .in("id", ids);

  if (updateError) {
    console.error("Stale-match cleanup update failed:", updateError);
    return { hidden: 0, grace_hours: 5 };
  }

  return { hidden: ids.length, grace_hours: 5 };
}

async function disableExpiredStreams(client: any, now: Date) {
  const { data: rows, error } = await client
    .from("stream_links")
    .update({
      is_active: false,
      health_status: "failed",
    })
    .eq("is_active", true)
    .not("expires_at", "is", null)
    .lt("expires_at", now.toISOString())
    .select("id");

  if (error) {
    console.error("Expired-stream cleanup failed:", error);
    return { disabled: 0 };
  }

  return { disabled: (rows ?? []).length };
}

async function syncStreamHealth(
  client: any,
  now: Date,
  force: boolean,
) {
  const { data: matches, error: matchError } = await client
    .from("matches")
    .select("id")
    .eq("is_active", true)
    .eq("publish_state", "published")
    .eq("is_featured", true)
    .limit(200);

  if (matchError) {
    console.error("Health match query failed:", matchError);
    return { checked: 0, healthy: 0, slow: 0, failed: 0, unknown: 0 };
  }

  const matchIds = (matches ?? [])
    .map((row: any) => row.id)
    .filter(Boolean);

  if (matchIds.length === 0) {
    return { checked: 0, healthy: 0, slow: 0, failed: 0, unknown: 0 };
  }

  const { data: links, error: linkError } = await client
    .from("stream_links")
    .select(
      "id,match_id,stream_url,referer,origin,use_webview,webview_url,last_checked_at",
    )
    .eq("is_active", true)
    .in("match_id", matchIds)
    .limit(60);

  if (linkError) {
    console.error("Health link query failed:", linkError);
    return { checked: 0, healthy: 0, slow: 0, failed: 0, unknown: 0 };
  }

  const minAgeMs = 10 * 60 * 1000;
  const due = (links ?? [])
    .filter((link: any) => {
      if (force || !link.last_checked_at) return true;
      const checked = new Date(link.last_checked_at).getTime();
      return !Number.isFinite(checked) || now.getTime() - checked >= minAgeMs;
    })
    .slice(0, 16);

  const totals = {
    checked: 0,
    healthy: 0,
    slow: 0,
    failed: 0,
    unknown: 0,
  };

  for (let offset = 0; offset < due.length; offset += 4) {
    const batch = due.slice(offset, offset + 4);
    const results = await Promise.all(
      batch.map((link: any) => probeStreamLink(client, link)),
    );

    for (const status of results) {
      totals.checked += 1;
      if (status === "healthy") totals.healthy += 1;
      else if (status === "slow") totals.slow += 1;
      else if (status === "failed") totals.failed += 1;
      else totals.unknown += 1;
    }
  }

  return totals;
}

async function probeStreamLink(
  client: any,
  link: any,
): Promise<"healthy" | "slow" | "failed" | "unknown"> {
  const url = link.use_webview ? link.webview_url : link.stream_url;

  if (!url) {
    await updateHealth(client, link.id, "failed", 0);
    return "failed";
  }

  const headers: Record<string, string> = {
    "Accept": "*/*",
    "Range": "bytes=0-4095",
  };
  if (link.referer) headers["Referer"] = link.referer;
  if (link.origin) headers["Origin"] = link.origin;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6500);
  const started = Date.now();

  let status: "healthy" | "slow" | "failed" | "unknown" = "failed";
  let latency = 0;

  try {
    const response = await fetch(url, {
      method: "GET",
      headers,
      redirect: "follow",
      signal: controller.signal,
    });

    latency = Date.now() - started;

    if (
      response.ok ||
      response.status === 206 ||
      (response.status >= 300 && response.status < 400)
    ) {
      status = latency > 2800 ? "slow" : "healthy";
    } else if (
      response.status === 401 ||
      response.status === 403 ||
      response.status === 405 ||
      response.status === 429
    ) {
      status = "unknown";
    } else {
      status = "failed";
    }

    try {
      const reader = response.body?.getReader();
      if (reader) {
        await reader.read();
        await reader.cancel();
      }
    } catch (_) {}
  } catch (_) {
    latency = Date.now() - started;
    status = "failed";
  } finally {
    clearTimeout(timeout);
  }

  await updateHealth(client, link.id, status, latency);
  return status;
}

async function updateHealth(
  client: any,
  id: string,
  status: string,
  latency: number,
) {
  const { error } = await client
    .from("stream_links")
    .update({
      health_status: status,
      health_latency_ms: latency,
      last_checked_at: new Date().toISOString(),
    })
    .eq("id", id);

  if (error) {
    console.error(`Health update failed for ${id}:`, error);
  }
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
