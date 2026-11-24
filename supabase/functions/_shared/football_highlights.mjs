// Direct-link extraction only. No embedded websites or video player adapters.
import {publicSourceUrl, readPublicSource} from './public_source_media.mjs';

export const highlightSources = [
  {id:'dasfootball',name:'DasFootball',url:'https://dasfootball.com/',mode:'feed'},
];
const cache = new Map(), inFlight = new Map(), entryCache=new Map(), searchCache=new Map();
const clean = value => String(value || '').replace(/<[^>]*>/g,' ').replace(/&amp;/gi,'&')
  .replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'").replace(/\s+/g,' ').trim();
const excluded = /\b(?:extended\s*(?:hl|highlights?)|full\s*match|(?:1st|2nd|first|second)\s*half|extra\s*time|ceremony|half\s*time\s*show|interview|press\s*conference)\b/i;

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
function streamableId(value){
 const address=publicSourceUrl(value);if(!address)return null;
 const url=new URL(address);if(url.protocol!=='https:'||!['streamable.com','www.streamable.com'].includes(url.hostname))return null;
 return url.pathname.match(/^\/(?:e\/)?([a-zA-Z0-9]{3,32})\/?$/)?.[1]||null;
}
export function parseDasHighlights(html,{includeEmbeds=false,sourcePage=null}={}) {
  const entries=new Map();
  for (const video of structuredVideos(html).slice(0,150)) {
    const page=publicSourceUrl(video.url||sourcePage,'https://dasfootball.com/');
    const title=clean(video.name);
    if (!page || new URL(page).hostname!=='dasfootball.com' || !/highlights/i.test(new URL(page).pathname) || !title || excluded.test(title)) continue;
    const lines=uniqueLines([video.contentUrl,video.embedUrl].map(link=>highlightLine({link,title:'Highlights'})));
    // Never list a website player as an extracted video URL.
    const embedId=includeEmbeds?streamableId(video.embedUrl):null;
    if (!lines.length&&!embedId) continue;
    const previous=entries.get(page);
    if (previous) {previous.lines=uniqueLines([...previous.lines,...lines]);continue;}
    const date=Date.parse(video.uploadDate || '');
    entries.set(page,{id:'dasfootball:'+page,provider:'dasfootball',title:title.slice(0,240),source_page_url:page,
      thumbnail_url:publicSourceUrl(Array.isArray(video.thumbnailUrl)?video.thumbnailUrl[0]:video.thumbnailUrl),
      published_at:Number.isFinite(date)?new Date(date).toISOString():null,lines,...(embedId?{embed_id:embedId}:{})});
  }
  return [...entries.values()];
}

