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
    const footballKey = Deno.env.get("API_FOOTBALL_KEY");
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

    if (!cronAuthorized && !adminAuthorized) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const force = adminAuthorized && body?.force === true;

    const client = createClient(supabaseUrl, serviceRole);
    const now = new Date();

    const scoreSummary = footballKey
      ? await syncScores(client, footballKey, now, force)
      : {
          synced: 0,
          candidates: 0,
          failed_updates: 0,
          api_calls: 0,
          score_sync_skipped: "API_FOOTBALL_KEY is not configured.",
        };

    const finishedCleanup = await hideFinishedMatchesAfterGrace(client, now);
    const healthSummary = await syncStreamHealth(client, now, force);

    return json({
      ok: true,
      ...scoreSummary,
      finished_cleanup: finishedCleanup,
      stream_health: healthSummary,
      forced: force,
      checked_at: now.toISOString(),
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

async function syncScores(
  client: any,
  footballKey: string,
  now: Date,
  force: boolean,
) {
  const windowStart = new Date(now.getTime() - 6 * 60 * 60 * 1000);
  const windowEnd = new Date(now.getTime() + 90 * 60 * 1000);

  const { data: rows, error } = await client
    .from("matches")
    .select(
      `
        id,
        external_fixture_id,
        kickoff_at,
        last_score_sync_at,
        is_active,
        publish_state,
        is_featured,
        is_finished
      `,
    )
    .eq("is_active", true)
    .eq("publish_state", "published")
    .eq("is_featured", true)
    .not("external_fixture_id", "is", null);

  if (error) throw error;

  const minIntervalSeconds = Number(
    Deno.env.get("SCORE_SYNC_INTERVAL_SECONDS") ?? "120",
  );

  const candidates = (rows ?? []).filter((match: any) => {
    if (match.is_finished === true) return false;
    if (!match.kickoff_at) return false;

    const kickoff = new Date(match.kickoff_at);

    if (
      kickoff.getTime() < windowStart.getTime() ||
      kickoff.getTime() > windowEnd.getTime()
    ) {
      return false;
    }

    if (!force && match.last_score_sync_at) {
      const previousSync = new Date(match.last_score_sync_at);
      const elapsed = now.getTime() - previousSync.getTime();

      if (elapsed < Math.max(30, minIntervalSeconds) * 1000) {
        return false;
      }
    }

    return true;
  });

  let synced = 0;
  let apiCalls = 0;
  let failedUpdates = 0;
  let receivedFixtures = 0;
  const providerErrors: unknown[] = [];

  const candidateIds = new Set(
    candidates.map((item: any) => String(item.external_fixture_id)),
  );

  const dates = [
    ...new Set(
      candidates.map((item: any) =>
        new Date(item.kickoff_at).toISOString().slice(0, 10)
      ),
    ),
  ];

  const headers = {
    "x-apisports-key": footballKey,
    "Accept": "application/json",
  };

  for (const date of dates) {
    const url = new URL("https://v3.football.api-sports.io/fixtures");
    // The Free API-Football plan rejects the multi-ID parameter. A date query
    // is available on the Free plan and lets us refresh every selected fixture
    // for that day with one request.
    url.searchParams.set("date", date);

    const apiResponse = await fetch(url, {
      method: "GET",
      headers,
    });

    apiCalls += 1;

    if (!apiResponse.ok) {
      providerErrors.push({ date, status: apiResponse.status });
      console.error("API-Football request failed:", apiResponse.status);
      continue;
    }

    const payload = await apiResponse.json();

    if (payload?.errors && Object.keys(payload.errors).length > 0) {
      providerErrors.push({ date, errors: payload.errors });
      console.error("API-Football returned errors:", payload.errors);
      continue;
    }

    const allFixtures = Array.isArray(payload?.response)
      ? payload.response
      : [];

    const fixtures = allFixtures.filter((row: any) =>
      candidateIds.has(String(row?.fixture?.id ?? ""))
    );

    receivedFixtures += fixtures.length;

    for (const row of fixtures) {
      const fixtureId = row?.fixture?.id;
      if (!fixtureId) continue;

      const statusShort = row?.fixture?.status?.short ?? "NS";

      const isLive = [
        "1H",
        "HT",
        "2H",
        "ET",
        "BT",
        "P",
        "LIVE",
        "INT",
        "SUSP",
      ].includes(statusShort);

      const isFinished = ["FT", "AET", "PEN"].includes(statusShort);

      const { error: updateError } = await client
        .from("matches")
        .update({
          kickoff_at: row?.fixture?.date ?? null,
          home_score: row?.goals?.home ?? 0,
          away_score: row?.goals?.away ?? 0,
          status_short: statusShort,
          status_elapsed: row?.fixture?.status?.elapsed ?? null,
          is_live: isLive,
          is_finished: isFinished,
          // Keep FT visible briefly so users can see the final score.
          // A separate cleanup below removes it from Live after 10 minutes.
          last_score_sync_at: now.toISOString(),
        })
        .eq("external_fixture_id", fixtureId);

      if (updateError) {
        failedUpdates += 1;
        console.error(
          `Failed updating fixture ${fixtureId}:`,
          updateError,
        );
      } else {
        synced += 1;
      }
    }
  }

  return {
    synced,
    candidates: candidates.length,
    received_fixtures: receivedFixtures,
    failed_updates: failedUpdates,
    api_calls: apiCalls,
    provider_errors: providerErrors.slice(0, 5),
  };
}

async function hideFinishedMatchesAfterGrace(
  client: any,
  now: Date,
) {
  const graceMs = 10 * 60 * 1000;
  const { data: rows, error } = await client
    .from("matches")
    .select("id,is_finished,status_short,last_score_sync_at,updated_at")
    .eq("is_active", true)
    .eq("publish_state", "published")
    .eq("is_featured", true);

  if (error) {
    console.error("Finished-match cleanup query failed:", error);
    return { hidden: 0, grace_minutes: 10 };
  }

  const finishedStatuses = new Set(["FT", "AET", "PEN"]);
  const ids = (rows ?? [])
    .filter((row: any) => {
      const finished =
        row.is_finished === true ||
        finishedStatuses.has(String(row.status_short ?? "").toUpperCase());
      if (!finished) return false;

      const detectedAt = row.last_score_sync_at ?? row.updated_at;
      if (!detectedAt) return false;
      const timestamp = new Date(detectedAt).getTime();
      return Number.isFinite(timestamp) && now.getTime() - timestamp >= graceMs;
    })
    .map((row: any) => row.id)
    .filter(Boolean);

  if (ids.length === 0) {
    return { hidden: 0, grace_minutes: 10 };
  }

  const { error: updateError } = await client
    .from("matches")
    .update({
      is_live: false,
      is_finished: true,
      is_featured: false,
    })
    .in("id", ids);

  if (updateError) {
    console.error("Finished-match cleanup update failed:", updateError);
    return { hidden: 0, grace_minutes: 10 };
  }

  return { hidden: ids.length, grace_minutes: 10 };
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
