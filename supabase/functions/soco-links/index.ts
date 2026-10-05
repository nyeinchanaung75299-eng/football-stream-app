import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MATCHES_URL = "https://json.vnres.co/matches.json";
const ROOM_BASE = "https://json.vnres.co/room";

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
    const action = body.action === "streams" ? "streams" : "matches";

    if (action === "streams") {
      const roomNum = String(body.room_num ?? "").trim();
      if (!/^\d{2,12}$/.test(roomNum)) {
        return json({ error: "Invalid Soco room number." }, 400);
      }

      const raw = await fetchText(
        `${ROOM_BASE}/${roomNum}/detail.json?v=${Date.now()}`,
      );
      const payload = parseJsonp(raw);
      const data = payload?.data ?? {};
      const room = data.room ?? {};
      const stream = data.stream ?? {};

      const lines = [
        line("HD (1080p) · M3U8", "hls", stream.hdM3u8, "1080p"),
        line("SD (720p) · M3U8", "hls", stream.m3u8, "720p"),
        line("HD (1080p) · FLV", "flv", stream.hdFlv, "1080p"),
        line("SD (720p) · FLV", "flv", stream.flv, "720p"),
      ].filter((item) => item.url);

      return json({
        ok: true,
        room_num: roomNum,
        title: room.title ?? null,
        anchor_name: room.anchor?.nickName ?? null,
        live_status: room.liveStatus ?? null,
        lines,
        source: "soco",
        generated_at: new Date().toISOString(),
      });
    }

    const raw = await fetchText(`${MATCHES_URL}?v=${Date.now()}`);
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
      .map((row: any) => ({
        schedule_id: row.scheduleId,
        league: row.subCateName ?? row.categoryName ?? "Football",
        home_team: row.hostName ?? "Home",
        away_team: row.guestName ?? "Away",
        home_logo: row.hostIcon ?? null,
        away_logo: row.guestIcon ?? null,
        match_time: Number.isFinite(Number(row.matchTime))
          ? new Date(Number(row.matchTime)).toISOString()
          : null,
        hot: String(row.hot ?? "0") === "1",
        status: row.status ?? null,
        match_status: row.matchStatus ?? null,
        anchors: Array.isArray(row.anchors)
          ? row.anchors
              .map((anchor: any) => ({
                uid: anchor.uid ?? null,
                nick_name: anchor.nickName ?? "Streamer",
                icon: anchor.cutOutIcon ?? anchor.icon ?? null,
                room_num: String(anchor.anchor?.roomNum ?? "").trim(),
              }))
              .filter((anchor: any) => anchor.room_num)
          : [],
      }))
      .sort((a: any, b: any) => {
        const at = new Date(a.match_time ?? 0).getTime();
        const bt = new Date(b.match_time ?? 0).getTime();
        if (at !== bt) return at - bt;
        return String(a.home_team).localeCompare(String(b.home_team));
      });

    return json({
      ok: true,
      matches,
      results: matches.length,
      source: "soco",
      generated_at: new Date().toISOString(),
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

function line(
  label: string,
  streamType: string,
  url: unknown,
  resolution: string,
) {
  return {
    label,
    stream_type: streamType,
    resolution,
    url: typeof url === "string" ? url.trim() : "",
  };
}

async function fetchText(url: string) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/javascript,application/json,text/plain,*/*",
      "User-Agent": "Mozilla/5.0 NCA-Admin/9.8",
      "Cache-Control": "no-cache",
    },
  });

  if (!response.ok) {
    throw new Error(`Soco source returned HTTP ${response.status}.`);
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
    throw new Error("Soco source returned an invalid payload.");
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
