const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, apikey, Content-Type, X-Client-Info, Cache-Control, X-Supabase-Api-Version",
  "Access-Control-Expose-Headers": "Retry-After",
  "Cache-Control": "private, no-store",
  "Content-Type": "application/json",
};
const providers = ["posthog", "cloudflare", "vercel", "google-drive"];
const githubRepo = "nyeinchanaung75299-eng/football-stream-app";
const encoder = new TextEncoder();
const output = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: cors });
const number = (v) => Number.isFinite(Number(v)) ? Number(v) : 0;
const timestamp = () => new Date().toISOString();
function upstreamHost(row) {
  try { return new URL(row.use_webview ? row.webview_url : row.stream_url).hostname; }
  catch { return 'unknown'; }
}
export function redact(value, max = 700) {
  return String(value ?? "").replace(/https?:\/\/[^\s"'<>]+/gi, "[URL]")
    .replace(/\b(?:Bearer\s+)?eyJ[\w-]+\.[\w-]+\.[\w-]+\b/g, "[TOKEN]")
    .replace(/\bBearer\s+[^\s,"'<>]+/gi, "[TOKEN]")
    .replace(/\b(?:phx_|phc_|sb_secret_|sb_publishable_)[\w-]+/g, "[KEY]")
    .replace(/\b(?:token|password|api[_-]?key|key[_-]?data|authorization|secret)["']?\s*[:=]\s*["']?[^,"'\s;]+/gi, "[REDACTED]")
    .replace(/\b[0-9a-f]{32,64}\b/gi, "[KEY]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[EMAIL]").slice(0, max);
}
export function endpointName(raw) {
  let path;
  try { path = new URL(raw).pathname; } catch { path = String(raw || ""); }
  if (path.startsWith("/p/")) return "/p/:token/:media";
  if (/^\/matches\/[^/]+\/streams$/.test(path)) return "/matches/:id/streams";
  if (/^\/(auth|rest|storage|functions)\/v1/.test(path)) return "/" + path.split("/")[1] + "/v1/*";
  if (/^\/sources\/(soco|yyzb|fawa|cola)\/(matches|streams)$/.test(path)) return path;
  return ["/health", "/matches", "/backend-health"].includes(path) ? path : "/other";
}
export function lineSummary(rows, total = rows.length, now = Date.now()) {
  const counts = { healthy: 0, slow: 0, failed: 0, unknown: 0, stale: 0, alerts: 0 };
  const lines = rows.map(row => {
    const age = now - Date.parse(row.last_checked_at || "");
    const stale = !Number.isFinite(age) || age > 20 * 60000;
    const health = stale ? "stale" : (["healthy", "slow", "failed"].includes(row.health_status) ? row.health_status : "unknown");
    const streak = number(row.health_failure_streak);
    counts[health]++;
    // A stale failed check must not be presented as a source currently down.
    const alert = !stale && health === "failed" && streak >= 3;
    if (alert) counts.alerts++;
    return { label: redact(row.label, 100), type: redact(row.stream_type, 20),
      health, alert, consecutiveFailures: streak, totalFailures: number(row.health_total_failures),
      latencyMs: row.health_latency_ms, checkedAt: row.last_checked_at,
      match: redact(row.matches ? row.matches.home_team + " vs " + row.matches.away_team : "", 180),
      source: upstreamHost(row) };
  }).sort((a,b) => Number(b.alert) - Number(a.alert) || b.consecutiveFailures - a.consecutiveFailures);
  const groups = [...new Set(lines.map(r => r.source))].map(source => {
    const group = lines.filter(r => r.source === source);
    return { source, checked: group.filter(r => !["unknown","stale"].includes(r.health)).length,
      alerts: group.filter(r => r.alert).length, allFailing: source !== 'unknown' && rows.length === total && group.length >= 2 && group.every(r => r.alert) };
  });
  return { counts, total, truncated: rows.length < total, lines, sources: groups,
    note: "Reachability checks, not playback verification. Three consecutive failed checks raise an alert; no line is disabled." };
}
async function cryptKey(secret) {
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode("nca-monitor-v1:" + secret));
  return crypto.subtle.importKey("raw", hash, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}
const base64 = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const unbase64 = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));
export async function encryptSecret(value, serverKey, provider) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv,
    additionalData: encoder.encode(provider) }, await cryptKey(serverKey), encoder.encode(value));
  return "v1." + base64(iv) + "." + base64(encrypted);
}
export async function decryptSecret(value, serverKey, provider) {
  const [version, iv, body] = value.split(".");
  if (version !== "v1") throw new Error("Credential version");
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM",
    iv: unbase64(iv), additionalData: encoder.encode(provider) }, await cryptKey(serverKey), unbase64(body)));
}
export function validateConfig(provider, config = {}) {
  if (!providers.includes(provider)) throw new Error("Unsupported provider");
  if (provider === "posthog") {
    if (!/^\d{1,12}$/.test(String(config.projectId))) throw new Error("Project ID required");
    return { projectId: String(config.projectId), region: config.region === "eu" ? "eu" : "us" };
  }
  if (provider === "cloudflare") {
    if (!/^[a-f0-9]{32}$/.test(config.accountId || "") || !/^[\w-]{1,100}$/.test(config.worker || "")) throw new Error("Account and Worker required");
    return { accountId: config.accountId, worker: config.worker };
  }
  if (provider === "vercel") {
    if (!/^[\w-]{1,150}$/.test(config.project || "") || !/^team_[\w]+$/.test(config.teamId || "")) throw new Error("Project and Team required");
    return { project: config.project, teamId: config.teamId };
  }
  if (!/^[\w-]{10,200}$/.test(config.folderId || "")) throw new Error("Drive folder required");
  return { folderId: config.folderId };
}
class FetchError extends Error {
  constructor(status) { super("Upstream request failed"); this.status = status; }
}
export function createMonitor(env, { fetcher = fetch } = {}) {
  const base = (env.SUPABASE_URL || "").replace(/\/+$/, "");
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY || "";
  const anonKey = env.SUPABASE_ANON_KEY || env.SUPABASE_PUBLISHABLE_KEY || "";
  async function request(url, options = {}, timeout = 6000) {
    const response = await fetcher(url, { ...options, signal: AbortSignal.timeout(timeout), redirect: "error" });
    if (!response.ok) { await response.body?.cancel(); throw new FetchError(response.status); }
    // The timeout covers headers and body. Refuse oversized responses and
    // never forward upstream error bodies that might contain credentials.
    const reader = response.body?.getReader(); const parts = []; let size = 0;
    try {
      if (reader) for (;;) {
        const part = await reader.read(); if (part.done) break;
        size += part.value.byteLength; if (size > 1024 * 1024) throw new Error("Response too large");
        parts.push(part.value);
      }
    } finally { await reader?.cancel().catch(() => {}); }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
    const text = new TextDecoder().decode(bytes);
    return { data: text ? JSON.parse(text) : null, headers: response.headers };
  }
  function db(path, options = {}, bearer = serviceKey, apiKey = serviceKey) {
    return request(base + "/rest/v1/" + path, { ...options,
      headers: { apikey: apiKey, Authorization: "Bearer " + bearer,
        "Content-Type": "application/json", ...options.headers } }, 4000);
  }
  const card = (id, state, detail, data = {}) => ({ id, state, detail, collectedAt: timestamp(), ...data });
  const failed = (id, error) => card(id, error?.status === 401 || error?.status === 403 ? "needs_access" : "unavailable",
    error?.status === 401 || error?.status === 403 ? "Read access was denied. Check this service connection." :
      error?.status === 429 ? "The service rate limit was reached. Try later." : "Monitoring data could not be read. Try again.");
  async function posthog(config, key) {
    const host = config.region === "eu" ? "https://eu.posthog.com" : "https://us.posthog.com";
    const query = async sql => (await request(host + "/api/projects/" + config.projectId + "/query/", {
      method: "POST", headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" },
      body: JSON.stringify({ query: { kind: "HogQLQuery", query: sql } }) })).data;
    const range = " timestamp >= now() - INTERVAL 1 DAY ";
    const [summary, breakdown, issues] = await Promise.all([
      query("SELECT event, count(), uniqExact(person_id) FROM events WHERE " + range +
        " AND event IN ('$exception','playback line failed','playback buffering','admin function failed') GROUP BY event"),
      query("SELECT event, coalesce(nullIf(toString(properties.app),''),toString(properties.$app_name),'unknown'), coalesce(nullIf(toString(properties.platform),''),toString(properties.$os_name),'unknown'), count(),uniqExact(person_id) FROM events WHERE " + range +
        " AND event IN ('$exception','playback line failed','admin function failed') GROUP BY event,2,3 ORDER BY count() DESC LIMIT 20"),
      query("SELECT coalesce(nullIf(toString(properties.$exception_issue_id),''),nullIf(toString(properties.$exception_fingerprint),''),'ungrouped'), any(toString(properties.$exception_types)),any(toString(properties.$exception_values)),count(),uniqExact(person_id),max(timestamp),argMax(properties.$exception_list,timestamp),argMax(toString(properties.$screen_name),timestamp) FROM events WHERE event='$exception' AND " + range + " GROUP BY 1 ORDER BY count() DESC LIMIT 10"),
    ]);
    if (![summary,breakdown,issues].every(q => Array.isArray(q.results))) throw new Error("Query incomplete");
    const events = ['$exception','playback line failed','playback buffering','admin function failed'].map(event => {
      const row = summary.results.find(r => r[0] === event);
      return {event,count:number(row?.[1]),affectedUsers:number(row?.[2])};
    });
    return card("posthog", events.some(e => e.event !== "playback buffering" && e.count > 0) ? "warning" : "ok",
      "Captured events in the last 24 hours. Anonymous devices can count separately; missing telemetry is not proof of no crashes.",
      { events, breakdown: breakdown.results.map(r => ({ event:r[0], app:redact(r[1],80), platform:redact(r[2],40), count:number(r[3]), affectedUsers:number(r[4]) })),
        issues: issues.results.map(r => ({ issue:redact(r[0],100), title:redact(r[1] + ": " + r[2],300), count:number(r[3]),
          affectedUsers:number(r[4]), lastSeen:r[5], stack:redact(JSON.stringify(r[6] ?? []),6000), screen:redact(r[7],80),
          url: /^[a-f0-9-]{36}$/i.test(r[0]) ? host + "/project/" + config.projectId + "/error_tracking/" + r[0] : null })),
        url:host + "/project/" + config.projectId + "/error_tracking",
        replay:"Session recording is currently off. Use the issue page for available event and stack context." });
  }
  async function cloudflare(config, key) {
    const end = timestamp(); const start = new Date(Date.now() - 86400000).toISOString();
    const result = (await request("https://api.cloudflare.com/client/v4/graphql", { method:"POST",
      headers:{ Authorization:"Bearer " + key,"Content-Type":"application/json" },
      body:JSON.stringify({ query:"query($account: string!, $worker: string!, $start: Time!, $end: Time!) { viewer { accounts(filter:{accountTag:$account}) { workersInvocationsAdaptive(limit:1,filter:{scriptName:$worker,datetime_geq:$start,datetime_leq:$end}) { sum {requests errors subrequests} quantiles {cpuTimeP50 cpuTimeP99 wallTimeP50 wallTimeP99} } } } }",
        variables:{account:config.accountId,worker:config.worker,start,end} }) })).data;
    if (result.errors?.length || !result.data?.viewer?.accounts?.length) throw new FetchError(403);
    const row = result.data.viewer.accounts[0].workersInvocationsAdaptive?.[0];
    if (!row) return card('cloudflare','no_data','No invocations were returned for this Worker in the last 24 hours. Check the Worker name.');
    return card("cloudflare", number(row?.sum?.errors) ? "warning" : "ok",
      "Cloudflare invocation metrics · last 24 hours. Runtime errors are separate from HTTP 4xx/5xx responses.",
      { metrics:{ requests:number(row?.sum?.requests), runtimeErrors:number(row?.sum?.errors), subrequests:number(row?.sum?.subrequests),
          cpuP50Ms:row ? number(row.quantiles.cpuTimeP50) / 1000 : null, cpuP99Ms:row ? number(row.quantiles.cpuTimeP99) / 1000 : null,
          wallP50Ms:number(row.quantiles.wallTimeP50) / 1000, wallP99Ms:number(row.quantiles.wallTimeP99) / 1000 },
        url:"https://dash.cloudflare.com/" + config.accountId + "/workers/services/view/" + config.worker + "/production/metrics",
        logs:"HTTP status, endpoint and upstream log details require Workers Logs. Open the Worker dashboard to inspect them." });
  }
  async function vercel(config, key) {
    const headers = {Authorization:"Bearer " + key};
    const project = (await request("https://api.vercel.com/v9/projects/" + config.project + "?teamId=" + config.teamId,{headers})).data;
    const result = (await request("https://api.vercel.com/v6/deployments?projectId=" + encodeURIComponent(project.id) + "&teamId=" + config.teamId + "&target=production&limit=3",{headers})).data;
    if (!Array.isArray(result.deployments)) throw new Error("Deployment response");
    const deployments = result.deployments.map(r => ({ state:r.readyState || r.state, createdAt:new Date(r.createdAt || r.created).toISOString(),
      sha:r.meta?.githubCommitSha?.slice(0,12), url:r.url && /^[-.\w]+$/.test(r.url) ? "https://" + r.url : null }));
    return card("vercel", deployments[0]?.state === "ERROR" ? "warning" : "ok","Latest production deployments.",{
      deployments,url:"https://vercel.com/nca16/" + encodeURIComponent(config.project) + "/logs",
      logs:"Runtime logs are available in the linked Vercel dashboard; account and plan access apply." });
  }
  async function driveToken(secret) {
    const credentials = JSON.parse(secret);
    if (!credentials.client_id || !credentials.client_secret || !credentials.refresh_token) throw new Error("Drive credentials");
    return (await request("https://oauth2.googleapis.com/token", {method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},
      body:new URLSearchParams({client_id:credentials.client_id,client_secret:credentials.client_secret,refresh_token:credentials.refresh_token,grant_type:"refresh_token"})})).data.access_token;
  }
  async function drive(config, key) {
    const token = await driveToken(key);
    if (!token) throw new Error("Drive token");
    const search = new URLSearchParams({q:"'" + config.folderId + "' in parents and trashed = false",pageSize:"10",orderBy:"modifiedTime desc",
      fields:"files(id,name,mimeType,modifiedTime,webViewLink)"});
    const files = (await request("https://www.googleapis.com/drive/v3/files?" + search,{headers:{Authorization:"Bearer " + token}})).data.files;
    if (!Array.isArray(files)) throw new Error("Drive response");
    return card("google-drive","ok","Report/archive folder. No live-error monitoring.",{
      files:files.map(f => ({name:redact(f.name,150),type:f.mimeType,modifiedAt:f.modifiedTime})),
      url:"https://drive.google.com/drive/folders/" + config.folderId });
  }
  const readers = {posthog,cloudflare,vercel,"google-drive":drive};
  async function connectionRows() { return (await db("system_monitor_connections?select=provider,config,encrypted_secret")).data || []; }
  async function providerCards(connections) {
    const cached = (await db("system_monitor_cache?select=provider,summary,collected_at")).data || [];
    return Promise.all(providers.map(async id => {
      const row = connections.find(r => r.provider === id);
      if (!row) return card(id,"not_configured","Connect a server-side read credential to load account monitoring data.");
      const prior = cached.find(c => c.provider === id);
      if (prior && Date.now() - Date.parse(prior.collected_at) < 60000) return {...prior.summary,cached:true};
      try {
        const config = validateConfig(id,row.config);
        const key = await decryptSecret(row.encrypted_secret,serviceKey,id);
        const summary = await readers[id](config,key);
        await db("system_monitor_cache?on_conflict=provider",{method:"POST",headers:{Prefer:"resolution=merge-duplicates,return=minimal"},
          body:JSON.stringify({provider:id,summary,collected_at:summary.collectedAt})});
        return summary;
      } catch (error) {
        return {...failed(id,error), ...(prior ? {lastKnown:{collectedAt:prior.collected_at,metrics:prior.summary.metrics,events:prior.summary.events}} : {})};
      }
    }));
  }
  async function builds() {
    try {
      const cached = (await db("system_monitor_cache?provider=eq.github&select=summary,collected_at")).data?.[0];
      if (cached && Date.now() - Date.parse(cached.collected_at) < 300000) return {...cached.summary,cached:true};
      const runs = await Promise.all(["deploy-web.yml","build-apks.yml"].map(async workflow => {
        const result = (await request("https://api.github.com/repos/" + githubRepo + "/actions/workflows/" + workflow + "/runs?branch=main&per_page=1",
          {headers:{Accept:"application/vnd.github+json","User-Agent":"NCA-System-Monitor"}})).data.workflow_runs?.[0];
        if (!result) return {workflow,state:"no_runs"};
        return {workflow,state:result.conclusion || result.status,sha:result.head_sha?.slice(0,12),updatedAt:result.updated_at,url:result.html_url,runNumber:result.run_number};
      }));
      const summary = card("github",runs.some(r => ["failure","timed_out","action_required"].includes(r.state)) ? "warning" : "ok","Latest main-branch Web/APK workflow runs; queued or running jobs have not succeeded yet.",{runs});
      await db("system_monitor_cache?on_conflict=provider",{method:"POST",headers:{Prefer:"resolution=merge-duplicates,return=minimal"},
        body:JSON.stringify({provider:"github",summary,collected_at:summary.collectedAt})});
      return summary;
    } catch (error) { return failed("github",error); }
  }
  async function database() {
    const began = Date.now();
    const [matches,streams] = await Promise.all([
      db("matches?select=id&deleted_at=is.null&limit=1",{headers:{Prefer:"count=exact"}}),
      db("stream_links?select=label,stream_type,stream_url,use_webview,webview_url,health_status,health_latency_ms,last_checked_at,health_failure_streak,health_total_failures,matches(home_team,away_team,source)&is_active=eq.true&order=last_checked_at.asc.nullsfirst&limit=500",{headers:{Prefer:"count=exact"}}),
    ]);
    const count = response => number(response.headers.get("Content-Range")?.split("/")[1] ?? response.data?.length);
    return { database:card("supabase","ok","Authenticated database query succeeded.",{metrics:{matches:count(matches),activeLines:count(streams),latencyMs:Date.now()-began}}),
      streams:lineSummary(streams.data || [],count(streams)) };
  }
  async function snapshot() {
    const [connections, dbResult, github] = await Promise.all([
      connectionRows(),database().catch(error=>({database:failed("supabase",error),streams:null})),builds()]);
    return {version:1,generatedAt:timestamp(),windowHours:24,services:[dbResult.database,github,...await providerCards(connections)],streams:dbResult.streams};
  }
  return async function handler(req) {
    if (req.method === "OPTIONS") return new Response(null,{status:204,headers:cors});
    if (req.method !== "POST") return output({error:"Method not allowed."},405);
    if (!base || !serviceKey || !anonKey) return output({error:"Monitoring server is not configured."},503);
    const authorization = req.headers.get("Authorization") || "";
    if (!/^Bearer \S+$/i.test(authorization)) return output({error:"Admin session required."},401);
    try {
      // Never authorize with user_metadata, an unverified decoded JWT, or an
      // old role claim. Auth verifies the session and profiles is authoritative.
      const user = (await request(base + "/auth/v1/user",{headers:{apikey:anonKey,Authorization:authorization}},4000)).data;
      if (!user?.id || !/^[a-f0-9-]{36}$/i.test(user.id)) return output({error:"Invalid session."},401);
      const profiles = (await db("profiles?select=role&id=eq." + user.id,{},authorization.slice(7),anonKey)).data;
      if (profiles?.[0]?.role !== "admin") return output({error:"Admin access required."},403);
    } catch (error) {
      return output({error:error?.status === 401 || error?.status === 403 ? "Invalid session." : "Admin access could not be verified."},error?.status === 401 || error?.status === 403 ? 401 : 503);
    }
    try {
      const raw = await req.text();
      if (raw.length > 20000) return output({error:"Request too large."},413);
      let body; try { body = raw ? JSON.parse(raw) : {}; } catch { return output({error:"Invalid request."},400); }
      if (body.action === "connect") {
        let config; try { config = validateConfig(body.provider,body.config); } catch { return output({error:"Check the provider IDs."},400); }
        const secret = typeof body.secret === "string" ? body.secret.trim() : "";
        if (!secret || secret.length > 16000 || /^phc_/.test(secret)) return output({error:"A server read credential is required. The public SDK token cannot read monitoring data."},400);
        let summary;
        try { summary = await readers[body.provider](config,secret); }
        catch(error) { return output({error:failed(body.provider,error).detail},422); }
        const encrypted = await encryptSecret(secret,serviceKey,body.provider);
        await db("rpc/save_monitor_connection",{method:"POST",
          body:JSON.stringify({p_provider:body.provider,p_config:config,p_encrypted_secret:encrypted,p_summary:summary})});
        return output({ok:true,service:summary});
      }
      if (body.action && body.action !== "summary") return output({error:"Unsupported action."},400);
      return output(await snapshot());
    } catch (_) {
      // Never log request bodies, user sessions, encrypted credentials or
      // provider error bodies. Missing data is never converted to healthy zero.
      console.error("System monitor request failed");
      return output({error:"Monitoring could not finish. Try again."},503);
    }
  };
}
