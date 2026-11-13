// Bounded reads of public provider pages. No cookies, credentials, page JS or
// authentication challenges are executed by this discovery code.
export function publicSourceUrl(value, base) {
  if (typeof value !== 'string' || !value.trim() || value.length > 4096) return null;
  try {
    const url = new URL(value.replace(/&amp;/gi, '&'), base);
    const host = url.hostname.toLowerCase().replace(/\.$/, '');
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.port ||
        !host.includes('.') || host.includes(':') || /^[\d.]+$/.test(host) ||
        /(?:^|\.)(?:localhost|local|internal|invalid|test|onion)$/.test(host)) return null;
    url.hostname = host; url.hash = '';
    return url.toString();
  } catch (_) { return null; }
}

export async function readPublicSource(value, {fetcher = fetch, timeoutMs = 5000,
  kind = 'html', allowedHosts = null} = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(50, timeoutMs));
  let url = publicSourceUrl(value);
  const allowed = candidate => !allowedHosts || allowedHosts.some(host =>
    candidate.hostname === host || candidate.hostname.endsWith('.' + host));
  try {
    for (let redirects = 0; redirects <= 3; redirects++) {
      if (!url || !allowed(new URL(url))) throw Error('Unsupported public source URL');
      const response = await fetcher(url, {redirect: 'manual', signal: controller.signal,
        headers: {Accept: kind === 'json' ? 'application/json' : kind === 'text' ? 'text/plain' : 'text/html',
          'Cache-Control': 'no-cache'}});
      if (response.status >= 300 && response.status < 400) {
        const next = response.headers?.get?.('location');
        await response.body?.cancel?.().catch(() => {});
        url = next ? publicSourceUrl(next, url) : null;
        continue;
      }
      if (!response.ok) throw Error('Source page HTTP ' + response.status);
      const finalUrl = publicSourceUrl(response.url || url);
      if (!finalUrl || !allowed(new URL(finalUrl))) throw Error('Source redirected outside configured provider');
      const type = response.headers?.get?.('content-type') || '';
      if (kind === 'html' && type && !/text\/html|application\/xhtml\+xml/i.test(type)) throw Error('Source page is not HTML');
      if (kind === 'json' && type && !/json/i.test(type)) throw Error('Source did not return public JSON');
      if (Number(response.headers?.get?.('content-length')) > 1500000) throw Error('Source page exceeds size limit');
      const text = await response.text();
      if (text.length > 1500000) throw Error('Source page exceeds size limit');
      return {text, url: finalUrl, headers: response.headers};
    }
    throw Error('Too many source redirects');
  } finally {clearTimeout(timer);}
}

export function publishedMediaUrls(html, page) {
  const clean = html.replace(/\\\//g, '/').replace(/\\u002f/gi,'/').replace(/\\u0026/gi,'&').replace(/&amp;/gi, '&');
  const found = new Set();
  const patterns = [
    /(?:https?:\/\/|\/\/)[^\s"'<>\\]+?\.(?:m3u8|mpd|mp4)(?:\?[^\s"'<>\\]*)?/gi,
    /\b(?:src|href|data-src|data-file|data-hls|data-dash|data-video|data-stream|data-stream-url)\s*=\s*["']([^"']+\.(?:m3u8|mpd|mp4)(?:\?[^"']*)?)["']/gi,
    /["'](?:file|src|hls|dash|manifest|playlist|source|video)["']\s*:\s*["']([^"'<>\s]+\.(?:m3u8|mpd|mp4)(?:\?[^"'<>\s]*)?)["']/gi,
  ];
  for (const pattern of patterns) for (const hit of clean.matchAll(pattern)) {
    const url = publicSourceUrl(hit[1] || hit[0], page);
    if (url && /\.(?:m3u8|mpd|mp4)$/i.test(new URL(url).pathname)) found.add(url);
  }
  return [...found].slice(0, 12);
}

function playerPages(html, page) {
  const found = new Set();
  const add = raw => {
    const url = publicSourceUrl(raw, page);
    if (url && !/youtube|discord|facebook|twitter|telegram|google|doubleclick|ads\./i.test(new URL(url).hostname)) found.add(url);
  };
  for (const hit of html.matchAll(/<iframe\b[^>]*\b(?:src|data-src)\s*=\s*["']([^"']+)["']/gi)) add(hit[1]);
  for (const hit of html.matchAll(/["'](?:embed|iframe|player)(?:_?url)?["']?\s*[:=]\s*["']([^"'<>]+)["']/gi)) add(hit[1].replace(/\\\//g, '/'));
  for (const hit of html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
    const label = hit[2].replace(/<[^>]+>/g, ' ').trim();
    if (!/^(?:link|server|stream|watch|player|broadcast)(?:\s*(?:\d+|hd|sd|live|now))*$/i.test(label)) continue;
    const href = hit[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1];
    if (href) add(href);
  }
  for (const hit of html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+)["']/gi)) {
    const url = publicSourceUrl(hit[1],page);
    if (url && new URL(url).origin===new URL(page).origin &&
        /(?:player|embed|stream|video)[^/]*\.(?:js|json)(?:[?]|$)/i.test(url)) add(url);
  }
  return [...found].slice(0, 6);
}

export async function discoverPublicMedia(page, {fetcher = fetch, firstHtml = null,
  deadline = Date.now() + 6500, initialAllowedHosts = null, extraPages = []} = {}) {
  const queue = [{url: page, depth: 0}, ...extraPages.map(url=>({url,depth:1}))], seen = new Set(), lines = new Map(), failures = [];
  while (queue.length && seen.size < 6 && Date.now() < deadline && lines.size < 12) {
    const job = queue.shift();
    if (seen.has(job.url)) continue;
    seen.add(job.url);
    if (/\.(?:m3u8|mpd|mp4)$/i.test(new URL(job.url).pathname)) {
      lines.set(job.url,{url:job.url,referer:page,origin:new URL(page).origin});
      continue; // The independent media probe validates this published URL.
    }
    try {
      const read = job.depth === 0 && firstHtml !== null ? {text:firstHtml,url:job.url} :
        await readPublicSource(job.url, {fetcher, timeoutMs:Math.min(2500, deadline-Date.now()),
          allowedHosts:job.depth===0?initialAllowedHosts:null,
          kind:/\.(?:js|json)(?:[?]|$)/i.test(job.url)?'text':'html'});
      const html = read.text;
      for (const url of publishedMediaUrls(html, read.url)) if (!lines.has(url)) {
        lines.set(url, {url, referer: read.url, origin:new URL(read.url).origin});
      }
      if (job.depth < 2) for (const url of playerPages(html, read.url)) {
        if (!seen.has(url)) queue.push({url,depth:job.depth+1});
      }
    } catch (e) {failures.push(String(e?.message || e).slice(0,100));}
  }
  return {lines:[...lines.values()], pagesChecked:seen.size, failures};
}
