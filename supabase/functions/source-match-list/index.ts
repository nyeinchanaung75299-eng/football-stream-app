import { websiteMatches, websiteStreams, experimentalMatches, isExperimentalFootballSource } from "../_shared/website_sources.mjs";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { englishFootballName, firstFootballName, providerEnglishName, sourceFootballNames, englishStreamerName } from "../_shared/football_names.mjs";
import { sourceMatchRows, isFootballSourceRow, hasPublishedSourceRoom } from "../_shared/source_match_rows.mjs";
import { sourceLogo } from "../_shared/source_team_logos.mjs";
import { loadYyzbFootballCatalogue } from '../_shared/yyzb_schedule.mjs';
import { footballHighlights } from '../_shared/football_highlights.mjs';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SOCO_MATCHES_URL = "https://json.vnres.co/matches.json";
const YYZB_MATCHES_URL = "https://json.ncctrials.com/matches.json";
const FAWA_HOME = "http://www.fawanews.sc/";
const COLA_HOME = "https://colatv66.live/";
const COLA_API = "https://api.cltvlv.com/api/matches";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "Not signed in." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: {
        headers: { Authorization: authHeader },
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
    if (body.source === 'highlights') {
      return json(await footballHighlights(body));
    }
    const source = normalizeSource(body.source);
    if (source === null) {
      return json({ error: "Unsupported source." }, 400);
    }

    if (isExperimentalFootballSource(source)) {
      return json(await experimentalMatches(source));
    }

    if (source === "sofascore") {
      try {
        return json(await sofascoreMatches(body.date));
      } catch (_) {
        return json(await fallbackFootballMatches({
          supabaseUrl,
          anonKey,
          authHeader,
          rawDate: body.date,
        }));
      }
    }

    if (source === "arena") {
      const payload = { ok: true, source, matches: await websiteMatches(source, { date: body.date }), generated_at: new Date().toISOString() };
      return json(payload);
    }

    if (source === "fawa") {
      return await fawaMatches();
    }
    if (source === "cola") {
      return await colaMatches();
    }

    return await jsonpMatches({
      source: source === "yyzb" ? "yyzb" : "soco",
      url: source === "yyzb" ? YYZB_MATCHES_URL : SOCO_MATCHES_URL,
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

function normalizeSource(value: unknown): "soco" | "yyzb" | "fawa" | "cola" | "arena" | "sofascore" | null {
  const source = String(value ?? "").trim().toLowerCase();
  if (!source) return "soco";
  if (isExperimentalFootballSource(source)) return source as any;
  if (source === "soco" || source === "yyzb" || source === "fawa" || source === "cola" || source === "arena" || source === "sofascore") {
    return source;
  }
  return null;
}


async function fallbackFootballMatches(args: { supabaseUrl: string; anonKey: string; authHeader: string; rawDate: unknown }) {
  const value = String(args.rawDate ?? "").trim();
  const date = /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : new Date().toISOString().slice(0, 10);
  const response = await fetch(args.supabaseUrl + "/functions/v1/football-fixtures", {
    method: "POST",
    headers: {
      Authorization: args.authHeader,
      apikey: args.anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ mode: "all", date }),
  });
  if (!response.ok) throw new Error("Football fixture fallback returned HTTP " + response.status + ".");
  const payload = await response.json();
  const fixtures = Array.isArray(payload?.fixtures) ? payload.fixtures : [];
  const matches = fixtures.map((row: any) => {
    const id = String(row?.fixture_id ?? row?.id ?? "").trim();
    const home = String(row?.home_name ?? row?.home_team ?? "").trim();
    const away = String(row?.away_name ?? row?.away_team ?? "").trim();
    if (!id || !home || !away) return null;
    const status = String(row?.status_short ?? row?.status ?? "NS").toUpperCase();
    const live = row?.is_live === true || status === "LIVE" || status === "1H" || status === "2H";
    return {
      source: "sofascore",
      source_id: id,
      fixture_id: Number(row?.fixture_id ?? row?.id),
      provider: "fixture-fallback",
      league: String(row?.league_name ?? row?.league ?? "Football"),
      home_team: home,
      away_team: away,
      home_logo: row?.home_logo ?? null,
      away_logo: row?.away_logo ?? null,
      poster_url: row?.poster_url ?? null,
      match_time: normalizeMatchTime(row?.kickoff_at ?? row?.match_time),
      hot: live,
      status: live ? "LIVE" : status,
      match_status: live ? "LIVE" : status,
      anchors: [],
    };
  }).filter((row: any) => row != null).sort(compareMatches);
  return { ok: true, source: "sofascore", served_by: "football-fixtures", matches, results: matches.length, date, generated_at: new Date().toISOString() };
}

async function sofascoreMatches(rawDate: unknown) {
  const value = String(rawDate ?? "").trim();
  const date = /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? value
    : new Date().toISOString().slice(0, 10);
  let raw = "";
  let lastError: unknown = null;
  for (const base of [
    "https://api.sofascore.com/api/v1/sport/football/scheduled-events/",
    "https://www.sofascore.com/api/v1/sport/football/scheduled-events/",
  ]) {
    try {
      raw = await fetchText(base + encodeURIComponent(date));
      break;
    } catch (error) {
      lastError = error;
    }
  }
  if (!raw) {
    throw lastError instanceof Error
      ? lastError
      : new Error("SofaScore schedule is unavailable.");
  }
  const payload = JSON.parse(raw);
  const events = Array.isArray(payload?.events) ? payload.events : [];
  const matches = events.slice(0, 1000).map((event: any) => {
    const id = Number(event?.id);
    const home = event?.homeTeam ?? {};
    const away = event?.awayTeam ?? {};
    const timestamp = Number(event?.startTimestamp);
    if (!Number.isFinite(id) || !home?.name || !away?.name) return null;
    const status = String(event?.status?.type ?? event?.status?.description ?? "").toLowerCase();
    const live = status === "inprogress" || status === "live";
    return {
      source: "sofascore",
      source_id: String(id),
      fixture_id: 9000000000 + id,
      provider: "sofascore",
      league: event?.tournament?.name ?? event?.uniqueTournament?.name ?? "Football",
      home_team: String(home.name),
      away_team: String(away.name),
      home_logo: home?.id ? "https://img.sofascore.com/api/v1/team/" + home.id + "/image" : null,
      away_logo: away?.id ? "https://img.sofascore.com/api/v1/team/" + away.id + "/image" : null,
      poster_url: "https://img.sofascore.com/api/v1/event/" + id + "/share-image/16x9",
      match_time: Number.isFinite(timestamp)
        ? new Date(timestamp * 1000).toISOString()
        : null,
      hot: live,
      status: live ? "LIVE" : "NS",
      match_status: live ? "LIVE" : "NS",
      anchors: [],
    };
  }).filter((row: any) => row != null).sort(compareMatches);
  return { ok: true, source: "sofascore", matches, results: matches.length, date, generated_at: new Date().toISOString() };
}

async function jsonpMatches(args: {
  source: "soco" | "yyzb";
  url: string;
}) {
  const payload = args.source==='yyzb'?await loadYyzbFootballCatalogue(fetchText):parseJsonp(await fetchText(`${args.url}?v=${Date.now()}`));
  const matches = sourceMatchRows(payload?.data ?? payload,
    (row: any) => isFootballSourceRow(row, { allowUnclassified: args.source === "soco" }))
    .map((row: any) => {
      const scheduleId =
        row.scheduleId ?? row.schedule_id ?? row.fixtureId ??
        row.matchId ?? row.match_id ?? row.gameId ?? row.eventId ?? row.id;
      const anchors = Array.isArray(row.anchors)
        ? row.anchors
        : Array.isArray(row.anchorList)
          ? row.anchorList
          : [];

      return {
        source: args.source,
        source_id: String(scheduleId ?? ""),
        schedule_id: scheduleId,
        ...sourceFootballNames(row, args.source === "yyzb"),
        home_logo: sourceLogo(row, "home", args.source),
        away_logo: sourceLogo(row, "away", args.source),
        match_time: normalizeMatchTime(
          row.matchTime ?? row.match_time ?? row.startTime ?? row.kickoff,
        ),
        hot:
          row.hot === true ||
          String(row.hot ?? row.isHot ?? "0") === "1",
        anchors: anchors
          .map((anchor: any, index: number) => {
            const names = englishStreamerName({
              ...anchor,
              nickName: decodeHtml(stripTags(String(anchor.nickName ?? anchor.name ?? "")))
                .replace(/\s+/g, " ").trim(),
            }, index);
            return {
              uid: anchor.uid ?? anchor.id ?? null,
              // Older Admin APKs import by nick_name. Preserve that identity;
              // updated clients use nick_name_en for display only.
              nick_name: names.import_name,
              ...(args.source === "yyzb" ? { nick_name_en: names.nick_name } : {}),
              ...(names.commentary_language ? { commentary_language: names.commentary_language } : {}),
              room_num: roomNumber(anchor),
            };
          })
          .filter((anchor: any) => anchor.room_num),
      };
    })
    // Match-list parity with the source: finished games are not a history
    // archive, and upstream removal is authoritative on a successful fetch.
    .filter((row: any) => !staleKickoff(row.match_time) &&
      (args.source !== "yyzb" || hasPublishedSourceRoom(row)))
    .sort(compareMatches);

  return json({
    ok: true,
    source: args.source,
    matches,
    results: matches.length,
    generated_at: new Date().toISOString(),
  });
}

async function fawaMatches() {
  const html = await fetchFawaText(FAWA_HOME);
  const grouped = new Map<string, any>();
  const nameRegex =
    /<div\s+class=["']user-item__name["'][^>]*>([\s\S]*?)<\/div>/gi;

  let hit: RegExpExecArray | null;
  while ((hit = nameRegex.exec(html)) !== null) {
    const name = decodeHtml(stripTags(hit[1])).replace(/\s+/g, " ").trim();
    if (!/\bvs\b/i.test(name)) continue;

    const before = html.slice(Math.max(0, hit.index - 1800), hit.index);
    const hrefRegex = /href=["']([^"']+\.html)["']/gi;
    let hrefHit: RegExpExecArray | null;
    let href = "";
    while ((hrefHit = hrefRegex.exec(before)) !== null) {
      href = decodeHtml(hrefHit[1]).trim();
    }
    if (!href) continue;

    const after = html.slice(nameRegex.lastIndex, nameRegex.lastIndex + 900);
    const playingHit = after.match(
      /class=["']user-item__playing["'][^>]*>([\s\S]*?)<\/div>/i,
    );
    const playing = playingHit
      ? decodeHtml(stripTags(playingHit[1])).replace(/\s+/g, " ").trim()
      : "Football";

    const baseName = name
      .replace(/\s*---\s*CH\s*\d+\s*$/i, "")
      .trim();
    const teams = baseName.split(/\s+vs\s+/i);
    if (teams.length < 2) continue;

    const key = baseName.toLowerCase();
    const existing = grouped.get(key) ?? {
      source: "fawa",
      source_id: key,
      page_url: absoluteFawaUrl(href),
      league:
        playing.replace(/\s+\d{1,2}:\d{2}\s*$/, "").trim() ||
        "Football",
      home_team: teams[0]?.trim() || baseName,
      away_team: teams[1]?.trim() || "",
      match_time: null,
      time_label: playing,
      hot: false,
      anchors: [],
    };

    const pageUrl = absoluteFawaUrl(href);
    if (
      pageUrl &&
      !existing.anchors.some((item: any) => item.page_url === pageUrl)
    ) {
      existing.anchors.push({
        uid: href,
        nick_name: channelLabel(name),
        room_num: href,
        page_url: pageUrl,
      });
    }

    grouped.set(key, existing);
  }

  // Fallback for Fawa revisions that drop the user-item__name class.
  // Only same-site .html links whose visible text contains "vs" are accepted.
  if (grouped.size === 0) {
    const anchorRegex =
      /<a\b[^>]*href=["']([^"']+\.html(?:\?[^"']*)?)["'][^>]*>([\s\S]{0,2200}?)<\/a>/gi;
    let anchorHit: RegExpExecArray | null;
    while ((anchorHit = anchorRegex.exec(html)) !== null) {
      const href = decodeHtml(anchorHit[1]).trim();
      const visible = decodeHtml(stripTags(anchorHit[2]))
        .replace(/\s+/g, " ")
        .trim();
      if (!/\bvs\b/i.test(visible)) continue;

      const cleaned = visible
        .replace(/\s*---\s*CH\s*\d+\s*$/i, "")
        .trim();
      const teams = cleaned.split(/\s+vs\s+/i);
      if (teams.length < 2) continue;

      const pageUrl = absoluteFawaUrl(href);
      if (!pageUrl) continue;
      const key = cleaned.toLowerCase();

      const existing = grouped.get(key) ?? {
        source: "fawa",
        source_id: key,
        page_url: pageUrl,
        league: "Football",
        home_team: teams[0]?.trim() || cleaned,
        away_team: teams[1]?.trim() || "",
        home_logo: null,
        away_logo: null,
        match_time: null,
        time_label: null,
        hot: false,
        status: null,
        match_status: null,
        anchors: [],
      };

      if (!existing.anchors.some((item: any) => item.page_url === pageUrl)) {
        existing.anchors.push({
          uid: href,
          nick_name: channelLabel(visible),
          icon: null,
          room_num: href,
          page_url: pageUrl,
        });
      }

      grouped.set(key, existing);
    }
  }

  const matches = [...grouped.values()].sort((a, b) =>
    String(a.home_team).localeCompare(String(b.home_team))
  );

  return json({
    ok: true,
    source: "fawa",
    matches,
    results: matches.length,
    generated_at: new Date().toISOString(),
  });
}

async function colaMatches() {
  const payload = await fetchColaMatchesPayload();
  const rawData = payload?.data;
  if (!rawData || typeof rawData !== "object" || Array.isArray(rawData)) {
    throw new Error("ColaTV returned an invalid match payload.");
  }

  const matches = Object.entries(rawData)
    .map(([slug, raw]: [string, any]) => colaMatchRow(slug, raw))
    .filter((row: any) => row != null)
    .sort(compareMatches);

  return json({
    ok: true,
    source: "cola",
    matches,
    results: matches.length,
    language: "en",
    generated_at: new Date().toISOString(),
  });
}

async function fetchColaMatchesPayload() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(`${COLA_API}?v=${Date.now()}`, {
      headers: {
        Accept: "application/json",
        "Accept-Language": "en-US,en;q=0.9",
        "X-Domain": "colatv66.live",
        Referer: COLA_HOME,
        Origin: "https://colatv66.live",
        "User-Agent":
          "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36 NCA-Admin/9.8",
        "Cache-Control": "no-cache",
        Pragma: "no-cache",
      },
      redirect: "follow",
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`ColaTV API returned HTTP ${response.status}.`);
    }
    const payload = await response.json();
    if (String(payload?.code ?? "") !== "0000") {
      throw new Error(
        String(payload?.message ?? payload?.msg ?? "ColaTV API returned an error."),
      );
    }
    return payload;
  } finally {
    clearTimeout(timer);
  }
}

function colaMatchRow(slug: string, row: any) {
  if (Number(row?.sportId ?? row?.sport_id ?? 0) !== 1) return null;

  const node = row?.node_api_data ?? {};
  const homeNode = node?.home_team ?? {};
  const awayNode = node?.away_team ?? {};
  const competitionNode = node?.competition ?? {};

  const matchId = String(
    row?.matchId ?? row?.match_id ?? node?.match_id ?? slug,
  ).trim();
  if (!matchId) return null;

  const home = englishFootballName(firstFootballName(
    providerEnglishName(homeNode), row?.homeTeamNameEn,
    homeNode, row?.homeTeamName, row?.home_team, "Home",
  ));
  const away = englishFootballName(firstFootballName(
    providerEnglishName(awayNode), row?.awayTeamNameEn,
    awayNode, row?.awayTeamName, row?.away_team, "Away",
  ));
  const league = englishFootballName(firstFootballName(
    providerEnglishName(competitionNode), row?.competitionNameEn,
    competitionNode, row?.competitionName,
    row?.competition, "Football",
  ), "league");
  const statusNum = Number(
    row?.matchStatus ?? row?.match_status_num ?? node?.status_id ?? 1,
  );
  const hasSource = colaHasPlayableSource(row);

  return {
    source: "cola",
    source_id: matchId,
    schedule_id: matchId,
    slug,
    page_url: `${COLA_HOME}${encodeURI(slug)}`,
    league,
    home_team: home,
    away_team: away,
    home_logo:
      homeNode?.logo ??
      row?.homeTeamLogo ??
      row?.home_team?.logo ??
      null,
    away_logo:
      awayNode?.logo ??
      row?.awayTeamLogo ??
      row?.away_team?.logo ??
      null,
    match_time: normalizeMatchTime(
      row?.matchTime ?? row?.match_time ?? node?.match_time,
    ),
    hot: statusNum === 2,
    status: statusNum === 2 ? "LIVE" : statusNum === 3 ? "FT" : "NS",
    match_status:
      statusNum === 2 ? "LIVE" : statusNum === 3 ? "FT" : "SCHEDULED",
    anchors: hasSource
      ? [{
          uid: matchId,
          nick_name: "ColaTV",
          icon: null,
          room_num: matchId,
          page_url: `${COLA_HOME}${encodeURI(slug)}`,
        }]
      : [],
  };
}

function colaHasPlayableSource(row: any) {
  const candidates: unknown[] = [
    row?.videoUrl,
    row?.video_url,
  ];
  const anchors = Array.isArray(row?.anchorAppointmentVoList)
    ? row.anchorAppointmentVoList
    : [];
  for (const anchor of anchors) {
    candidates.push(anchor?.playStreamAddress2);
    candidates.push(anchor?.playStreamAddress);
    if (Array.isArray(anchor?.servers)) {
      candidates.push(...anchor.servers);
    }
  }
  return candidates.some((value) => colaMediaUrl(value) != null);
}

function colaMediaUrl(value: unknown) {
  const raw = String(value ?? "").trim();
  if (!/^https?:\/\//i.test(raw)) return null;
  const lower = raw.toLowerCase();
  if (
    !lower.includes(".m3u8") &&
    !lower.includes(".flv") &&
    !lower.includes(".mpd") &&
    !lower.includes(".mp4")
  ) {
    return null;
  }
  try {
    const url = new URL(raw);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    return url.toString();
  } catch (_) {
    return null;
  }
}

function staleKickoff(value: unknown) {
  const normalized = normalizeMatchTime(value);
  if (!normalized) return false;
  const millis = Date.parse(normalized);
  if (!Number.isFinite(millis)) return false;
  return Date.now() - millis > 4 * 60 * 60 * 1000;
}

function normalizeMatchTime(value: unknown) {
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

function roomNumber(anchor: any) {
  return String(
    anchor?.anchor?.roomNum ??
      anchor?.anchor?.room_num ??
      anchor?.room?.roomNum ??
      anchor?.roomNum ??
      anchor?.room_num ??
      anchor?.roomId ??
      "",
  ).trim();
}

function compareMatches(a: any, b: any) {
  const at = new Date(a.match_time ?? 0).getTime();
  const bt = new Date(b.match_time ?? 0).getTime();
  if (at !== bt) return at - bt;
  return String(a.home_team ?? "").localeCompare(String(b.home_team ?? ""));
}

function absoluteFawaUrl(href: string) {
  try {
    return new URL(href, FAWA_HOME).toString();
  } catch (_) {
    return "";
  }
}

function channelLabel(name: string) {
  const channel = name.match(/---\s*(CH\s*\d+)\s*$/i);
  return channel?.[1]?.toUpperCase() ?? "Main";
}

function stripTags(value: string) {
  return value.replace(/<[^>]*>/g, " ");
}

function decodeHtml(value: string) {
  return value
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

async function fetchFawaText(url: string) {
  const candidates = [url];

  try {
    const parsed = new URL(url);
    if (
      parsed.hostname === "www.fawanews.sc" ||
      parsed.hostname === "fawanews.sc"
    ) {
      const alt = new URL(parsed.toString());
      alt.protocol = parsed.protocol === "https:" ? "http:" : "https:";
      candidates.push(alt.toString());

      const hostAlt = new URL(parsed.toString());
      hostAlt.hostname =
        parsed.hostname === "www.fawanews.sc"
          ? "fawanews.sc"
          : "www.fawanews.sc";
      candidates.push(hostAlt.toString());
    }
  } catch (_) {}

  let lastError: unknown = null;
  for (const candidate of [...new Set(candidates)]) {
    try {
      return await fetchText(candidate);
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError instanceof Error
    ? lastError
    : new Error("Fawa source is unreachable.");
}

async function fetchText(url: string) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);

  try {
    const response = await fetch(url, {
      headers: {
        Accept: "application/javascript,application/json,text/html,text/plain,*/*",
        "User-Agent":
          "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36 NCA-Admin/9.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Cache-Control": "no-cache",
        Pragma: "no-cache",
      },
      redirect: "follow",
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Source returned HTTP ${response.status}.`);
    }

    return await response.text();
  } finally {
    clearTimeout(timer);
  }
}

function parseJsonp(text: string): any {
  const trimmed = text.replace(/^\uFEFF/, "").trim().replace(/;\s*$/, "");

  const candidates = [trimmed];

  const firstParen = trimmed.indexOf("(");
  const lastParen = trimmed.lastIndexOf(")");
  if (firstParen >= 0 && lastParen > firstParen) {
    candidates.push(trimmed.slice(firstParen + 1, lastParen).trim());
  }

  const assignment = trimmed.match(/^[\w.$]+\s*=\s*([\s\S]+)$/);
  if (assignment?.[1]) candidates.push(assignment[1].trim());

  const firstBrace = trimmed.indexOf("{");
  const lastBrace = trimmed.lastIndexOf("}");
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    candidates.push(trimmed.slice(firstBrace, lastBrace + 1));
  }

  for (const candidate of candidates) {
    try {
      return JSON.parse(candidate.replace(/;\s*$/, ""));
    } catch (_) {}
  }

  throw new Error("Source returned an invalid JSON/JSONP payload.");
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
