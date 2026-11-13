// Experimental, read-only discovery for public football pages. Do not bypass
// authentication, DRM, CAPTCHA, or a publisher's access restrictions.
// Only expose HTTP(S) HLS/DASH URLs explicitly published by public players.
import {publicSourceUrl, readPublicSource, discoverPublicMedia} from './public_source_media.mjs';
import {hasPublicFootballFeed, publicFootballFeedMatches, publicFootballFeedPlayer, configuredPublicMedia} from './public_football_feeds.mjs';
export const experimentalFootballSites = Object.freeze({
  camel:     { label: "Camel Live",       home: "https://www.camel1.tv/",                      host: "camel1.tv" },
  xoilac:    { label: "Xoilac TV",        home: "https://xoilacls.tv/",                        host: "xoilacls.tv" },
  livetv:    { label: "LiveTV",           home: "https://livetv.li/soccer",                   host: "livetv.li", aliases:["livetvsx.org"] },
  rojadirecta:{label: "Rojadirecta",     home: "https://www.rojadirectavivo.me/live-football", host: "rojadirectavivo.me" },
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
        ![site.host,...(site.aliases||[])].some(host=>hostname===host||hostname.endsWith('.'+host))) return null;
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
    .replace(/^\s*\d{1,2}:\d{2}\s+/, '')
    .replace(/\b\d{1,2}:\d{2}\s*(?:watch|live)\b/gi, " ")
    .replace(/\b(?:live\s*(?:stream|tv)|watch\s*(?:live|now)|football|soccer)\b/gi, " ")
    .replace(/\s+/g, " ").trim();
  // Some source cards are "SAFF Championship vs India – Maldives Watch".
  // That first "vs" separates league from teams, not the two teams.
  const competition = name.match(/^.{2,65}?\b(?:cup|league|championship|tournament)\s+vs?\.?\s+(.+)$/i);
  if (competition) {
    const parts = competition[1].split(/\s+[–—]\s+/).map(s => s.trim()).filter(Boolean);
    if (parts.length < 2) return null;
    const home = parts[parts.length - 2], away = parts[parts.length - 1];
    return home.length > 1 && away.length > 1 && home.length <= 65 && away.length <= 65
      ? {home, away} : null;
  }
  const match = name.match(/^(.{2,70}?)\s+(?:vs?\.?|[-–—]|ضد)\s+(.{2,70}?)(?:\s*(?:\||•|\().*)?$/i);
  if (!match) return null;
  const home = match[1].trim(), away = match[2].trim()
    .replace(/\s+luc\s+\d{3,4}\s+ngay\s+\d{1,2}\s+\d{1,2}\s+\d{4}.*$/i, '').trim();
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

async function publicHtml(url, fetcher, {withClock = false, now = Date.now, allowedHost = null, timeoutMs = 8000} = {}) {
  const read = await readPublicSource(url, {fetcher, timeoutMs,
    allowedHosts: allowedHost ? [allowedHost] : null});
  if (!withClock) return read.text;
  const observedAt = typeof now === "function" ? now() : now;
  const ageValue = read.headers?.get?.("age");
  const age = ageValue == null ? 0 : Number(ageValue);
  const dateValue = read.headers?.get?.("date");
  const responseDate = dateValue ? Date.parse(dateValue) : NaN;
  const clockFresh = Number.isFinite(observedAt) &&
    Number.isFinite(age) && age >= 0 && age <= 60 &&
    (!Number.isFinite(responseDate) || Math.abs(observedAt-responseDate) <= 120000);
  return {html:read.text,observedAt,clockFresh};
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
  const title = part => part.replace(/-luc-\d{3,4}-ngay-\d{1,2}-\d{1,2}-\d{4}.*$/i,'')
    .replace(/-/g, " ").replace(/\b[a-z]/g, c => c.toUpperCase()).trim();
  const home = title(match[1]), away = title(match[2]);
  if (home.length < 2 || away.length < 2 || home.length > 65 || away.length > 65) return null;
  return {home, away};
}


// Countdowns can be outside the <a> but inside the same single-match
// <article>/<li> card. Reject shared wrappers with multiple match links.

function structuredCardTeams(markup) {
  if (!markup) return null;
  const attrs = {
    home: markup.match(/\bdata-(?:home|home-team|host|host-team)\s*=\s*["']([^"']+)["']/i)?.[1],
    away: markup.match(/\bdata-(?:away|away-team|guest|guest-team)\s*=\s*["']([^"']+)["']/i)?.[1],
  };
  function classSide(side) {
    const indicator = side === "home"
      ? /\b(?:home|host)(?:[-_]?team)?\b/i
      : /\b(?:away|guest)(?:[-_]?team)?\b/i;
    for (const node of markup.matchAll(/<(?:span|div|strong)\b([^>]*)>([\s\S]*?)<\/(?:span|div|strong)>/gi)) {
      const className = node[1].match(/\bclass\s*=\s*["']([^"']+)["']/i)?.[1] ?? "";
      if (indicator.test(className)) return node[2];
    }
    return null;
  }
  const home = normalizeText(attrs.home ?? classSide("home"));
  const away = normalizeText(attrs.away ?? classSide("away"));
  return home.length > 1 && away.length > 1 &&
    home.length <= 65 && away.length <= 65 && home !== away ? {home,away} : null;
}

// A multi-sport listing can label an individual event as soccer without
// putting "football" in its URL. Read evidence ONLY within one match card
// (or its anchor), never from global page headings or unrelated cards.
function explicitFixtureSport(markup) {
  if (!markup) return "unknown";
  const labels = [];
  for (const hit of markup.matchAll(/\bdata-(?:sport(?:-type)?|category(?:-name)?|discipline)\s*=\s*["']([^"']{1,60})["']/gi)) {
    labels.push(hit[1].trim());
  }
  for (const hit of markup.matchAll(/<(span|small|label|div)\b([^>]*)>([^<]{1,50})<\/\1>/gi)) {
    const className = hit[2].match(/\bclass\s*=\s*["']([^"']{1,120})["']/i)?.[1] ?? "";
    if (/(?:^|[\s_-])(?:sport|category|discipline)(?:$|[\s_-])/i.test(className)) {
      labels.push(normalizeText(hit[3]));
    }
  }
  // Explicit non-football evidence wins over both URL hints and other labels.
  const otherSport = /\b(?:basketball|cricket|tennis|rugby|hockey|baseball|golf|snooker|boxing|mma|ufc|volleyball|badminton|esports|motorsport|american football)\b/i;
  if (labels.some(label => otherSport.test(label))) return "other";
  return labels.some(label => /^(?:football|soccer)$/i.test(label)) ? "football" : "unknown";
}

function matchCardMarkup(html, hit) {
  // List and article wrappers are common, but SPA sites also publish
  // individual <div class="fixture-card"> / <section class="event-item">
  // cards. Only accept a bounded single-anchor wrapper, never a page-wide
  // parent that could leak another event's sport or kickoff into this match.
  for (const tag of ["article", "li", "section", "div"]) {
    let searchBefore = hit.index;
    for (let attempt = 0; attempt < 6 && searchBefore >= 0; attempt++) {
      const start = html.lastIndexOf("<" + tag, searchBefore);
      if (start < 0 || hit.index - start > 3500) break;
      const openingEnd = html.indexOf(">", start);
      if (openingEnd < 0 || openingEnd > hit.index) break;
      const opening = html.slice(start, openingEnd + 1);
      const className = opening.match(/\bclass\s*=\s*["']([^"']+)["']/i)?.[1] ?? "";
      const eventClass = /(?:^|[\s_-])(?:fixture|match|event|game)[-_](?:card|item|row)(?:$|[\s_-])/i.test(className);
      if ((tag === "div" || tag === "section") && !eventClass) {
        searchBefore = start - 1;
        continue;
      }
      const close = "</" + tag + ">";
      const finish = html.indexOf(close, hit.index + hit[0].length);
      if (finish < 0 || finish - start > 3500) {
        searchBefore = start - 1;
        continue;
      }
      const card = html.slice(start, finish + close.length);
      if (card.includes(hit[0]) && [...card.matchAll(/<a\b/gi)].length === 1) return card;
      searchBefore = start - 1;
    }
  }
  return "";
}

// Only fields documenting a fixture's kickoff are accepted. In particular,
// another event's timestamp, countdown and the server clock are NOT kickoffs.
function pageKickoff(markup) {
  const patterns = [
    /<time\b[^>]*\bdatetime\s*=\s*["']([^"']+)["'][^>]*>/gi,
    /\bdata-(?:kickoff|start(?:-time|-date)?|timestamp)\s*=\s*["']([^"']+)["']/gi,
    /(?:startDate|start_date|startTime|kickoff_at|kickoffAt)\s*["']?\s*[:=]\s*["']([^"']+)["']/gi,
    /<meta\b[^>]*(?:name|property)\s*=\s*["'](?:event:start_time|startDate|event:start_date)["'][^>]*content\s*=\s*["']([^"']+)["']/gi,
  ];
  for (const pattern of patterns) {
    for (const match of markup.matchAll(pattern)) {
      const kickoff = explicitKickoff(match[1]);
      if (kickoff) return kickoff;
    }
  }
  // Unix seconds/milliseconds accepted ONLY when explicitly marked as a
  // match kickoff/start attribute, not an arbitrary page timestamp.
  for (const hit of markup.matchAll(/\bdata-(?:kickoff|start-time|start-timestamp)\s*=\s*["'](\d{10}|\d{13})["']/gi)) {
    const n = Number(hit[1]);
    const ms = n > 1e12 ? n : n * 1000;
    if (ms >= 1577836800000 && ms <= 4102444800000)
      return new Date(ms).toISOString();
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


// Team badges are optional metadata. Never manufacture an image URL from a
// team name or silently use league badges / streamer avatars as team crests.
function safePublishedTeamBadge(value, site) {
  if (value && typeof value === "object") {
    value = value.url ?? value.contentUrl ?? value.src ?? null;
  }
  if (typeof value !== "string" || value.length > 2048) return null;
  const raw = value.trim().replace(/&amp;/gi, "&");
  if (!raw || /[\s<>"'\\]/.test(raw) || raw.startsWith("data:")) return null;
  try {
    const url = new URL(raw, site.home);
    if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
    const host = url.hostname.toLowerCase();
    if (/^(?:localhost|127\.|0\.|10\.|192\.168\.|169\.254\.|172\.(?:1[6-9]|2\d|3[01])\.|::1)$/.test(host) ||
        /\.(?:local|internal)$/.test(host)) return null;
    return url.toString();
  } catch (_) { return null; }
}

function fixtureTeamBadge(item, side, site) {
  const home = side === "home";
  const objects = home
    ? [item.homeTeam, item.home_team, item.home, item.teams?.home, item.team1]
    : [item.awayTeam, item.away_team, item.away, item.teams?.away, item.team2];
  const direct = home
    ? [item.home_logo, item.homeLogo, item.homeLogoUrl, item.homeTeamLogo,
       item.homeCrest, item.hostLogo, item.team1Logo]
    : [item.away_logo, item.awayLogo, item.awayLogoUrl, item.awayTeamLogo,
       item.awayCrest, item.guestLogo, item.team2Logo];
  for (const value of direct) {
    const badge = safePublishedTeamBadge(value, site);
    if (badge) return badge;
  }
  for (const obj of objects) {
    if (!obj || typeof obj !== "object") continue;
    for (const key of ["logo", "logoUrl", "logo_url", "crest", "crestUrl",
                       "crest_url", "badge", "badgeUrl", "image", "imageUrl"]) {
      const badge = safePublishedTeamBadge(obj[key], site);
      if (badge) return badge;
    }
  }
  return null;
}

function htmlTeamBadges(markup, teams, site) {
  const result = {home: null, away: null};
  if (!markup) return result;
  for (const img of markup.matchAll(/<img\b([^>]+)>/gi)) {
    const attrs = img[1];
    const alt = attrs.match(/\balt\s*=\s*["']([^"']+)["']/i)?.[1] ?? "";
    const label = normalizeText(alt).replace(/\s+(?:logo|crest|badge)$/i, "").trim().toLowerCase();
    if (!label) continue;
    const side = label === teams.home.toLowerCase() ? "home"
      : label === teams.away.toLowerCase() ? "away" : null;
    if (!side || result[side]) continue;
    const src = attrs.match(/\b(?:src|data-src|data-original)\s*=\s*["']([^"']+)["']/i)?.[1];
    result[side] = safePublishedTeamBadge(src, site);
  }
  return result;
}

function eventRecord(source, site, page, teams, kickoff, timingSource = "none", badges = {}) {
  const id = sourceId(page ?? [source, teams.home, teams.away, kickoff].join(":"));
  const hasTime = kickoff != null;
  return {
    source, source_id: id, schedule_id: id,
    league: "Football", home_team: teams.home, away_team: teams.away,
    home_logo: badges.home ?? null, away_logo: badges.away ?? null, poster_url: null,
    match_time: kickoff, status: hasTime ? "NS" : "UNVERIFIED",
    match_status: hasTime ? "SCHEDULED" : "UNVERIFIED",
    hot: false, page_url: page,
    // These rows are for admin inspection, not proven video playback.
    verified_kickoff: hasTime && timingSource === "explicit",
    kickoff_estimated: hasTime && timingSource === "countdown",
    kickoff_source: timingSource,
    schedule_only: page == null,
    // Never present metadata-only fixtures as a stream line.
    anchors: page ? [{room_num: id, page_url: page, nick_name: site.label}] : [],
  };
}


// Browser-generated pages frequently preload public match information as JSON
// before hydrating their UI. Parse DATA only: never execute the page's JS,
// request private APIs, or guess a provider endpoint.
function publicEmbeddedJson(html, source) {
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
  // Score088/LiveSports808 publish typed initialMatches plus the actual link
  // for each slug. Join those fields; never synthesize a route from a slug.
  const links = [...html.matchAll(/<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']/gi)].map(m=>m[1]);
  for (const root of ['score088','sports808'].includes(source) ? [...values] : []) {
    const rows = root?.props?.pageProps?.initialMatches;
    if (!Array.isArray(rows)) continue;
    values.push(rows.slice(0,150).flatMap(row => {
      if (!row || typeof row !== 'object' || typeof row.slug !== 'string') return [];
      const href = links.find(link=>link.split('?')[0].replace(/\/$/,'').endsWith('/'+row.slug));
      return href ? [{...row,url:href,sport:'Soccer'}] : [];
    }));
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
  const home = nameOfTeam(item.homeTeam ?? item.home_team ?? item.home ??
    item.homeName ?? item.home_name ?? item.homeTeamName ?? item.teams?.home ??
    item.hostTeam ?? item.host_team);
  const away = nameOfTeam(item.awayTeam ?? item.away_team ?? item.away ??
    item.awayName ?? item.away_name ?? item.awayTeamName ?? item.teams?.away ??
    item.guestTeam ?? item.guest_team);
  if (home.length > 1 && away.length > 1 &&
      home.length <= 65 && away.length <= 65 && home !== away) return {home, away};
  const participants = item.competitor ?? item.competitors ?? item.participant ?? item.participants ??
    (Array.isArray(item.teams) ? item.teams : null);
  if (Array.isArray(participants)) {
    const sides = participants;
    const h = sides.find(s => /home/i.test(String(s?.homeOrAway ?? s?.qualifier ?? s?.side ?? "")));
    const a = sides.find(s => /away/i.test(String(s?.homeOrAway ?? s?.qualifier ?? s?.side ?? "")));
    if (h && a) {
      const first = nameOfTeam(h), second = nameOfTeam(a);
      if (first.length > 1 && second.length > 1 &&
          first.length <= 65 && second.length <= 65 && first !== second)
        return {home:first, away:second};
    }
  }
  // Public structured SportsEvent feeds sometimes publish only a title
  // ("Home vs Away") rather than separately named home/away fields.
  // Keep the existing football-category and same-site URL requirements.
  const eventType = String(item["@type"] ?? item.type ?? "");
  const sport = String(item.sport?.name ?? item.sport ?? item.category?.name ?? "");
  if (/sports?event/i.test(eventType) || /(?:football|soccer)/i.test(sport)) {
    const title = item.name ?? item.eventName ?? item.matchName ?? item.title;
    if (typeof title === "string") return fixtureTitle(title);
  }
  return null;
}

function kickoffFromJson(item, observedAt, clockFresh) {
  const raw = item.startDate ?? item.start_date ?? item.start_time ?? item.startTime ??
    item.kickoff_at ?? item.kickoffAt ?? item.kickoff ??
    item.match_time ?? item.matchTime ?? item.scheduledAt ?? item.startsAt ?? null;
  if (typeof raw === "string") {
    const value = explicitKickoff(raw);
    if (value) return {kickoff:value, timingSource:"explicit"};
  }
  const ts = item.startTimestamp ?? item.start_timestamp ??
    item.startTimeUnix ?? item.kickoffTimestamp ?? item.kickoff_unix;
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
  } else if (typeof rawCountdown === "number" && Number.isInteger(rawCountdown)
      && rawCountdown > 0 && rawCountdown <= 7*24*3600 &&
      clockFresh && Number.isFinite(observedAt)) {
    return {kickoff:new Date(observedAt + rawCountdown*1000).toISOString(),
      timingSource:"countdown"};
  }
  return {kickoff:null, timingSource:"none"};
}

function publicFixtureJsonRows(html, site, source, clock) {
  const output = new Map();
  // Generic all-sports indexes need an explicit football/soccer marker
  // associated with the event. Football-only catalogs can be accepted.
  // LiveTV /soccer is a mixed-sports HTML page in practice: its URL alone
  // is NOT proof that every embedded event is football.
  const footballCatalog = (source !== "livetv" &&
    /(?:football|soccer)/i.test(new URL(site.home).pathname)) ||
    ["camel","xoilac","kooralive"].includes(source);
  const state = publicEmbeddedJson(html, source);
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
      const categoryOtherSport = /(?:american\s+football|basketball|cricket|tennis|rugby|hockey|baseball|golf|snooker|volleyball|badminton|esports|e-sports|mma|boxing)/i.test(sport);
      const linkValue = node.url ?? node.href ?? node.page_url ?? node.matchUrl ??
        node.match_url ?? node.eventUrl ?? node.event_url ?? node.fixtureUrl ??
        node.fixture_url ?? node.permalink ?? node.link;
      const linkedPage = typeof linkValue === "string" ? allowedPageUrl(linkValue, site) : null;
      // Football-specific links are meaningful evidence on multi-sport homes,
      // but an explicitly different sport always wins.
      const linkedFootball = linkedPage &&
        /\/(?:football|soccer)(?:\/|[-?]|$)/i.test(new URL(linkedPage).pathname);
      const eventIsFootball = !categoryOtherSport && (football || categoryIsFootball ||
        linkedFootball || /\b(?:soccer|football)\b/i.test(String(node.sportType ?? "")));
      const teams = embeddedTeamPair(node);
      const link = linkValue;
      const page = linkedPage;
      // A verified SportsEvent with an explicit UTC/offset kickoff but no
      // event URL can be listed as a schedule only. Never follow foreign URLs.
      const rawLink = typeof link === "string" ? link.trim() : "";
      const schemaType = String(node["@type"] ?? node.type ?? "");
      const recognizedSchema = /(?:^|:)SportsEvent$/i.test(schemaType);
      if (teams && eventIsFootball && output.size < 80) {
        const when = kickoffFromJson(node,clock.observedAt,clock.clockFresh);
        const scheduleOnly = !rawLink && recognizedSchema &&
          when.timingSource === "explicit";
        if (page || scheduleOnly) {
          const key = page ?? ["schedule", source, teams.home, teams.away, when.kickoff].join(":");
          if (!output.has(key)) {
            const row = eventRecord(source,site,page,teams,when.kickoff,when.timingSource,
              {home: fixtureTeamBadge(node, 'home', site),
               away: fixtureTeamBadge(node, 'away', site)});
            const league = nameOfTeam(node.tournament ?? node.league ??
              node.competition ?? node.leagueName);
            if (league && league.length < 100) row.league = league;
            output.set(key,row);
          }
        }
      }
      if (depth < 10) for (const [key,value] of Object.entries(node).slice(0,90)) {
        if (value && typeof value === "object" && !["__proto__","constructor"].includes(key))
          queue.push({node:value,football:categoryOtherSport?false:eventIsFootball,depth:depth+1});
      }
    }
  }
  return {rows:output, jsonDocumentCount:state.length};
}

// LiveTV publishes soccer fixtures in nested table rows under
// .side-match-item, not in <article>/<li> cards or SportsEvent JSON. Accept
// only rows with their OWN explicit Soccer marker and a real same-site link.
// The display clock ("19:45 (Soccer)") lacks a timezone, so it must not
// become a fabricated UTC kickoff.
function publicLiveTvSoccerRows(html, site, source) {
  const rows = [];
  const cards = /<div\b[^>]*\bclass\s*=\s*["'][^"']*\bside-match-item\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/gi;
  for (const hit of html.matchAll(cards)) {
    if (rows.length >= 80) break;
    const card = hit[1];
    const imageSports = [...card.matchAll(/<img\b[^>]*\balt\s*=\s*["']([^"']+)["']/gi)]
      .map(m => m[1].trim());
    const labelSports = [...card.matchAll(/<span\b[^>]*\bclass\s*=\s*["'][^"']*\bevdesc\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/gi)]
      .map(m => normalizeText(m[1]).match(/\(([^()]+)\)/)?.[1]?.trim()).filter(Boolean);
    const sports = [...imageSports,...labelSports];
    const other = /^(?:basketball|cricket|tennis|rugby|hockey|baseball|golf|snooker|boxing|mma|ufc|volleyball|badminton|esports|motorsport|american football)$/i;
    if (sports.some(value => other.test(value)) ||
        !sports.some(value => /^(?:soccer|football)$/i.test(value))) continue;
    // Multiple fixture links in a shared wrapper are ambiguous: reject.
    const anchors = [...card.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)]
      .map(m => ({href:m[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1],
        teams:fixtureTitle(m[2])}))
      .filter(m => m.href && m.teams);
    if (!anchors.length || anchors.some(a=>a.teams.home!==anchors[0].teams.home||a.teams.away!==anchors[0].teams.away)) continue;
    const item = anchors[0];
    const page = allowedPageUrl(item.href.replace(/&amp;/gi,"&"), site);
    if (!page || page === site.home) continue;
    const kickoff = pageKickoff(card);
    const row=eventRecord(source,site,page,item.teams,kickoff,
      kickoff ? "explicit" : "none",htmlTeamBadges(card,item.teams,site));
    row.anchors=anchors.flatMap(a=>{const url=allowedPageUrl(a.href,site);return url?
      [{room_num:sourceId(url),page_url:url,nick_name:site.label}]:[];});
    rows.push(row);
  }
  return rows;
}

function rojadirectaRows(html, site) {
  const rows=[];
  for(const m of html.matchAll(/<details\b[^>]*\bclass\s*=\s*['"][^'"]*game-item-details[^'"]*['"][^>]*>([\s\S]*?)<\/details>/gi)) {
    const card=m[1];
    const name=card.match(/<span\b[^>]*\bclass\s*=\s*['"]game-teams['"][^>]*>([\s\S]*?)<\/summary>/i)?.[1];
    if(!name)continue;
    const plain=normalizeText(name).replace(/\s+\d+\s*☆?$/,'').replace(/[☆★]/g,'').trim();
    const pair=fixtureTitle(plain);if(!pair)continue;
    const kickoff=pageKickoff(card);
    const row=eventRecord('rojadirecta',site,null,pair,kickoff,kickoff?'explicit':'none');
    row.source_id=row.schedule_id=m[0].match(/data-game-id=['"]([\w-]+)['"]/)?.[1]||row.source_id;
    row.anchors=[...card.matchAll(/<a\b[^>]*href=['"]([^'"]+)['"]/gi)].flatMap(a=>{
      const url=publicSourceUrl(a[1],site.home);return url?[{room_num:row.source_id+':'+sourceId(url),page_url:url,nick_name:site.label}]:[];
    }).slice(0,6);
    row.page_url=row.anchors[0]?.page_url||null;row.schedule_only=!row.anchors.length;
    rows.push(row);if(rows.length>=100)break;
  }
  return rows;
}

export async function experimentalMatches(source, {fetcher = fetch, now = Date.now} = {}) {
  const site = experimentalFootballSites[source];
  if (!site) throw Error("Unsupported source");
  const deadline=Date.now()+6500;
  let feedError=null;
  if(hasPublicFootballFeed(source)) {
    try{return await publicFootballFeedMatches(source,{fetcher,now});}
    catch(error){feedError=String(error?.message||error).slice(0,100);}
  }
  const catalog = await publicHtml(site.home, fetcher, {withClock: true, now,
    allowedHost: site.host,timeoutMs:Math.max(50,deadline-Date.now())});
  const {html} = catalog;
  const embedded = publicFixtureJsonRows(html,site,source,catalog);
  if(source==='rojadirecta')for(const row of rojadirectaRows(html,site))embedded.rows.set(row.source_id,row);
  if (source === "livetv") {
    for (const row of publicLiveTvSoccerRows(html,site,source)) {
      if (!embedded.rows.has(row.page_url)) embedded.rows.set(row.page_url,row);
    }
  }
  const candidates = new Map();
  const anchors = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  for (const hit of html.matchAll(anchors)) {
    if (candidates.size >= 80) break;
    const href = hit[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1];
    const page = href && allowedPageUrl(href.replace(/&amp;/gi, "&"), site);
    if (!page || page === site.home || candidates.has(page)) continue;
    const card = matchCardMarkup(html, hit);
    const cardSport = explicitFixtureSport(card || hit[0]);
    const footballLink = /\b(?:soccer|football)\b/i.test(page);
    // LiveTV has basketball and tennis links mixed into /soccer. For its
    // legacy <li>/<article> form keep only one-event structured team cards
    // with a soccer-specific URL. Table rows use the dedicated parser above.
    if (source === "livetv" &&
        (!card || !structuredCardTeams(card) || !footballLink ||
          cardSport === "other")) continue;
    // Even a football-looking URL must not turn a labelled basketball
    // or cricket card into a football fixture.
    if (cardSport === "other") continue;
    // On multi-sport home pages, a generic /event/... URL is allowed ONLY
    // when that single match's own markup explicitly says football/soccer.
    // Other generic links remain unverified, not invented as fixtures.
    if (["ppv", "livextv", "streamfree"].includes(source) &&
        !footballLink && cardSport !== "football") continue;
    const teams = teamsFromLink(page, hit[2]) ?? structuredCardTeams(card || hit[0]);
    if (!teams) continue;
    const footballCatalog = /(?:football|soccer)/i.test(new URL(site.home).pathname) ||
      ["camel","xoilac","kooralive"].includes(source);
    if (!footballCatalog && !footballLink && cardSport !== "football") continue;
    // The timestamp must be inside this anchor or immediately preceding it,
    // with a preceding sibling anchor acting as a hard event boundary.
    const preceding = html.slice(Math.max(0, hit.index - 240), hit.index);
    const boundary = preceding.lastIndexOf("</a>");
    const local = boundary < 0 ? preceding : preceding.slice(boundary + 4);
    const explicit = pageKickoff(hit[0]) ?? pageKickoff(local) ??
      (card ? pageKickoff(card) : null);
    const countdown = explicit ? null :
      countdownKickoff(hit[0], catalog.observedAt, catalog.clockFresh) ??
      (card ? countdownKickoff(card, catalog.observedAt, catalog.clockFresh) : null);
    const kickoff = explicit ?? countdown;
    const timingSource = explicit ? "explicit" : countdown ? "countdown" : "none";
    candidates.set(page, {page, teams, kickoff, timingSource,
      badges: htmlTeamBadges(card || hit[0], teams, site)});
  }

  // Detail pages may publish authoritative UTC/offset timestamps that the
  // index omits. Bound network work: only 6 pages, at most 3 concurrent.
  const needDetail = [...candidates.values()]
    .filter(candidate => {
      const existing=embedded.rows.get(candidate.page);
      return !(existing?.match_time||candidate.kickoff)||
        !(existing?.home_logo||candidate.badges.home)||!(existing?.away_logo||candidate.badges.away);
    }).slice(0, 8);
  for (let offset = 0; offset < needDetail.length; offset += 3) {
    if(Date.now()>=deadline)break;
    await Promise.all(needDetail.slice(offset, offset + 3).map(async item => {
      try {
        const detail = await publicHtml(item.page, fetcher, {withClock: true, now,
          allowedHost: site.host,timeoutMs:Math.min(1800,deadline-Date.now())});
        const exact = pageKickoff(detail.html);
        const estimated = exact ? null :
          countdownKickoff(detail.html, detail.observedAt, detail.clockFresh);
        if (!item.kickoff) {
          item.kickoff = exact ?? estimated;
          item.timingSource = exact ? "explicit" : estimated ? "countdown" : "none";
        }
        const htmlBadges = htmlTeamBadges(detail.html, item.teams, site);
        item.badges.home ??= htmlBadges.home;
        item.badges.away ??= htmlBadges.away;
        // Some detail pages publish team badges only in a SportsEvent JSON
        // block. Require the SAME named team pair, not a generic page image.
        const detailRows = publicFixtureJsonRows(detail.html, site, source, detail).rows;
        for (const badgeRow of detailRows.values()) {
          if (badgeRow.home_team.toLowerCase() !== item.teams.home.toLowerCase() ||
              badgeRow.away_team.toLowerCase() !== item.teams.away.toLowerCase()) continue;
          item.badges.home ??= badgeRow.home_logo;
          item.badges.away ??= badgeRow.away_logo;
          break;
        }
      } catch (_) { /* Keep as unverified, never manufacture a kickoff. */ }
    }));
  }

  // Prefer the embedded state when the same page is represented in both.
  for (const row of candidates.values()) {
    if (!embedded.rows.has(row.page)) embedded.rows.set(row.page,
      eventRecord(source,site,row.page,row.teams,row.kickoff,row.timingSource,row.badges));
    else {
      const original = embedded.rows.get(row.page);
      embedded.rows.set(row.page, {
        ...original,
        ...(!original.match_time && row.kickoff ? {
          match_time: row.kickoff,
          verified_kickoff: row.timingSource === "explicit",
          kickoff_estimated: row.timingSource === "countdown",
          kickoff_source: row.timingSource,
          status: "NS", match_status: "SCHEDULED",
        } : {}),
        home_logo: original.home_logo ?? row.badges.home,
        away_logo: original.away_logo ?? row.badges.away,
      });
    }
  }
  const matches = [...embedded.rows.values()].sort((a,b) =>
    (a.match_time ?? "9999").localeCompare(b.match_time ?? "9999"));
  const scheduleOnly = matches.filter(row => row.schedule_only).length;
  const confirmed = matches.filter(row => row.verified_kickoff).length;
  const estimated = matches.filter(row => row.kickoff_estimated).length;
  // The source page is not scoped to the requested date. Expose actual
  // published MMT days so Admin can distinguish a calendar mismatch from
  // broken fixture parsing. Never infer dates for untimed events.
  const publishedDaysMMT = [...new Set(matches
    .filter(row => row.match_time && !Number.isNaN(Date.parse(row.match_time)))
    .map(row => new Date(Date.parse(row.match_time) + 390 * 60000)
      .toISOString().slice(0, 10)))].sort();
  return {
    ok: true, source, matches, results: matches.length,
    diagnostics: {candidate_count: matches.length,
      extraction_mode: embedded.rows.size > candidates.size ? "embedded-json" : "html-or-mixed",
      embedded_json_documents: embedded.jsonDocumentCount,
      schedule_only_count: scheduleOnly,
      content_state: matches.length ? "matches_found" : embedded.jsonDocumentCount ? "no_recognized_football_fixtures" :
        /<script\b/i.test(html) ? "browser_render_or_unsupported_markup" : "empty_page",
      confirmed_kickoff_count: confirmed,
      estimated_countdown_count: estimated,
      missing_kickoff_count: matches.length - confirmed - estimated,
      available_days_mmt: publishedDaysMMT,
      ...(feedError ? {public_feed_error:feedError} : {}),
      note: "Countdown kickoffs are estimates from a fresh page response, not verified fixture times."},
    generated_at: new Date().toISOString(),
  };
}

export async function experimentalStreams(source, body, {fetcher = fetch} = {}) {
  const site = experimentalFootballSites[source];
  if (!site) throw Error("Unsupported source");
  const deadline = Date.now() + 7000;
  let page = hasPublicFootballFeed(source)
    ? await publicFootballFeedPlayer(source,body,{fetcher})
    : typeof body?.page_url === 'string' && body.page_url.trim()
      ? allowedPageUrl(body.page_url, site) : null;
  if(source==='rojadirecta'){
    const published=await experimentalMatches(source,{fetcher});
    const room=String(body?.room_num||'');
    page=published.matches.flatMap(row=>row.anchors||[]).find(a=>a.room_num===room)?.page_url||page;
    // A client URL is accepted only if it is one of this index's players.
    if(page&&!published.matches.some(row=>(row.anchors||[]).some(a=>a.page_url===page)))page=null;
  }
  if (!page) return {ok: true, source, lines: [], line_count: 0,
    ready: false, message: "No verified public match page."};
  let firstHtml=null,configured=[];
  if (source==='roxie') {
    const read=await readPublicSource(page,{fetcher,allowedHosts:[site.host],timeoutMs:2500});
    firstHtml=read.text;
    configured=await configuredPublicMedia(source,firstHtml,read.url,{fetcher});
  }
  const result = await discoverPublicMedia(page,{fetcher,deadline,firstHtml,
    initialAllowedHosts:hasPublicFootballFeed(source)||source==='rojadirecta'?null:[site.host,...(site.aliases||[])]});
  result.lines=[...new Map([...result.lines,...configured].map(line=>[line.url,line])).values()];
  if (!result.lines.length && result.failures.some(error=>error.includes('outside configured provider'))) {
    throw Error('Source redirected outside configured provider');
  }
  const lines = result.lines.map((line, i) => ({
    ...line,
    label: site.label + " • " + (/\.mpd(?:\?|$)/i.test(line.url) ? "DASH / MPD" : "HLS / M3U8") + " " + (i + 1),
    stream_type: /\.mpd(?:\?|$)/i.test(line.url) ? "dash" : "hls",
    resolution: "Auto",
    health_status: "unknown",
  }));
  if (body?.status_only === true || body?.status_only === "true") {
    return {ok: true, source, ready: lines.length > 0, line_count: lines.length,
      live_status: false};
  }
  return {ok: true, source, ready: lines.length > 0,
    lines, line_count: lines.length, live_status: false,
    diagnostics:{pages_checked:result.pagesChecked,
      content_state:lines.length?'media_found':result.failures.length?'player_unavailable':'no_public_media',
      playback_verified:false},
    message: lines.length ? "Check permission and playback before importing." :
      "No public HLS/DASH URL in static page. Login, scripts or player restrictions are not bypassed.",
    generated_at: new Date().toISOString()};
}
