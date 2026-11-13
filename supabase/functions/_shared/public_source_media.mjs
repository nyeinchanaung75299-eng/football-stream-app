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
  kind = 'html', allowedHosts = null, referer = null} = {}) {
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
          'Cache-Control': 'no-cache',
          ...(referer && publicSourceUrl(referer) ? {Referer:publicSourceUrl(referer)} : {})}});
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
      const mediaType = publicMediaMime(type);
      if (kind === 'auto' && mediaType) {
        await response.body?.cancel?.().catch(() => {});
        return {text:'',url:finalUrl,headers:response.headers,mediaType};
      }
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

// A player may preload a sponsor/preroll MP4 while the match is unavailable.
// Public and reachable does not make that asset a programme stream.
function programmeMediaUrl(value) {
  const url=publicSourceUrl(value);
  if (!url) return null;
  const target=new URL(url);
  if (/(?:^|\.)(?:ads?|doubleclick|googlesyndication)(?:\.|$)/i.test(target.hostname) ||
      /(?:^|[\/_-])(?:ads?|advert(?:isement)?|preroll|pre-roll|sponsor-video|promo-video)(?:[\/_.-]|$)/i.test(target.pathname)) return null;
  return url;
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
    if (url && programmeMediaUrl(url) && /\.(?:m3u8|mpd|mp4)$/i.test(new URL(url).pathname)) found.add(url);
  }
  // AlbaPlayer publishes a plain base64-encoded CSV of source URLs. This is
  // player configuration, not DRM/key data or executable packed JavaScript.
  for(const hit of html.matchAll(/<(?:div|video)\b([^>]*)>/gi)) {
    if(!/^aplr[_-]/i.test(attribute(hit[1],'data-uid')||''))continue;
    const encoded=attribute(hit[1],'data-src');
    if(!encoded || encoded.length>16000 || !/^[a-z0-9+/=_-]+$/i.test(encoded))continue;
    try {
      for(const value of atob(encoded.replace(/-/g,'+').replace(/_/g,'/')).split(',')) {
        const url=publicSourceUrl(value.trim(),page);
        if(url && programmeMediaUrl(url) && /\.(?:m3u8|mpd|mp4)$/i.test(new URL(url).pathname))found.add(url);
      }
    }catch{/* Malformed public source data is ignored. */}
  }
  return [...found].slice(0, 12);
}

export function publicMediaMime(value) {
  const type=String(value||'').split(';')[0].trim().toLowerCase();
  if (['application/vnd.apple.mpegurl','application/x-mpegurl','audio/mpegurl','audio/x-mpegurl'].includes(type)) return 'hls';
  if (type==='application/dash+xml') return 'dash';
  if (type==='video/mp4') return 'mp4';
  return null;
}

