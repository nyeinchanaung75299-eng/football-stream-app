import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Read-only experiment. This function never writes to matches, channels,
// fixtures, or any other production tables.
const competitions: Record<string, string> = {
  "saudi-professional-league": "Saudi Professional League",
  "united-states-major-league-soccer": "Major League Soccer",
  "english-premier-league": "English Premier League",
  "uefa-champions-league": "UEFA Champions League",
};
const myanmarOffsetMs = 390 * 60 * 1000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function validUtcDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const parsed = new Date(value + "T00:00:00.000Z");
  return !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

function utcDaysForMyanmarDay(date: string): string[] {
  // A Myanmar calendar day spans the previous and current UTC dates.
  const midnight = Date.parse(date + "T00:00:00.000Z");
  return [
    new Date(midnight - 86400000).toISOString().slice(0, 10),
    date,
  ];
}

async function loadUtcDay(date: string, competition: string) {
  const url = new URL("https://sportscore.com/api/v1/fixtures/");
  url.searchParams.set("sport", "football");
  url.searchParams.set("date", date);
  url.searchParams.set("competition", competition);
  url.searchParams.set("limit", "200");
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) {
    throw new Error("SportScore returned HTTP " + response.status);
  }
  const data: unknown = await response.json();
  if (!data || typeof data !== "object" ||
      !Array.isArray((data as Record<string, unknown>).matches)) {
    throw new Error("SportScore returned an unexpected response");
  }
  const matches = (data as { matches: unknown[] }).matches;
  return { matches, atLimit: matches.length >= 200 };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond({ error: "Method not allowed" }, 405);
  }
  const header = request.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ") || header.length < 10) {
    return respond({ error: "Admin sign-in required" }, 401);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !anonKey) return respond({ error: "Server not configured" }, 500);

    const client = createClient(url, anonKey, {
      global: { headers: { Authorization: header } },
    });
    const { data: { user }, error: authError } = await client.auth.getUser();
    if (authError || !user) return respond({ error: "Invalid session" }, 401);
    const { data: profile, error: profileError } = await client
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();
    if (profileError || profile?.role !== "admin") {
      return respond({ error: "Admin access required" }, 403);
    }

    const body: unknown = await request.json().catch(() => null);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return respond({ error: "Invalid request" }, 400);
    }
    const input = body as Record<string, unknown>;
    const date = input.date;
    const competition = input.competition;
    if (!validUtcDate(date)) return respond({ error: "Invalid date" }, 400);
    if (typeof competition !== "string" ||
        !Object.hasOwn(competitions, competition)) {
      return respond({ error: "Unsupported competition" }, 400);
    }

    const days = utcDaysForMyanmarDay(date);
    // Both UTC days are required. Do not silently display partial results.
    let results: Awaited<ReturnType<typeof loadUtcDay>>[];
    try {
      results = await Promise.all(days.map((day) => loadUtcDay(day, competition)));
    } catch (error) {
      console.error("SportScore preview request failed", error);
      return respond({ error: "SportScore fixture request failed" }, 502);
    }

    const seen = new Set<string>();
    const matches: Record<string, unknown>[] = [];
    let malformed = 0;
    for (const result of results) {
      for (const row of result.matches) {
        if (!row || typeof row !== "object") {
          malformed++;
          continue;
        }
        const raw = row as Record<string, unknown>;
        const home = typeof raw.home === "string" ? raw.home.trim() : "";
        const away = typeof raw.away === "string" ? raw.away.trim() : "";
        const kickoffMs = Date.parse(String(raw.time ?? ""));
        if (!home || !away || !Number.isFinite(kickoffMs)) {
          malformed++;
          continue;
        }
        const yangonDay = new Date(kickoffMs + myanmarOffsetMs)
          .toISOString().slice(0, 10);
        if (yangonDay !== date) continue;
        const key = home.toLowerCase() + "|" + away.toLowerCase() + "|" +
          String(kickoffMs);
        if (seen.has(key)) continue;
        seen.add(key);
        matches.push({
          home,
          away,
          home_score: raw.home_score ?? null,
          away_score: raw.away_score ?? null,
          status: String(raw.status ?? "unknown"),
          kickoff_at: new Date(kickoffMs).toISOString(),
          competition: competitions[competition],
        });
      }
    }

    matches.sort((a, b) =>
      String(a.kickoff_at).localeCompare(String(b.kickoff_at))
    );
    return respond({
      provider: "sportscore",
      preview_only: true,
      date_myanmar: date,
      competition,
      competition_name: competitions[competition],
      count: matches.length,
      matches,
      utc_dates_checked: days,
      possibly_truncated: results.some((item) => item.atLimit),
      ignored_malformed_rows: malformed,
    });
  } catch (error) {
    console.error("SportScore preview failed", error);
    return respond({ error: "Unable to load SportScore preview" }, 500);
  }
});
