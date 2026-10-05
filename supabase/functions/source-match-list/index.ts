import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SOCO_MATCHES_URL = "https://json.vnres.co/matches.json";
const YYZB_MATCHES_URL = "https://json.ncctrials.com/match_all.json";
const FAWA_HOME = "http://www.fawanews.sc/";

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

    if (source === "fawa") {
      return await fawaMatches();
    }

    return await jsonpMatches({
      source,
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

function normalizeSource(value: unknown): "soco" | "yyzb" | "fawa" {
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
      const anchors = Array.isArray(row.anchors) ? row.anchors : [];
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
        match_time: Number.isFinite(Number(row.matchTime))
          ? new Date(Number(row.matchTime)).toISOString()
          : null,
        hot: String(row.hot ?? "0") === "1",
        anchors: anchors
          .map((anchor: any, index: number) => ({
            uid: anchor.uid ?? null,
            nick_name: `Streamer ${index + 1}`,
            room_num: String(anchor.anchor?.roomNum ?? "").trim(),
          }))
          .filter((anchor: any) => anchor.room_num),
      };
    })
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
  const html = await fetchText(FAWA_HOME);
  const grouped = new Map<string, any>();
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

function friendlyText(value: unknown) {
  let text = String(value ?? "").trim();
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
    ["越南", "Vietnam"],
    ["泰国", "Thailand"],
    ["日本", "Japan"],
    ["缅甸", "Myanmar"],
    ["老挝", "Laos"],
    ["新加坡", "Singapore"],
    ["伊朗", "Iran"],
    ["伊拉克", "Iraq"],
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
