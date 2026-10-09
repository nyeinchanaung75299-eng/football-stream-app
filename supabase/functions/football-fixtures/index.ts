import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { englishFootballName } from "../_shared/football_names.mjs";

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
        if (result.fixtures.length > 0) {
          return json({
            ...result,
            provider: "api_football",
            fallback_used: false,
          });
        }
        failures.push({
          provider: "api_football",
          error: "provider returned 0 fixtures",
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
        if (result.fixtures.length > 0) {
          return json({
            ...result,
            provider: "football_data_org",
            fallback_used: failures.length > 0,
            compatibility_key_used: !footballDataKey && Boolean(apiFootballKey),
            primary_failure: failures[0]?.error ?? null,
          });
        }
        failures.push({
          provider: "football_data_org",
          error: "provider returned 0 fixtures",
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        failures.push({ provider: "football_data_org", error: message });
        console.error("football-data.org fixture load failed:", message);
      }
    }

    try {
      const sourceResult = await loadSourceFallbackFixtures({
        supabaseUrl,
        anonKey,
        authHeader,
        mode,
        date,
        deletedFixtureIds,
      });

      if (sourceResult.fixtures.length > 0) {
        return json({
          ...sourceResult,
          provider: "source_fallback",
          fallback_used: true,
          primary_failures: failures,
        });
      }

      failures.push({
        provider: "source_fallback",
        error: "Soco/YYZB returned 0 fixtures for the selected date.",
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      failures.push({ provider: "source_fallback", error: message });
      console.error("Soco/YYZB fixture fallback failed:", message);
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

async function loadSourceFallbackFixtures(args: {
  supabaseUrl: string;
  anonKey: string;
  authHeader: string;
  mode: "live" | "date";
  date: string;
  deletedFixtureIds: Set<number>;
}) {
  const fixtures: any[] = [];
  const failures: string[] = [];

  for (const source of ["soco", "yyzb"] as const) {
    try {
      const response = await fetch(
        args.supabaseUrl.replace(/\/+$/, "") + "/functions/v1/source-match-list",
        {
          method: "POST",
          headers: {
            apikey: args.anonKey,
            Authorization: args.authHeader,
            "Content-Type": "application/json",
            Accept: "application/json",
          },
          body: JSON.stringify({ source }),
        },
      );

      const payload = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(
          String(payload?.error ?? `source returned HTTP ${response.status}`),
        );
      }

      const rows = Array.isArray(payload?.matches) ? payload.matches : [];
      for (const row of rows) {
        const kickoff = normalizeSourceKickoff(row?.match_time);
        if (!kickoff) continue;

        const statusShort = sourceStatus(row);
        const isLive =
          ["LIVE", "1H", "HT", "2H", "ET", "INT", "SUSP"].includes(
            statusShort,
          ) ||
          isLikelyLiveKickoff(kickoff);

        if (args.mode === "date") {
          if (yangonDate(kickoff) !== args.date) continue;
        } else if (!isLive) {
          continue;
        }

        const sourceKey = String(
          row?.source_id ??
            row?.schedule_id ??
            `${row?.home_team ?? ""}|${row?.away_team ?? ""}|${kickoff}`,
        );
        const fixtureId = sourceFixtureId(source, sourceKey);
        if (args.deletedFixtureIds.has(fixtureId)) continue;

        fixtures.push({
          provider: source,
          fixture_id: fixtureId,
          provider_fixture_id: sourceKey,
          kickoff_at: kickoff,
          status_short: statusShort,
          status_long: row?.match_status ?? row?.status ?? null,
          is_live: isLive,
          league_name: englishFootballName(row?.league ?? "Football", "league"),
          league_logo: null,
          home_name: englishFootballName(row?.home_team ?? "Home"),
          away_name: englishFootballName(row?.away_team ?? "Away"),
          home_logo: row?.home_logo ?? row?.home_logo_url ?? null,
          away_logo: row?.away_logo ?? row?.away_logo_url ?? null,
        });
      }
    } catch (error) {
      failures.push(
        `${source}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  const deduped = new Map<string, any>();
  for (const fixture of fixtures) {
    const key = sourceFixtureDedupKey(fixture);
    const current = deduped.get(key);
    if (current == null) {
      deduped.set(key, fixture);
      continue;
    }

    // Soco and YYZB can publish the same match with different language
    // labels. Keep one card and prefer the row with the clearer English name,
    // while filling any missing logo/status fields from the other source.
    const preferred =
      fixtureEnglishScore(fixture) > fixtureEnglishScore(current)
        ? fixture
        : current;
    const other = preferred === fixture ? current : fixture;

    deduped.set(key, {
      ...other,
      ...preferred,
      home_logo: preferred.home_logo ?? other.home_logo,
      away_logo: preferred.away_logo ?? other.away_logo,
      league_logo: preferred.league_logo ?? other.league_logo,
      status_short:
        preferred.status_short !== "NS"
          ? preferred.status_short
          : other.status_short,
      is_live: preferred.is_live === true || other.is_live === true,
    });
  }

  const result = [...deduped.values()];
  sortFixtures(result);

  if (result.length === 0 && failures.length === 2) {
    throw new Error(failures.join(" | "));
  }

  return {
    fixtures: result,
    results: result.length,
    hidden_deleted: args.deletedFixtureIds.size,
    fallback_sources: ["soco", "yyzb"],
    source_failures: failures,
    remaining: null,
  };
}

function sourceFixtureDedupKey(fixture: any) {
  const kickoff = new Date(fixture?.kickoff_at ?? 0);
  const minute = Number.isFinite(kickoff.getTime())
    ? kickoff.toISOString().slice(0, 16)
    : yangonDate(String(fixture?.kickoff_at ?? ""));

  const homeLogo = canonicalLogoKey(fixture?.home_logo);
  const awayLogo = canonicalLogoKey(fixture?.away_logo);
  if (homeLogo && awayLogo) {
    return [minute, "logos", homeLogo, awayLogo].join("|");
  }

  return [
    minute,
    "names",
    canonicalTeamName(fixture?.home_name),
    canonicalTeamName(fixture?.away_name),
  ].join("|");
}

function canonicalLogoKey(value: unknown) {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  try {
    const url = new URL(raw);
    return (url.hostname + url.pathname)
      .toLowerCase()
      .replace(/\/+$/, "");
  } catch (_) {
    return raw.toLowerCase().split("?")[0];
  }
}

function canonicalTeamName(value: unknown) {
  const original = String(value ?? "").normalize("NFKC").toLowerCase();
  let text = original
    .replace(/乌兹别克斯坦/g, "uzbekistan")
    .replace(/乌兹别克/g, "uzbekistan")
    .replace(/韩国/g, "south korea")
    .replace(/越南/g, "vietnam")
    .replace(/哈萨克斯坦/g, "kazakhstan");

  // Some feeds partially translate a name, producing strings such as
  // "Uzbekistan斯坦". If Latin text is already present, remove leftover Han
  // suffixes so the translated and untranslated provider rows collapse.
  if (/[a-z]/.test(text)) {
    text = text.replace(/[\u3400-\u9fff]+/g, " ");
  }

  const latinKey = text
    .replace(/\b(?:fc|cf|sc|afc)\b/g, " ")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (latinKey) return latinKey;

  // Unknown non-Latin names must not collapse to an empty key. Preserve
  // Unicode letters/numbers as a stable provider-independent fallback.
  return original
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function fixtureEnglishScore(fixture: any) {
  const text = [
    fixture?.league_name,
    fixture?.home_name,
    fixture?.away_name,
  ].join(" ");
  const latin = (text.match(/[A-Za-z]/g) ?? []).length;
  const han = (text.match(/[\u3400-\u9fff]/g) ?? []).length;
  return latin - han * 4;
}

function normalizeSourceKickoff(value: unknown) {
  if (value == null || value === "") return null;

  const numeric = Number(value);
  if (Number.isFinite(numeric) && numeric > 0) {
    const millis = numeric < 1_000_000_000_000 ? numeric * 1000 : numeric;
    const date = new Date(millis);
    if (Number.isFinite(date.getTime())) return date.toISOString();
  }

  const parsed = new Date(String(value));
  return Number.isFinite(parsed.getTime()) ? parsed.toISOString() : null;
}

function yangonDate(value: string) {
  const millis = new Date(value).getTime();
  if (!Number.isFinite(millis)) return "";
  return new Date(millis + 390 * 60 * 1000).toISOString().slice(0, 10);
}

function sourceStatus(row: any) {
  const raw = String(
    row?.status_short ??
      row?.match_status ??
      row?.status ??
      "",
  ).trim().toUpperCase();

  if (["FT", "AET", "PEN"].includes(raw)) return raw;
  if (/LIVE|PLAY|1H|2H|HT|ET|INT|SUSP/.test(raw)) return "LIVE";
  return "NS";
}

function isLikelyLiveKickoff(kickoff: string) {
  const time = new Date(kickoff).getTime();
  if (!Number.isFinite(time)) return false;
  const now = Date.now();
  return time >= now - 3 * 60 * 60 * 1000 &&
    time <= now + 30 * 60 * 1000;
}

function sourceFixtureId(source: "soco" | "yyzb", key: string) {
  let hash = 2166136261;
  for (const char of `${source}:${key}`) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  const unsigned = hash >>> 0;
  const base = source === "soco" ? 6_000_000_000_000 : 7_000_000_000_000;
  return -(base + unsigned);
}

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
      league_name: row.league?.name ?? "Football",
      league_logo: row.league?.logo ?? null,
      home_name: row.teams?.home?.name ?? "Home",
      away_name: row.teams?.away?.name ?? "Away",
      home_logo: row.teams?.home?.logo ?? null,
      away_logo: row.teams?.away?.logo ?? null,
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

  return {
    provider: "football_data_org",
    fixture_id: fixtureId,
    provider_fixture_id: rawId,
    kickoff_at: row?.utcDate ?? null,
    status_short: statusShort,
    status_long: row?.status ?? null,
    is_live: isLive,
    league_name: row?.competition?.name ?? "Football",
    league_logo: row?.competition?.emblem ?? null,
    home_name: row?.homeTeam?.name ?? row?.homeTeam?.shortName ?? "Home",
    away_name: row?.awayTeam?.name ?? row?.awayTeam?.shortName ?? "Away",
    home_logo: row?.homeTeam?.crest ?? null,
    away_logo: row?.awayTeam?.crest ?? null,
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
