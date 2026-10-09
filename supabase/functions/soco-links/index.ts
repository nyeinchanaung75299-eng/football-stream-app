import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { englishFootballName, firstFootballName, providerEnglishName } from "../_shared/football_names.mjs";
import { probeStreamFirstChunk } from "../_shared/stream_probe.mjs";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SOCO_MATCHES_URL = "https://json.vnres.co/matches.json";
const SOCO_ROOM_BASE = "https://json.vnres.co/room";

const YYZB_MATCHES_URL = "https://json.ncctrials.com/match_all.json";
const YYZB_ROOM_BASE = "https://json.ncctrials.com/room";

const FAWA_BASE = "http://www.fawanews.sc";
const FAWA_HOME = FAWA_BASE + "/";
const COLA_HOME = "https://colatv66.live/";
const COLA_API = "https://api.cltvlv.com/api/matches";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST" && req.method !== "GET") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const requestUrl = new URL(req.url);
    const body: Record<string, any> = req.method === "GET"
      ? Object.fromEntries(requestUrl.searchParams.entries())
      : await req.json().catch(() => ({}));
    const viewerPublic =
      body.viewer_public === true ||
      body.viewer_public === "true" ||
      body.viewer_public === "1";

    // Admin continues to require a verified admin session. The Viewer may use
    // this function only in explicit read-only source-browser mode; this
    // function fetches public provider match/stream metadata and never writes
    // application data.
    if (!viewerPublic) {
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
    }

    const source = normalizeSource(body.source);
    const action = body.action === "streams" ? "streams" : "matches";

    if (action === "streams") {
      if (source === "fawa") {
        return await fawaStreams(body);
      }
      if (source === "cola") {
        return await colaStreams(body);
      }
      if (source === "yyzb") {
        return await roomStreams({
          source,
          roomBase: YYZB_ROOM_BASE,
          roomNum: body.room_num,
          scheduleId: body.schedule_id,
          refererOrigin: "https://m.yyzb22.live",
          statusOnly: body.status_only === true || body.status_only === "true" || body.status_only === "1",
          skipProbe: body.skip_probe === true || body.skip_probe === "true" || body.skip_probe === "1",
        });
      }
      return await roomStreams({
        source: "soco",
        roomBase: SOCO_ROOM_BASE,
        roomNum: body.room_num,
        scheduleId: body.schedule_id,
        refererOrigin: "https://m.sutbongtv.com",
        statusOnly: body.status_only === true || body.status_only === "true" || body.status_only === "1",
        skipProbe: body.skip_probe === true || body.skip_probe === "true" || body.skip_probe === "1",
      });
    }

    if (source === "fawa") {
      return await fawaMatches();
    }
    if (source === "cola") {
      return await colaMatches();
    }
    if (source === "yyzb") {
      return await jsonpMatches({
        source,
        url: YYZB_MATCHES_URL,
      });
    }

    return await jsonpMatches({
      source: "soco",
      url: SOCO_MATCHES_URL,
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

function normalizeSource(value: unknown) {
  const source = String(value ?? "soco").trim().toLowerCase();
  if (source === "yyzb" || source === "fawa" || source === "cola") {
    return source;
  }
  return "soco";
}

async function jsonpMatches(args: {
  source: "soco" | "yyzb";
  url: string;
}) {
  const raw = await fetchText(`${args.url}?v=${Date.now()}`);
  const payload = parseJsonp(raw);
  const flattened = collectMatchRows(payload?.data ?? payload);

  const seen = new Set<string>();
  const matches = flattened
    .filter(isFootballRow)
    .filter((row: any) => {
      const id = String(
        row.scheduleId ?? row.schedule_id ?? row.fixtureId ?? row.id ?? "",
      ).trim();
      if (!id || seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .map((row: any) => {
      const scheduleId =
        row.scheduleId ?? row.schedule_id ?? row.fixtureId ?? row.id;
      const rawAnchors = Array.isArray(row.anchors)
        ? row.anchors
        : Array.isArray(row.anchorList)
          ? row.anchorList
          : [];

      return {
        source: args.source,
        source_id: String(scheduleId ?? ""),
        schedule_id: scheduleId,
        league: englishFootballName(firstFootballName(
          row.subCateNameEn, row.leagueNameEn, row.subCateName,
          row.leagueName, row.categoryName, "Football",
        ), "league"),
        home_team: englishFootballName(firstFootballName(
          row.hostNameEn, row.homeNameEn, row.hostName, row.homeName,
          row.home_team, "Home",
        )),
        away_team: englishFootballName(firstFootballName(
          row.guestNameEn, row.awayNameEn, row.guestName, row.awayName,
          row.away_team, "Away",
        )),
        original_home_team: row.hostName ?? row.homeName ?? null,
        original_away_team: row.guestName ?? row.awayName ?? null,
        home_logo: row.hostIcon ?? row.homeIcon ?? row.home_logo ?? null,
        away_logo: row.guestIcon ?? row.awayIcon ?? row.away_logo ?? null,
        match_time: normalizeMatchTime(
          row.matchTime ?? row.match_time ?? row.startTime ?? row.kickoff,
        ),
        hot:
          row.hot === true ||
          String(row.hot ?? row.isHot ?? "0") === "1",
        status: row.status ?? null,
        match_status: row.matchStatus ?? row.match_status ?? null,
        anchors: rawAnchors
          .map((anchor: any, index: number) => ({
            uid: anchor.uid ?? anchor.id ?? null,
            nick_name:
              decodeHtml(
                stripTags(String(anchor.nickName ?? anchor.name ?? "")),
              ).replace(/\s+/g, " ").trim() ||
              `Streamer ${index + 1}`,
            original_nick_name: anchor.nickName ?? anchor.name ?? null,
            icon:
              anchor.cutOutIcon ??
              anchor.icon ??
              anchor.avatar ??
              anchor.avatarUrl ??
              null,
            room_num: roomNumber(anchor),
          }))
          .filter((anchor: any) => anchor.room_num),
      };
    })
    .filter((row: any) => !staleKickoff(row.match_time))
    .sort(compareMatches);

  return json({
    ok: true,
    matches,
    results: matches.length,
    source: args.source,
    generated_at: new Date().toISOString(),
  });
}

async function roomStreams(args: {
  source: "soco" | "yyzb";
  roomBase: string;
  roomNum: unknown;
  scheduleId: unknown;
  refererOrigin: string;
  statusOnly?: boolean;
  skipProbe?: boolean;
}) {
  const roomNum = String(args.roomNum ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(roomNum)) {
    return json({ error: "Invalid room number." }, 400);
  }

  const raw = await fetchText(
    `${args.roomBase}/${encodeURIComponent(roomNum)}/detail.json?v=${Date.now()}`,
  );
  const payload = parseJsonp(raw);
  const data = payload?.data ?? payload ?? {};
  const room = data.room ?? data.roomInfo ?? data.info ?? {};
  const stream =
    data.stream ??
    data.streams ??
    data.playUrl ??
    data.playUrls ??
    room.stream ??
    room.streams ??
    {};

  const scheduleId = String(args.scheduleId ?? "").trim();
  const referer = scheduleId
    ? `${args.refererOrigin}/room/${encodeURIComponent(roomNum)}?scheduleId=${encodeURIComponent(scheduleId)}`
    : `${args.refererOrigin}/room/${encodeURIComponent(roomNum)}`;

  const lines = extractStreamLines(stream, referer);
  const checkedLines = args.statusOnly
    ? []
    : await probeLines(lines, args.skipProbe);
  const liveStatus =
    room.liveStatus ??
    room.live_status ??
    data.liveStatus ??
    data.live_status ??
    null;

  return json({
    ok: true,
    room_num: roomNum,
    title: room.title ?? room.name ?? data.title ?? null,
    anchor_name:
      room.anchor?.nickName ??
      room.anchor?.name ??
      room.nickName ??
      room.name ??
      null,
    live_status: liveStatus,
    line_count: lines.length,
    ready: lines.length > 0,
    lines: checkedLines,
    source: args.source,
    generated_at: new Date().toISOString(),
  });
}

async function fawaMatches() {
  const html = await fetchFawaText(FAWA_HOME);
  const grouped = new Map<string, any>();

  // Fawa has nested/unclosed <a> tags. Parsing one whole card with a single
  // regex is brittle, so anchor each record on the stable name element and
  // inspect only the nearby markup for its href + league/time text.
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
      home_logo: null,
      away_logo: null,
      match_time: null,
      time_label: playing,
      hot: false,
      status: null,
      match_status: null,
      anchors: [],
    };

    const anchorKey = absoluteFawaUrl(href);
    if (
      anchorKey &&
      !existing.anchors.some((item: any) => item.page_url === anchorKey)
    ) {
      existing.anchors.push({
        uid: href,
        nick_name: channelLabel(name),
        icon: null,
        room_num: href,
        page_url: anchorKey,
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
    matches,
    results: matches.length,
    source: "fawa",
    generated_at: new Date().toISOString(),
  });
}

async function fawaStreams(body: any) {
  const pageUrl = safeFawaPageUrl(body.page_url ?? body.room_num);
  if (!pageUrl) {
    return json({ error: "Invalid Fawa match page." }, 400);
  }

  const html = await fetchFawaText(pageUrl);
  const origin = new URL(pageUrl).origin;
  const urls = extractMediaUrls(html, pageUrl);

  const lines = [...urls]
    .map((value, index) => ({
      label: `Fawa Server ${index + 1} · ${detectType(value).toUpperCase()}`,
      stream_type: detectType(value),
      resolution: qualityFromUrl(value),
      url: value,
      referer: pageUrl,
      origin,
      expires_at: streamExpiry(value),
    }))
    .filter((line) => line.stream_type !== "auto");

  const checkedLines = await probeLines(lines, skipProbeRequested(body));

  return json({
    ok: true,
    page_url: pageUrl,
    title: pageTitle(html),
    lines: checkedLines,
    source: "fawa",
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
    matches,
    results: matches.length,
    source: "cola",
    language: "en",
    generated_at: new Date().toISOString(),
  });
}

async function colaStreams(body: any) {
  const payload = await fetchColaMatchesPayload();
  const rawData = payload?.data;
  if (!rawData || typeof rawData !== "object" || Array.isArray(rawData)) {
    return json({ error: "ColaTV match data is unavailable." }, 502);
  }

  const target = String(
    body?.schedule_id ?? body?.room_num ?? body?.source_id ?? "",
  ).trim();
  const pageUrl = String(body?.page_url ?? "").trim();

  let slug = "";
  let match: any = null;
  for (const [candidateSlug, candidate] of Object.entries(rawData) as [string, any][]) {
    const candidateId = String(
      candidate?.matchId ?? candidate?.match_id ?? candidate?.node_api_data?.match_id ?? "",
    ).trim();
    const candidatePage = `${COLA_HOME}${encodeURI(candidateSlug)}`;
    if (
      (target && (target === candidateId || target === candidateSlug)) ||
      (pageUrl && pageUrl === candidatePage)
    ) {
      slug = candidateSlug;
      match = candidate;
      break;
    }
  }

  if (!match) {
    return json({ error: "ColaTV match is no longer available." }, 404);
  }

  const found = new Map<string, any>();
  const add = (
    value: unknown,
    label: string,
    anchorName: string | null = null,
  ) => {
    const url = colaMediaUrl(value);
    if (!url || found.has(url)) return;
    const type = detectType(url);
    if (type === "auto") return;
    found.set(url, {
      label: anchorName
        ? `ColaTV • ${anchorName} • ${label}`
        : `ColaTV • ${label}`,
      stream_type: type,
      resolution: qualityFromUrl(url),
      url,
      referer: COLA_HOME,
      origin: "https://colatv66.live",
      expires_at: streamExpiry(url),
    });
  };

  add(match?.videoUrl, "Main");
  add(match?.video_url, "Main");

  const anchors = Array.isArray(match?.anchorAppointmentVoList)
    ? match.anchorAppointmentVoList
    : [];
  for (const anchor of anchors) {
    const anchorName = decodeHtml(
      stripTags(String(anchor?.nickName ?? anchor?.houseName ?? "Streamer")),
    ).replace(/\s+/g, " ").trim();
    add(anchor?.playStreamAddress2, "HLS", anchorName);
    add(anchor?.playStreamAddress, "FLV", anchorName);
    if (Array.isArray(anchor?.servers)) {
      anchor.servers.forEach((server: unknown, index: number) => {
        add(server, `Backup ${index + 1}`, anchorName);
      });
    }
  }

  const lines = await probeLines([...found.values()], skipProbeRequested(body));
  const row = colaMatchRow(slug, match);

  return json({
    ok: true,
    page_url: `${COLA_HOME}${encodeURI(slug)}`,
    title: row == null ? null : `${row.home_team} vs ${row.away_team}`,
    lines,
    source: "cola",
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
    anchors: colaHasPlayableSource(row)
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
  const candidates: unknown[] = [row?.videoUrl, row?.video_url];
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

function collectMatchRows(value: any, depth = 0, output: any[] = []) {
  if (depth > 6 || value == null) return output;

  if (Array.isArray(value)) {
    for (const item of value) collectMatchRows(item, depth + 1, output);
    return output;
  }

  if (typeof value !== "object") return output;

  const row = value as Record<string, any>;
  const looksLikeMatch =
    row.hostName != null ||
    row.guestName != null ||
    row.homeName != null ||
    row.awayName != null ||
    row.home_team != null ||
    row.away_team != null;

  if (looksLikeMatch) output.push(row);

  for (const child of Object.values(row)) {
    if (child && typeof child === "object") {
      collectMatchRows(child, depth + 1, output);
    }
  }

  return output;
}

function isFootballRow(row: any) {
  const categoryId = Number(row?.categoryId ?? row?.category_id);
  if (Number.isFinite(categoryId) && categoryId === 1) return true;

  const category = [
    row?.categoryName,
    row?.subCateName,
    row?.leagueName,
    row?.sportName,
  ].map((value) => String(value ?? "").toLowerCase()).join(" ");

  if (/football|soccer|足球/.test(category)) return true;

  return !Number.isFinite(categoryId) &&
    (row?.hostName != null || row?.homeName != null) &&
    (row?.guestName != null || row?.awayName != null);
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

function extractStreamLines(value: any, referer: string) {
  const found = new Map<string, any>();

  const known = [
    ["HD (1080p) · M3U8", "hls", value?.hdM3u8 ?? value?.hd_m3u8, "1080p"],
    ["SD (720p) · M3U8", "hls", value?.m3u8 ?? value?.sdM3u8 ?? value?.sd_m3u8, "720p"],
    ["HD (1080p) · FLV", "flv", value?.hdFlv ?? value?.hd_flv, "1080p"],
    ["SD (720p) · FLV", "flv", value?.flv ?? value?.sdFlv ?? value?.sd_flv, "720p"],
    ["DASH · MPD", "dash", value?.mpd ?? value?.dash ?? value?.dashUrl, "Auto"],
  ];

  for (const [label, type, raw, resolution] of known) {
    const line = roomLine(
      String(label),
      String(type),
      raw,
      String(resolution),
      referer,
    );
    if (line.url) found.set(line.url, line);
  }

  const walk = (node: any, path: string[] = [], depth = 0) => {
    if (depth > 7 || node == null) return;

    if (typeof node === "string") {
      const url = normalizeMediaUrl(node, referer);
      if (!url || !looksLikeMediaUrl(url)) return;
      const loweredPath = path.join(".").toLowerCase();
      if (/license|drm|clearkey|keyid|key_data|keydata/.test(loweredPath)) {
        return;
      }

      const type = detectType(url);
      const resolution = qualityFromUrl(url);
      const pathLabel = path
        .filter(Boolean)
        .slice(-2)
        .join(" · ")
        .replace(/[_-]+/g, " ")
        .trim();
      const label =
        (pathLabel ? pathLabel : "Stream") +
        ` · ${type.toUpperCase()}`;

      if (!found.has(url)) {
        found.set(url, roomLine(label, type, url, resolution, referer));
      }
      return;
    }

    if (Array.isArray(node)) {
      node.forEach((item, index) => walk(item, [...path, String(index)], depth + 1));
      return;
    }

    if (typeof node === "object") {
      for (const [key, child] of Object.entries(node)) {
        walk(child, [...path, key], depth + 1);
      }
    }
  };

  walk(value);

  return [...found.values()].sort((a, b) => {
    const rank = (line: any) => {
      const type = String(line.stream_type ?? "");
      if (type === "hls") return 0;
      if (type === "dash") return 1;
      if (type === "mp4") return 2;
      if (type === "flv") return 3;
      return 4;
    };
    return rank(a) - rank(b);
  });
}

function extractMediaUrls(html: string, baseUrl: string) {
  const normalized = decodeHtml(
    html
      .replace(/\\u002[fF]/g, "/")
      .replace(/\\\//g, "/"),
  );
  const urls = new Set<string>();

  const add = (raw: string) => {
    const url = normalizeMediaUrl(raw, baseUrl);
    if (url && looksLikeMediaUrl(url)) urls.add(url);
  };

  for (const regex of [
    /(?:source|file|url|src|hls|dash|mpd|m3u8)\s*[:=]\s*["']([^"']+)["']/gi,
    /<(?:source|video|iframe)[^>]+(?:src|data-src)=["']([^"']+)["']/gi,
    /["']((?:https?:)?\/\/[^"'<>\s]+)["']/gi,
  ]) {
    let hit: RegExpExecArray | null;
    while ((hit = regex.exec(normalized)) !== null) add(hit[1]);
  }

  return urls;
}

function normalizeMediaUrl(value: unknown, baseUrl: string) {
  let raw = String(value ?? "").trim();
  if (!raw) return "";

  raw = decodeHtml(raw)
    .replace(/\\u002[fF]/g, "/")
    .replace(/\\\//g, "/");

  try {
    const url = new URL(raw, baseUrl);
    if (url.protocol !== "http:" && url.protocol !== "https:") return "";
    return url.toString();
  } catch (_) {
    return "";
  }
}

function looksLikeMediaUrl(value: string) {
  const lower = value.toLowerCase();
  return (
    lower.includes(".m3u8") ||
    lower.includes(".mpd") ||
    lower.includes(".flv") ||
    lower.includes(".mp4") ||
    /(?:manifest|playlist|master|index)\.(?:m3u8|mpd)(?:[?#]|$)/.test(lower)
  );
}

function roomLine(
  label: string,
  streamType: string,
  url: unknown,
  resolution: string,
  referer: string,
) {
  const cleaned = typeof url === "string" ? url.trim() : "";
  return {
    label,
    stream_type: streamType,
    resolution,
    url: cleaned,
    referer,
    origin: new URL(referer).origin,
    expires_at: streamExpiry(cleaned),
  };
}

function skipProbeRequested(body: any) {
  return body?.skip_probe === true || body?.skip_probe === "true" ||
    body?.skip_probe === "1";
}

async function probeLines(lines: any[], skipProbe = false) {
  if (skipProbe) {
    return lines.map((line) => ({
      ...line, health_status: "unknown", health_http: null, checked_at: null,
    }));
  }
  return await Promise.all(lines.map((line) => probeLine(line)));
}

async function probeLine(line: any) {
  const value = String(line?.url ?? "").trim();
  if (!value) {
    return { ...line, health_status: "dead", health_http: null };
  }

  const headers: Record<string, string> = {
    Accept: "*/*",
    Range: "bytes=0-1023",
    "User-Agent": "Mozilla/5.0 NCA-Admin/9.8",
  };

  if (line.referer) headers.Referer = String(line.referer);
  if (line.origin) headers.Origin = String(line.origin);

  const type = String(line.stream_type ?? "").toLowerCase();
  const result = await probeStreamFirstChunk(value, {
    headers, timeoutMs: 5500,
    validateFirstChunk: type === "hls"
      ? (chunk: Uint8Array, status: number) =>
        new TextDecoder().decode(chunk).includes("#EXTM3U") || status === 206
      : null,
  });
  return {
    ...line,
    health_status: ["healthy", "slow"].includes(result.status)
      ? result.status
      : [404, 410].includes(result.httpStatus) ? "dead" : "unknown",
    health_http: result.httpStatus || null,
    checked_at: new Date().toISOString(),
  };
}

function streamExpiry(value: string) {
  if (!value) return null;

  try {
    const url = new URL(value);

    const txTime = url.searchParams.get("txTime");
    if (txTime) {
      const seconds = Number.parseInt(txTime, 16);
      if (Number.isFinite(seconds) && seconds > 0) {
        return new Date(seconds * 1000).toISOString();
      }
    }

    const authKey = url.searchParams.get("auth_key");
    if (authKey) {
      const seconds = Number.parseInt(authKey.split("-")[0], 10);
      if (Number.isFinite(seconds) && seconds > 0) {
        return new Date(seconds * 1000).toISOString();
      }
    }
  } catch (_) {}

  return null;
}

function compareMatches(a: any, b: any) {
  const at = new Date(a.match_time ?? 0).getTime();
  const bt = new Date(b.match_time ?? 0).getTime();
  if (at !== bt) return at - bt;
  return String(a.home_team ?? "").localeCompare(String(b.home_team ?? ""));
}

function detectType(url: string) {
  const lower = url.toLowerCase();
  if (lower.includes(".m3u8")) return "hls";
  if (lower.includes(".mpd")) return "dash";
  if (lower.includes(".flv")) return "flv";
  if (lower.includes(".mp4")) return "mp4";
  return "auto";
}

function qualityFromUrl(url: string) {
  const lower = url.toLowerCase();
  if (/(1080|fhd|_hd|lhd)/.test(lower)) return "1080p";
  if (/(720|_sd|lsd)/.test(lower)) return "720p";
  return "Auto";
}

function absoluteFawaUrl(href: string) {
  try {
    return new URL(href, FAWA_HOME).toString();
  } catch (_) {
    return "";
  }
}

function safeFawaPageUrl(value: unknown) {
  const raw = String(value ?? "").trim();
  if (!raw) return null;

  try {
    const url = new URL(raw, FAWA_HOME);
    if (url.hostname !== "www.fawanews.sc" && url.hostname !== "fawanews.sc") {
      return null;
    }
    return url.toString();
  } catch (_) {
    return null;
  }
}

function channelLabel(name: string) {
  const channel = name.match(/---\s*(CH\s*\d+)\s*$/i);
  return channel?.[1]?.toUpperCase() ?? "Main";
}

function pageTitle(html: string) {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return match ? decodeHtml(stripTags(match[1])).trim() : null;
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
