// Admin-only TFLIX imports. Catalog entries are candidates; only a bounded
// manifest + media check can return media_verified. No browser script executes.
const HOME = "https://tflix.su";
const CATALOG_URL = HOME + "/api/live-scores?scope=board";
const CHANNEL_URL = HOME + "/api/channels";
const ALLOWED_HOSTS = new Set([
  "tflix.su", "www.tflix.su", "xtrahut.xyz", "vixembed.bid",
  "tmaxapp.site", "cdnfan.site", "event-65s.dsfigosdhgfvsshed.xyz",
  "polovo.margutm.su", "vix.cdn9859.shop",
  "p16-common-sign.tiktokcdn-us.com",
]);
const MAX_TEXT_BYTES = 1024 * 1024;
const MAX_MANIFEST_BYTES = 512 * 1024;
const BUDGET_MS = 6500;
const USER_AGENT = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36";
const sportExclusion = /\b(cricket|golf|tennis|rugby|motogp|formula\s*1|formula\s*one|f1|racing|horse|cycling|basketball|nba|baseball|mlb|nfl|nhl|ufc|boxing|wrestling)\b/i;
const sportsChannel = /\b(bein|sky\s*sports|tnt\s*sports|bt\s*sport|espn|dazn|super\s*sport|supersport|sport\s*tv|sports|football|soccer|premier\s*league|laliga|bundesliga|ligue|serie\s*a|arenasport|arena\s*sport|eleven|optus|fubo|ziggo|canal\+?\s*sport|willow)\b/i;

const clean = (value) => String(value ?? "").trim();
const slugOK = (value) => /^[a-z0-9][a-z0-9_-]{0,159}$/i.test(value);
const leagueKey = (value) => clean(value).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const iso = (value) => {
  const millis = Date.parse(clean(value));
  return Number.isFinite(millis) ? new Date(millis).toISOString() : null;
};

export function safeTflixUrl(raw, base = HOME) {
  let url;
  try { url = new URL(clean(raw), base); } catch { throw new Error("Unsupported source URL."); }
  if (url.protocol !== "https:" || url.username || url.password ||
    (url.port && url.port !== "443") || !ALLOWED_HOSTS.has(url.hostname.toLowerCase())) {
    throw new Error("Unsupported source host.");
  }
  return url;
}

function context(options = {}) {
  const timeout = Math.max(1, Math.min(BUDGET_MS, options.timeoutMs ?? BUDGET_MS));
  return { deadline: Date.now() + timeout, fetcher: options.fetcher ?? fetch };
}

function requestHeaders(referer, range = null) {
  const headers = { Accept: "*/*", "User-Agent": USER_AGENT };
  if (referer) {
    const ref = safeTflixUrl(referer);
    headers.Referer = ref.toString();
    headers.Origin = ref.origin;
  }
  if (range) headers.Range = range;
  return headers;
}

// Validate every redirect before fetching it. Every fetch/body read shares the
// caller's deadline; body readers are always cancelled after their small cap.
async function fetchBounded(ctx, raw, { referer = HOME, cap = MAX_TEXT_BYTES, prefix = false, range = null } = {}) {
  let url = safeTflixUrl(raw);
  for (let hop = 0; hop < 4; hop++) {
    const left = ctx.deadline - Date.now();
    if (left <= 0) throw new Error("Source verification timed out.");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(left, 2500));
    let response, reader;
    try {
      response = await ctx.fetcher(url.toString(), {
        headers: requestHeaders(referer, range), redirect: "manual", signal: controller.signal,
      });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get("Location");
        if (!location) throw new Error("Source redirect has no destination.");
        url = safeTflixUrl(location, url);
        continue;
      }
      if (!response.ok) throw new Error("Source returned HTTP " + response.status + ".");
      reader = response.body?.getReader();
      if (!reader) throw new Error("Source response is empty.");
      const chunks = [];
      let length = 0;
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        if (!part.value?.byteLength) continue;
        if (!prefix && length + part.value.byteLength > cap) throw new Error("Source response is too large.");
        const partSize = Math.min(part.value.byteLength, cap - length);
        chunks.push(part.value.slice(0, partSize));
        length += partSize;
        if (prefix && length >= cap) break;
      }
      if (!length) throw new Error("Source response is empty.");
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return { bytes, url: url.toString(), status: response.status, headers: response.headers };
    } catch (error) {
      if (controller.signal.aborted) throw new Error("Source verification timed out.");
      throw error;
    } finally {
      clearTimeout(timer);
      controller.abort();
      // A provider's cancellation callback may itself stall. Aborting already
      // stops network reads; detached cancellation must not extend the budget.
      if (reader) void reader.cancel().catch(() => {});
      else if (response?.body) void response.body.cancel().catch(() => {});
    }
  }
  throw new Error("Source redirected too many times.");
}