function cardEntry(card,force=false){
  const address=card.slug?'/'+card.slug+'/':card.href;
  const page=publicSourceUrl(address,'https://dasfootball.com/');
  const title=clean(card.title);
  if(!page||new URL(page).hostname!=='dasfootball.com'||!/highlights/i.test(new URL(page).pathname)||!title||excluded.test(title))return null;
  const id='dasfootball:'+page,old=entryCache.get(id);
  const logo=card.thumbnailUrl||card.thumbnail_url||card.homeTeam?.logoUrl;
  const entry={...old,id,provider:'dasfootball',title,source_page_url:page,
    league:clean(card.categoryName)||old?.league||null,
    thumbnail_url:publicSourceUrl(logo,'https://dasfootball.com/')||old?.thumbnail_url||null,
    published_at:card.publishedAt||old?.published_at||null,lines:force?[]:old?.lines||[],
    links_checked_at:force?null:old?.links_checked_at};
  entryCache.set(id,entry);return entry;
}
// A successful HTTP request does not prove the publisher added a new highlight.
export function highlightCatalogueFreshness(entries, now=Date.now()) {
  const times=entries.map(row=>Date.parse(row.published_at || '')).filter(time=>Number.isFinite(time)&&time<=now);
  const latest=times.length?Math.max(...times):null;
  const latest_published_at=latest===null?null:new Date(latest).toISOString();
  const publisher_age_hours=latest===null?null:Math.floor((now-latest)/3600000);
  const warnings=publisher_age_hours!==null&&publisher_age_hours>=36
    ? ['Latest dated highlight in this source page: '+latest_published_at.slice(0,10)+' UTC. Refresh succeeded, but no newer published highlight was verified in this response.']
    : [];
  return {latest_published_at,publisher_age_hours,warnings};
}
// Normal match pages are catalogue metadata only, not direct media URLs.
function matchPage(value) {
  const address=publicSourceUrl(value,'https://dasfootball.com/');
  if(!address)return null;
  const url=new URL(address);
  if(url.protocol!=='https:'||url.hostname!=='dasfootball.com'||
     !/^\/match\/[a-z0-9-]+-\d{4}-\d{2}-\d{2}-\d+\/?$/i.test(url.pathname))return null;
  url.search='';url.pathname=url.pathname.replace(/\/+$/,'')+'/';
  return url.toString();
}
function normalLabel(value){
  return /^(?:watch\s+)?(?:normal\s+)?highlights?$/i.test(clean(value));
}
export function publicNormalMatchCandidates(html){
  const pages=new Set();
  for(const hit of html.matchAll(/<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>/gi)){
    const page=matchPage(hit[1]);if(!page)continue;
    pages.add(page);
    if(pages.size>=12)break;
  }
  return [...pages];
}
export function publicNormalMatchMetadata(html,page){
  page=matchPage(page);if(!page)return null;
  const visible=html.replace(/<script\b[\s\S]*?<\/script>/gi,'').replace(/<style\b[\s\S]*?<\/style>/gi,'');
  // A finished fixture alone does not establish Normal HL availability.
  const normal=[...visible.matchAll(/<(button|a)\b[^>]*>([\s\S]*?)<\/\1>/gi)].some(hit=>normalLabel(hit[2])) ||
    [...visible.matchAll(/\b(?:aria-label|title)\s*=\s*["']([^"']+)["']/gi)].some(hit=>normalLabel(hit[1]));
  if(!normal)return null;
  const match=new URL(page).pathname.match(/^\/match\/(.+)-(\d{4}-\d{2}-\d{2})-\d+\/$/i);
  const rawTitle=clean(visible.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)?.[1]||'')
    .replace(/\s*(?:[|–—-]\s*DasFootball.*|\bHighlights(?:\s+and\s+Goals)?\b.*)$/i,'').trim();
  const title=/\bvs\.?\b/i.test(rawTitle)?rawTitle:match[1].replace(/-/g,' ').replace(/\b\w/g,c=>c.toUpperCase()).replace(/\bVs\b/,'vs');
  // Match date is distinct from a verified upload time.
  return {id:'dasfootball:'+page,provider:'dasfootball',title:title.slice(0,240),
    source_page_url:page,match_date:match[2],published_at:null,
    highlight_variant:'normal',source_page_only:true,lines:[]};
}
async function discoverNormalMatchPages(fetcher,query=''){
  const {text}=await readPublicSource('https://dasfootball.com/',{fetcher,kind:'html',timeoutMs:3000,allowedHosts:['dasfootball.com']});
  const words=query.toLowerCase().split(/\s+/).filter(Boolean);
  const pages=publicNormalMatchCandidates(text).filter(page=>words.every(word=>page.toLowerCase().includes(word))).slice(0,6);
  const rows=await Promise.all(pages.map(async page=>{
    try{
      const {text}=await readPublicSource(page,{fetcher,kind:'html',timeoutMs:2500,allowedHosts:['dasfootball.com']});
      return publicNormalMatchMetadata(text,page);
    }catch{return null;}
  }));
  return rows.filter(Boolean).sort((a,b)=>b.match_date.localeCompare(a.match_date));
}

