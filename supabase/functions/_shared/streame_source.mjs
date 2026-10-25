// StreamCenter adapter. It reads the site's public, server-rendered
// game cards and public iframe chain. Only an HLS manifest that also returns a
// bounded media sample is offered to Admin; no page script is executed.
const CATALOG = "https://streamcenter.st/game-cards/embed";
const CATALOG_ORIGIN = "https://streamcenter.st";
// Both names are public player destinations returned by the catalog's own
// source redirect. Keep exact host checks when the provider rotates aliases.
const PLAYER_HOSTS = new Set(["streame.center", "streamec.st", "embedcenter.st"]);
const USER_AGENT = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36";
const MAX_HTML_BYTES = 1024 * 1024;
const MAX_MANIFEST_BYTES = 512 * 1024;
const BUDGET_MS = 7000;

const clean = (value) => String(value ?? "").trim();
const decode = (value) => clean(value)
  .replace(/&amp;/gi, "&").replace(/&quot;/gi, '"')
  .replace(/&#39;|&apos;/gi, "'")
  .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
  .replace(/&#([0-9]+);/g, (_, n) => String.fromCodePoint(Number(n)));
const text = (value) => decode(clean(value).replace(/<[^>]*>/g, " "))
  .replace(/\s+/g, " ").trim();

function sourceContext(options = {}) {
  const timeout = Math.max(1, Math.min(BUDGET_MS, options.timeoutMs ?? BUDGET_MS));
  return { deadline: Date.now() + timeout, fetcher: options.fetcher ?? fetch };
}

export function safeStreameUrl(raw, base = CATALOG_ORIGIN) {
  let url;
  try { url = new URL(clean(raw), base); } catch { throw new Error("Unsupported source URL."); }
  const host = url.hostname.toLowerCase();
  const allowed = host === "streamcenter.st" || PLAYER_HOSTS.has(host) ||
    /^edgestream(?:[1-9]|[1-9][0-9])\.pro$/.test(host);
  if (url.protocol !== "https:" || url.username || url.password ||
    (url.port && url.port !== "443") || !allowed) {
    throw new Error("Unsupported source host.");
  }
  return url;
}

async function fetchBounded(ctx, raw, {
  referer = CATALOG, cap = MAX_HTML_BYTES, prefix = false, range = null,
} = {}) {
  let url = safeStreameUrl(raw);
  for (let hop = 0; hop < 4; hop++) {
    const left = ctx.deadline - Date.now();
    if (left <= 0) throw new Error("Source verification timed out.");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(left, 2500));
    let response, reader;
    try {
      const ref = safeStreameUrl(referer);
      const headers = {
        Accept: "*/*", "User-Agent": USER_AGENT,
        Referer: ref.toString(), Origin: ref.origin,
      };
      if (range) headers.Range = range;
      response = await ctx.fetcher(url.toString(), {
        headers, redirect: "manual", signal: controller.signal,
      });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get("Location");
        if (!location) throw new Error("Source redirect has no destination.");
        url = safeStreameUrl(location, url);
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
        if (!prefix && length + part.value.byteLength > cap) {
          throw new Error("Source response is too large.");
        }
        const size = Math.min(part.value.byteLength, cap - length);
        chunks.push(part.value.slice(0, size));
        length += size;
        if (prefix && length >= cap) break;
      }
      if (!length) throw new Error("Source response is empty.");
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return { bytes, url: url.toString(), headers: response.headers };
    } catch (error) {
      if (controller.signal.aborted) throw new Error("Source verification timed out.");
      throw error;
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) void reader.cancel().catch(() => {});
      else if (response?.body) void response.body.cancel().catch(() => {});
    }
  }
  throw new Error("Source redirected too many times.");
}

function attribute(tag, name) {
  const hit = tag.match(new RegExp("\\b" + name + "\\s*=\\s*([\"'])([\\s\\S]*?)\\1", "i"));
  return hit ? decode(hit[2]) : "";
}

