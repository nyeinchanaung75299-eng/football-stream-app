import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Not signed in." }, 401);

    const { data: profile } = await userClient.from("profiles").select("role").eq("id", user.id).single();
    if (profile?.role !== "admin") return json({ error: "Admin access required." }, 403);

    const body = await req.json().catch(() => ({}));
    const linkId = body.link_id?.toString();
    if (!linkId) return json({ error: "link_id is required." }, 400);

    const admin = createClient(supabaseUrl, serviceRole);
    const { data: link, error } = await admin
      .from("stream_links")
      .select("id,stream_url,referer,origin,use_webview,webview_url")
      .eq("id", linkId)
      .single();
    if (error || !link) return json({ error: "Link not found." }, 404);

    const url = link.use_webview ? link.webview_url : link.stream_url;
    if (!url) return json({ error: "URL is empty." }, 400);

    const headers: Record<string, string> = { "Accept": "*/*", "Range": "bytes=0-4095" };
    if (link.referer) headers["Referer"] = link.referer;
    if (link.origin) headers["Origin"] = link.origin;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    const started = Date.now();
    let health = "failed";
    let statusCode = 0;
    let latency = 0;

    try {
      const res = await fetch(url, { method: "GET", headers, redirect: "follow", signal: controller.signal });
      statusCode = res.status;
      latency = Date.now() - started;
      if (res.ok || (res.status >= 300 && res.status < 400)) health = latency > 3000 ? "slow" : "healthy";
      try {
        const reader = res.body?.getReader();
        if (reader) { await reader.read(); await reader.cancel(); }
      } catch (_) {}
    } catch (_) {
      latency = Date.now() - started;
      health = "failed";
    } finally {
      clearTimeout(timeout);
    }

    await admin.from("stream_links").update({
      health_status: health,
      health_latency_ms: latency,
      last_checked_at: new Date().toISOString(),
    }).eq("id", linkId);

    return json({ health_status: health, latency_ms: latency, http_status: statusCode });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}
