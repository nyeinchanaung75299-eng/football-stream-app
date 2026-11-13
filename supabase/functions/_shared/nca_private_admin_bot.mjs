import { probeStreamFirstChunk } from "./stream_probe.mjs";
import { withTelegramUpdateDedup } from './telegram_update_dedup.mjs';
import { sendTelegramReleaseApk, ReleaseDeliveryError } from './telegram_apk_delivery.mjs';
import { footballHighlights, checkHighlightLine } from './football_highlights.mjs';
// NCA Telegram bots: private webhook commands backed by safe Supabase metadata.
// NO stream URLs, key IDs, key data, DRM, service keys or session tokens in replies.
export const VIEWER_SITE = "https://nyeinchanaung75299-eng.github.io/football-stream-app/";
export const ADMIN_SITE = VIEWER_SITE + "admin/";
// Telegram inline keyboards stay on bot messages rather than occupying typing space.
// The legacy text labels remain recognized below for previously displayed buttons.
export const ADMIN_INLINE_MENU = {
  inline_keyboard: [
    [{text:"📺 Channels",callback_data:"/channels"},{text:"⚽ Fixtures",callback_data:"/matches"}],
    [{text:"📡 Monitoring",callback_data:"/monitor"},{text:"🔔 Alerts",callback_data:"/alerts"}],
    [{text:"🩺 Diagnostics",callback_data:"/diagnostics"},{text:"🧰 More tools",callback_data:"/tools"}],
    [{text:"📦 APK Downloads",callback_data:"/apk"}],
  ],
};
export const ADMIN_APK_MENU = {
  inline_keyboard: [
    [{ text: "📱 Viewer APK", callback_data: "/apk_viewer" },
     { text: "🛡️ Admin APK", callback_data: "/apk_admin" }],
    [{ text: "🏠 Main menu", callback_data: "/menu" }],
  ],
};
export const ADMIN_TOOLS_MENU = {
  inline_keyboard: [
    [{text:"🛠️ Manage",callback_data:"/manage"},{text:"📅 Broadcasts",callback_data:"/broadcasts"}],
    [{text:"🔎 Search",callback_data:"/search"},{text:"🟢 Health",callback_data:"/health"}],
    [{text:"⚽ Match readiness",callback_data:"/readiness"},{text:"🧪 Test bot",callback_data:"/testbot"}],
    [{text:"📊 Stats",callback_data:"/stats"},{text:"🧾 Logs",callback_data:"/logs"}],
    [{text:"🎬 Highlights",callback_data:"/highlights"}],
    [{text:'🚩 Viewer reports',callback_data:'/reports'}],
    [{text:"🔒 Security",callback_data:"/security"},{text:"🛠 Builds",callback_data:"/build"}],
    [{text:"🏠 Main menu",callback_data:"/start"}],
  ],
};
const ADMIN_BOTTOM_COMMANDS = {
  "📡 Auto Stream Monitoring": "/monitor",
  "🚨 Channel Error Alerts": "/alerts",
  "📺 Channel Details": "/channels",
  "🔎 Advanced Search": "/search",
  "📊 Database Statistics": "/stats",
  "⚽ Fixtures & Alerts": "/matches",
  "🛠 Channel Enable/Disable": "/manage",
  "🧾 Audit & Health History": "/logs",
  "🗃 Backup Status Report": "/backup",
  "🔒 Admin Security": "/security",
  "📅 Channel–Match Schedule": "/broadcasts",
  "🔗 Match–Channel Mapping": "/mapmatch",
  "📺 All Channels": "/channels",
  "📦 APK Downloads": "/apk",
  "🏠 Main Menu": "/start"
};


