// Direct-link extraction only. No embedded websites or video player adapters.
import {publicSourceUrl, readPublicSource} from './public_source_media.mjs';

export const highlightSources = [
  {id:'dasfootball',name:'DasFootball',url:'https://dasfootball.com/',mode:'feed'},
];
const cache = new Map(), inFlight = new Map();
const clean = value => String(value || '').replace(/<[^>]*>/g,' ').replace(/&amp;/gi,'&')
  .replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'").replace(/\s+/g,' ').trim();
const excluded = /\b(?:full\s*match|(?:1st|2nd|first|second)\s*half|extra\s*time|ceremony|half\s*time\s*show|interview|press\s*conference)\b/i;

export function highlightLine(item, fallbackLabel='Highlights') {
  if (!item || typeof item !== 'object') return null;
  const label=clean(item.title || item.name || item.label || fallbackLabel).slice(0,150);
  if (excluded.test(label) || item.visible===false || item.publish===0 || item.publish==='0' ||
      item.drm_key || item.key_data || item.drm_scheme || String(item.type)==='1') return null;
  const [address,...suffix]=String(item.link || item.stream_url || item.url || '').split('|');
  const url=publicSourceUrl(address); if (!url) return null;
  const ext=new URL(url).pathname.match(/\.(m3u8|mp4)$/i)?.[1]?.toLowerCase();
  if (!ext) return null;
  const headers={};
  // Only non-secret playback headers. Never copy Cookie/accountToken/auth.
  for (const [key,value] of new URLSearchParams(suffix.join('&'))) {
    const field=key.toLowerCase();
    if (['referer','referrer','origin','user-agent'].includes(field) && !/[\r\n]/.test(value)) {
      if (field==='user-agent') headers.user_agent=value.slice(0,512);
      else headers[field==='referrer'?'referer':field]=value;
    }
  }
  for (const field of ['referer','origin']) {
    const value=item[field] || item.headers?.[field] || headers[field];
    const valid=publicSourceUrl(value);
    headers[field]=valid ? (field==='origin'?new URL(valid).origin:valid) : null;
  }
  const fingerprint=JSON.stringify([url,headers.referer,headers.origin,headers.user_agent || '']);
  return {id:fingerprint,label,stream_url:url,stream_type:ext==='m3u8'?'hls':'mp4',
    referer:headers.referer,origin:headers.origin,user_agent:headers.user_agent || null,
    health_status:'not_checked',playback_verified:false};
}

function uniqueLines(lines) {
  return [...new Map(lines.filter(Boolean).map(line=>[line.id,line])).values()];
}
function structuredVideos(html) {
  const videos=[];
  function visit(value,depth=0) {
    if (!value || typeof value!=='object' || depth>12) return;
    if (Array.isArray(value)) {for (const item of value) visit(item,depth+1);return;}
    if (value['@type']==='VideoObject') videos.push(value);
    for (const key of ['@graph','itemListElement','item','video','subjectOf']) visit(value[key],depth+1);
  }
  for (const hit of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {visit(JSON.parse(hit[1]));} catch (_) { /* An unrelated invalid schema must not hide other videos. */ }
  }
  return videos;
}
export function parseDasHighlights(html) {
  const entries=new Map();
  for (const video of structuredVideos(html).slice(0,150)) {
    const page=publicSourceUrl(video.url,'https://dasfootball.com/');
    const title=clean(video.name);
    if (!page || new URL(page).hostname!=='dasfootball.com' || !/highlights/i.test(new URL(page).pathname) || !title || excluded.test(title)) continue;
    const lines=uniqueLines([video.contentUrl,video.embedUrl].map(link=>highlightLine({link,title:'Highlights'})));
    // Never list a website player as an extracted video URL.
    if (!lines.length) continue;
    const previous=entries.get(page);
    if (previous) {previous.lines=uniqueLines([...previous.lines,...lines]);continue;}
    const date=Date.parse(video.uploadDate || '');
    entries.set(page,{id:'dasfootball:'+page,provider:'dasfootball',title:title.slice(0,240),source_page_url:page,
      thumbnail_url:publicSourceUrl(Array.isArray(video.thumbnailUrl)?video.thumbnailUrl[0]:video.thumbnailUrl),
      published_at:Number.isFinite(date)?new Date(date).toISOString():null,lines});
  }
  return [...entries.values()];
}