function attribute(markup,name) {
  const hit=markup.match(new RegExp('(?:^|\\s)'+name+'\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'=<>`]+))','i'));
  return hit ? hit[1] ?? hit[2] ?? hit[3] : null;
}

// Follow only explicit public player references. A typed JSON station entry
// and a stream dropdown button are player references too, not just iframes.
export function publishedPlayerPages(html,page) {
  const found=new Map();
  const add=(raw,kind='page')=>{
    const url=publicSourceUrl(raw,page);
    if (url && !/youtube|discord|facebook|twitter|telegram|google|doubleclick|(?:^|\.)ads\./i.test(new URL(url).hostname)) {
      if(!found.has(url))found.set(url,{url,kind});
    }
  };
  for(const hit of html.matchAll(/<(?:iframe|video|source)\b([^>]*)>/gi)) {
    const raw=attribute(hit[1],'src') ?? attribute(hit[1],'data-src');
    if(raw)add(raw);
  }
  for(const hit of html.matchAll(/(?:["'](?:embed|iframe|player)(?:_?url|Src)?["']|\b(?:iframe|player|embed)(?:Url|Src)|\biframe\.src)\s*[:=]\s*["']([^"'<>]+)["']/gi)) {
    add(hit[1].replace(/\\\//g,'/'));
  }
  for(const hit of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    if(!/^(?:application\/(?:json|ld\+json)|text\/json)$/i.test(attribute(hit[1],'type')||''))continue;
    try {
      const queue=[JSON.parse(hit[2])];
      for(let i=0;i<queue.length&&i<600;i++) {
        const item=queue[i];if(!item||typeof item!=='object')continue;
        const type=String(item.playback_type ?? item.type ?? '').toLowerCase();
        if(/^(?:iframe|hls|dash|mpd|mp4|application\/x-mpegurl|application\/vnd\.apple\.mpegurl|application\/dash\+xml|video\/mp4)$/.test(type)) {
          const value=item.server_url ?? item.stream_url ?? item.file ?? item.src ?? item.url;
          if(typeof value==='string')add(value);
        }
        queue.push(...Object.values(item).filter(v=>v&&typeof v==='object').slice(0,80));
      }
    }catch{/* Data only: JavaScript expressions are never evaluated. */}
  }
  // Prioritise the current player's script before trying alternative servers.
  for(const hit of html.matchAll(/<script\b([^>]*)>/gi)) {
    const url=publicSourceUrl(attribute(hit[1],'src'),page);
    if(!url)continue;
    const explicitBootstrap=attribute(hit[1],'data-play')!==null || attribute(hit[1],'data-player')!==null;
    if(explicitBootstrap || (new URL(url).origin===new URL(page).origin &&
        /(?:player|embed|stream|video)[^/]*\.(?:js|json)(?:[?]|$)/i.test(url)))add(url,'script');
  }
  for(const hit of html.matchAll(/<(a|button)\b([^>]*)>([\s\S]*?)<\/\1>/gi)) {
    const label=hit[3].replace(/<[^>]+>/g,' ').replace(/&nbsp;|&#160;/gi,' ').replace(/\s+/g,' ').trim();
    if(!/^(?:link|server|stream|watch|player|broadcast)(?:\s*(?:\d+|hd|sd|live|now))*$/i.test(label))continue;
    const raw=attribute(hit[2],hit[1].toLowerCase()==='button'?'data-uri':'href');
    if(raw)add(raw);
  }
  return [...found.values()].slice(0,10);
}

export async function discoverPublicMedia(page,{fetcher=fetch,firstHtml=null,
  deadline=Date.now()+6500,initialAllowedHosts=null,extraPages=[]}={}) {
  const queue=[{url:page,depth:0,parent:page,kind:'page'},
    ...extraPages.map(url=>({url,depth:1,parent:page,kind:'page'}))];
  const seen=new Set(),lines=new Map(),failures=[];
  const addLine=(url,parent,type=null)=>{
    if(programmeMediaUrl(url))lines.set(url,{url,referer:parent,origin:new URL(parent).origin,
      ...(type?{stream_type:type}:{})});
  };
  while(queue.length&&seen.size<8&&Date.now()<deadline&&lines.size<12) {
    const job=queue.shift();if(seen.has(job.url))continue;
    seen.add(job.url);
    if(/\.(?:m3u8|mpd|mp4)$/i.test(new URL(job.url).pathname)) {
      addLine(job.url,job.parent);continue;
    }
    try {
      const read=job.depth===0&&firstHtml!==null ? {text:firstHtml,url:job.url} :
        await readPublicSource(job.url,{fetcher,timeoutMs:Math.min(2500,deadline-Date.now()),
          allowedHosts:job.depth===0?initialAllowedHosts:null,referer:job.parent,
          kind:job.kind==='script'||/\.(?:js|json)(?:[?]|$)/i.test(job.url)?'text':'auto'});
      const body=read.text.trimStart();
      const type=read.mediaType || (body.startsWith('#EXTM3U')?'hls':
        /^(?:<\?xml[^>]*>\s*)?<(?:[\w-]+:)?MPD(?:\s|>)/i.test(body)?'dash':null);
      if(type){addLine(read.url,job.parent,type);continue;}
      for(const url of publishedMediaUrls(read.text,read.url))if(!lines.has(url))addLine(url,read.url);
      if(job.depth<4)for(const child of publishedPlayerPages(read.text,read.url)) {
        if(!seen.has(child.url))queue.push({...child,depth:job.depth+1,parent:read.url});
      }
    }catch(e){failures.push(String(e?.message||e).slice(0,100));}
  }
  return {lines:[...lines.values()],pagesChecked:seen.size,failures};
}
