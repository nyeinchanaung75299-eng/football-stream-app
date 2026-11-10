// Experimental, read-only discovery for public football pages. Do not bypass
// authentication, DRM, CAPTCHA, or a publisher's access restrictions.
// Only expose literal HTTP(S) HLS/DASH media URLs already present in page HTML.
export const experimentalFootballSites = Object.freeze({
  camel:     { label: "Camel Live",       home: "https://www.camel1.tv/",                      host: "camel1.tv" },
  xoilac:    { label: "Xoilac TV",        home: "https://xoilacls.tv/",                        host: "xoilacls.tv" },
  livetv:    { label: "LiveTV",           home: "https://livetv.li/soccer",                   host: "livetv.li" },
  rojadirecta:{label: "Rojadirecta",     home: "https://en.rojadirectaes.org/live-football", host: "rojadirectaes.org" },
  crichd:    { label: "CricHD",           home: "https://crichd.pk/",                         host: "crichd.pk" },
  roxie:     { label: "RoxieStreams",     home: "https://roxiestreams.su/soccer",             host: "roxiestreams.su" },
  vipbox:    { label: "VIPBox",           home: "https://www.vipboxtv.st/football-stream",    host: "vipboxtv.st" },
  viprow:    { label: "VIPRow",           home: "https://www.viprow.lc/sports-football-online",host: "viprow.lc" },
  score088:  { label: "Score088TV",       home: "https://www.score088tv.live/football",        host: "score088tv.live" },
  sports808: { label: "LiveSports808",    home: "https://www.livesports808.cc/football?lang=2",host: "livesports808.cc" },
  phut90:    { label: "90phut TV",        home: "https://90phuttv-sports.com/",                host: "90phuttv-sports.com" },
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

async function publicHtml(url, fetcher) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 8000);
  try {
    const response = await fetcher(url, {
      headers: { Accept: "text/html" },
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
    return html;
  } finally { clearTimeout(timer); }
}

export async function experimentalMatches(source, {fetcher = fetch} = {}) {
  const site = experimentalFootballSites[source];
  if (!site) throw Error("Unsupported source");
  const html = await publicHtml(site.home, fetcher);
  const matches = [], seen = new Set();
  // Static server-rendered anchors only; JavaScript-only pages return no rows.
  const anchors = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  for (const hit of html.matchAll(anchors)) {
    if (matches.length >= 100) break;
    const href = hit[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1];
    const page = href && allowedPageUrl(href.replace(/&amp;/gi, "&"), site);
    if (!page || page === site.home || seen.has(page)) continue;
    const teams = fixtureTitle(hit[2]);
    if (!teams) continue;
    // Only accept a timestamp explicitly tied to the link or its adjacent
    // immediate markup. Never generate fake kickoff times.
    const nearby = html.slice(Math.max(0, hit.index - 280), hit.index + hit[0].length + 120);
    const kickoff = explicitKickoff(hit[0]) ?? explicitKickoff(nearby);
    if (!kickoff) continue;
    const id = sourceId(page);
    seen.add(page);
    matches.push({
      source, source_id: id, schedule_id: id,
      league: "Football", home_team: teams.home, away_team: teams.away,
      home_logo: null, away_logo: null, poster_url: null,
      match_time: kickoff, status: "NS", match_status: "SCHEDULED", hot: false,
      page_url: page,
      anchors: [{room_num: id, page_url: page, nick_name: site.label}],
    });
  }
  matches.sort((a,b) => a.match_time.localeCompare(b.match_time));
  return {ok: true, source, matches, results: matches.length, generated_at: new Date().toISOString()};
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