function cards(html) {
  const rows = [];
  for (const hit of html.matchAll(/<article\b[^>]*class=["'][^"']*game-card-row[^"']*["'][^>]*>([\s\S]*?)<\/article>/gi)) {
    const card = hit[1];
    const sourceMatches = [...card.matchAll(/<a\b[^>]*class=["'][^"']*game-card-open-link[^"']*["'][^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)];
    if (!sourceMatches.length) continue;
    const watch = card.match(/href=["']\/watch\/([^"'/?#]+)["']/i)?.[1];
    const eventId = clean(watch ?? sourceMatches[0][1].split("/").filter(Boolean).at(-2));
    if (!/^event-[a-z0-9-]{1,190}$/i.test(eventId)) continue;
    // The StreamCenter board also includes NFL/NHL/MLB/basketball cards. NCA
    // destinations are football matches, whose stable public event IDs carry
    // the provider's explicit soccer category.
    if (!/-soccer-/i.test(eventId)) continue;
    const title = decode(card.match(/<h3\b[^>]*aria-label=["']([^"']+)["']/i)?.[1] ?? "");
    const teams = [...card.matchAll(/data-team-position=["'][^"']+["'][^>]*title=["']([^"']+)["']/gi)]
      .map((item) => decode(item[1]));
    const split = title.split(/\s+vs\.?\s+/i);
    const home = teams[0] || split[0] || title;
    const away = teams[1] || split[1] || "";
    if (!home || !away) continue;
    const league = text(card.match(/<p\b[^>]*class=["'][^"']*game-card-league[^"']*["'][^>]*>([\s\S]*?)<\/p>/i)?.[1]) || "Football";
    const kickoff = clean(card.match(/<time\b[^>]*dateTime=["']([^"']+)["']/i)?.[1]);
    const time = Number.isFinite(Date.parse(kickoff)) ? new Date(kickoff).toISOString() : null;
    const status = text(card.match(/<span\b[^>]*class=["'][^"']*game-card-status[^"']*["'][^>]*>([\s\S]*?)<\/span>/i)?.[1]);
    const anchors = sourceMatches.map((source, index) => {
      const rawPath = decode(source[1]);
      let page;
      try { page = safeStreameUrl(rawPath, CATALOG_ORIGIN); } catch { return null; }
      if (!new RegExp("^/api/stream-link/iframe/" + eventId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "/[0-9a-f-]{36}$", "i").test(page.pathname)) return null;
      const id = page.pathname.split("/").at(-1);
      return {
        uid: id, room_num: eventId + ":" + id,
        nick_name: text(source[2]) || "StreamCenter " + (index + 1),
        page_url: page.toString(),
      };
    }).filter(Boolean);
    if (!anchors.length) continue;
    rows.push({
      source: "streame", source_id: eventId, schedule_id: eventId,
      league, home_team: home, away_team: away,
      home_logo: null, away_logo: null, match_time: time,
      is_live: /^live$/i.test(status), status,
      page_url: CATALOG_ORIGIN + "/watch/" + eventId, anchors,
    });
  }
  return [...new Map(rows.map((row) => [row.source_id, row])).values()]
    .sort((a, b) => (Date.parse(a.match_time ?? "") || Infinity) -
      (Date.parse(b.match_time ?? "") || Infinity));
}

export async function streameMatches(_body = {}, options = {}) {
  const ctx = sourceContext(options);
  const response = await fetchBounded(ctx, CATALOG);
  const matches = cards(new TextDecoder().decode(response.bytes));
  return {
    ok: true, source: "streame", matches, results: matches.length,
    message: matches.length ? "Select a public source to verify its HLS media before adding it."
      : "No current StreamCenter football sources are listed.",
    generated_at: new Date().toISOString(),
  };
}

function mediaBytes(bytes) {
  if (bytes.length < 32) return false;
  const firstBox = new TextDecoder().decode(bytes.slice(4, 8));
  if (["ftyp", "styp", "moof", "sidx"].includes(firstBox)) return true;
  for (let start = 0; start < Math.min(188, bytes.length - 752); start++) {
    if ([0, 188, 376, 564, 752].every((offset) => bytes[start + offset] === 0x47)) return true;
  }
  return false;
}

async function verifyHls(ctx, raw, referer) {
  let url = safeStreameUrl(raw);
  for (let depth = 0; depth < 3; depth++) {
    const response = await fetchBounded(ctx, url, { referer, cap: MAX_MANIFEST_BYTES });
    const manifest = new TextDecoder().decode(response.bytes).replace(/^\uFEFF/, "").trim();
    if (!manifest.startsWith("#EXTM3U")) throw new Error("Source returned an invalid HLS manifest.");
    const lines = manifest.split(/\r?\n/).map((line) => line.trim());
    if (lines.some((line) => line.startsWith("#EXT-X-KEY:") && !/METHOD=NONE(?:,|$)/i.test(line))) {
      throw new Error("Encrypted HLS is not supported by this source import.");
    }
    const master = lines.findIndex((line) => line.startsWith("#EXT-X-STREAM-INF:"));
    if (master >= 0) {
      const child = lines.slice(master + 1).find((line) => line && !line.startsWith("#"));
      if (!child) throw new Error("HLS master has no media playlist.");
      url = safeStreameUrl(child, response.url);
      continue;
    }
    const segment = lines.find((line, index) => line && !line.startsWith("#") &&
      lines.slice(0, index).some((previous) => previous.startsWith("#EXTINF:")));
    if (!segment) throw new Error("HLS playlist has no media segment.");
    const sample = await fetchBounded(ctx, safeStreameUrl(segment, response.url), {
      referer, prefix: true, cap: 4096, range: "bytes=0-4095",
    });
    if (!mediaBytes(sample.bytes)) throw new Error("Source response is not verified media data.");
    return safeStreameUrl(raw).toString();
  }
  throw new Error("HLS playlist nesting is unsupported.");
}

export async function streameStreams(body = {}, options = {}) {
  const ctx = sourceContext(options);
  const target = clean(body.room_num ?? body.source_id ?? body.schedule_id);
  const idMatch = target.match(/^(event-[a-z0-9-]{1,190}):([0-9a-f-]{36})$/i);
  if (!idMatch) throw new Error("Invalid StreamCenter source.");
  const catalog = await streameMatches({}, { ...options, fetcher: ctx.fetcher,
    timeoutMs: Math.max(1, ctx.deadline - Date.now()) });
  const match = catalog.matches.find((row) => row.source_id === idMatch[1]);
  const anchor = match?.anchors.find((row) => row.uid === idMatch[2]);
  if (!anchor || (body.page_url && safeStreameUrl(body.page_url).toString() !== anchor.page_url)) {
    throw new Error("StreamCenter source is no longer available.");
  }

  const redirect = await fetchBounded(ctx, anchor.page_url, { referer: match.page_url });
  return resolvePlayerPage(ctx, redirect, anchor, match, idMatch[2], {
    visited: new Set(), remaining: 6,
  });
}

function playerKind(url) {
  if (!PLAYER_HOSTS.has(url.hostname)) return null;
  if (["/embed/hls2.php", "/embed/hls_cdn.php"].includes(url.pathname) &&
    /^[A-Za-z0-9_-]{6,96}$/.test(url.searchParams.get("stream") ?? "")) return "hls";
  if (/^\/embed\/ch[1-9][0-9]{0,2}\.php$/.test(url.pathname)) return "wrapper";
  return null;
}

// Inspect only static, public HLS literals. Do not execute player scripts,
// follow unknown hosts, or accept a URL until its manifest and segment verify.
function publicHlsCandidates(playerText, base) {
  const urls = [];
  for (const hit of playerText.matchAll(
    /(?:\bstreamUrl\b|["']streamUrl["'])\s*[:=]\s*(["'])(https:[^"'\r\n]+)\1/gi,
  )) {
    try {
      const media = safeStreameUrl(decode(hit[2]).replace(/\\\//g, "/"), base);
      if (media.pathname.toLowerCase().endsWith(".m3u8") && !urls.includes(media.href)) {
        urls.push(media.href);
      }
    } catch { /* Ignore unknown hosts and non-media literals. */ }
  }
  return urls.slice(0, 4);
}

async function resolvePlayerPage(ctx, page, anchor, match, sourceId, state, depth = 0) {
  if (state.visited.has(page.url)) throw new Error("StreamCenter player contains a loop.");
  state.visited.add(page.url);
  const kind = playerKind(new URL(page.url));
  if (kind === "hls") return verifyPlayer(ctx, page, anchor, match, sourceId);

  const playerPage = new TextDecoder().decode(page.bytes);
  // A known public wrapper may contain a direct, literal streamUrl instead
  // of a second iframe. This is not permission to follow other player hosts.
  const direct = kind === "wrapper" && publicHlsCandidates(playerPage, page.url).length > 0;
  const iframeTags = [...playerPage.matchAll(/<iframe\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi)];
  const players = [];
  if (depth < 3) {
    for (const tag of iframeTags) {
      try {
        const iframe = safeStreameUrl(decode(tag[1]), page.url);
        if (playerKind(iframe) && !state.visited.has(iframe.href) &&
            !players.some((value) => value.href === iframe.href)) {
          players.push(iframe);
        }
      } catch { /* Never fetch unrelated/ad/private iframe hosts. */ }
    }
  }

  let failure;
  for (const iframe of players.slice(0, 4)) {
    if (state.remaining-- <= 0) break;
    try {
      const child = await fetchBounded(ctx, iframe, { referer: page.url });
      return await resolvePlayerPage(ctx, child, anchor, match, sourceId, state, depth + 1);
    } catch (error) {
      failure = error;
    }
  }
  if (direct) {
    try { return await verifyPlayer(ctx, page, anchor, match, sourceId); }
    catch (error) { failure ??= error; }
  }
  if (failure) throw failure;
  if (depth >= 3) throw new Error("StreamCenter player nesting is unsupported.");
  throw new Error(iframeTags.length ? "Unsupported StreamCenter player." :
    "StreamCenter player is unavailable.");
}

async function verifyPlayer(ctx, player, anchor, match, sourceId) {
  const playerText = new TextDecoder().decode(player.bytes);
  // A site can expose the same public URL either as a top-level variable
  // or a literal property; neither requires executing page JavaScript.
  const mediaUrls = publicHlsCandidates(playerText, player.url);
  if (!mediaUrls.length) {
    throw new Error("StreamCenter player has no supported HLS source.");
  }
  const started = Date.now();
  let verified, failure;
  for (const media of mediaUrls.slice(0, 4)) {
    try { verified = await verifyHls(ctx, media, player.url); break; }
    catch (error) { failure = error; }
  }
  if (!verified) throw failure ?? new Error("StreamCenter media could not be verified.");
  const checkedAt = new Date().toISOString();
  const line = {
    id: "streame:" + sourceId, label: anchor.nick_name || "English",
    server_name: anchor.nick_name || "English", resolution: "Auto",
    url: verified, stream_type: "hls", referer: player.url,
    origin: new URL(player.url).origin, key_id: null, key_data: null,
    expires_at: null, media_verified: true,
    health_status: Date.now() - started > 3000 ? "slow" : "healthy",
    health_http: 200, checked_at: checkedAt, gateway_compatible: true,
    verification_scope: "Manifest and a bounded media sample; playback duration is not guaranteed.",
  };
  return {
    ok: true, source: "streame", ready: true, live_status: match.is_live,
    anchor_name: anchor.nick_name, lines: [line], line_count: 1,
    checked_at: checkedAt,
  };
}
