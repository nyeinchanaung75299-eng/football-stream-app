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
    const footballDataKey =
      Deno.env.get("FOOTBALL_DATA_ORG_KEY") ??
      Deno.env.get("FOOTBALL_DATA_KEY");
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

    const scoreSummary = footballKey || footballDataKey
      ? await syncScores(
          client,
          footballKey,
          footballDataKey,
          now,
          force,
        )
      : {
          synced: 0,
          candidates: 0,
          failed_updates: 0,
          api_calls: 0,
          score_sync_skipped:
            "Neither API_FOOTBALL_KEY nor FOOTBALL_DATA_ORG_KEY is configured.",
        };

    const finishedCleanup = await hideFinishedMatchesAfterGrace(client, now);
    const staleCleanup = await hideStaleMatches(client, now);
    const expiredStreamCleanup = await disableExpiredStreams(client, now);
    const healthSummary = await syncStreamHealth(client, now, force);

    return json({
      ok: true,
      ...scoreSummary,
      finished_cleanup: finishedCleanup,
      stale_cleanup: staleCleanup,
      expired_stream_cleanup: expiredStreamCleanup,
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
  footballKey: string | undefined,
  footballDataKey: string | undefined,
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
        source,
        external_fixture_id,
        kickoff_at,
        last_score_sync_at,
        is_active,
        publish_state,
        is_featured,
        is_finished,
        is_live
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

  const apiCandidates = candidates.filter((item: any) =>
    item.source !== "football_data_org" &&
    Number(item.external_fixture_id) > 0
  );
  const dataCandidates = candidates.filter((item: any) =>
    item.source === "football_data_org" ||
    Number(item.external_fixture_id) < 0
  );

  const totals = {
    synced: 0,
    candidates: candidates.length,
    received_fixtures: 0,
    failed_updates: 0,
    api_calls: 0,
    provider_errors: [] as unknown[],
  };

  if (apiCandidates.length > 0) {
    if (footballKey) {
      const summary = await syncApiFootballScores(
        client,
        footballKey,
        apiCandidates,
        now,
      );
      mergeScoreSummary(totals, summary);
    } else {
      totals.provider_errors.push({
        provider: "api_football",
        error: "API_FOOTBALL_KEY is not configured.",
      });
    }
  }

  if (dataCandidates.length > 0) {
    if (footballDataKey) {
      const summary = await syncFootballDataScores(
        client,
        footballDataKey,
        dataCandidates,
        now,
      );
      mergeScoreSummary(totals, summary);
    } else {
      totals.provider_errors.push({
        provider: "football_data_org",
        error: "FOOTBALL_DATA_ORG_KEY is not configured.",
      });
    }
  }

  return {
    ...totals,
    provider_errors: totals.provider_errors.slice(0, 8),
  };
}

async function syncApiFootballScores(
  client: any,
  key: string,
  candidates: any[],
  now: Date,
) {
  const summary = emptyScoreSummary();
  const candidateIds = new Set(
    candidates.map((item: any) => String(item.external_fixture_id)),
  );
  const candidateByFixture = new Map(
    candidates.map((item: any) => [
      String(item.external_fixture_id),
      item,
    ]),
  );

  for (const date of candidateDates(candidates)) {
    const url = new URL("https://v3.football.api-sports.io/fixtures");
    url.searchParams.set("date", date);

    const response = await fetch(url, {
      method: "GET",
      headers: {
        "x-apisports-key": key,
        "Accept": "application/json",
      },
    });

    summary.api_calls += 1;

    if (!response.ok) {
      summary.provider_errors.push({
        provider: "api_football",
        date,
        status: response.status,
      });
      continue;
    }

    const payload = await response.json();
    if (payload?.errors && Object.keys(payload.errors).length > 0) {
      summary.provider_errors.push({
        provider: "api_football",
        date,
        errors: payload.errors,
      });
      console.error("API-Football returned errors:", payload.errors);
      continue;
    }

    const fixtures = (Array.isArray(payload?.response) ? payload.response : [])
      .filter((row: any) =>
        candidateIds.has(String(row?.fixture?.id ?? ""))
      );

    summary.received_fixtures += fixtures.length;

    for (const row of fixtures) {
      const fixtureId = Number(row?.fixture?.id);
      if (!Number.isFinite(fixtureId)) continue;

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
      const existing = candidateByFixture.get(String(fixtureId));
      const nextLive = isFinished
        ? false
        : isLive || existing?.is_live === true;

      const { error: updateError } = await client
        .from("matches")
        .update({
          kickoff_at: row?.fixture?.date ?? null,
          home_score: row?.goals?.home ?? 0,
          away_score: row?.goals?.away ?? 0,
          status_short: statusShort,
          status_elapsed: row?.fixture?.status?.elapsed ?? null,
          is_live: nextLive,
          is_finished: isFinished,
          last_score_sync_at: now.toISOString(),
        })
        .eq("external_fixture_id", fixtureId);

      if (updateError) {
        summary.failed_updates += 1;
      } else {
        summary.synced += 1;
      }
    }
  }

  return summary;
}

async function syncFootballDataScores(
  client: any,
  key: string,
  candidates: any[],
  now: Date,
) {
  const summary = emptyScoreSummary();
  const candidateIds = new Set(
    candidates.map((item: any) => String(item.external_fixture_id)),
  );
  const candidateByFixture = new Map(
    candidates.map((item: any) => [
      String(item.external_fixture_id),
      item,
    ]),
  );

  for (const date of candidateDates(candidates)) {
    const url = new URL("https://api.football-data.org/v4/matches");
    url.searchParams.set("dateFrom", date);
    url.searchParams.set("dateTo", date);

    const response = await fetch(url, {
      method: "GET",
      headers: {
        "X-Auth-Token": key,
        "Accept": "application/json",
      },
    });

    summary.api_calls += 1;
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      summary.provider_errors.push({
        provider: "football_data_org",
        date,
        status: response.status,
        error: payload?.message ?? payload?.error ?? null,
      });
      continue;
    }

    const fixtures = (Array.isArray(payload?.matches) ? payload.matches : [])
      .filter((row: any) => {
        const rawId = Number(row?.id);
        if (!Number.isFinite(rawId)) return false;
        return candidateIds.has(String(-Math.abs(rawId)));
      });

    summary.received_fixtures += fixtures.length;

    for (const row of fixtures) {
      const rawId = Number(row?.id);
      if (!Number.isFinite(rawId)) continue;
      const fixtureId = -Math.abs(rawId);
      const statusShort = footballDataStatus(row?.status);
      const isLive = ["LIVE", "HT", "SUSP"].includes(statusShort);
      const isFinished = statusShort === "FT";
      const existing = candidateByFixture.get(String(fixtureId));
      const nextLive = isFinished
        ? false
        : isLive || existing?.is_live === true;

      const { error: updateError } = await client
        .from("matches")
        .update({
          kickoff_at: row?.utcDate ?? null,
          home_score:
            row?.score?.fullTime?.home ??
            row?.score?.halfTime?.home ??
            0,
          away_score:
            row?.score?.fullTime?.away ??
            row?.score?.halfTime?.away ??
            0,
          status_short: statusShort,
          status_elapsed: Number.isFinite(Number(row?.minute))
            ? Number(row.minute)
            : null,
          is_live: nextLive,
          is_finished: isFinished,
          last_score_sync_at: now.toISOString(),
        })
        .eq("source", "football_data_org")
        .eq("external_fixture_id", fixtureId);

      if (updateError) {
        summary.failed_updates += 1;
      } else {
        summary.synced += 1;
      }
    }
  }

  return summary;
}

