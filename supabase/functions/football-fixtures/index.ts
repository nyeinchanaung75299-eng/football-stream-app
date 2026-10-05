import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "Not signed in." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const apiFootballKey =
      Deno.env.get("API_FOOTBALL_KEY") ??
      Deno.env.get("APISPORTS_KEY") ??
      Deno.env.get("API_SPORTS_KEY");
    const footballDataKey =
      Deno.env.get("FOOTBALL_DATA_ORG_KEY") ??
      Deno.env.get("FOOTBALL_DATA_KEY");
    // Compatibility: some existing installs stored a football-data.org token
    // in API_FOOTBALL_KEY. We still try API-Football first, then reuse that
    // token as the football-data.org fallback only when no dedicated key exists.
    const footballDataFallbackKey = footballDataKey ?? apiFootballKey;

    if (!apiFootballKey && !footballDataKey) {
      return json(
        {
          error:
            "No football fixture provider is configured. Add API_FOOTBALL_KEY and/or FOOTBALL_DATA_ORG_KEY in Edge Functions > Secrets.",
          code: "FOOTBALL_PROVIDERS_MISSING",
        },
        500,
      );
    }

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

    if (userError || !user) {
      return json({ error: "Invalid session." }, 401);
    }

    const { data: profile } = await userClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profile?.role !== "admin") {
      return json({ error: "Admin access required." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const mode = body.mode === "live" ? "live" : "date";
    const date =
      typeof body.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.date)
        ? body.date
        : new Date().toISOString().slice(0, 10);

    const { data: deletedRows } = await userClient
      .from("matches")
      .select("external_fixture_id")
      .not("deleted_at", "is", null);

    const deletedFixtureIds = new Set(
      (deletedRows ?? [])
        .map((row: any) => Number(row.external_fixture_id))
        .filter((id: number) => Number.isFinite(id)),
    );

    const failures: Array<{ provider: string; error: string }> = [];

    if (apiFootballKey) {
      try {
        const result = await loadApiFootballFixtures(
          apiFootballKey,
          mode,
          date,
          deletedFixtureIds,
        );
        return json({
          ...result,
          provider: "api_football",
          fallback_used: false,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        failures.push({ provider: "api_football", error: message });
        console.error("API-Football fixture load failed:", message);
      }
    }

    if (footballDataFallbackKey) {
      try {
        const result = await loadFootballDataFixtures(
          footballDataFallbackKey,
          mode,
          date,
          deletedFixtureIds,
        );
        return json({
          ...result,
          provider: "football_data_org",
          fallback_used: failures.length > 0,
          compatibility_key_used: !footballDataKey && Boolean(apiFootballKey),
          primary_failure: failures[0]?.error ?? null,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        failures.push({ provider: "football_data_org", error: message });
        console.error("football-data.org fixture load failed:", message);
      }
    }

    return json(
      {
        error: failures
          .map((item) => `${item.provider}: ${item.error}`)
          .join(" | "),
        code: "FOOTBALL_PROVIDERS_FAILED",
        providers: failures,
      },
      502,
    );
  } catch (error) {
    return json(
      {
        error: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});

async function loadApiFootballFixtures(
  key: string,
  mode: "live" | "date",
  date: string,
  deletedFixtureIds: Set<number>,
) {
  const url = new URL("https://v3.football.api-sports.io/fixtures");
  if (mode === "live") {
    url.searchParams.set("live", "all");
  } else {
    url.searchParams.set("date", date);
  }

  const response = await fetch(url, {
    headers: {
      "x-apisports-key": key,
      "Accept": "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`request failed (HTTP ${response.status})`);
  }

  const payload = await response.json();

  if (payload?.errors && Object.keys(payload.errors).length > 0) {
    const providerError = JSON.stringify(payload.errors);
    if (providerError.toLowerCase().includes("suspended")) {
      throw new Error("account is suspended");
    }
    throw new Error(providerError);
  }

  const rows = Array.isArray(payload?.response) ? payload.response : [];
  const fixtures = rows
    .filter((row: any) => {
      const id = Number(row?.fixture?.id);
      return Number.isFinite(id) && !deletedFixtureIds.has(id);
    })
    .map((row: any) => ({
      provider: "api_football",
      fixture_id: Number(row.fixture.id),
      provider_fixture_id: Number(row.fixture.id),
      kickoff_at: row.fixture?.date,
      status_short: row.fixture?.status?.short ?? "NS",
      status_long: row.fixture?.status?.long ?? null,
      status_elapsed: row.fixture?.status?.elapsed ?? null,
      is_live: [
        "1H",
        "HT",
        "2H",
        "ET",
        "BT",
        "P",
        "SUSP",
        "INT",
        "LIVE",
      ].includes(row.fixture?.status?.short),
      is_finished: ["FT", "AET", "PEN"].includes(row.fixture?.status?.short),
      league_name: row.league?.name ?? "Football",
      league_logo: row.league?.logo ?? null,
      home_name: row.teams?.home?.name ?? "Home",
      away_name: row.teams?.away?.name ?? "Away",
      home_logo: row.teams?.home?.logo ?? null,
      away_logo: row.teams?.away?.logo ?? null,
      home_score: row.goals?.home ?? null,
      away_score: row.goals?.away ?? null,
    }));

  sortFixtures(fixtures);

  return {
    fixtures,
    results: fixtures.length,
    hidden_deleted: deletedFixtureIds.size,
    remaining: response.headers.get("x-ratelimit-requests-remaining") ?? null,
  };
}

async function loadFootballDataFixtures(
  key: string,
  mode: "live" | "date",
  date: string,
  deletedFixtureIds: Set<number>,
) {
  const url = new URL("https://api.football-data.org/v4/matches");

  if (mode === "live") {
    const now = new Date();
    url.searchParams.set("dateFrom", dateOffset(now, -1));
    url.searchParams.set("dateTo", dateOffset(now, 1));
  } else {
    url.searchParams.set("dateFrom", date);
    url.searchParams.set("dateTo", date);
  }

  const response = await fetch(url, {
    headers: {
      "X-Auth-Token": key,
      "Accept": "application/json",
    },
  });

  const payload = await response.json().catch(() => ({}));

  if (!response.ok) {
    const detail =
      payload?.message ??
      payload?.error ??
      `request failed (HTTP ${response.status})`;
    throw new Error(String(detail));
  }

  const rows = Array.isArray(payload?.matches) ? payload.matches : [];
  const fixtures = rows
    .map((row: any) => mapFootballDataFixture(row))
    .filter((row: any) => row != null)
    .filter((row: any) => !deletedFixtureIds.has(Number(row.fixture_id)))
    .filter((row: any) => mode !== "live" || row.is_live === true);

  sortFixtures(fixtures);

  return {
    fixtures,
    results: fixtures.length,
    hidden_deleted: deletedFixtureIds.size,
    remaining:
      response.headers.get("x-requests-available-minute") ??
      response.headers.get("x-requestcounter-reset") ??
      null,
  };
}

function mapFootballDataFixture(row: any) {
  const rawId = Number(row?.id);
  if (!Number.isFinite(rawId) || rawId <= 0) return null;

  // Keep provider IDs in separate numeric namespaces without a schema change.
  // API-Football uses positive IDs; football-data.org uses the negative form.
  const fixtureId = -Math.abs(rawId);
  const statusShort = footballDataStatus(row?.status);
  const isLive = ["LIVE", "1H", "HT", "2H", "ET", "INT", "SUSP"].includes(
    statusShort,
  );
  const isFinished = statusShort === "FT";

  return {
    provider: "football_data_org",
    fixture_id: fixtureId,
    provider_fixture_id: rawId,
    kickoff_at: row?.utcDate ?? null,
    status_short: statusShort,
    status_long: row?.status ?? null,
    status_elapsed: Number.isFinite(Number(row?.minute))
      ? Number(row.minute)
      : null,
    is_live: isLive,
    is_finished: isFinished,
    league_name: row?.competition?.name ?? "Football",
    league_logo: row?.competition?.emblem ?? null,
    home_name: row?.homeTeam?.name ?? row?.homeTeam?.shortName ?? "Home",
    away_name: row?.awayTeam?.name ?? row?.awayTeam?.shortName ?? "Away",
    home_logo: row?.homeTeam?.crest ?? null,
    away_logo: row?.awayTeam?.crest ?? null,
    home_score:
      row?.score?.fullTime?.home ??
      row?.score?.halfTime?.home ??
      null,
    away_score:
      row?.score?.fullTime?.away ??
      row?.score?.halfTime?.away ??
      null,
  };
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
    case "SCHEDULED":
    case "TIMED":
    default:
      return "NS";
  }
}

function sortFixtures(fixtures: any[]) {
  fixtures.sort((a: any, b: any) => {
    const at = new Date(a.kickoff_at ?? 0).getTime();
    const bt = new Date(b.kickoff_at ?? 0).getTime();
    if (at !== bt) return at - bt;
    return String(a.home_name ?? "").localeCompare(
      String(b.home_name ?? ""),
    );
  });
}

function dateOffset(date: Date, days: number) {
  const copy = new Date(date.getTime());
  copy.setUTCDate(copy.getUTCDate() + days);
  return copy.toISOString().slice(0, 10);
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
