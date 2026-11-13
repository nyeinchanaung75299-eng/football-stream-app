import {publicSourceUrl, readPublicSource} from './public_source_media.mjs';

// These GET endpoints are used by the providers' own public home pages.
// Never send an NCA session, cookies or credentials to a provider.
const ppvFeed = 'https://api.ppv.st/api/streams';
const supported = source => source === 'ppv' || source === 'livextv' || source === 'streamfree';
export const hasPublicFootballFeed = supported;

function teams(name) {
  const vs = String(name ?? '').match(/^(.{2,65}?)\s+vs?\.?\s+(.{2,65})$/i);
  if (vs) return {home:vs[1].trim(),away:vs[2].trim()};
  const at = String(name ?? '').match(/^(.{2,65}?)\s+at\s+(.{2,65})$/i);
  return at ? {home:at[2].trim(),away:at[1].trim()} : null;
}

async function events(source, {fetcher = fetch} = {}) {
  if (!supported(source)) return [];
  const read = await readPublicSource(ppvFeed,{fetcher,kind:'json',timeoutMs:5000,
    allowedHosts:['api.ppv.st']});
  const data = JSON.parse(read.text);
  if (data.success === false || !Array.isArray(data.streams)) throw Error('Public football feed unavailable');
  return data.streams.filter(group => /^(?:football|soccer)$/i.test(group.category || ''))
    .flatMap(group => Array.isArray(group.streams) ? group.streams : []).slice(0,150);
}

function players(event) {
  return [event,...(Array.isArray(event.substreams) ? event.substreams : [])].slice(0,12)
    .map(item => ({id:String(item.id), url:publicSourceUrl(item.iframe),
      label:String(item.source_tag || item.name || 'Player').slice(0,100)}))
    .filter(item => item.url && /^\d+$/.test(item.id));
}

export async function publicFootballFeedMatches(source, {fetcher = fetch, now = Date.now} = {}) {
  if (source === 'streamfree') return streamFreeMatches({fetcher,now});
  const rows = await events(source,{fetcher});
  const current = typeof now === 'function' ? now() : now;
  const matches = [];
  for (const event of rows) {
    const pair = teams(event.name), entries = players(event);
    const start = Number(event.starts_at)*1000, end = Number(event.ends_at)*1000;
    if (!pair || !entries.length || !/^\d+$/.test(String(event.id)) ||
        !Number.isFinite(start) || start < 1577836800000 || start > 4102444800000 ||
        (Number.isFinite(end) && end > 0 && end < current - 4*3600000)) continue;
    const sourceId = String(event.id);
    matches.push({source,source_id:sourceId,schedule_id:sourceId,
      home_team:pair.home,away_team:pair.away,league:String(event.tag || 'Football'),
      home_logo:null,away_logo:null,match_time:new Date(start).toISOString(),
      verified_kickoff:true,kickoff_estimated:false,kickoff_source:'explicit',
      status:'NS',match_status:'SCHEDULED',hot:false,schedule_only:false,
      page_url:entries[0].url,
      anchors:entries.map(p=>({room_num:sourceId+':'+p.id,page_url:p.url,nick_name:p.label})),
    });
  }
  matches.sort((a,b)=>a.match_time.localeCompare(b.match_time));
  return {ok:true,source,matches,results:matches.length,generated_at:new Date().toISOString(),
    diagnostics:{content_state:matches.length?'matches_found':'no_published_football_events',
      extraction_mode:'public-provider-api',confirmed_kickoff_count:matches.length,
      estimated_countdown_count:0,missing_kickoff_count:0,
      available_days_mmt:[...new Set(matches.map(m=>new Date(Date.parse(m.match_time)+390*60000).toISOString().slice(0,10)))].sort()}};
}

// Resolve a stable event/player ID again, rather than trusting a client-sent
// arbitrary iframe URL. Removed players cannot be resurrected from a cache.
export async function publicFootballFeedPlayer(source, body, {fetcher = fetch} = {}) {
  const room = String(body?.room_num ?? body?.room ?? body?.source_id ?? body?.schedule_id ?? '');
  if (source === 'streamfree') {
    const streams = await streamFreeStreams(fetcher);
    const item = streams.find(row=>String(row.stream_key)===room);
    return item ? streamFreePage(item.stream_key) : null;
  }
  const [eventId, playerId] = room.split(':');
  if (!/^\d+$/.test(eventId) || (playerId && !/^\d+$/.test(playerId))) return null;
  const event = (await events(source,{fetcher})).find(e=>String(e.id)===eventId);
  if (!event) return null;
  const published = players(event);
  return (playerId ? published.find(p=>p.id===playerId) : published[0])?.url ?? null;
}

