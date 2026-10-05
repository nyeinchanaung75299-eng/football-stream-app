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

    if (!footballKey) {
      return json({ error: "API_FOOTBALL_KEY is not configured." }, 500);
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
      Deno.env.get("SCORE_SYNC_INTERVAL_SECONDS") ?? "600",
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

    if (candidates.length === 0) {
      return json({
        ok: true,
        synced: 0,
        api_calls: 0,
        forced: force,
        message: "Nothing due.",
      });
    }

    let synced = 0;
    let apiCalls = 0;
    let failedUpdates = 0;

    for (let offset = 0; offset < candidates.length; offset += 20) {
      const batch = candidates.slice(offset, offset + 20);

      const ids = batch
        .map((item: any) => item.external_fixture_id)
        .filter(Boolean)
        .join("-");

      if (!ids) continue;

      const url = new URL("https://v3.football.api-sports.io/fixtures");
      url.searchParams.set("ids", ids);

      const apiResponse = await fetch(url, {
        method: "GET",
        headers: {
          "x-apisports-key": footballKey,
          "Accept": "application/json",
        },
      });

      apiCalls += 1;

      if (!apiResponse.ok) {
        console.error("API-Football request failed:", apiResponse.status);
        continue;
      }

      const payload = await apiResponse.json();

      if (payload?.errors && Object.keys(payload.errors).length > 0) {
        console.error("API-Football returned errors:", payload.errors);
        continue;
      }

      const fixtures = Array.isArray(payload?.response)
        ? payload.response
        : [];

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

    return json({
      ok: true,
      synced,
      candidates: candidates.length,
      failed_updates: failedUpdates,
      api_calls: apiCalls,
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

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