async function catalogue(fetcher,force=false,{offset=0,query=''}={}) {
  const key=query+'|'+offset,previous=cache.get(key);
  if (!force && previous && Date.now()-Date.parse(previous.updated_at)<300000) return previous;
  if (inFlight.has(key)) return inFlight.get(key);
  const work=(async()=>{
    try {
      let cards,hasMore,nextOffset;
      if(query){
        let found=searchCache.get(query);
        if(force||!found||Date.now()-found.time>300000){
          const {text}=await readPublicSource('https://dasfootball.com/api/search/?q='+encodeURIComponent(query),{fetcher,kind:'json',timeoutMs:5500,allowedHosts:['dasfootball.com']});
          const rows=JSON.parse(text);if(!Array.isArray(rows))throw Error('Invalid highlights search');
          // Search API variants may call public highlights "article", "post",
          // or omit type. Never admit team/category results: cardEntry still
          // enforces a DasFootball /highlights/ article URL and safe title.
          const published=rows.filter(r=>
            ['article','post','highlight',undefined,null,''].includes(r.type) &&
            Boolean(cardEntry(r)));
          found={time:Date.now(),rows:published};searchCache.set(query,found);
        }
        cards=found.rows.slice(offset,offset+9);nextOffset=offset+cards.length;hasMore=nextOffset<found.rows.length;
      }else{
        const {text}=await readPublicSource('https://dasfootball.com/api/homepage-posts/?offset='+offset,{fetcher,kind:'json',timeoutMs:5500,allowedHosts:['dasfootball.com']});
        const payload=JSON.parse(text);if(!Array.isArray(payload.cards)||typeof payload.hasMore!=='boolean')throw Error('Invalid highlights catalogue');
        cards=payload.cards;nextOffset=offset+cards.length;hasMore=payload.hasMore&&cards.length>0;
      }
      let entries=[...new Map(cards.map(card=>cardEntry(card,force)).filter(Boolean).map(e=>[e.id,e])).values()];
      const legacyFreshness=highlightCatalogueFreshness(entries);
      let matchPages=[];
      if(offset===0&&(!entries.length||(!query&&legacyFreshness.publisher_age_hours!==null&&legacyFreshness.publisher_age_hours>=36))){
        try{matchPages=await discoverNormalMatchPages(fetcher,query);}catch{/* retain legacy results */}
      }
      for(const row of matchPages)entryCache.set(row.id,row);
      entries=[...new Map([...matchPages,...entries].map(e=>[e.id,e])).values()];
      const freshness=!query&&offset===0?highlightCatalogueFreshness(entries):{warnings:[]};
      if(matchPages.length)freshness.warnings=['Normal HL match pages listed separately; video upload dates and direct media availability are unverified.'];
      const data={entries,...freshness,updated_at:new Date().toISOString(),has_more:hasMore&&nextOffset<5000,next_offset:nextOffset};
      // Invalidate subsequent cursors only after the first-page refresh succeeds.
      // A failed refresh must not erase the last known catalogue.
      if(force && offset===0) {
        for(const cachedKey of cache.keys())if(cachedKey.startsWith(query+'|'))cache.delete(cachedKey);
      }
      cache.set(key,data);
      if(cache.size>200)cache.delete(cache.keys().next().value);
      if(searchCache.size>50)searchCache.delete(searchCache.keys().next().value);
      if(entryCache.size>3000)entryCache.delete(entryCache.keys().next().value);
      return data;
    } catch(error) {
      const warnings=[clean(error.message) || 'Could not extract highlight links.'];
      return previous?{...previous,stale:true,warnings:[...new Set([...(previous.warnings||[]),...warnings])]}:
        {entries:[],updated_at:null,unavailable:true,warnings,has_more:false,next_offset:offset};
    }
  })();
  inFlight.set(key,work);
  try {return await work;}
  finally {if (inFlight.get(key)===work) inFlight.delete(key);}
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
  if (action==='catalog') {
    const offset=Number(body.offset??0),query=clean(body.query).slice(0,80);
    if(!Number.isInteger(offset)||offset<0||offset>5000)throw Error('Invalid highlights offset');
    const data=await catalogue(fetcher,body.force===true,{offset,query});
    const entries=data.entries;
    return {ok:true,source:'highlights',provider,sources:highlightSources,...data,entries,total:entries.length};
  }
  const page=typeof body.entry_id==='string'&&body.entry_id.startsWith('dasfootball:')?publicSourceUrl(body.entry_id.slice(12)):null;
  const modernPage=matchPage(page);
  if(modernPage){
    if(action!=='details')throw Error('Direct media not available for this source page');
    let entry=entryCache.get('dasfootball:'+modernPage);
    if(!entry||!entry.source_page_only){
      const {text}=await readPublicSource(modernPage,{fetcher,kind:'html',timeoutMs:3500,allowedHosts:['dasfootball.com']});
      entry=publicNormalMatchMetadata(text,modernPage);
    }
    if(!entry)throw Error('Normal highlights were not confirmed by this page');
    return {ok:true,source:'highlights',provider,entry:{...entry,lines:[]}};
  }
  if(!page||new URL(page).hostname!=='dasfootball.com'||!/^[\w/-]+highlights[\w/-]*\/?$/i.test(new URL(page).pathname))throw Error('Invalid highlight entry');
  let entry=entryCache.get(body.entry_id);
  if(!entry||!entry.lines.length&&!entry.links_checked_at||entry.links_checked_at&&Date.now()-Date.parse(entry.links_checked_at)>300000){
    const {text}=await readPublicSource(page,{fetcher,kind:'html',timeoutMs:5500,allowedHosts:['dasfootball.com']});
    const extracted=parseDasHighlights(text,{includeEmbeds:true,sourcePage:page}).find(row=>row.source_page_url.replace(/\/+$/,'')===page.replace(/\/+$/,''));
    if(!extracted)throw Error('No native highlight link published for this entry');
    entry={...entry,...extracted,id:body.entry_id,source_page_url:page};
    if(!entry.lines.length&&entry.embed_id){
      try{
        const {text}=await readPublicSource('https://api.streamable.com/videos/'+entry.embed_id,{fetcher,kind:'json',timeoutMs:5000,allowedHosts:['api.streamable.com']});
        const media=JSON.parse(text);entry.lines=uniqueLines(['mp4','mp4-mobile'].map(key=>{
          const file=media.files?.[key],address=publicSourceUrl(file?.url,'https://streamable.com/');
          if(!address||!/(^|\.)streamable\.com$/i.test(new URL(address).hostname))return null;
          if(Number.isFinite(file.duration))entry.duration=file.duration;
          return highlightLine({link:address,title:file.height?`${file.height}p`:'Highlights'});
        }));
      }catch{entry.lines=[];}
    }
    entryCache.set(body.entry_id,entry);
  }
  if (action==='details') {
    if (!entry.links_checked_at || Date.now()-Date.parse(entry.links_checked_at)>300000) {
      const checks=await Promise.all(entry.lines.slice(0,8).map(async line=>{
        const link_check=await checkHighlightLine(line,{fetcher});
        return link_check.status==='reachable'?{...line,health_status:'reachable',link_check}:null;
      }));
      entry.lines=checks.filter(Boolean);
      entry.links_checked_at=new Date().toISOString();
    }
    return {ok:true,source:'highlights',provider,entry};
  }
  const line=entry.lines.find(item=>item.id===body.line_id);
  if (!line) throw Error('This video link changed. Reopen the highlight.');
  return {ok:true,source:'highlights',provider,check:await checkHighlightLine(line,{fetcher})};
}
