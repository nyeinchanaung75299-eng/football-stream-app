// Experimental, read-only discovery for public football pages. Do not bypass
// authentication, DRM, CAPTCHA, or a publisher's access restrictions.
// Only expose literal HTTP(S) HLS/DASH media URLs already present in page HTML.
export const experimentalFootballSites = Object.freeze({
  camel:     { label: "Camel Live",       home: "https://www.camel1.tv/",                      host: "camel1.tv" },
  xoilac:    { label: "Xoilac TV",        home: "https://xoilacls.tv/",                        host: "xoilacls.tv" },
  livetv:    { label: "LiveTV",           home: "https://livetv.li/soccer",                   host: "livetv.li" },
  rojadirecta:{label: "Rojadirecta",     home: "https://en.rojadirectaes.org/live-football", host: "rojadirectaes.org" },
  crichd:    { label: "CricHD",           home: "https://crichd.pk/sports/soccer-streams",                         host: "crichd.pk" },
  roxie:     { label: "RoxieStreams",     home: "https://roxiestreams.su/soccer",             host: "roxiestreams.su" },
  vipbox:    { label: "VIPBox",           home: "https://www.vipboxtv.st/football-stream",    host: "vipboxtv.st" },
  viprow:    { label: "VIPRow",           home: "https://www.viprow.lc/sports-football-online",host: "viprow.lc" },
  score088:  { label: "Score088TV",       home: "https://www.score088tv.live/football",        host: "score088tv.live" },
  sports808: { label: "LiveSports808",    home: "https://www.livesports808.cc/football?lang=2",host: "livesports808.cc" },
  kooralive: { label: "Koora Live",       home: "https://kooralive.watch/",                   host: "kooralive.watch" },
  livextv:   { label: "LiveXTV",          home: "https://livextv.pro/",                       host: "livextv.pro" },
  streamfree:{label: "StreamFree",       home: "https://strmfree.st/",                       host: "strmfree.st" },
  ppv:       { label: "PPV.st",           home: "https://ppv.st/",                            host: "ppv.st" },
});

export const isExperimentalFootballSource = (source) =>
  Object.prototype.hasOwnProperty.call(experimentalFootballSites, String(source ?? ""));

function allowedPageUrl(value, site) {
  try {
    const url = new URL(value, site.home);
    const hostname = url.hostname.toLowerCase();
    if (!["http:", "https:"].includes(url.protocol) ||
        url.username || url.password || url.port ||
        (hostname !== site.host && !hostname.endsWith("." + site.host))) return null;
    url.hash = "";
    return url.toString();
  } catch (_) { return null; }
}

function normalizeText(value) {
  return String(value ?? "")
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Math.min(Number(n), 0x10ffff)))
    .replace(/\s+/g, " ").trim();
}

function fixtureTitle(text) {
  const name = normalizeText(text)
    .replace(/\b(?:live\s*(?:stream|tv)|watch\s*(?:live|now)|football|soccer)\b/gi, " ")
    .replace(/\s+/g, " ").trim();
  const match = name.match(/^(.{2,70}?)\s+(?:vs?\.?|[-–—]|ضد)\s+(.{2,70}?)(?:\s*(?:\||•|\().*)?$/i);
  if (!match) return null;
  const home = match[1].trim(), away = match[2].trim();
  if (!home || !away || home.length > 65 || away.length > 65) return null;
  return {home, away};
}

// Never infer timezone from the server or the user's phone: dates must include
// an explicit ISO-8601 offset or Z. Unknown/ambiguous kickoffs are discarded.
export function explicitKickoff(fragment) {
  const iso = String(fragment).match(/\b20\d{2}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})\b/i);
  if (!iso) return null;
  const value = iso[0].replace(" ", "T").replace(/([+-]\d{2})(\d{2})$/, "$1:$2");
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function sourceId(value) {
  let hash = 2166136261;
  for (const code of String(value)) hash = Math.imul(hash ^ code.charCodeAt(0), 16777619);
  return (hash >>> 0).toString(36);
}

