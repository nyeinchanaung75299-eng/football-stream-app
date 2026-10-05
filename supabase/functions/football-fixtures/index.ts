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
    const footballKey =
      Deno.env.get("API_FOOTBALL_KEY") ??
      Deno.env.get("APISPORTS_KEY") ??
      Deno.env.get("API_SPORTS_KEY");

    if (!footballKey) {
      return json(
        {
          error: "Football API key is missing. Add API_FOOTBALL_KEY in Edge Functions > Secrets.",
          code: "FOOTBALL_API_KEY_MISSING",
        },
        500,
      );
    }

    // Verify the caller and require admin role.
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

    const url = new URL("https://v3.football.api-sports.io/fixtures");

    if (mode === "live") {
      url.searchParams.set("live", "all");
    } else {
      url.searchParams.set("date", date);
    }

    const apiResponse = await fetch(url, {
      headers: {
        "x-apisports-key": footballKey,
        "Accept": "application/json",
      },
    });

    if (!apiResponse.ok) {
      return json(
        {
          error: `Football API request failed (${apiResponse.status}).`,
        },
        502,
      );
    }

    const payload = await apiResponse.json();

    if (payload.errors && Object.keys(payload.errors).length > 0) {
      return json(
        {
          error: JSON.stringify(payload.errors),
        },
        502,
      );
    }

    const rows = Array.isArray(payload.response) ? payload.response : [];

    const { data: deletedRows } = await userClient
      .from("matches")
      .select("external_fixture_id")
      .not("deleted_at", "is", null);

    const deletedFixtureIds = new Set(
      (deletedRows ?? [])
        .map((row: any) => Number(row.external_fixture_id))
        .filter((id: number) => Number.isFinite(id)),
    );

    const fixtures = rows
      .filter(
        (row: any) =>
          !deletedFixtureIds.has(Number(row.fixture?.id)),
      )
      .map((row: any) => ({
      fixture_id: row.fixture?.id,
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

    fixtures.sort((a: any, b: any) => {
      const at = new Date(a.kickoff_at ?? 0).getTime();
      const bt = new Date(b.kickoff_at ?? 0).getTime();
      if (at !== bt) return at - bt;
      return String(a.home_name ?? "").localeCompare(
        String(b.home_name ?? ""),
      );
    });

    return json({
      fixtures,
      results: fixtures.length,
      hidden_deleted: deletedFixtureIds.size,
      remaining:
        apiResponse.headers.get("x-ratelimit-requests-remaining") ?? null,
    });
  } catch (error) {
    return json(
      {
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
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