async function fetchJson(ctx, url) {
  const response = await fetchBounded(ctx, url);
  try { return JSON.parse(new TextDecoder().decode(response.bytes)); }
  catch { throw new Error("Source returned invalid catalog data."); }
}

function logo(raw) {
  if (!clean(raw)) return null;
  try { return safeTflixUrl(raw).toString(); } catch { return null; }
}

function footballRows(payload) {
  const footballLeagues = new Set((payload?.boardLeagues ?? [])
    .filter((row) => row?.sport === "football").map((row) => leagueKey(row.label)));
  // Only the assigned streams array creates imports. The much larger score
  // list never supplies anchors, URLs, or invented broadcast availability.
  return (Array.isArray(payload?.streams) ? payload.streams : []).filter((row) =>
    row && slugOK(clean(row.slug)) && !row.isFinished && !sportExclusion.test(clean(row.league)) &&
    (row.sport === "football" || footballLeagues.has(leagueKey(row.league))))
    .map((row) => {
      const id = "match:" + row.slug;
      const page = HOME + "/match/" + row.slug;
      return {
        source: "tflix", source_id: id, schedule_id: id, kind: "match",
        home_team: clean(row.homeTeam?.name), away_team: clean(row.awayTeam?.name),
        home_logo: logo(row.homeTeam?.logo), away_logo: logo(row.awayTeam?.logo),
        league: clean(row.league) || "Football", match_time: iso(row.date),
        is_live: row.isLive === true, page_url: page,
        anchors: [{ uid: id, room_num: id, nick_name: "TFLIX streams", page_url: page }],
      };
    });
}

function channelRows(payload) {
  const rows = Array.isArray(payload) ? payload : Array.isArray(payload?.channels) ? payload.channels : [];
  return rows.filter((row) => row && slugOK(clean(row.slug)) &&
    sportsChannel.test(clean(row.name)) && !sportExclusion.test(clean(row.name)))
    .map((row) => {
      const id = "channel:" + row.slug;
      const page = HOME + "/channel/" + row.slug;
      return {
        source: "tflix", source_id: id, schedule_id: id, kind: "channel",
        home_team: clean(row.name), away_team: "", home_logo: logo(row.logo), away_logo: null,
        league: "Sports channels", match_time: null, is_live: row.isLive === true,
        page_url: page, anchors: [{ uid: id, room_num: id, nick_name: clean(row.name), page_url: page }],
      };
    });
}

async function catalog(ctx, requested) {
  const kind = requested === "channels" ? "channels" : "matches";
  const payload = await fetchJson(ctx, kind === "channels" ? CHANNEL_URL : CATALOG_URL);
  const rows = kind === "channels" ? channelRows(payload) : footballRows(payload);
  const unique = [...new Map(rows.map((row) => [row.source_id, row])).values()];
  return { kind, rows: unique };
}

export async function tflixMatches(body = {}, options = {}) {
  const { kind, rows } = await catalog(context(options), body.catalog);
  return {
    ok: true, source: "tflix", catalog: kind, matches: rows, results: rows.length,
    message: rows.length ? "Select a source to verify its media before adding it."
      : kind === "matches" ? "No football streams are currently assigned by TFLIX."
        : "No football-related sports channels are currently listed by TFLIX.",
    generated_at: new Date().toISOString(),
  };
}