async function publicHtml(url, fetcher, {withClock = false, now = Date.now} = {}) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 8000);
  try {
    const response = await fetcher(url, {
      headers: { Accept: "text/html", "Cache-Control": "no-cache" },
      redirect: "follow",
      signal: ctl.signal,
    });
    if (!response.ok) throw Error("Source page HTTP " + response.status);
    const type = response.headers?.get?.("content-type") ?? "";
    if (type && !/text\/html|application\/xhtml\+xml/i.test(type)) {
      throw Error("Source page is not HTML");
    }
    const length = Number(response.headers?.get?.("content-length") ?? 0);
    if (length > 1500000) throw Error("Source page exceeds size limit");
    const html = await response.text();
    if (html.length > 1500000) throw Error("Source page exceeds size limit");
    if (!withClock) return html;
    const observedAt = now();
    const ageValue = response.headers?.get?.("age");
    const age = ageValue == null ? 0 : Number(ageValue);
    const dateValue = response.headers?.get?.("date");
    const responseDate = dateValue ? Date.parse(dateValue) : NaN;
    // A cached/pre-rendered countdown cannot be assumed to be current.
    const clockFresh = Number.isFinite(observedAt) &&
      Number.isFinite(age) && age >= 0 && age <= 60 &&
      (!Number.isFinite(responseDate) ||
        Math.abs(observedAt - responseDate) <= 120000);
    return {html, observedAt, clockFresh};
  } finally { clearTimeout(timer); }
}

// Read only match links that are explicitly published on this site. Some
// providers put the fixture identity in /event/home-vs-away instead of the
// anchor text, so the original "Team A vs Team B" regex dropped every row.
function teamsFromLink(url, inner) {
  const visible = fixtureTitle(inner);
  if (visible) return visible;
  let path;
  try { path = decodeURIComponent(new URL(url).pathname); }
  catch (_) { return null; }
  const match = path.match(/(?:^|\/)(?:event|events|match|matches|watch|live)?\/?([a-z0-9-]+)-vs-([a-z0-9-]+)(?:\/|$)/i);
  if (!match) return null;
  const title = part => part.replace(/-/g, " ").replace(/\b[a-z]/g, c => c.toUpperCase()).trim();
  const home = title(match[1]), away = title(match[2]);
  if (home.length < 2 || away.length < 2 || home.length > 65 || away.length > 65) return null;
  return {home, away};
}