async function catalogue(fetcher,force=false) {
  const previous=cache.get('dasfootball');
  if (!force && previous && Date.now()-Date.parse(previous.updated_at)<300000) return previous;
  if (inFlight.has('dasfootball')) return inFlight.get('dasfootball');
  const work=(async()=>{
    try {
      const {text}=await readPublicSource('https://dasfootball.com/',{fetcher,kind:'html',timeoutMs:5500,allowedHosts:['dasfootball.com']});
      const data={entries:parseDasHighlights(text),warnings:[],updated_at:new Date().toISOString()};
      cache.set('dasfootball',data);return data;
    } catch(error) {
      const warnings=[clean(error.message) || 'Could not extract highlight links.'];
      return previous?{...previous,stale:true,warnings}:
        {entries:[],updated_at:null,unavailable:true,warnings};
    }
  })();
  inFlight.set('dasfootball',work);
  try {return await work;}
  finally {if (inFlight.get('dasfootball')===work) inFlight.delete('dasfootball');}
}

// Bounded first-byte test only. No public arbitrary-URL checker: callers must
// select a line that the provider actually published in this catalogue.
export async function checkHighlightLine(line,{fetcher=fetch}={}) {
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),5000);
  const start=Date.now();let url=publicSourceUrl(line.stream_url);
  try {
    for(let hop=0;hop<4;hop++) {
      if (!url) throw Error('Invalid media URL');
      const response=await fetcher(url,{signal:controller.signal,redirect:'manual',headers:{
        Accept:'*/*',Range:'bytes=0-4095',...(line.referer?{Referer:line.referer}:{}),
        ...(line.origin?{Origin:line.origin}:{}),...(line.user_agent?{'User-Agent':line.user_agent}:{})}});
      if(response.status>=300&&response.status<400) {
        const location=response.headers.get('location');await response.body?.cancel();
        url=location?publicSourceUrl(location,url):null;continue;
      }
      if (!response.ok) {await response.body?.cancel();return {status:'failed',http:response.status,ms:Date.now()-start,playback_verified:false};}
      const reader=response.body?.getReader();if (!reader) throw Error('Empty media');
      const chunks=[];let size=0;
      try {while(size<4096) {const {value,done}=await reader.read();if(done)break;chunks.push(value);size+=value.length;}}
      finally {await reader.cancel().catch(()=>{});}
      const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
      const valid=line.stream_type==='hls'?new TextDecoder().decode(bytes).trimStart().startsWith('#EXTM3U'):
        bytes.length>=8 && new TextDecoder().decode(bytes.slice(4,8))==='ftyp';
      return {status:valid?'reachable':'invalid_media',http:response.status,ms:Date.now()-start,playback_verified:false};
    }
    throw Error('Too many media redirects');
  } catch (_) {return {status:'failed',http:0,ms:Date.now()-start,playback_verified:false};}
  finally {clearTimeout(timer);controller.abort();}
}

export async function footballHighlights(body,{fetcher=fetch}={}) {
  const provider=String(body.provider || 'dasfootball');
  if (provider!=='dasfootball') throw Error('Unsupported highlights provider');
  const action=String(body.action || 'catalog');
  if (!['catalog','details','check'].includes(action)) throw Error('Unsupported highlights action');
  const data=await catalogue(fetcher,body.force===true);
  if (action==='catalog') return {ok:true,source:'highlights',provider,sources:highlightSources,...data,total:data.entries.length};
  const entry=data.entries.find(row=>row.id===body.entry_id);
  if (!entry) throw Error('This highlight is no longer in the source. Refresh the list.');
  if (action==='details') return {ok:true,source:'highlights',provider,entry};
  const line=entry.lines.find(item=>item.id===body.line_id);
  if (!line) throw Error('This video link changed. Reopen the highlight.');
  return {ok:true,source:'highlights',provider,check:await checkHighlightLine(line,{fetcher})};
}