// A public, metadata-only view of the exact match catalog used by Admin.
// No player/page URLs, server anchors, media/DRM data, or provider labels.
// Stream resolution remains exclusively in the authorized Admin workflow.
export async function tflixPublicMatches(options = {}) {
  const catalog = await tflixMatches({ catalog: "matches" }, options);
  const matches = catalog.matches.slice(0, 200).map((row) => ({
    source_id: row.source_id,
    league: row.league,
    home_team: row.home_team,
    away_team: row.away_team,
    match_time: row.match_time,
    is_live: row.is_live === true,
  }));
  return {
    ok: true, source: "nca", catalog: "matches", matches,
    results: matches.length, generated_at: catalog.generated_at,
  };
}

// RSC chunk arguments are JSON, not executable player code. Parse only their
// literal strings and ordinary quoted properties exposed in the public page.
export function publicPageText(html) {
  const parts = [html];
  for (const hit of html.matchAll(/self\.__next_f\.push\((\[[\s\S]*?\])\)/g)) {
    try {
      const value = JSON.parse(hit[1]);
      if (Array.isArray(value)) parts.push(...value.filter((item) => typeof item === "string"));
    } catch {}
  }
  return parts.join("\n");
}

function decodeEntities(value) {
  return value.replace(/&amp;/gi, "&").replace(/&quot;/gi, '"').replace(/&#39;|&apos;/gi, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .replace(/&#([0-9]+);/g, (_, n) => String.fromCharCode(Number(n)));
}

// The exact public xtrahut/vixembed wrapper observed in October 2026 is a
// literal integer array followed by XOR/subtract into character codes. Decode
// data only, with strict length/range/identifier checks; NEVER eval the result.
export function decodePublicPlayerWrapper(html) {
  const pattern = /var\s+([A-Za-z_$][\w$]*)\s*=\s*\[([\d,\s]+)\]\s*,\s*([A-Za-z_$][\w$]*)\s*=\s*(\d+)\s*,\s*([A-Za-z_$][\w$]*)\s*=\s*(\d+)\s*,\s*([A-Za-z_$][\w$]*)\s*=\s*(["'])\8\s*,\s*([A-Za-z_$][\w$]*)\s*;/g;
  const decoded = [];
  for (const hit of html.matchAll(pattern)) {
    const values = hit[2].split(",").map((n) => Number(n.trim()));
    if (!values.length || values.length > 65536 || values.some((n) => !Number.isInteger(n) || n < 0 || n > 1024)) continue;
    const xor = Number(hit[4]), minus = Number(hit[6]);
    if (xor > 255 || minus > 255) continue;
    const tail = html.slice(hit.index + hit[0].length, hit.index + hit[0].length + 512).replace(/\s+/g, "");
    const expression = hit[7] + "+=String.fromCharCode(((" + hit[1] + "[" + hit[9] + "]^" + hit[3] + ")-" + hit[5] + "+256)%256)";
    const loop = "for(" + hit[9] + "=0;" + hit[9] + "<" + hit[1] + ".length;" + hit[9] + "++){";
    if (!tail.startsWith(loop) || !tail.includes(expression)) continue;
    decoded.push(values.map((n) => String.fromCharCode(((n ^ xor) - minus + 256) % 256)).join(""));
  }
  return decoded.join("\n");
}

function hexKey(raw) {
  const value = clean(raw).replace(/-/g, "");
  return /^[0-9a-f]{32}$/i.test(value) ? value.toLowerCase() : null;
}

function publicClearKey(text) {
  const pairs = [];
  for (const hit of text.matchAll(/clearKeys\s*:\s*\{([^{}]{1,4096})\}/g)) {
    for (const pair of hit[1].matchAll(/["']([0-9a-f-]{32,36})["']\s*:\s*["']([0-9a-f-]{32,36})["']/gi)) {
      const kid = hexKey(pair[1]), key = hexKey(pair[2]);
      if (kid && key) pairs.push([kid, key]);
    }
  }
  const kid = text.match(/(?:key_id|keyId)\s*["']?\s*:\s*["']([^"']+)["']/)?.[1];
  const key = text.match(/(?:key_data|keyData)\s*["']?\s*:\s*["']([^"']+)["']/)?.[1];
  if (kid !== undefined || key !== undefined) {
    if (!hexKey(kid) || !hexKey(key)) throw new Error("Public ClearKey configuration is incomplete.");
    pairs.push([hexKey(kid), hexKey(key)]);
  }
  const unique = [...new Map(pairs.map((pair) => [pair.join(":"), pair])).values()];
  if (unique.length > 1) throw new Error("Multiple public ClearKey pairs are unsupported.");
  if (/clearKeys\s*:/.test(text) && !unique.length) throw new Error("Public ClearKey configuration is invalid.");
  return unique.length ? { key_id: unique[0][0], key_data: unique[0][1] } : { key_id: null, key_data: null };
}

function mediaType(url) {
  const path = new URL(url).pathname.toLowerCase();
  return path.endsWith(".m3u8") ? "hls" : path.endsWith(".mpd") ? "dash" : null;
}

export function extractPublicPlayerConfig(html, base) {
  const text = publicPageText(html) + "\n" + decodePublicPlayerWrapper(html);
  const vars = new Map();
  for (const hit of text.matchAll(/\b(?:var|let|const)\s+([A-Za-z_$][\w$]*)\s*=\s*(["'])([^"'\r\n]+)\2/g)) vars.set(hit[1], hit[3]);
  const values = [];
  for (const hit of text.matchAll(/(?:file|src|source|hlsUrl|dashUrl|manifest)\s*["']?\s*:\s*(?:(["'])([^"'\r\n]+)\1|([A-Za-z_$][\w$]*))/g)) values.push(hit[2] ?? vars.get(hit[3]));
  const keys = publicClearKey(text);
  const found = new Map();
  for (const value of values) {
    try {
      const url = safeTflixUrl(decodeEntities(clean(value)).replace(/\\\//g, "/"), base).toString();
      const type = mediaType(url);
      if (type) found.set(url, { url, stream_type: type, ...keys });
    } catch {}
  }
  return [...found.values()];
}

function sourceEmbedUrls(html, base) {
  const text = publicPageText(html);
  const embeds = new Map();
  // Preserve each source position from the public match/channel page. The site
  // does not always provide a reliable display name, so never invent one.
  for (const hit of text.matchAll(/["'](streamUrl2?)["']\s*:\s*["']([^"']+)["']/g)) {
    try {
      const url = safeTflixUrl(decodeEntities(hit[2]).replace(/\\\//g, "/"), base).toString();
      const order = hit[1] === "streamUrl2" ? 2 : 1;
      const previous = embeds.get(url);
      if (!previous || order < previous.order) {
        embeds.set(url, { url, order, server_name: "Server " + order });
      }
    } catch {}
  }
  return [...embeds.values()].sort((a, b) => a.order - b.order).slice(0, 4);
}

export function signedExpiry(raw) {
  const url = new URL(raw);
  const pathExpiry = url.pathname.match(/\/secure\/[^/]+\/(\d{10})\//)?.[1];
  const queryExpiry = url.searchParams.get("expires") ?? url.searchParams.get("exp");
  const seconds = Number(pathExpiry ?? queryExpiry);
  return Number.isFinite(seconds) && seconds > 0 ? new Date(seconds * 1000).toISOString() : null;
}

function mediaBytes(bytes) {
  if (bytes.length < 32) return false;
  const prefix = new TextDecoder().decode(bytes.slice(0, 128)).trim().toLowerCase();
  if (prefix.startsWith("<") || prefix.startsWith("{") || prefix.startsWith("[")) return false;
  // Observed source wraps MPEG-TS in a small RIFF prefix and mislabels MIME as
  // image/webp. Match Media3's sniff requirement: five sync bytes spaced by
  // 188 bytes, with the first packet starting inside the first packet length.
  for (let start = 0; start < Math.min(188, bytes.length - 752); start++) {
    if ([0, 188, 376, 564, 752].every((offset) => bytes[start + offset] === 0x47)) return true;
  }
  const firstBox = new TextDecoder().decode(bytes.slice(4, 8));
  if (["ftyp", "styp", "moof", "sidx"].includes(firstBox)) return true;
  return false;
}

async function sampleMedia(ctx, url, referer) {
  const result = await fetchBounded(ctx, url, { referer, prefix: true, cap: 4096, range: "bytes=0-4095" });
  if (!mediaBytes(result.bytes)) throw new Error("Source response is not verified media data.");
  return result;
}

function attribute(text, name) {
  const regex = new RegExp("(?:^|[,\\s])" + name + '=(?:"([^"]*)"|([^,\\s]+))', "i");
  const match = text.match(regex);
  return match?.[1] ?? match?.[2] ?? "";
}

async function verifyHls(ctx, candidate, referer) {
  let url = candidate.url;
  for (let depth = 0; depth < 3; depth++) {
    const result = await fetchBounded(ctx, url, { referer, cap: MAX_MANIFEST_BYTES });
    const text = new TextDecoder().decode(result.bytes).replace(/^\uFEFF/, "").trim();
    if (!text.startsWith("#EXTM3U")) throw new Error("Source returned an invalid HLS manifest.");
    const lines = text.split(/\r?\n/).map((line) => line.trim());
    if (lines.some((line) => line.startsWith("#EXT-X-SESSION-KEY:")) ||
      lines.some((line) => line.startsWith("#EXT-X-MEDIA:") && attribute(line, "URI"))) {
      throw new Error("HLS external renditions or session encryption are unsupported.");
    }
    const master = lines.findIndex((line) => line.startsWith("#EXT-X-STREAM-INF:"));
    if (master >= 0) {
      const child = lines.slice(master + 1).find((line) => line && !line.startsWith("#"));
      if (!child) throw new Error("HLS master has no media playlist.");
      url = safeTflixUrl(child, result.url).toString();
      continue;
    }
    for (const line of lines.filter((line) => line.startsWith("#EXT-X-KEY:"))) {
      const method = attribute(line.slice(11), "METHOD");
      if (method !== "NONE") {
        throw new Error("Encrypted HLS format is unsupported.");
      }
    }
    const init = lines.find((line) => line.startsWith("#EXT-X-MAP:"));
    if (init) await sampleMedia(ctx, safeTflixUrl(attribute(init, "URI"), result.url), referer);
    const segment = lines.find((line, index) => line && !line.startsWith("#") &&
      lines.slice(0, index).some((previous) => previous.startsWith("#EXTINF:")));
    if (!segment) throw new Error("HLS playlist has no media segment.");
    await sampleMedia(ctx, safeTflixUrl(segment, result.url), referer);
    return { key_id: null, key_data: null };
  }
  throw new Error("HLS playlist nesting is unsupported.");
}

// Small non-executing XML reader. External entities/DTD are rejected. The
// hierarchy is retained so nested BaseURL and inherited segment configs resolve.
function xmlTree(text) {
  if (/<!DOCTYPE|<!ENTITY/i.test(text)) throw new Error("Unsupported DASH document.");
  const root = { name: "", attrs: {}, children: [], parent: null, text: "" };
  let node = root, count = 0, depth = 0;
  for (const hit of text.matchAll(/<!--[\s\S]*?-->|<[^>]+>|[^<]+/g)) {
    const token = hit[0];
    if (token.startsWith("<?") || token.startsWith("<!")) continue;
    if (token.startsWith("</")) {
      const closing = token.match(/^<\/([^\s/>]+)\s*>$/)?.[1]?.split(":").pop();
      if (!closing || node === root || closing !== node.name) throw new Error("Invalid DASH XML hierarchy.");
      node = node.parent; depth--; continue;
    }
    if (token.startsWith("<")) {
      if (++count > 10000) throw new Error("DASH document is too complex.");
      const name = token.match(/^<([^\s/>]+)/)?.[1]?.split(":").pop();
      if (!name) throw new Error("Invalid DASH XML.");
      const child = { name, attrs: {}, children: [], parent: node, text: "" };
      for (const attr of token.matchAll(/([^\s=<>]+)\s*=\s*(["'])([\s\S]*?)\2/g)) child.attrs[attr[1]] = decodeEntities(attr[3]);
      node.children.push(child);
      if (!token.endsWith("/>")) {
        if (++depth > 64) throw new Error("DASH document is too deeply nested.");
        node = child;
      }
    } else {
      if (node === root && token.trim()) throw new Error("Invalid DASH XML document.");
      node.text += decodeEntities(token.trim());
    }
  }
  if (node !== root || root.children.length !== 1) throw new Error("Invalid DASH XML hierarchy.");
  const mpd = root.children.find((child) => child.name === "MPD");
  if (!mpd) throw new Error("Source returned an invalid DASH manifest.");
  return mpd;
}

const childrenNamed = (node, name) => node.children.filter((child) => child.name === name);
function ancestors(node) {
  const nodes = [];
  while (node?.name) { nodes.unshift(node); node = node.parent; }
  return nodes;
}
function xmlBase(node, url) {
  let base = url;
  for (const parent of ancestors(node)) {
    const child = childrenNamed(parent, "BaseURL")[0];
    if (child?.text) base = safeTflixUrl(child.text, base).toString();
  }
  return base;
}
function inherited(node, name) {
  let result = null;
  for (const parent of ancestors(node)) {
    const child = childrenNamed(parent, name)[0];
    if (child) result = { ...child, attrs: { ...(result?.attrs ?? {}), ...child.attrs } };
  }
  return result;
}
function durationSeconds(value) {
  const match = clean(value).match(/^PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$/);
  return match ? Number(match[1] ?? 0) * 3600 + Number(match[2] ?? 0) * 60 + Number(match[3] ?? 0) : 0;
}
function replaceTemplate(template, representation, number, time) {
  return template.replace(/\$\$/g, "\u0000").replace(/\$(RepresentationID|Bandwidth|Number|Time)(?:%0(\d+)d)?\$/g,
    (_, key, width) => String(({ RepresentationID: representation.attrs.id, Bandwidth: representation.attrs.bandwidth, Number: number, Time: time })[key] ?? "").padStart(Math.min(12, Number(width) || 0), "0")).replace(/\u0000/g, "$");
}

async function verifyDash(ctx, candidate, referer) {
  const response = await fetchBounded(ctx, candidate.url, { referer, cap: MAX_MANIFEST_BYTES });
  const mpd = xmlTree(new TextDecoder().decode(response.bytes));
  const all = [];
  const visit = (node) => { all.push(node); node.children.forEach(visit); };
  visit(mpd);
  const protections = all.filter((node) => node.name === "ContentProtection");
  const kids = new Set();
  for (const protection of protections) {
    const scheme = clean(protection.attrs.schemeIdUri).toLowerCase();
    if (!["urn:mpeg:dash:mp4protection:2011", "urn:uuid:e2719d58-a985-b3c9-781a-b030af78d30e", "org.w3.clearkey"].includes(scheme) ||
      (scheme === "urn:mpeg:dash:mp4protection:2011" && !["", "cenc"].includes(clean(protection.attrs.value).toLowerCase()))) {
      throw new Error("DASH encryption format is unsupported.");
    }
    for (const [name, value] of Object.entries(protection.attrs)) {
      if (name.split(":").pop() === "default_KID") for (const raw of value.split(/\s+/)) {
        const kid = hexKey(raw);
        if (!kid) throw new Error("DASH key ID is invalid.");
        kids.add(kid);
      }
    }
  }
  if (kids.size > 1) throw new Error("Multiple DASH key IDs are unsupported.");
  if (protections.length && kids.size !== 1) throw new Error("DASH encrypted key identity is unsupported.");
  if (protections.length && (!candidate.key_id || !candidate.key_data)) throw new Error("DASH public ClearKey data is missing.");
  if (kids.size && !kids.has(candidate.key_id)) throw new Error("DASH public ClearKey does not match the manifest.");
  const representations = all.filter((node) => node.name === "Representation");
  const selected = [];
  for (const representation of representations) {
    const parent = representation.parent;
    const kind = representation.attrs.contentType ?? parent?.attrs.contentType ??
      (representation.attrs.mimeType ?? parent?.attrs.mimeType ?? "").split("/")[0] ?? "";
    if (!selected.some((item) => item.kind === kind)) selected.push({ representation, kind });
    if (selected.length >= 2) break;
  }
  if (!selected.length) throw new Error("DASH has no supported media representation.");
  for (const { representation } of selected) {
    const base = xmlBase(representation, response.url);
    const segmentList = inherited(representation, "SegmentList");
    if (segmentList) {
      const initialization = childrenNamed(segmentList, "Initialization")[0]?.attrs.sourceURL;
      if (initialization) await sampleMedia(ctx, safeTflixUrl(initialization, base), referer);
      const media = childrenNamed(segmentList, "SegmentURL")[0]?.attrs.media;
      if (!media) throw new Error("DASH segment list has no media URL.");
      await sampleMedia(ctx, safeTflixUrl(media, base), referer);
      continue;
    }
    const segmentTemplate = inherited(representation, "SegmentTemplate");
    if (!segmentTemplate?.attrs.media) throw new Error("DASH segment format is unsupported.");
    const attrs = segmentTemplate.attrs;
    const timescale = Number(attrs.timescale ?? 1), startNumber = Number(attrs.startNumber ?? 1);
    if (!Number.isFinite(timescale) || timescale <= 0 || !Number.isFinite(startNumber)) throw new Error("DASH segment timing is invalid.");
    let number = startNumber, time = Number(attrs.presentationTimeOffset ?? 0);
    const elapsed = Math.max(0, (Date.now() - Date.parse(mpd.attrs.availabilityStartTime ?? "")) / 1000 -
      durationSeconds(ancestors(representation).find((node) => node.name === "Period")?.attrs.start));
    const timeline = childrenNamed(segmentTemplate, "SegmentTimeline")[0];
    if (timeline) {
      let next = 0, offset = 0;
      for (const segment of childrenNamed(timeline, "S")) {
        const d = Number(segment.attrs.d), repeat = Number(segment.attrs.r ?? 0);
        next = Number(segment.attrs.t ?? next);
        if (!(d > 0) || !Number.isFinite(next) || !Number.isInteger(repeat)) throw new Error("DASH timeline is invalid.");
        const count = repeat >= 0 ? repeat + 1 : Number.isFinite(elapsed) ? Math.max(1, Math.floor((elapsed * timescale - next) / d) - 1) : 0;
        if (count <= 0 || count > 1000000) throw new Error("DASH timeline format is unsupported.");
        time = next + (count - 1) * d; number = startNumber + offset + count - 1;
        offset += count; next += count * d;
      }
    } else if (mpd.attrs.type === "dynamic") {
      const d = Number(attrs.duration);
      if (!Number.isFinite(elapsed) || !(d > 0)) throw new Error("DASH live timing is unsupported.");
      const offset = Math.max(0, Math.floor(elapsed * timescale / d) - 3);
      number += offset; time += offset * d;
    }
    if (attrs.initialization) await sampleMedia(ctx, safeTflixUrl(replaceTemplate(attrs.initialization, representation, number, time), base), referer);
    await sampleMedia(ctx, safeTflixUrl(replaceTemplate(attrs.media, representation, number, time), base), referer);
  }
  return { key_id: candidate.key_id ?? null, key_data: candidate.key_data ?? null };
}

export async function verifyTflixMedia(candidate, referer, options = {}) {
  const ctx = options.ctx ?? context(options);
  const started = Date.now();
  const url = safeTflixUrl(candidate.url).toString();
  const type = mediaType(url);
  if (!type) throw new Error("Source player has no supported direct media URL.");
  const expiry = signedExpiry(url);
  if (expiry && Date.parse(expiry) <= Date.now() + 15000) throw new Error("Source media URL has expired.");
  if ((candidate.key_id || candidate.key_data) && (!hexKey(candidate.key_id) || !hexKey(candidate.key_data))) throw new Error("Public ClearKey configuration is incomplete.");
  const keys = type === "hls" ? await verifyHls(ctx, { ...candidate, url }, referer)
    : await verifyDash(ctx, { ...candidate, url }, referer);
  const ref = safeTflixUrl(referer);
  return {
    label: type === "hls" ? "HLS" : "DASH", resolution: "Auto", url, stream_type: type,
    referer: ref.toString(), origin: ref.origin, ...keys, expires_at: expiry,
    media_verified: true, health_status: Date.now() - started > 3000 ? "slow" : "healthy",
    health_http: 200, checked_at: new Date().toISOString(),
    verification_scope: "Manifest, required keys, and a bounded media sample; playback duration is not guaranteed.",
  };
}

export async function tflixStreams(body = {}, options = {}) {
  const ctx = context(options);
  const target = clean(body.room_num ?? body.source_id ?? body.schedule_id);
  const kind = target.startsWith("channel:") ? "channels" : "matches";
  const { rows } = await catalog(ctx, kind);
  const item = rows.find((row) => row.source_id === target);
  if (!item || (body.page_url && body.page_url !== item.page_url)) throw new Error("TFLIX source is no longer available.");
  const page = await fetchBounded(ctx, item.page_url);
  const html = new TextDecoder().decode(page.bytes);
  const embeds = sourceEmbedUrls(html, item.page_url);
  const failures = [];
  const found = new Map();

  async function checkServer(embed) {
    try {
      let candidates;
      if (mediaType(embed.url)) {
        candidates = [{ url: embed.url, stream_type: mediaType(embed.url), key_id: null, key_data: null, referer: item.page_url }];
      } else {
        const embedded = await fetchBounded(ctx, embed.url, { referer: item.page_url });
        candidates = extractPublicPlayerConfig(new TextDecoder().decode(embedded.bytes), embedded.url)
          .map((candidate) => ({ ...candidate, referer: embedded.url }));
      }
      // Each source is verified independently. Keep one usable quality per
      // server, but do not stop scanning other servers after the first success.
      for (const candidate of candidates.slice(0, 4)) {
        try {
          const verified = await verifyTflixMedia(candidate, candidate.referer, { ctx });
          return { ...verified, server_name: embed.server_name, label: embed.server_name + " • " + verified.label };
        } catch (error) {
          failures.push(error instanceof Error ? error.message : "Source media could not be verified.");
        }
      }
    } catch (error) {
      failures.push(error instanceof Error ? error.message : "Source player could not be read.");
    }
    return null;
  }

  // Bound concurrency to two. This lets a slow primary and a working backup
  // progress within the same deadline, without increasing upstream load wildly.
  for (let offset = 0; offset < embeds.length; offset += 2) {
    if (Date.now() >= ctx.deadline) break;
    const batch = await Promise.all(embeds.slice(offset, offset + 2).map(checkServer));
    for (const line of batch) {
      if (line && !found.has(line.url)) found.set(line.url, line);
    }
  }
  const lines = [...found.values()];
  return {
    ok: true, source: "tflix", catalog: kind, kind: item.kind, room_num: target, page_url: item.page_url,
    title: item.kind === "channel" ? item.home_team : item.home_team + " vs " + item.away_team,
    line_count: lines.length, ready: lines.length > 0, live_status: lines.length ? item.is_live : false,
    lines, message: lines.length ? "Verified manifest and media sample."
      : failures[0] ?? "The public player does not expose a supported direct stream configuration.",
    generated_at: new Date().toISOString(),
  };
}
