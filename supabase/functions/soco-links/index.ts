import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

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
    const source = normalizeSource(body.source);
    const action = body.action === "streams" ? "streams" : "matches";

    if (action === "streams") {
      if (source === "fawa") {
        return await fawaStreams(body);
      }
      if (source === "yyzb") {
        return await roomStreams({
          source,
          roomBase: YYZB_ROOM_BASE,
          roomNum: body.room_num,
          scheduleId: body.schedule_id,
          refererOrigin: "https://m.yyzb22.live",
        });
      }
      return await roomStreams({
        source: "soco",
        roomBase: SOCO_ROOM_BASE,
        roomNum: body.room_num,
        scheduleId: body.schedule_id,
        refererOrigin: "https://m.sutbongtv.com",
      });
    }

    if (source === "fawa") {
      return await fawaMatches();
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
  if (source === "yyzb" || source === "fawa") return source;
  return "soco";
}

async function jsonpMatches(args: {
  source: "soco" | "yyzb";
  url: string;
}) {
  const raw = await fetchText(`${args.url}?v=${Date.now()}`);
  const payload = parseJsonp(raw);
  const buckets = payload?.data ?? {};

  const flattened: any[] = [];
  if (buckets && typeof buckets === "object") {
    for (const value of Object.values(buckets)) {
      if (Array.isArray(value)) flattened.push(...value);
    }
  }

  const seen = new Set<string>();
  const matches = flattened
    .filter((row: any) => Number(row.categoryId) === 1)
    .filter((row: any) => {
      const id = String(row.scheduleId ?? "");
      if (!id || seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .map((row: any) => {
      const rawAnchors = Array.isArray(row.anchors) ? row.anchors : [];
      return {
        source: args.source,
        source_id: String(row.scheduleId ?? ""),
        schedule_id: row.scheduleId,
        league: args.source === "yyzb"
          ? friendlyText(row.subCateName ?? row.categoryName ?? "Football")
          : row.subCateName ?? row.categoryName ?? "Football",
        home_team: args.source === "yyzb"
          ? friendlyText(row.hostName ?? "Home")
          : row.hostName ?? "Home",
        away_team: args.source === "yyzb"
          ? friendlyText(row.guestName ?? "Away")
          : row.guestName ?? "Away",
        original_home_team: row.hostName ?? null,
        original_away_team: row.guestName ?? null,
        home_logo: row.hostIcon ?? null,
        away_logo: row.guestIcon ?? null,
        match_time: Number.isFinite(Number(row.matchTime))
          ? new Date(Number(row.matchTime)).toISOString()
          : null,
        hot: String(row.hot ?? "0") === "1",
        status: row.status ?? null,
        match_status: row.matchStatus ?? null,
        anchors: rawAnchors
          .map((anchor: any, index: number) => ({
            uid: anchor.uid ?? null,
            nick_name: `Streamer ${index + 1}`,
            original_nick_name: anchor.nickName ?? null,
            icon: anchor.cutOutIcon ?? anchor.icon ?? null,
            room_num: String(anchor.anchor?.roomNum ?? "").trim(),
          }))
          .filter((anchor: any) => anchor.room_num),
      };
    })
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
}) {
  const roomNum = String(args.roomNum ?? "").trim();
  if (!/^\d{2,12}$/.test(roomNum)) {
    return json({ error: "Invalid room number." }, 400);
  }

  const raw = await fetchText(
    `${args.roomBase}/${roomNum}/detail.json?v=${Date.now()}`,
  );
  const payload = parseJsonp(raw);
  const data = payload?.data ?? {};
  const room = data.room ?? {};
  const stream = data.stream ?? {};

  const scheduleId = String(args.scheduleId ?? "").trim();
  const referer = scheduleId
    ? `${args.refererOrigin}/room/${roomNum}?scheduleId=${encodeURIComponent(scheduleId)}`
    : `${args.refererOrigin}/room/${roomNum}`;

  const lines = [
    roomLine("HD (1080p) · M3U8", "hls", stream.hdM3u8, "1080p", referer),
    roomLine("SD (720p) · M3U8", "hls", stream.m3u8, "720p", referer),
    roomLine("HD (1080p) · FLV", "flv", stream.hdFlv, "1080p", referer),
    roomLine("SD (720p) · FLV", "flv", stream.flv, "720p", referer),
  ].filter((item) => item.url);

  const checkedLines = await probeLines(lines);

  return json({
    ok: true,
    room_num: roomNum,
    title: room.title ?? null,
    anchor_name: room.anchor?.nickName ?? null,
    live_status: room.liveStatus ?? null,
    lines: checkedLines,
    source: args.source,
    generated_at: new Date().toISOString(),
  });
}

async function fawaMatches() {
  const html = await fetchText(FAWA_HOME);
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

    const before = html.slice(Math.max(0, hit.index - 700), hit.index);
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

  const html = await fetchText(pageUrl);
  const urls = new Set<string>();

  const videosMatch = html.match(/var\s+videos\s*=\s*\[([\s\S]*?)\]/i);
  if (videosMatch) {
    const quoteRegex = /["'](https?:\/\/[^"'\s]+)["']/gi;
    let hit: RegExpExecArray | null;
    while ((hit = quoteRegex.exec(videosMatch[1])) !== null) {
      urls.add(decodeHtml(hit[1]));
    }
  }

  for (const regex of [
    /\bsource\s*:\s*["'](https?:\/\/[^"']+)["']/gi,
    /<source[^>]+src=["'](https?:\/\/[^"']+)["']/gi,
    /\bfile\s*:\s*["'](https?:\/\/[^"']+)["']/gi,
  ]) {
    let hit: RegExpExecArray | null;
    while ((hit = regex.exec(html)) !== null) {
      urls.add(decodeHtml(hit[1]));
    }
  }

  const origin = new URL(pageUrl).origin;
  const lines = [...urls]
    .filter((value) => /^https?:\/\//i.test(value))
    .map((value, index) => ({
      label: `Fawa Server ${index + 1}`,
      stream_type: detectType(value),
      resolution: qualityFromUrl(value),
      url: value,
      referer: pageUrl,
      origin,
      expires_at: streamExpiry(value),
    }));

  const checkedLines = await probeLines(lines);

  return json({
    ok: true,
    page_url: pageUrl,
    title: pageTitle(html),
    lines: checkedLines,
    source: "fawa",
    generated_at: new Date().toISOString(),
  });
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

async function probeLines(lines: any[]) {
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

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5500);

  try {
    const response = await fetch(value, {
      method: "GET",
      headers,
      redirect: "follow",
      signal: controller.signal,
    });

    const status = response.status;
    const goodHttp = status >= 200 && status < 400;

    let looksPlayable = goodHttp;
    const type = String(line.stream_type ?? "").toLowerCase();

    if (goodHttp && type === "hls") {
      try {
        const reader = response.body?.getReader();
        const chunk = reader ? await reader.read() : null;
        await reader?.cancel();
        if (chunk?.value) {
          const text = new TextDecoder().decode(chunk.value);
          looksPlayable = text.includes("#EXTM3U") || status === 206;
        }
      } catch (_) {
        looksPlayable = goodHttp;
      }
    } else {
      try {
        await response.body?.cancel();
      } catch (_) {}
    }

    return {
      ...line,
      health_status: looksPlayable
        ? "healthy"
        : [401, 403, 404, 410].includes(status)
          ? "dead"
          : "unknown",
      health_http: status,
      checked_at: new Date().toISOString(),
    };
  } catch (_) {
    return {
      ...line,
      health_status: "unknown",
      health_http: null,
      checked_at: new Date().toISOString(),
    };
  } finally {
    clearTimeout(timer);
  }
}

function friendlyText(value: unknown) {
  let text = String(value ?? "").trim();
  if (!text) return text;

  const replacements: Array<[string, string]> = [
    ["中国台北", "Chinese Taipei"],
    ["乌兹别克", "Uzbekistan"],
    ["菲律宾", "Philippines"],
    ["哈萨克斯坦", "Kazakhstan"],
    ["俄罗斯", "Russia"],
    ["英格兰", "England"],
    ["比利时", "Belgium"],
    ["柬埔寨", "Cambodia"],
    ["马来西亚", "Malaysia"],
    ["印度尼西亚", "Indonesia"],
    ["新西兰", "New Zealand"],
    ["澳大利亚", "Australia"],
    ["韩国", "South Korea"],
    ["朝鲜", "North Korea"],
    ["越南", "Vietnam"],
    ["泰国", "Thailand"],
    ["日本", "Japan"],
    ["缅甸", "Myanmar"],
    ["老挝", "Laos"],
    ["新加坡", "Singapore"],
    ["伊朗", "Iran"],
    ["伊拉克", "Iraq"],
    ["沙特", "Saudi Arabia"],
    ["卡塔尔", "Qatar"],
    ["阿联酋", "UAE"],
    ["国际友谊", "International Friendly"],
    ["中亚女", "Central Asia Women "],
    ["女足", " Women "],
    ["后备队", " Reserves"],
    ["足球", "Football"],
  ];

  for (const [from, to] of replacements) {
    text = text.replaceAll(from, to);
  }

  return text.replace(/\s+/g, " ").trim();
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

async function fetchText(url: string) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/javascript,application/json,text/html,text/plain,*/*",
      "User-Agent": "Mozilla/5.0 NCA-Admin/9.8",
      "Cache-Control": "no-cache",
    },
    redirect: "follow",
  });

  if (!response.ok) {
    throw new Error(`Source returned HTTP ${response.status}.`);
  }

  return await response.text();
}

function parseJsonp(text: string): any {
  const trimmed = text.trim();

  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    return JSON.parse(trimmed);
  }

  const first = trimmed.indexOf("(");
  const last = trimmed.lastIndexOf(")");
  if (first < 0 || last <= first) {
    throw new Error("Source returned an invalid payload.");
  }

  return JSON.parse(trimmed.slice(first + 1, last));
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
