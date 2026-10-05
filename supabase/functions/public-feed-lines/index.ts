import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type MatchRow = {
  id: string;
};

type StreamRow = {
  id: string;
  match_id: string;
  label: string | null;
  resolution: string | null;
  stream_type: string | null;
  stream_url: string | null;
  referer: string | null;
  origin: string | null;
  use_webview: boolean | null;
  is_active: boolean | null;
  priority: number | null;
  available_from: string | null;
  expires_at: string | null;
  health_status: string | null;
  key_id: string | null;
  key_data: string | null;
};

Deno.serve(async (req) => {
  try {
    if (req.method !== "GET" && req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRole) {
      return json({ error: "Supabase server credentials are missing." }, 500);
    }

    const admin = createClient(supabaseUrl, serviceRole);

    const { data: matches, error: matchError } = await admin
      .from("matches")
      .select("id")
      .eq("is_active", true)
      .eq("is_featured", true)
      .eq("publish_state", "published")
      .is("deleted_at", null)
      .limit(250);

    if (matchError) throw matchError;

    const matchIds = ((matches ?? []) as MatchRow[])
      .map((row) => row.id)
      .filter(Boolean);

    if (matchIds.length === 0) {
      return json({ ok: true, lines: [], count: 0 });
    }

    const { data: streams, error: streamError } = await admin
      .from("stream_links")
      .select(
        "id,match_id,label,resolution,stream_type,stream_url,referer,origin,use_webview,is_active,priority,available_from,expires_at,health_status,key_id,key_data",
      )
      .in("match_id", matchIds)
      .eq("is_active", true)
      .eq("use_webview", false)
      .order("priority", { ascending: true })
      .limit(1000);

    if (streamError) throw streamError;

    const now = Date.now();
    const lines = ((streams ?? []) as StreamRow[])
      .filter((row) => {
        if (!row.stream_url?.trim()) return false;
        if (row.key_id?.trim() || row.key_data?.trim()) return false;

        const availableFrom = Date.parse(row.available_from ?? "");
        if (Number.isFinite(availableFrom) && now < availableFrom) return false;

        const expiresAt = Date.parse(row.expires_at ?? "");
        if (Number.isFinite(expiresAt) && now >= expiresAt) return false;

        return true;
      })
      .map((row) => ({
        id: row.id,
        match_id: row.match_id,
        label: row.label,
        resolution: row.resolution,
        stream_type: normalizeType(row.stream_type, row.stream_url),
        stream_url: row.stream_url!,
        referer: row.referer,
        origin: row.origin,
        use_webview: false,
        is_active: true,
        priority: row.priority ?? 100,
        available_from: row.available_from,
        expires_at: row.expires_at,
        health_status: row.health_status ?? "unknown",
        backup_transport: "github_mirror_direct",
      }));

    return json({
      ok: true,
      count: lines.length,
      generated_at: new Date().toISOString(),
      lines,
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

function normalizeType(type: string | null, url: string | null) {
  const declared = (type ?? "auto").trim().toLowerCase();
  if (declared === "m3u8") return "hls";
  if (declared === "mpd") return "dash";
  if (declared !== "auto") return declared;

  const lower = (url ?? "").toLowerCase();
  if (lower.includes(".m3u8")) return "hls";
  if (lower.includes(".mpd")) return "dash";
  if (lower.includes(".mp4")) return "mp4";
  if (lower.includes(".flv")) return "flv";
  return "auto";
}

function json(
  body: Record<string, unknown>,
  status = 200,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store, max-age=0",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