function footballDataStatus(value: unknown) {
  const status = String(value ?? "").trim().toUpperCase();
  switch (status) {
    case "FINISHED":
      return "FT";
    case "LIVE":
    case "IN_PLAY":
      return "LIVE";
    case "PAUSED":
      return "HT";
    case "POSTPONED":
      return "PST";
    case "SUSPENDED":
      return "SUSP";
    case "CANCELLED":
      return "CANC";
    case "AWARDED":
      return "AWD";
    default:
      return "NS";
  }
}

function candidateDates(candidates: any[]) {
  return [
    ...new Set(
      candidates.map((item: any) =>
        new Date(item.kickoff_at).toISOString().slice(0, 10)
      ),
    ),
  ];
}

function emptyScoreSummary() {
  return {
    synced: 0,
    received_fixtures: 0,
    failed_updates: 0,
    api_calls: 0,
    provider_errors: [] as unknown[],
  };
}

function mergeScoreSummary(target: any, source: any) {
  target.synced += source.synced ?? 0;
  target.received_fixtures += source.received_fixtures ?? 0;
  target.failed_updates += source.failed_updates ?? 0;
  target.api_calls += source.api_calls ?? 0;
  target.provider_errors.push(...(source.provider_errors ?? []));
}

async function hideFinishedMatchesAfterGrace(
  client: any,
  now: Date,
) {
  const graceMs = 8 * 60 * 1000;
  const { data: rows, error } = await client
    .from("matches")
    .select("id,is_finished,status_short,last_score_sync_at,updated_at")
    .eq("is_active", true)
    .eq("publish_state", "published")
    .eq("is_featured", true);

  if (error) {
    console.error("Finished-match cleanup query failed:", error);
    return { hidden: 0, grace_minutes: 8 };
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
    return { hidden: 0, grace_minutes: 8 };
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
    return { hidden: 0, grace_minutes: 8 };
  }

  return { hidden: ids.length, grace_minutes: 8 };
}

async function hideStaleMatches(
  client: any,
  now: Date,
) {
  const cutoff = new Date(now.getTime() - 5 * 60 * 60 * 1000).toISOString();
  const { data: rows, error } = await client
    .from("matches")
    .select("id")
    .eq("is_active", true)
    .eq("publish_state", "published")
    .eq("is_featured", true)
    .eq("is_live", false)
    .eq("is_finished", false)
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

async function disableExpiredStreams(
  client: any,
  now: Date,
) {
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