async function streamFreeJson(path, fetcher) {
  const r = await readPublicSource('https://strmfree.st'+path,{fetcher,kind:'json',
    allowedHosts:['strmfree.st'],timeoutMs:4000});
  return JSON.parse(r.text);
}
const streamFreePage = key => typeof key === 'string' && /^[a-z0-9_-]{1,180}$/i.test(key)
  ? 'https://strmfree.st/player/soccer/'+encodeURIComponent(key) : null;
async function streamFreeStreams(fetcher) {
  const data = await streamFreeJson('/streams',fetcher);
  return Array.isArray(data.streams?.soccer) ? data.streams.soccer.slice(0,100) : [];
}
async function streamFreeMatches({fetcher,now}) {
  const [data,streams] = await Promise.all([
    streamFreeJson('/fixtures/soccer',fetcher),streamFreeStreams(fetcher),
  ]);
  const current = typeof now==='function' ? now() : now;
  const matches=[];
  const key = pair => [pair.home,pair.away].map(v=>v.toLowerCase().replace(/[^a-z0-9]/g,'')).sort().join(':');
  for (const group of Object.values(data.fixtures||{})) for (const fixture of Array.isArray(group.fixtures)?group.fixtures:[]) {
    if (matches.length>=100 || fixture.category!=='soccer') continue;
    const pair=teams(fixture.event_name),stamp=Number(fixture.date_unix)*1000;
    if (!pair || !Number.isFinite(stamp) || stamp<current-4*3600000 || stamp>4102444800000) continue;
    const stream=streams.find(s=>{
      const p=teams(s.name);
      return p&&key(p)===key(pair)&&Math.abs(Number(s.match_timestamp)*1000-stamp)<2*3600000;
    });
    const page=stream?streamFreePage(stream.stream_key):null;
    const id=stream?.stream_key||'schedule-'+fixture.date_unix+'-'+matches.length;
    matches.push({source:'streamfree',source_id:id,schedule_id:id,league:String(fixture.competition||'Football'),
      home_team:pair.home,away_team:pair.away,home_logo:null,away_logo:null,
      match_time:new Date(stamp).toISOString(),verified_kickoff:true,kickoff_source:'explicit',
      kickoff_estimated:false,status:'NS',match_status:'SCHEDULED',hot:false,schedule_only:!page,
      page_url:page,anchors:page?[{room_num:id,page_url:page,nick_name:'StreamFree'}]:[]});
  }
  return {ok:true,source:'streamfree',matches,results:matches.length,
    diagnostics:{content_state:matches.length?'matches_found':'no_published_football_events',
      extraction_mode:'public-provider-api',confirmed_kickoff_count:matches.length,
      missing_kickoff_count:0,estimated_countdown_count:0,schedule_only_count:matches.filter(m=>m.schedule_only).length},
    generated_at:new Date().toISOString()};
}

// Roxie publishes a small stream-path + host-list player configuration. Read
// those literal values only; never evaluate its player/advertising JavaScript.
export async function configuredPublicMedia(source, html, page, {fetcher = fetch} = {}) {
  if (source!=='roxie') return [];
  const root=html.match(/return\s*`https:\/\/\$\{subdomain\}\.([a-z0-9.-]+)\/\$\{streamPath\}`/i)?.[1];
  const fallback=html.match(/function\s+getRandomStream\s*\(\s*streamPath\s*,\s*subdomain\s*=\s*['"]([a-z0-9-]+)['"]/i)?.[1];
  if (!root||!fallback) return [];
  const domains=[root];
  const file=html.match(/fetch\(\s*['"]([^'"]+\.txt)['"]\s*\)/i)?.[1];
  const listUrl=file&&publicSourceUrl(file,page);
  if (listUrl&&new URL(listUrl).hostname===new URL(page).hostname) {
    try {const r=await readPublicSource(listUrl,{fetcher,kind:'text',timeoutMs:1200});
      for(const host of r.text.split(/[\s,]+/))if(/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(host))domains.push(host);
    }catch(_){/* The publisher's explicit fallback remains available. */}
  }
  const urls=new Set();
  for(const m of html.matchAll(/getRandomStream\(\s*['"]([a-z0-9_-]+\.m3u8)['"]\s*(?:,\s*['"]([a-z0-9-]+)['"])?\s*\)/gi)) {
    for(const domain of [...new Set(domains)].slice(0,3)) {
      const url=publicSourceUrl('https://'+(m[2]||fallback)+'.'+domain+'/'+m[1]);
      if(url)urls.add(url);
    }
  }
  return [...urls].slice(0,6).map(url=>({url,referer:page,origin:new URL(page).origin}));
}