const reply = (body, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const text = (value, limit = 100) => String(value ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, limit);
const dateInMyanmar = (iso) => {
  const date = new Date(iso);
  return Number.isNaN(date.valueOf()) ? "Time unavailable" :
    new Intl.DateTimeFormat("en-GB", {
      timeZone: "Asia/Yangon", day: "2-digit", month: "short",
      hour: "2-digit", minute: "2-digit", hour12: true,
    }).format(date) + " MMT";
};
const myanmarDay = (date) => new Date(date.getTime() + 390 * 60000).toISOString().slice(0, 10);

async function sameSecret(provided, expected) {
  if (!provided || !expected) return false;
  const encoder = new TextEncoder();
  const digests = await Promise.all([provided, expected].map(v => crypto.subtle.digest("SHA-256", encoder.encode(v))));
  const a = new Uint8Array(digests[0]), b = new Uint8Array(digests[1]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function createTelegramHandler({ mode, env, fetcher = fetch, clock = () => new Date() }) {
  if (mode !== "viewer" && mode !== "admin") throw new Error("Unknown bot mode");
  const prefix = mode === "viewer" ? "TG_VIEWER" : "TG_ADMIN";

  async function telegram(method, token, body) {
    const response = await fetcher("https://api.telegram.org/bot" + token + "/" + method, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      const error = new Error("Telegram API unavailable");
      // Keep diagnostic codes, never the Telegram token or API response body.
      error.code = "telegram_http_" + String(response.status);
      throw error;
    }
    const data = await response.json();
    if (data.ok !== true) {
      const error = new Error("Telegram rejected message");
      error.code = "telegram_rejected";
      throw error;
    }
    return data;
  }
  async function database(path, env) {
    const url = (env.SUPABASE_URL || "").replace(/\/+$/, "") + "/rest/v1/" + path;
    const response = await fetcher(url, {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: "Bearer " + env.SUPABASE_SERVICE_ROLE_KEY,
        Accept: "application/json",
      },
    });
    if (!response.ok) throw new Error("Database metadata unavailable");
    const rows = await response.json();
    if (!Array.isArray(rows)) throw new Error("Invalid database metadata");
    return rows;
  }
  // Only directly published, public MP4 video URLs. Never send landing
  // pages, HLS playlists, tokenized links, DRM media, or header-bound videos.
  // Independently check the first bytes before offering the copyable URL.
  // Five distinct matches per Telegram page. The callback cursor is a source
  // entry offset, so unknown/failed MP4 links cannot pin navigation to page 1.
  async function publicHighlightMp4Links(start = 0) {
    if (!Number.isSafeInteger(start) || start < 0 || start > 150) {
      return {responseText: 'Invalid Highlights page. Use /highlights to restart.'};
    }
    const result = await footballHighlights({
      provider: 'dasfootball', action: 'catalog', force: start === 0,
    }, {fetcher});
    const candidates = [];
    for (const entry of result.entries || []) {
      const lines = [];
      for (const line of entry.lines || []) {
        if (line.stream_type !== 'mp4' ||
            line.referer || line.origin || line.user_agent) continue;
        try {
          const url = new URL(line.stream_url);
          if (url.protocol !== 'https:' || url.search || url.hash ||
              !/\.mp4$/i.test(url.pathname)) continue;
          lines.push({...line, stream_url: url.href});
        } catch (_) { /* Ignore invalid or protected external video URLs. */ }
      }
      if (lines.length) candidates.push({
        title: text(entry.title || 'Football highlights', 96),
        lines: lines.slice(0, 2),
      });
    }

    const available = [];
    let cursor = Math.min(start, candidates.length);
    let scanned = 0;
    // Bounded scans prevent a broken provider from tying up the webhook.
    while (cursor < candidates.length && scanned < 12 && available.length < 5) {
      const count = Math.min(5 - available.length, 12 - scanned, candidates.length - cursor);
      const batch = candidates.slice(cursor, cursor + count);
      cursor += count;
      scanned += count;
      const checked = await Promise.all(batch.map(async item => {
        const results = await Promise.all(item.lines.map(async line => {
          try {
            const check = await checkHighlightLine(line, {fetcher});
            return check.status === 'reachable' ? line.stream_url : null;
          } catch (_) { return null; }
        }));
        const url = results.find(Boolean);
        return url ? {title: item.title, url} : null;
      }));
      available.push(...checked.filter(Boolean));
    }

    const hasNext = cursor < candidates.length;
    const heading = '🎬 FOOTBALL HIGHLIGHTS — DIRECT MP4';
    const listing = available.length
      ? available.map((item, i) => (i + 1) + '. ' + item.title +
          '\n' + item.url).join('\n\n') +
          '\n\nMP4 first bytes checked; full playback is not verified.'
      : 'No verified public direct MP4 video URL on this page.';
    const keyboard = {inline_keyboard: [
      ...(hasNext ? [[{text:'➡️ Next 5',callback_data:'hl:' + cursor}]] : []),
      [{text:'🔄 First page',callback_data:'/highlights'},
       {text:'🧰 Tools',callback_data:'/tools'}],
    ]};
    return {responseText: heading + '\n' + listing, keyboard};
  }

  async function matches(command, env) {
    const data = await database("matches?select=league,home_team,away_team,kickoff_at,is_live" +
      "&is_active=eq.true&publish_state=eq.published&deleted_at=is.null" +
      "&order=kickoff_at.asc&limit=100", env);
    const today = myanmarDay(clock()), now = clock().valueOf();
    const items = data.filter(m => {
      const t = new Date(m.kickoff_at).valueOf();
      if (!Number.isFinite(t)) return false;
      if (command === "/live") return m.is_live === true;
      if (command === "/today") return myanmarDay(new Date(t)) === today;
      return t >= now && t <= now + 7 * 86400000;
    }).slice(0, 9);
    if (!items.length) return command === "/live" ?
      "No verified live football matches right now." : "No published football matches for this selection.";
    return (command === "/live" ? "🔴 LIVE FOOTBALL" : command === "/today" ? "⚽ TODAY'S FOOTBALL" : "📅 UPCOMING FOOTBALL") +
      "\n" + items.map(m => text(m.home_team, 50) + " vs " + text(m.away_team, 50) +
        "\n" + text(m.league, 70) + " • " + dateInMyanmar(m.kickoff_at)).join("\n\n") +
      "\n\nWatch on NCA: " + VIEWER_SITE;
  }
  // Private Admin navigation: only safe, non-credential channel metadata is sent.
  const PAGE_SIZE = 8;
  function makePage(rows, page, prefix, title) {
    const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
    const requested = /^\d{1,4}$/.test(String(page)) ? Number(page) : 0;
    const current = Math.min(Math.max(requested, 0), totalPages - 1);
    const inline_keyboard = rows.slice(current * PAGE_SIZE, (current + 1) * PAGE_SIZE)
      .map(row => [{ text: text(row.name, 58), callback_data: "channel:" + row.id }]);
    const navigation = [];
    if (current > 0) navigation.push({ text: "⬅️ Previous", callback_data: prefix + ":" + (current - 1) });
    if (current + 1 < totalPages) navigation.push({ text: "Next ➡️", callback_data: prefix + ":" + (current + 1) });
    if (navigation.length) inline_keyboard.push(navigation);
    inline_keyboard.push([
      { text: "📁 Categories", callback_data: "/categories" },
      { text: "🏠 Main menu", callback_data: "/start" },
    ]);
    return {
      responseText: "📺 " + title + " (" + rows.length + ")\nPage " + (current + 1) +
        "/" + totalPages + "\nSelect a channel to view its details.",
      keyboard: { inline_keyboard },
    };
  }
  function groupCategories(rows) {
    const groups = new Map();
    for (const row of rows) {
      const category = String(row.category || "Other").trim() || "Other";
      groups.set(category, (groups.get(category) || 0) + 1);
    }
    return [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }
  function makeCategoryPage(rows, page) {
    const groups = groupCategories(rows);
    const totalPages = Math.max(1, Math.ceil(groups.length / PAGE_SIZE));
    const requested = /^\d{1,4}$/.test(String(page)) ? Number(page) : 0;
    const current = Math.min(Math.max(requested, 0), totalPages - 1);
    const inline_keyboard = groups.slice(current * PAGE_SIZE, (current + 1) * PAGE_SIZE)
      .map(([name, count], index) => [{
        text: text(name, 42) + " (" + count + ")",
        callback_data: "cat:" + (current * PAGE_SIZE + index) + ":0",
      }]);
    const navigation = [];
    if (current > 0) navigation.push({ text: "⬅️ Previous", callback_data: "cats:" + (current - 1) });
    if (current + 1 < totalPages) navigation.push({ text: "Next ➡️", callback_data: "cats:" + (current + 1) });
    if (navigation.length) inline_keyboard.push(navigation);
    inline_keyboard.push([{ text: "📺 All Channels", callback_data: "/channels" },
      { text: "🏠 Main menu", callback_data: "/start" }]);
    return {
      responseText: "📁 Categories (" + groups.length + ")\nPage " + (current + 1) + "/" +
        totalPages + "\nChoose a category.",
      keyboard: { inline_keyboard },
    };
  }
  function searchToken(query) {
    const bytes = new TextEncoder().encode(query);
    if (!bytes.length || bytes.length > 32) return null;
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  function decodeSearchToken(token) {
    if (!/^[A-Za-z0-9_-]{1,43}$/.test(token)) return null;
    try {
      const decoded = atob(token.replace(/-/g, "+").replace(/_/g, "/"));
      const bytes = Uint8Array.from(decoded, ch => ch.charCodeAt(0));
      return bytes.length > 32 ? null : new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      return null;
    }
  }
  async function channelList(env, onlyBein) {
    const rows = await database("channels?select=id,name,category,epg_id,epg_source" +
      "&is_active=eq.true&order=name.asc&limit=250", env);
    return onlyBein ? rows.filter(r => /bein/i.test(r.name || "") || /bein/i.test(r.category || "")) : rows;
  }
  async function channelDetails(id, env) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return "Invalid channel selection.";
    const rows = await database("channels?select=id,name,category,epg_id,epg_source" +
      "&is_active=eq.true&id=eq." + encodeURIComponent(id) + "&limit=1", env);
    if (!rows.length) return "Channel not found.";
    // Never retrieve stream_url, key_id, key_data, or session credentials in Telegram.
    const lines = await database("channel_lines?select=label,stream_type,health_status,last_checked_at" +
      "&is_active=eq.true&channel_id=eq." + encodeURIComponent(id) + "&limit=20", env);
    const channel = rows[0];
    const statuses = lines.map((line, n) => "Line " + (n + 1) +
      " (" + text(line.label || "Server", 28) + "): " + text(line.stream_type || "auto", 16) +
      " • " + text(line.health_status || "unknown", 22));
    return "📺 " + text(channel.name, 110) + "\nCategory: " + text(channel.category, 65) +
      "\nEPG: " + text(channel.epg_id || "Not linked", 80) +
      "\nChannel ID: " + channel.id + "\nActive lines: " + lines.length + (statuses.length ? "\n" + statuses.join("\n") : "") +
      "\n\nManage protected playback details in the authenticated NCA Admin:\n" + ADMIN_SITE;
  }

  // NCA private admin extensions: only allowlisted private chats reach these operations.
  const uuidValid = id => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id||"");
  async function writeDb(path, method, body, {ignoreDuplicates=false, expectRows=false}={}) {
    const res = await fetcher((env.SUPABASE_URL||"").replace(/\/+$/,"") + "/rest/v1/" + path, {
      method, headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: "Bearer " + env.SUPABASE_SERVICE_ROLE_KEY,
        "Content-Type":"application/json", Accept:"application/json",
        Prefer: (ignoreDuplicates?"resolution=ignore-duplicates,":"resolution=merge-duplicates,") +
          (expectRows?"return=representation":"return=minimal"),
      },
      ...(body === undefined ? {} : {body:JSON.stringify(body)}),
    });
    if(!res.ok) throw Error("Database update failed (HTTP " + res.status + ")");
    return expectRows ? res.json() : [];
  }
  async function audit(chatId, actor, action, target="") {
    await writeDb("nca_bot_audit","POST",{chat_id:chatId,actor_id:actor,action,target_id:String(target).slice(0,150)});
  }
  async function getPrefs(chatId){
    const rows=await database("nca_bot_preferences?select=chat_id,alert_enabled,monitor_enabled,football_enabled&chat_id=eq."+chatId+"&limit=1",env);
    return rows[0]||null;
  }
  async function setPrefs(chatId,changes){
    const old=await getPrefs(chatId);
    await writeDb("nca_bot_preferences?on_conflict=chat_id","POST",{
      chat_id:chatId, alert_enabled:old?.alert_enabled??false,
      monitor_enabled:old?.monitor_enabled??false,
      football_enabled:old?.football_enabled??false, ...changes,
      updated_at:new Date().toISOString(),
    });
    return getPrefs(chatId);
  }
  function prefsText(p){
    return "🔔 Private Admin Notifications\nSubscribed: "+(p?"Yes":"No")+
    "\nAlerts: "+(p?.alert_enabled?"ON":"OFF")+
    "\nStream monitoring: "+(p?.monitor_enabled?"ON":"OFF")+
    "\nFootball events: "+(p?.football_enabled?"ON":"OFF")+
    (p && !p.alert_enabled && (p.monitor_enabled || p.football_enabled)
      ? "\n⚠️ Alerts are OFF: monitoring and football notifications are paused." : "")+
    "\n\n/subscribe enables all; /unsubscribe disables all.\n" +
    "/alerts on|off  /monitor on|off  /football on|off";
  }
  async function allChannels(){
    return database("channels?select=id,name,category,is_active,epg_id,epg_source&order=name.asc&limit=500",env);
  }
  async function lineStatuses(){
    return database("channel_lines?select=id,channel_id,label,stream_type,health_status,last_checked_at,is_active&limit=500",env);
  }
  async function fixtures(){
    return database("matches?select=id,league,home_team,away_team,kickoff_at,is_live,is_finished,is_featured,home_score,away_score,status_short,is_active,publish_state&is_active=eq.true&publish_state=eq.published&deleted_at=is.null&order=kickoff_at.asc&limit=300",env);
  }
  async function mappings(){
    const [links,manual,epg]=await Promise.all([
      database("stream_links?select=match_id,channel_id&is_active=eq.true&channel_id=not.is.null&limit=500",env),
      database("nca_bot_match_channels?select=match_id,channel_id&limit=500",env),
      database("nca_epg_auto_match_channels?select=match_id,channel_id,last_verified_at&limit=500",env)
    ]);
    // Auto TV guide assignments must have a recent schedule verification.
    const cutoff=clock().getTime()-36*3600000;
    const freshEpg=epg.filter(x=>Date.parse(x.last_verified_at)>=cutoff);
    const result=new Map();
    for(const link of links.concat(manual,freshEpg)){
      if(!uuidValid(link.match_id)||!uuidValid(link.channel_id))continue;
      if(!result.has(link.match_id)) result.set(link.match_id,new Set());
      result.get(link.match_id).add(link.channel_id);
    }
    return result;
  }
  const displayMatch=m => text(m.home_team,44)+" vs "+text(m.away_team,44);
  const matchTime=m=>dateInMyanmar(m.kickoff_at);
  function channelNames(ids,channels){
    const map=new Map(channels.map(x=>[x.id,x.name]));
    return [...(ids||[])].map(id=>map.get(id)).filter(Boolean).slice(0,8);
  }
  async function matchDetail(matchId){
    if(!uuidValid(matchId))return "Invalid match ID.";
    const [matches,channels,mapping]=await Promise.all([fixtures(),allChannels(),mappings()]);
    const m=matches.find(x=>x.id===matchId);
    if(!m)return "Match not found in published fixtures.";
    const broadcast=channelNames(mapping.get(m.id),channels);
    return "⚽ "+displayMatch(m)+"\nLeague: "+text(m.league,70)+
      "\nKickoff: "+matchTime(m)+"\nStatus: "+(m.is_live?"LIVE":m.is_finished?"Finished":"Scheduled")+
      "\nChannels (confirmed in NCA database):\n"+
      (broadcast.length?broadcast.map(n=>"📺 "+text(n,80)).join("\n"):"Not assigned / not verified")+
      "\n\nMatch ID: "+m.id+"\nTo add an explicit mapping: /mapmatch MATCH_ID CHANNEL_ID";
  }
  async function matchReadiness(){
    const [ms, channelRows, assignments, lines] = await Promise.all([
      fixtures(), allChannels(), mappings(), lineStatuses(),
    ]);
    const now=clock().getTime();
    const upcoming=ms.filter(m=>!m.is_finished &&
      Date.parse(m.kickoff_at)>=now-30*60000 &&
      Date.parse(m.kickoff_at)<=now+3*3600000)
      .sort((a,b)=>Number(b.is_featured===true)-Number(a.is_featured===true))
      .slice(0,12);
    if(!upcoming.length)return "⚽ No published matches in the next three hours.";
    const healthyLine = new Set(lines.filter(l=>l.is_active &&
      (l.health_status==="healthy"||l.health_status==="slow") &&
      Date.parse(l.last_checked_at)>=now-30*60000).map(l=>l.channel_id));
    const activeChannels=new Set(channelRows.filter(c=>c.is_active).map(c=>c.id));
    return "⚽ UPCOMING MATCH READINESS (probe metadata only)\n"+
      upcoming.map(m=>{
        const channels=[...(assignments.get(m.id)||[])].filter(id=>activeChannels.has(id));
        const ready=channels.filter(id=>healthyLine.has(id)).length;
        const condition=!channels.length?"⚠️ No mapped channel":
          ready===0?"🔴 No recently reachable mapped line":
          ready<channels.length?"🟡 Partial reachability":"🟢 Reachable mapping";
        return (m.is_featured?"⭐ Featured • ":"")+displayMatch(m)+"\n"+matchTime(m)+"\n"+
          condition+" • "+ready+"/"+channels.length+" mapped channel(s) recently reachable";
      }).join("\n\n")+
      "\n\nFirst-chunk reachability is not proof of video playback.";
  }
  async function broadcastList(){
    const [matches,channels,mapping]=await Promise.all([fixtures(),allChannels(),mappings()]);
    const now=clock().getTime();
    const relevant=matches.filter(m=>(new Date(m.kickoff_at).getTime()>=now-2*86400000)&&
      (new Date(m.kickoff_at).getTime()<=now+7*86400000)).slice(0,25);
    if(!relevant.length)return "No published fixtures in the recent/upcoming window.";
    return "⚽ NCA MATCH CHANNEL SCHEDULE (Database links only)\n"+
      relevant.slice(0,18).map(m=>{
        const names=channelNames(mapping.get(m.id),channels);
        return "• "+displayMatch(m)+"\n"+matchTime(m)+
        "\n📺 "+(names.length?names.map(n=>text(n,55)).join(", "):"Channel not assigned");
      }).join("\n\n")+
      "\n\nUse /match MATCH_ID for details. No broadcast rights or live playback guarantees are inferred.";
  }
  async function matchList(){
    const ms=await fixtures(),now=clock().getTime();
    const upcoming=ms.filter(m=>{const d=new Date(m.kickoff_at).getTime();return d>=now-4*3600000 && d<=now+7*86400000;}).slice(0,12);
    if(!upcoming.length)return "No upcoming published football fixtures in the next 7 days.";
    return "⚽ Published Fixtures\n"+upcoming.map(m=>
      "• "+displayMatch(m)+"\n"+text(m.league,55)+" • "+matchTime(m)+
      (m.is_live?" 🔴 LIVE":"")+"\nID: "+m.id).join("\n\n")+
      "\n\nUse /broadcasts for mapped TV channels.";
  }
  async function stats(){
    const [channels,lines,ms]=await Promise.all([allChannels(),lineStatuses(),fixtures()]);
    const count=v=>lines.filter(l=>l.is_active&&l.health_status===v).length;
    return "📊 NCA DATABASE STATS\nChannels: "+channels.length+
      "\nActive: "+channels.filter(x=>x.is_active).length+
      "\nInactive: "+channels.filter(x=>!x.is_active).length+
      "\nChannel Lines: "+lines.length+
      "\nHealthy: "+count("healthy")+"\nSlow: "+count("slow")+
      "\nFailed: "+count("failed")+"\nUnknown: "+count("unknown")+
      "\nPublished matches: "+ms.length+
      "\n\nReachability is not proof of playable video.";
  }
  async function logReport(chatId){
    const [events,lines]=await Promise.all([
      database("nca_bot_audit?select=action,target_id,created_at&chat_id=eq."+chatId+"&order=created_at.desc&limit=12",env),
      lineStatuses()
    ]);
    const failed=lines.filter(x=>x.is_active&&x.health_status==="failed").slice(0,8);
    return "🧾 Private Admin Audit (latest "+events.length+")\n"+
      (events.length?events.map(e=>"• "+text(e.action,35)+" "+text(e.target_id,32)+"\n"+text(e.created_at,30)).join("\n"):"No recorded actions.")+
      "\n\nFailed channel lines: "+failed.length+(failed.length?"\n"+failed.map(x=>text(x.channel_id,36)).join("\n"):"")+
      "\n\nThis is an audit/health summary, not raw Supabase runtime logs.";
  }
  async function backupReport(){
    return "🗃️ Database backup readiness report\n"+await stats()+
      "\n\nNo actual backup has been created by this command. " +
      "Check managed backups and restore points in the secured Supabase Dashboard.";
  }
  function managePage(rows,page){
    const n=Math.max(1,Math.ceil(rows.length/8));
    const cur=Math.min(n-1,Math.max(0,Number(page)||0));
    const inline_keyboard=rows.slice(cur*8,cur*8+8).map(row=>[{
      text:(row.is_active?"🟢 ":"⚪ ")+text(row.name,45),
      callback_data:"toggle:"+row.id,
    }]);
    const nav=[];
    if(cur>0)nav.push({text:"⬅️",callback_data:"manage:"+(cur-1)});
    if(cur<n-1)nav.push({text:"➡️",callback_data:"manage:"+(cur+1)});
    if(nav.length)inline_keyboard.push(nav);
    inline_keyboard.push([{text:"🏠 Menu",callback_data:"/start"}]);
    return {responseText:"🛠️ Channel Management ("+rows.length+") • "+(cur+1)+"/"+n+
      "\nSelect a channel to confirm Enable/Disable.",keyboard:{inline_keyboard}};
  }
  async function handleToggle(raw,chatId,actor){
    const parts=raw.split(":"),id=parts[1];
    if(!uuidValid(id))return {responseText:"Invalid Channel ID."};
    const channels=await allChannels(),c=channels.find(x=>x.id===id);
    if(!c)return {responseText:"Channel not found."};
    if(parts[0]==="toggle")return {
      responseText:"⚠️ Confirm Channel status change\n"+text(c.name,80)+
      "\nCurrent: "+(c.is_active?"Active":"Inactive")+
      "\nRequested: "+(c.is_active?"Disable":"Enable"),
      keyboard:{inline_keyboard:[[
        {text:c.is_active?"Disable Channel":"Enable Channel",callback_data:"manage"+(c.is_active?"off":"on")+":"+id},
        {text:"Cancel",callback_data:"/manage"},
      ]]},
    };
    if(parts[0]==="manageon" && c.is_active)return {responseText:"Channel already active."};
    if(parts[0]==="manageoff" && !c.is_active)return {responseText:"Channel already inactive."};
    const newState=parts[0]==="manageon";
    await writeDb("channels?id=eq."+id,"PATCH",{is_active:newState,updated_at:new Date().toISOString()});
    await audit(chatId,actor,newState?"channel_enable":"channel_disable",id);
    return {responseText:"✅ "+text(c.name,85)+" is now "+(newState?"Active":"Inactive")+
      ".\nThis changes NCA channel availability. Use /manage to change it back."};
  }
  async function mapAction(raw,chatId,actor){
    const p=raw.trim().split(/\s+/),cmd=p[0].toLowerCase();
    if(p.length!==3||!uuidValid(p[1])||!uuidValid(p[2]))
      return "Usage: "+cmd+" MATCH_UUID CHANNEL_UUID";
    const matchId=p[1],channelId=p[2];
    const [matches,channels]=await Promise.all([fixtures(),allChannels()]);
    const match=matches.find(x=>x.id===matchId),channel=channels.find(x=>x.id===channelId);
    if(!match||!channel)return "Match or channel not found.";
    if(cmd==="/mapmatch")return "Confirm adding broadcast mapping:\n"+displayMatch(match)+
      "\n📺 "+text(channel.name,70)+"\nSend /confirmmap "+matchId+" "+channelId;
    if(cmd==="/unmapmatch")return "Confirm removing manual broadcast mapping:\n"+displayMatch(match)+
      "\n📺 "+text(channel.name,70)+"\nSend /confirmunmap "+matchId+" "+channelId;
    if(cmd==="/confirmmap"){
      await writeDb("nca_bot_match_channels?on_conflict=match_id,channel_id","POST",{
        match_id:matchId,channel_id:channelId,source:"admin_manual",
      });
      await audit(chatId,actor,"mapmatch",matchId+":"+channelId);
      return "✅ Channel–match mapping saved.\n"+displayMatch(match)+" → "+text(channel.name,70);
    }
    await writeDb("nca_bot_match_channels?match_id=eq."+matchId+"&channel_id=eq."+channelId,"DELETE");
    await audit(chatId,actor,"unmapmatch",matchId+":"+channelId);
    return "✅ Manual mapping removed (existing stream-link mappings remain unchanged).";
  }
  async function filterChannels(query,page){
    const raw=query.trim().toLowerCase();
    const allowed=["dash","hls","mp4","flv","auto","healthy","slow","failed","unknown","active","inactive"];
    if(!allowed.includes(raw))return {
      responseText:"🔎 Filter by stream type, status or availability.\n"+
      "Usage: /filter dash\nOptions: "+allowed.join(", "),
    };
    const [channels,lines]=await Promise.all([allChannels(),lineStatuses()]);
    const ids=new Set(lines.filter(l=>l.is_active&&
      (l.stream_type===raw||l.health_status===raw)).map(l=>l.channel_id));
    const rows=channels.filter(c=>raw==="active"?c.is_active:
      raw==="inactive"?!c.is_active:ids.has(c.id));
    return makePage(rows,page,"filter:"+raw,"Filter: "+raw);
  }
  async function pulseAuthorized(req){
    const key=req.headers.get("x-nca-pulse-key")||"";
    if(!/^[0-9a-f]{64}$/i.test(key))return false;
    const rows=await database("nca_bot_scheduler?select=secret_sha256&id=eq.1&limit=1",env);
    const bytes=new TextEncoder().encode(key);
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes)))
      .map(x=>x.toString(16).padStart(2,"0")).join("");
    const expected=rows[0]?.secret_sha256||"";
    return digest.length===expected.length && digest.split("").reduce((d,c,i)=>d|(c.charCodeAt(0)^expected.charCodeAt(i)),0)===0;
  }
  async function pulse(){
    const stored=await database("nca_bot_preferences?select=chat_id,alert_enabled,monitor_enabled,football_enabled&alert_enabled=eq.true&limit=50",env);
    const allowlist=new Set((env.TG_ADMIN_USER_IDS||"").split(",").map(s=>s.trim()).filter(Boolean));
    const prefs=stored.filter(x=>allowlist.has(String(x.chat_id)));
    // Continue checking channel health when no one can receive a notification.
    // Never bypass the private-admin allowlist just to make subscriber count nonzero.
    const skippedSubscribers=stored.length-prefs.length;
    const recordDelivery=async(chatId,kind,key,outcome,errorCode=null)=>{
      // Audit must never alter successful delivery or suppress a retry.
      // Only sanitized outcome codes are stored; never raw error text.
      try {
        await writeDb("nca_bot_delivery_attempts","POST",{
          chat_id:chatId,kind,event_key:key.slice(0,240),outcome,
          error_code:errorCode,
        });
      } catch (_) {
        console.warn("NCA Telegram delivery outcome could not be audited");
      }
    };
    const notify=async(chatId,kind,key,message)=>{
      const existing=await database("nca_bot_alert_state?select=event_key&chat_id=eq."+chatId+
        "&event_key=eq."+encodeURIComponent(key)+"&limit=1",env);
      if(existing.length)return;
      const result=await writeDb("nca_bot_alert_state?on_conflict=chat_id,event_key","POST",
        {chat_id:chatId,event_key:key},{ignoreDuplicates:true,expectRows:true});
      if(!result.length)return;
      try {
        await telegram("sendMessage",env.TG_ADMIN_BOT_TOKEN,{chat_id:chatId,
          text:message.slice(0,3500),disable_web_page_preview:true});
        await recordDelivery(chatId,kind,key,"sent");
      } catch (error) {
        const safeCode = typeof error?.code === "string" &&
          /^telegram_(http_[45][0-9]{2}|rejected)$/.test(error.code)
          ? error.code : "telegram_send_failed";
        await recordDelivery(chatId,kind,key,"failed",safeCode);
        // Release the dedupe claim if delivery failed, so the next pulse retries.
        // Telegram timeouts can be ambiguous; notifications are at-least-once.
        try {
          await writeDb("nca_bot_alert_state?chat_id=eq."+chatId+
            "&event_key=eq."+encodeURIComponent(key),"DELETE");
        } catch (_) { /* Keep the original delivery error. */ }
        throw error;
      }
    };
    // Check a bounded, rotating subset; never return or send source URLs / DRM fields.
    let checked=0, probeErrors=0;
    { // Perform monitoring independently of alert subscriptions.
      const lines=await database(
        "channel_lines?select=id,channel_id,stream_url,referer,origin,"+
        "telegram_probe_status,telegram_probe_http_status,"+
        "telegram_probe_failure_streak,telegram_probe_checked_at,"+
        "playback_status,last_playback_checked_at"+
        "&is_active=eq.true&order=telegram_probe_checked_at.asc.nullsfirst&limit=12",env);
      const channelRows=await allChannels();
      const names=new Map(channelRows.filter(c=>c.is_active).map(c=>[c.id,c.name]));
      // Bound concurrency: three batches of four, never streaming the media.
      // Independent of device playback and manifest/segment diagnostics.
      for(let offset=0;offset<lines.length;offset+=4){
        await Promise.allSettled(lines.slice(offset,offset+4).map(async line=>{
          if(!names.has(line.channel_id))return;
          try{
            const probe=await probeStreamFirstChunk(line.stream_url,{headers:{
              "Range":"bytes=0-4095","Accept":"*/*",
              ...(line.referer?{"Referer":line.referer}:{}),
              ...(line.origin?{"Origin":line.origin}:{}),
            },timeoutMs:4500});
            checked++;
            // A missing HTTP response (timeout/network error) is inconclusive:
            // it cannot prove that the Viewer cannot play the stream.
            const reachability=probe.status==="failed" && !probe.httpStatus
              ? "unknown" : probe.status;
            const previousFailures=Math.min(3,Math.max(0,
              Number(line.telegram_probe_failure_streak)||0));
            const failureStreak=reachability==="failed"
              ? Math.min(3,previousFailures+1) : 0;
            const checkedAt=new Date().toISOString();
            // Never overwrite health_status, health_http_status,
            // last_checked_at, manifest, segment or playback state.
            await writeDb("channel_lines?id=eq."+line.id,"PATCH",{
              telegram_probe_status:reachability,
              telegram_probe_http_status:probe.httpStatus,
              telegram_probe_latency_ms:probe.latencyMs,
              telegram_probe_failure_streak:failureStreak,
              telegram_probe_checked_at:checkedAt,
            });
            // Alert only after two consecutive HTTP probe failures,
            // not on a single failed request to a region-specific CDN.
            const failedNow=reachability==="failed" && previousFailures===1;
            const restored=previousFailures>=2 &&
              (reachability==="healthy"||reachability==="slow");
            if(failedNow || restored){
              // Identify each actual transition by its previous check, rather
              // than once per day. Fail -> recover -> fail gets a fresh alert.
              const key="reachability:"+line.id+":"+
                (failedNow?"failed":"recovered")+":"+
                String(line.telegram_probe_checked_at || "first");
              for(const admin of prefs.filter(x=>x.monitor_enabled)){
                try {
                  await notify(admin.chat_id,"health",key,
                    (failedNow?"⚠️ NCA SERVER HTTP PROBE FAILED TWICE":"✅ NCA SERVER HTTP PROBE RECOVERED")+
                    "\n📺 "+text(names.get(line.channel_id),85)+
                    "\nServer HTTP: "+reachability+" (first chunk only)"+
                    "\nVideo: "+
                      (line.playback_status==="verified"
                        ? "previously verified on device" : "NOT VERIFIED by bot")+
                    "\nLast check: "+checkedAt+
                    "\nThe Viewer may still play on another network/VPN.");
                } catch (_) { /* Keep monitoring other lines even if Telegram fails. */ }
              }
            }
          }catch{
            // Do not leak stream URLs or request headers to logs.
            probeErrors++;
          }
        }));
      }
    }
    if(prefs.some(p=>p.football_enabled)){
      const ms=(await fixtures()).filter(m=>{
        const t=new Date(m.kickoff_at).getTime(),now=clock().getTime();
        return t>=now-6*3600000 && t<=now+60*60000;
      });
      // Once per featured match, check mapped channels 15-45 min before kickoff.
      // Only private, allowlisted Admin subscribers may receive these reports.
      const featuredSoon=ms.filter(m=>m.is_featured===true && !m.is_finished &&
        Date.parse(m.kickoff_at)-clock().getTime()>=15*60000 &&
        Date.parse(m.kickoff_at)-clock().getTime()<=45*60000).slice(0,15);
      if(featuredSoon.length){
        const [assignments,channelRows,lines]=await Promise.all([
          mappings(),allChannels(),lineStatuses(),
        ]);
        const active=new Set(channelRows.filter(c=>c.is_active).map(c=>c.id));
        const recentlyReachable=new Set(lines.filter(l=>l.is_active &&
          (l.health_status==="healthy" || l.health_status==="slow") &&
          Date.parse(l.last_checked_at)>=clock().getTime()-30*60000)
          .map(l=>l.channel_id));
        for(const match of featuredSoon){
          const mapped=[...(assignments.get(match.id)||[])].filter(id=>active.has(id));
          const reachable=mapped.filter(id=>recentlyReachable.has(id)).length;
          const state=!mapped.length?"⚠️ No channel assignment":
            !reachable?"🔴 No recent reachable mapped channel":
            reachable<mapped.length?"🟡 Some mapped channels reachable":
            "🟢 Mapped channels recently reachable";
          const alertKey="readiness:"+match.id+":"+String(match.kickoff_at);
          const alertMessage="⭐ NCA FEATURED MATCH READINESS\n"+displayMatch(match)+"\n"+
            matchTime(match)+"\n"+state+" ("+reachable+"/"+mapped.length+")"+
            "\nCheck /readiness or /broadcasts. First-chunk reachability only; playback unverified.";
          for(const p of prefs.filter(x=>x.football_enabled)){
            try {await notify(p.chat_id,"readiness",alertKey,alertMessage);}
            catch (_) { /* Failed delivery can retry at the next scheduled pulse. */ }
          }
        }
      }
      for(const m of ms.slice(0,50)){
        const start=new Date(m.kickoff_at).getTime()-clock().getTime();
        const isKickoff=start>=0&&start<=15*60000&&!m.is_finished;
        const isLive=m.is_live===true;
        if(!isKickoff&&!isLive)continue;
        const marker=isLive?"score:"+text(m.status_short||"LIVE",18)+
          ":"+String(m.home_score??"-")+":"+String(m.away_score??"-"):"kickoff";
        const key="match:"+m.id+":"+marker;
        for(const p of prefs.filter(x=>x.football_enabled)){
          try{
            await notify(p.chat_id,"football",key,
              (isLive?"🔴 LIVE MATCH":"⏰ UPCOMING MATCH")+"\n"+
              displayMatch(m)+"\n"+text(m.league,70)+"\n"+
              matchTime(m)+(isLive?"\nScore: "+String(m.home_score??"-")+
              " - "+String(m.away_score??"-"):"")+
              "\nChannel assignments: /broadcasts");
          } catch { /* one Telegram send failure must not stop other subscribers */ }
        }
      }
    }
    return {ok:true,subscribers:prefs.length,configured_subscribers:stored.length,
      skipped_subscribers:skippedSubscribers,checked,probe_errors:probeErrors};
  }

  async function health(env) {
    const [channels, lines] = await Promise.all([
      database("channels?select=id&is_active=eq.true&limit=250", env),
      database("channel_lines?select=health_status,telegram_probe_status,playback_status&is_active=eq.true&limit=500", env),
    ]);
    const counts = { healthy: 0, slow: 0, failed: 0, unknown: 0 };
    const botProbes = { healthy: 0, slow: 0, failed: 0, unknown: 0 };
    let videoVerified = 0;
    for (const row of lines) {
      const status = String(row.health_status || "unknown").toLowerCase();
      const reachability = String(row.telegram_probe_status || "unknown").toLowerCase();
      counts[status in counts ? status : "unknown"]++;
      botProbes[reachability in botProbes ? reachability : "unknown"]++;
      if (row.playback_status === "verified") videoVerified++;
    }
    return "📊 NCA CHANNEL HEALTH\nActive channels: " + channels.length +
      "\nActive lines: " + lines.length + "\n🟢 Healthy lines: " + counts.healthy +
      "\n🟡 Slow lines: " + counts.slow + "\n🔴 Media probe FAILED: " + counts.failed +
      "\n⚪ Media probe UNKNOWN: " + counts.unknown +
      "\n🌐 Server HTTP probe FAILED: " + botProbes.failed +
      "\n🌐 Server HTTP probe UNKNOWN: " + botProbes.unknown +
      "\n▶️ Device video VERIFIED: " + videoVerified +
      "\n\nBot HTTP checks do not prove or disprove video playback.";
  }
  async function builds() {
    const response = await fetcher("https://api.github.com/repos/nyeinchanaung75299-eng/football-stream-app/actions/runs?branch=main&per_page=20", {
      headers: { Accept: "application/vnd.github+json", "User-Agent": "NCA-Telegram-Admin" },
    });
    if (!response.ok) throw new Error("GitHub build status unavailable");
    const json = await response.json();
    const recent = (json.workflow_runs || []).filter(r =>
      ["Build and Deploy Web Viewer", "Build Android V9.8 APKs"].includes(r.name)).slice(0, 2);
    if (!recent.length) return "No recent tracked Web/APK runs.";
    return "🛠️ NCA BUILDS\n" + recent.map(r => text(r.name, 55) + ": " +
      text(r.conclusion || r.status, 25) + "\n" + text(r.html_url, 190)).join("\n\n");
  }
  async function diagnostics(chatId){
    const [prefs,lines,stored,deliveries]=await Promise.all([
      getPrefs(chatId),lineStatuses(),
      database("nca_bot_preferences?select=chat_id,alert_enabled&alert_enabled=eq.true&limit=50",env),
      database("nca_bot_delivery_attempts?select=outcome,error_code,created_at"+
        "&chat_id=eq."+chatId+
        "&created_at=gte."+encodeURIComponent(
          new Date(clock().getTime()-24*3600000).toISOString())+
        "&order=created_at.desc&limit=200",env),
    ]);
    const allowlist=new Set((env.TG_ADMIN_USER_IDS||"").split(",").map(s=>s.trim()).filter(Boolean));
    const eligible=stored.filter(x=>allowlist.has(String(x.chat_id)));
    const recent=lines.filter(l=>l.is_active && Date.parse(l.last_checked_at)>clock().getTime()-30*60000).length;
    return "🩺 NCA BOT DIAGNOSTICS\n"+
      "Alert subscriptions: "+stored.length+" configured, "+eligible.length+" authorized\n"+
      "Your alerts: "+(prefs?.alert_enabled?"ON":"OFF")+"\n"+
      "Recently checked lines (30m): "+recent+"/"+lines.filter(l=>l.is_active).length+"\n"+
      "Your delivery attempts (24h): "+
        deliveries.filter(d=>d.outcome==="sent").length+" sent, "+
        deliveries.filter(d=>d.outcome==="failed").length+" failed"+
        (deliveries.length===200?" (latest 200)":"")+"\n"+
      (stored.length && !eligible.length?
        "⚠️ Subscription / TG_ADMIN_USER_IDS allowlist mismatch. Check the server secret; do not share IDs or tokens in chat.\n":"")+
      "Use /testbot to verify the Telegram API and webhook.\n"+
      "A successful cron response alone does not prove alerts were delivered.";
  }
  async function testBot(){
    const [me,webhook]=await Promise.all([
      telegram("getMe",env.TG_ADMIN_BOT_TOKEN),
      telegram("getWebhookInfo",env.TG_ADMIN_BOT_TOKEN),
    ]);
    return "🧪 TELEGRAM CONNECTION TEST\n"+
      "Token verified: "+(me?.result?.is_bot===true?"Yes":"No")+"\n"+
      "Webhook registered: "+(webhook?.result?.url?"Yes":"No")+"\n"+
      "Pending updates: "+Number(webhook?.result?.pending_update_count||0)+"\n"+
      "Latest webhook error: "+text(webhook?.result?.last_error_message||"None reported",180)+
      "\n\nThis reply also confirms the bot could send a message.";
  }
  async function handle(req) {
    if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);
    if (req.headers.get("x-nca-pulse-key") !== null) {
      if (!await pulseAuthorized(req)) return reply({error:"Unauthorized scheduler"},401);
      return reply(await pulse());
    }
    const token = env[prefix + "_BOT_TOKEN"];
    const secret = env[prefix + "_WEBHOOK_SECRET"];
    if (!token || !secret || !env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      return reply({ error: "Bot not configured" }, 503);
    }
    if (!await sameSecret(req.headers.get("X-Telegram-Bot-Api-Secret-Token"), secret)) {
      return reply({ error: "Invalid webhook" }, 401);
    }
    const update = await req.json().catch(() => null);
    if (!update || typeof update !== "object") return reply({ error: "Bad update" }, 400);
    const callback = update.callback_query;
    const message = callback?.message || update.message;
    const from = callback?.from || update.message?.from;
    const chat = message?.chat;
    if (!chat || !from || !Number.isSafeInteger(chat.id) || !Number.isSafeInteger(from.id)) return reply({ ok: true });
    const incomingText = String(callback ? callback.data || "" : message.text || "").trim();
    const raw = mode === "admin" && !callback ? (ADMIN_BOTTOM_COMMANDS[incomingText] || incomingText) : incomingText;
    const cmd = raw.split(/\s+/)[0].split("@")[0].toLowerCase();
    // The pairing command returns only the requesting user's OWN ID.
    // All Admin data remains inaccessible until that ID is explicitly allowlisted.
    if (mode === "admin") {
      if (chat.type !== "private" || String(chat.id) !== String(from.id)) return reply({ ok: true });
      if (cmd === "/whoami") {
        await telegram("sendMessage", token, {
          chat_id: chat.id, text: "Your Telegram User ID: " + String(from.id) +
            "\nAdd this ID to the private Supabase secret TG_ADMIN_USER_IDS to enable Admin commands.",
        });
        return reply({ ok: true });
      }
      const allowed = new Set((env.TG_ADMIN_USER_IDS || "").split(",").map(s => s.trim()).filter(Boolean));
      if (!allowed.has(String(from.id))) {
        // Clearing the old persistent keyboard is safe even for an unpaired
        // private chat; never reveal private Admin data or inline controls.
        if (cmd === "/start" || cmd === "/menu" || cmd === "/help") {
          await telegram("sendMessage", token, {
            chat_id:chat.id,
            text:"⌨️ Old permanent keyboard hidden. This chat is not linked to NCA Private Admin.\n"+
              "Use /whoami and add your Telegram ID to TG_ADMIN_USER_IDS in Supabase Edge Function Secrets.",
            reply_markup:{remove_keyboard:true},
          });
        }
        return reply({ ok: true });
      }
    }
    if (callback && callback.id) await telegram("answerCallbackQuery", token, { callback_query_id: callback.id });
    let responseText, keyboard, documentSent = false;
    try {
      if (mode === "viewer") {
        if (["/today", "/live", "/schedule"].includes(cmd)) {
          responseText = await matches(cmd, env);
        } else if (cmd === "/channels") {
          const rows = await channelList(env, false);
          responseText = "📺 NCA active channels: " + rows.length +
            "\nView EPG and authorized playback in the NCA website:\n" + VIEWER_SITE;
        } else {
          responseText = "⚽ NCA Football Viewer\nUse /today /live /schedule /channels.\n" +
            "Automatic match alerts are not enabled until subscriptions are configured.";
          keyboard = { inline_keyboard: [
            [{ text: "⚽ Today", callback_data: "/today" }, { text: "🔴 Live", callback_data: "/live" }],
            [{ text: "📅 Schedule", callback_data: "/schedule" }],
            [{ text: "Open Viewer", url: VIEWER_SITE }],
          ] };
        }
      } else if (cmd === "/start" || cmd === "/menu" || cmd === "/help") {
        // A Telegram message can remove the old reply keyboard OR show inline
        // buttons, not both. Send a one-time cleanup message on typed /menu.
        if (!callback) {
          await telegram("sendMessage",token,{chat_id:chat.id,
            text:"⌨️ Old permanent keyboard removed. Open this menu with /menu.",
            reply_markup:{remove_keyboard:true}});
        }
        responseText="🛡️ NCA PRIVATE ADMIN\nChoose a tool below. This menu stays in chat, not under the typing area.\n"+
          "Use /menu any time to open it again.";
        keyboard=ADMIN_INLINE_MENU;
      } else if (cmd === "/tools") {
        responseText="🧰 NCA ADMIN TOOLS\nChoose a function. /menu returns to the main menu.";
        keyboard=ADMIN_TOOLS_MENU;
      } else if (cmd === "/apk" || cmd === "/downloads") {
        responseText = "📦 NCA APK DOWNLOADS\nSelect the latest published, SHA-verified ARM64 release.\n" +
          "A different Android signing certificate can still block an in-place update.";
        keyboard = ADMIN_APK_MENU;
      } else if (cmd === "/apk_viewer" || cmd === "/apk_admin") {
        await sendTelegramReleaseApk({
          kind: cmd === "/apk_admin" ? "admin" : "viewer",
          chatId: chat.id, token, fetcher,
        });
        documentSent = true;
      } else if (cmd === "/highlights" || /^hl:\d{1,3}$/.test(raw)) {
        ({responseText, keyboard} = await publicHighlightMp4Links(
          cmd === "/highlights" ? 0 : Number(raw.slice(3))));
      } else if (cmd === "/testbot") {
        responseText=await testBot();
      } else if (cmd === "/diagnostics" || cmd === "/diag") {
        responseText=await diagnostics(chat.id);
      } else if (cmd === "/readiness") {
        responseText=await matchReadiness();
      } else if (cmd === '/reports') {
        const reports=await database('nca_viewer_reports?select=created_at,channels(name),channel_lines(label)&order=created_at.desc&limit=20',env);
        responseText='🚩 VIEWER LINE REPORTS\n'+(reports.length?reports.map(r=>
          text(r.channels?.name,70)+' • '+text(r.channel_lines?.label,50)+'\n'+text(r.created_at,25)).join('\n\n'):'No recent reports.');
      } else if (cmd === "/health" || cmd === "/status") {
        responseText = await health(env);
      } else if (cmd === "/build") {
        responseText = await builds();
      } else if (cmd === "/stats") {
        responseText = await stats();
      } else if (cmd === "/logs" || cmd === "/audit") {
        responseText = await logReport(chat.id);
      } else if (cmd === "/backup") {
        responseText = await backupReport();
      } else if (cmd === "/security") {
        const allowedUsers=(env.TG_ADMIN_USER_IDS||"").split(",").map(s=>s.trim()).filter(Boolean);
        responseText="🔒 NCA PRIVATE ADMIN SECURITY\nYour Telegram ID: "+String(from.id)+
          "\nAdmin allowlist entries: "+allowedUsers.length+
          "\nPrivate chat verified: Yes\nAction audit: Enabled\n"+
          "Webhook secret verification: Enabled\n"+
          "DRM credentials and session URLs: Never sent in Telegram.";
      } else if (cmd === "/subscribe" || cmd === "/unsubscribe") {
        if(cmd==="/subscribe") await setPrefs(chat.id,{alert_enabled:true,monitor_enabled:true,football_enabled:true});
        else await writeDb("nca_bot_preferences?chat_id=eq."+chat.id,"DELETE");
        await audit(chat.id,from.id,cmd.slice(1));
        responseText=prefsText(await getPrefs(chat.id));
      } else if (["/alerts","/monitor","/football"].includes(cmd)) {
        const arg=raw.split(/\s+/)[1]?.toLowerCase();
        if(arg==="on"||arg==="off"){
          const col=cmd==="/alerts"?"alert_enabled":cmd==="/monitor"?"monitor_enabled":"football_enabled";
          // Turning a notification category ON must also enable the master
          // alerts switch; /alerts off remains an explicit global pause.
          const changes={[col]:arg==="on"};
          if(arg==="on" && col!=="alert_enabled")changes.alert_enabled=true;
          await setPrefs(chat.id,changes);
          await audit(chat.id,from.id,col+"_"+arg);
        }
        responseText=prefsText(await getPrefs(chat.id));
      } else if (cmd === "/matches" || cmd === "/schedule") {
        responseText = await matchList();
      } else if (cmd === "/broadcasts" || cmd === "/channelmatch") {
        responseText = await broadcastList();
      } else if (cmd === "/match") {
        responseText = await matchDetail(raw.split(/\s+/)[1]);
      } else if (["/mapmatch","/unmapmatch","/confirmmap","/confirmunmap"].includes(cmd)) {
        responseText = await mapAction(raw,chat.id,from.id);
      } else if (cmd === "/details") {
        responseText = await channelDetails(raw.split(/\s+/)[1],env);
      } else if (cmd === "/filter" || /^filter:(?:dash|hls|mp4|flv|auto|healthy|slow|failed|unknown|active|inactive):\d{1,4}$/.test(raw)) {
        const isCallback=raw.startsWith("filter:");
        const bits=raw.split(":");
        ({responseText,keyboard}=await filterChannels(isCallback?bits[1]:raw.replace(/^\/filter(?:@\w+)?/i,""),isCallback?bits[2]:0));
      } else if (cmd === "/manage" || /^manage:\d{1,4}$/.test(raw)) {
        ({responseText,keyboard}=managePage(await allChannels(),cmd==="/manage"?0:raw.split(":")[1]));
      } else if (/^(toggle|manageon|manageoff):[0-9a-f-]{36}$/.test(raw)) {
        ({responseText,keyboard}=await handleToggle(raw,chat.id,from.id));
      } else if (cmd === "/channels" || /^all:\d{1,4}$/.test(raw)) {
        const rows=await channelList(env,false);
        ({responseText,keyboard}=makePage(rows,cmd==="/channels"?0:raw.split(":")[1],"all","All Channels"));
      } else if (cmd === "/categories" || /^cats:\d{1,4}$/.test(raw)) {
        const rows=await channelList(env,false);
        ({responseText,keyboard}=makeCategoryPage(rows,cmd==="/categories"?0:raw.split(":")[1]));
      } else if (/^cat:\d{1,4}:\d{1,4}$/.test(raw)) {
        const [_,categoryIndex,page]=raw.split(":");
        const rows=await channelList(env,false);
        const categories=groupCategories(rows),category=categories[Number(categoryIndex)]?.[0];
        if(!category)responseText="Category not found. Use /categories.";
        else ({responseText,keyboard}=makePage(rows.filter(row=>
          (String(row.category||"Other").trim()||"Other")===category),
          page,"cat:"+categoryIndex,category));
      } else if (cmd === "/bein" || /^bein:\d{1,4}$/.test(raw)) {
        const rows=await channelList(env,true);
        ({responseText,keyboard}=makePage(rows,cmd==="/bein"?0:raw.split(":")[1],"bein","beIN Sports"));
      } else if (cmd === "/search" || /^search:[A-Za-z0-9_-]{1,43}:\d{1,4}$/.test(raw)) {
        let query,page=0,token;
        if(cmd==="/search"){
          query=raw.replace(/^\/search(?:@\w+)?/i,"").trim();
          token=searchToken(query);
        }else{
          const parts=raw.split(":");token=parts[1];page=parts[2];query=decodeSearchToken(token);
        }
        if(!query)responseText="🔎 Search channels\nSend /search followed by channel name.\nExample: /search sports";
        else if(!token||!decodeSearchToken(token))responseText="Search too long; use shorter text.";
        else{
          const rows=(await channelList(env,false)).filter(row=>
            String(row.name||"").toLowerCase().includes(query.toLowerCase())||
            String(row.category||"").toLowerCase().includes(query.toLowerCase()));
          ({responseText,keyboard}=makePage(rows,page,"search:"+token,"Search: "+text(query,45)));
        }
      } else if (raw.startsWith("channel:")) {
        const channelId=raw.slice("channel:".length);
        responseText=await channelDetails(channelId,env);
        keyboard={inline_keyboard:[
          [{text:"⚽ Match schedule",callback_data:"/broadcasts"},{text:"📺 All Channels",callback_data:"/channels"}],
          [{text:"🏠 Menu",callback_data:"/start"}],
        ]};
      } else {
        responseText="Unknown command. Send /menu for compact NCA Admin controls.";
      }
    } catch (error) {
      responseText = error instanceof ReleaseDeliveryError
        ? "📦 APK delivery unavailable (" + error.code + "). No unverified file was sent. Try again later."
        : "NCA data is temporarily unavailable. Try again later.";
    }
    if (documentSent) return reply({ ok: true });
    if(callback && chat.id && message?.message_id) {
      try {
        await telegram("editMessageText",token,{
          chat_id:chat.id,message_id:message.message_id,
          text:responseText.slice(0,3900),disable_web_page_preview:true,
          reply_markup:keyboard||{inline_keyboard:[[{text:"🏠 Menu",callback_data:"/start"}]]},
        });
        return reply({ok:true});
      } catch (_) { /* Old or unavailable messages use a normal reply. */ }
    }
    await telegram("sendMessage", token, {
      chat_id: chat.id, text: responseText.slice(0, 3900),
      disable_web_page_preview: true,
      ...(keyboard ? { reply_markup: keyboard } : {}),
    });
    return reply({ ok: true });
  }
  return withTelegramUpdateDedup(handle, {mode, env, fetcher});
}