// Only fields documenting a fixture's kickoff are accepted. In particular,
// another event's timestamp, countdown and the server clock are NOT kickoffs.
function pageKickoff(markup) {
  const patterns = [
    /<time\b[^>]*\bdatetime\s*=\s*["']([^"']+)["'][^>]*>/gi,
    /(?:startDate|start_date|startTime|kickoff_at|kickoffAt)\s*["']?\s*[:=]\s*["']([^"']+)["']/gi,
    /<meta\b[^>]*(?:name|property)\s*=\s*["'](?:event:start_time|startDate|event:start_date)["'][^>]*content\s*=\s*["']([^"']+)["']/gi,
  ];
  for (const pattern of patterns) {
    for (const match of markup.matchAll(pattern)) {
      const kickoff = explicitKickoff(match[1]);
      if (kickoff) return kickoff;
    }
  }
  return null;
}

// Estimated kickoff = timestamp of this actual HTTP read + countdown duration.
// It must be bound to one match card; search-engine crawls and stale caches
// must never be used to calculate a scheduled kickoff.
export function countdownKickoff(fragment, observedAt, clockFresh = true) {
  if (!clockFresh || !Number.isFinite(observedAt)) return null;
  const text = normalizeText(fragment);
  const match = text.match(/\b(?:starts?\s+in|kick[\s-]?off\s+in)\s*[:：]?\s*(\d{1,3}):([0-5]\d):([0-5]\d)\b/i);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  const seconds = Number(match[3]);
  const total = hours * 3600 + minutes * 60 + seconds;
  if (total < 1 || total > 7 * 24 * 3600) return null;
  return new Date(observedAt + total * 1000).toISOString();
}

function eventRecord(source, site, page, teams, kickoff, timingSource = "none") {
  const id = sourceId(page);
  const hasTime = kickoff != null;
  return {
    source, source_id: id, schedule_id: id,
    league: "Football", home_team: teams.home, away_team: teams.away,
    home_logo: null, away_logo: null, poster_url: null,
    match_time: kickoff, status: hasTime ? "NS" : "UNVERIFIED",
    match_status: hasTime ? "SCHEDULED" : "UNVERIFIED",
    hot: false, page_url: page,
    // These rows are for admin inspection, not proven video playback.
    verified_kickoff: hasTime && timingSource === "explicit",
    kickoff_estimated: hasTime && timingSource === "countdown",
    kickoff_source: timingSource,
    anchors: [{room_num: id, page_url: page, nick_name: site.label}],
  };
}


// Browser-generated pages frequently preload public match information as JSON
// before hydrating their UI. Parse DATA only: never execute the page's JS,
// request private APIs, or guess a provider endpoint.
function publicEmbeddedJson(html) {
  const values = [];
  const scripts = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  for (const match of html.matchAll(scripts)) {
    if (values.length >= 20) break;
    const attributes = match[1] ?? "";
    const id = attributes.match(/\bid\s*=\s*["']([^"']+)["']/i)?.[1] ?? "";
    const type = attributes.match(/\btype\s*=\s*["']([^"']+)["']/i)?.[1] ?? "";
    if (!/^(application\/(?:ld\+json|json)|text\/json)$/i.test(type) &&
        !/^(?:__NEXT_DATA__|__NUXT_DATA__|__INITIAL_STATE__|__APOLLO_STATE__)$/i.test(id)) continue;
    const body = match[2].trim();
    if (!body || body.length > 900000) continue;
    try { values.push(JSON.parse(body)); } catch (_) { /* JS expressions are not JSON. */ }
  }
  // A limited set of applications include their state as a JSON literal
  // assignment, not a script with type=application/json. No eval and no JS.
  const state = /(?:window\.)?(?:__INITIAL_STATE__|__PRELOADED_STATE__)\s*=\s*(\{[^\n;]{1,100000}\})\s*;/gi;
  for (const hit of html.matchAll(state)) {
    if (values.length >= 20) break;
    try { values.push(JSON.parse(hit[1])); } catch (_) { /* Not a JSON literal. */ }
  }
  return values;
}

function nameOfTeam(value) {
  if (typeof value === "string") return normalizeText(value);
  if (value && typeof value === "object")
    return normalizeText(value.name ?? value.displayName ?? value.shortName ?? "");
  return "";
}

function embeddedTeamPair(item) {
  const home = nameOfTeam(item.homeTeam ?? item.home_team ?? item.home);
  const away = nameOfTeam(item.awayTeam ?? item.away_team ?? item.away);
  if (home.length > 1 && away.length > 1 &&
      home.length <= 65 && away.length <= 65 && home !== away) return {home, away};
  if (Array.isArray(item.competitor) || Array.isArray(item.competitors)) {
    const sides = item.competitor ?? item.competitors;
    const h = sides.find(s => /home/i.test(String(s?.homeOrAway ?? s?.qualifier ?? s?.side ?? "")));
    const a = sides.find(s => /away/i.test(String(s?.homeOrAway ?? s?.qualifier ?? s?.side ?? "")));
    if (h && a) {
      const first = nameOfTeam(h), second = nameOfTeam(a);
      if (first.length > 1 && second.length > 1 &&
          first.length <= 65 && second.length <= 65 && first !== second)
        return {home:first, away:second};
    }
  }
  return null;
}

function kickoffFromJson(item, observedAt, clockFresh) {
  const raw = item.startDate ?? item.start_time ?? item.startTime ??
    item.kickoff_at ?? item.kickoffAt ?? item.match_time ?? null;
  if (typeof raw === "string") {
    const value = explicitKickoff(raw);
    if (value) return {kickoff:value, timingSource:"explicit"};
  }
  const ts = item.startTimestamp ?? item.start_timestamp;
  if ((typeof ts === "number" || typeof ts === "string") && String(ts).trim()) {
    const n = Number(ts);
    if (Number.isFinite(n)) {
      const ms = n > 1e12 ? n : n * 1000;
      // Timestamp must represent a plausible modern fixture.
      if (ms >= 1577836800000 && ms <= 4102444800000)
        return {kickoff:new Date(ms).toISOString(), timingSource:"explicit"};
    }
  }
  const rawCountdown = item.countdown ?? item.countdownText ??
    item.startsIn ?? item.timeRemaining;
  if (typeof rawCountdown === "string") {
    const value = countdownKickoff(
      /\b(?:starts?\s+in|kick[\s-]?off\s+in)\b/i.test(rawCountdown)
        ? rawCountdown : "Starts in " + rawCountdown,
      observedAt, clockFresh,
    );
    if (value) return {kickoff:value, timingSource:"countdown"};
  }
  return {kickoff:null, timingSource:"none"};
}

function publicFixtureJsonRows(html, site, source, clock) {
  const output = new Map();
  // Generic all-sports indexes need an explicit football/soccer marker
  // associated with the event. Football-only catalogs can be accepted.
  const footballCatalog = /(?:football|soccer)/i.test(new URL(site.home).pathname) ||
    ["camel","xoilac","kooralive"].includes(source);
  const state = publicEmbeddedJson(html);
  let examined = 0;
  for (const root of state) {
    const queue = [{node:root, football:footballCatalog, depth:0}];
    for (let head = 0; head < queue.length && examined < 4000; head++) {
      const {node, football, depth} = queue[head];
      examined++;
      if (!node || typeof node !== "object" || depth > 10) continue;
      if (Array.isArray(node)) {
        for (const child of node.slice(0, 150)) queue.push({node:child,football,depth:depth+1});
        continue;
      }
      const sport = String(node.sport?.name ?? node.sport?.slug ?? node.sport ??
        node.category?.name ?? node.category?.slug ?? "");
      const categoryIsFootball = /(?:soccer|football)/i.test(sport);
      const categoryOtherSport = /(?:basketball|cricket|tennis|rugby|hockey|baseball|golf|snooker)/i.test(sport);
      const eventIsFootball = categoryOtherSport ? false : football || categoryIsFootball ||
        /\b(?:soccer|football)\b/i.test(String(node.sportType ?? ""));
      const teams = embeddedTeamPair(node);
      const link = node.url ?? node.href ?? node.page_url ?? node.matchUrl ?? node.link;
      const page = typeof link === "string" ? allowedPageUrl(link,site) : null;
      if (teams && page && eventIsFootball && !output.has(page) && output.size < 80) {
        const when = kickoffFromJson(node,clock.observedAt,clock.clockFresh);
        const row = eventRecord(source,site,page,teams,when.kickoff,when.timingSource);
        const league = nameOfTeam(node.tournament ?? node.league ??
          node.competition ?? node.leagueName);
        if (league && league.length < 100) row.league = league;
        output.set(page,row);
      }
      if (depth < 10) for (const [key,value] of Object.entries(node).slice(0,90)) {
        if (value && typeof value === "object" && !["__proto__","constructor"].includes(key))
          queue.push({node:value,football:categoryOtherSport?false:eventIsFootball,depth:depth+1});
      }
    }
  }
  return {rows:output, jsonDocumentCount:state.length};
}

export async function experimentalMatches(source, {fetcher = fetch, now = Date.now} = {}) {
  const site = experimentalFootballSites[source];
  if (!site) throw Error("Unsupported source");
  const catalog = await publicHtml(site.home, fetcher, {withClock: true, now});
  const {html} = catalog;
  const embedded = publicFixtureJsonRows(html,site,source,catalog);
  const candidates = new Map();
  const anchors = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  for (const hit of html.matchAll(anchors)) {
    if (candidates.size >= 80) break;
    const href = hit[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1];
    const page = href && allowedPageUrl(href.replace(/&amp;/gi, "&"), site);
    if (!page || page === site.home || candidates.has(page)) continue;
    // Multi-sport home pages cannot be trusted as football catalogs.
    // Skip them unless the published link itself identifies football.
    if (["ppv", "livextv", "streamfree"].includes(source) &&
        !/\b(?:soccer|football)\b/i.test(page)) continue;
    const teams = teamsFromLink(page, hit[2]);
    if (!teams) continue;
    // The timestamp must be inside this anchor or immediately preceding it,
    // with a preceding sibling anchor acting as a hard event boundary.
    const preceding = html.slice(Math.max(0, hit.index - 240), hit.index);
    const boundary = preceding.lastIndexOf("</a>");
    const local = boundary < 0 ? preceding : preceding.slice(boundary + 4);
    const explicit = pageKickoff(hit[0]) ?? pageKickoff(local);
    const countdown = explicit ? null :
      countdownKickoff(hit[0], catalog.observedAt, catalog.clockFresh) ??
      countdownKickoff(local, catalog.observedAt, catalog.clockFresh);
    const kickoff = explicit ?? countdown;
    const timingSource = explicit ? "explicit" : countdown ? "countdown" : "none";
    candidates.set(page, {page, teams, kickoff, timingSource});
  }

  // Detail pages may publish authoritative UTC/offset timestamps that the
  // index omits. Bound network work: only 6 pages, at most 3 concurrent.
  const needDetail = [...candidates.values()]
    .filter(candidate => !candidate.kickoff).slice(0, 6);
  for (let offset = 0; offset < needDetail.length; offset += 3) {
    await Promise.all(needDetail.slice(offset, offset + 3).map(async item => {
      try {
        const detail = await publicHtml(item.page, fetcher, {withClock: true, now});
        const exact = pageKickoff(detail.html);
        const estimated = exact ? null :
          countdownKickoff(detail.html, detail.observedAt, detail.clockFresh);
        item.kickoff = exact ?? estimated;
        item.timingSource = exact ? "explicit" : estimated ? "countdown" : "none";
      } catch (_) { /* Keep as unverified, never manufacture a kickoff. */ }
    }));
  }

  // Prefer the embedded state when the same page is represented in both.
  for (const row of candidates.values()) {
    if (!embedded.rows.has(row.page)) embedded.rows.set(row.page,
      eventRecord(source,site,row.page,row.teams,row.kickoff,row.timingSource));
    else if (!embedded.rows.get(row.page).match_time && row.kickoff)
      embedded.rows.set(row.page,eventRecord(source,site,row.page,row.teams,row.kickoff,row.timingSource));
  }
  const matches = [...embedded.rows.values()].sort((a,b) =>
    (a.match_time ?? "9999").localeCompare(b.match_time ?? "9999"));
  const confirmed = matches.filter(row => row.verified_kickoff).length;
  const estimated = matches.filter(row => row.kickoff_estimated).length;
  return {
    ok: true, source, matches, results: matches.length,
    diagnostics: {candidate_count: matches.length,
      extraction_mode: embedded.rows.size > candidates.size ? "embedded-json" : "html-or-mixed",
      embedded_json_documents: embedded.jsonDocumentCount,
      content_state: matches.length ? "matches_found" : embedded.jsonDocumentCount ? "no_recognized_football_fixtures" :
        /<script\b/i.test(html) ? "browser_render_or_unsupported_markup" : "empty_page",
      confirmed_kickoff_count: confirmed,
      estimated_countdown_count: estimated,
      missing_kickoff_count: matches.length - confirmed - estimated,
      note: "Countdown kickoffs are estimates from a fresh page response, not verified fixture times."},
    generated_at: new Date().toISOString(),
  };
}

function literalMediaUrls(html, pageUrl) {
  const urls = new Set();
  const cleaned = html.replace(/\\\//g, "/").replace(/&amp;/gi, "&");
  const quoted = /(?:https?:\/\/|\/\/)[^\s"'<>\\]+?\.(?:m3u8|mpd)(?:\?[^\s"'<>\\]*)?/gi;
  const relative = /(?:src|href)\s*=\s*["']([^"']+\.(?:m3u8|mpd)(?:\?[^"']*)?)["']/gi;
  function add(raw) {
    try {
      const url = new URL(raw, pageUrl);
      if (!["https:", "http:"].includes(url.protocol) || url.username ||
          url.password || !url.hostname || /\.(?:local|internal)$/i.test(url.hostname) ||
          /^(?:localhost|127\.|0\.|10\.|192\.168\.|169\.254\.|172\.(?:1[6-9]|2\d|3[01])\.|::1)$/i.test(url.hostname)) return;
      if (!/\.(?:m3u8|mpd)(?:\?|$)/i.test(url.pathname + url.search)) return;
      urls.add(url.toString());
    } catch (_) {}
  }
  for (const hit of cleaned.matchAll(quoted)) add(hit[0]);
  for (const hit of cleaned.matchAll(relative)) add(hit[1]);
  return [...urls].slice(0, 12);
}

export async function experimentalStreams(source, body, {fetcher = fetch} = {}) {
  const site = experimentalFootballSites[source];
  if (!site) throw Error("Unsupported source");
  const page = allowedPageUrl(body?.page_url, site);
  if (!page) return {ok: true, source, lines: [], line_count: 0,
    ready: false, message: "No verified public match page."};
  const html = await publicHtml(page, fetcher);
  const media = literalMediaUrls(html, page);
  const lines = media.map((url, i) => ({
    label: site.label + " • " + (url.toLowerCase().includes(".mpd") ? "DASH / MPD" : "HLS / M3U8") + " " + (i + 1),
    stream_type: url.toLowerCase().includes(".mpd") ? "dash" : "hls",
    resolution: "Auto", url, referer: page, origin: new URL(page).origin,
    health_status: "unknown",
  }));
  if (body?.status_only === true || body?.status_only === "true") {
    return {ok: true, source, ready: lines.length > 0, line_count: lines.length,
      live_status: false};
  }
  return {ok: true, source, ready: lines.length > 0,
    lines, line_count: lines.length, live_status: false,
    message: lines.length ? "Check permission and playback before importing." :
      "No public HLS/DASH URL in static page. Login, scripts or player restrictions are not bypassed.",
    generated_at: new Date().toISOString()};
}
