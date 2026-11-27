// Direct-link extraction only. No embedded websites or video player adapters.
import {publicSourceUrl, readPublicSource} from './public_source_media.mjs';

export const highlightSources = [
  {id:'dasfootball',name:'DasFootball',url:'https://dasfootball.com/',mode:'feed'},
];
const cache = new Map(), inFlight = new Map(), entryCache=new Map(), searchCache=new Map();
const normalCacheKey = (id, admin) => admin ? 'admin-normal|'+id : id;
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
function structuredRecords(html,type) {
  const records=[];
  function visit(value,depth=0) {
    if (!value || typeof value!=='object' || depth>12) return;
    if (Array.isArray(value)) {for (const item of value) visit(item,depth+1);return;}
    if (value['@type']===type) records.push(value);
    for (const key of ['@graph','itemListElement','item','video','subjectOf']) visit(value[key],depth+1);
  }
  for (const hit of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {visit(JSON.parse(hit[1]));} catch (_) { /* An unrelated invalid schema must not hide other videos. */ }
  }
  return records;
}
const structuredVideos=html=>structuredRecords(html,'VideoObject');
function streamableId(value){
 const address=publicSourceUrl(value);if(!address)return null;
 const url=new URL(address);if(url.protocol!=='https:'||!['streamable.com','www.streamable.com'].includes(url.hostname))return null;
 return url.pathname.match(/^\/(?:e\/)?([a-zA-Z0-9]{3,32})\/?$/)?.[1]||null;
}
function streamableMp4Id(value){
 const url=new URL(value);
 return url.protocol==='https:'&&/(^|\.)streamable\.com$/i.test(url.hostname)
  ? url.pathname.match(/^\/video\/mp4(?:-mobile)?\/([a-zA-Z0-9]{3,32})\.mp4$/)?.[1] : null;
}
async function streamableQualityLines(id,fetcher){
 const {text}=await readPublicSource('https://api.streamable.com/videos/'+id,{
  fetcher,kind:'json',timeoutMs:2200,allowedHosts:['api.streamable.com']});
 const files=JSON.parse(text).files;
 const lines=['mp4','mp4-mobile'].map(variant=>{
  const file=files?.[variant],address=publicSourceUrl(file?.url,'https://streamable.com/');
  if(!address||streamableMp4Id(address)!==id)return null;
  const resolution=Number.isInteger(file.height)&&file.height>0 ? file.height+'p' : null;
  const line=highlightLine({link:address,title:resolution||'Highlights'});
  return line&&{...line,id:'streamable:'+id+':'+variant,resolution};
 }).filter(Boolean);
 return [...new Map(lines.map(line=>[line.stream_url,line])).values()];
}
async function resolveNormalQualities(lines,fetcher){
 const clips=new Map();
 for(const line of lines){
  const id=streamableMp4Id(line.stream_url);
  if(id&&!clips.has(id))clips.set(id,line);
 }
 const replacements=new Map(await Promise.all([...clips].slice(0,4).map(async ([id,line])=>{
  const qualities=await streamableQualityLines(id,fetcher).catch(()=>[]);
  return [line.id,qualities.length?qualities.map(quality=>({...quality,source_page_url:line.source_page_url})): [line]];
 })));
 return uniqueLines(lines.flatMap(line=>replacements.get(line.id)||[line]));
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
// Normal match pages support metadata and public MP4 records.
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
function htmlAttribute(tag,name){
  const match=tag.match(new RegExp('(?:^|\\s)'+name+'\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')','i'));
  return match?.[1]??match?.[2];
}
function normalPanelVideoUrls(visible,page){
  const panels=new Set();
  for(const [,tag,label] of visible.matchAll(/(<button\b[^>]*>)([\s\S]*?)<\/button>/gi)){
    if(htmlAttribute(tag,'role')!=='tab'||!normalLabel(label))continue;
    const id=htmlAttribute(tag,'aria-controls');
    if(id)panels.add(id);
  }
  const urls=[];
  let depth=0;
  for(const [tag] of visible.matchAll(/<\/?div\b[^>]*>|<(?:video|source)\b[^>]*>/gi)){
    if(/^<\/div/i.test(tag)){if(depth>0)depth--;continue;}
    if(/^<div/i.test(tag)){
      if(depth>0)depth++;
      else if(htmlAttribute(tag,'role')==='tabpanel'&&panels.has(htmlAttribute(tag,'id')))depth=1;
      continue;
    }
    if(depth===0)continue;
    const src=htmlAttribute(tag,'src');
    const url=src&&publicSourceUrl(clean(src),page);
    if(url)urls.push(url);
    if(urls.length>=8)break;
  }
  return urls;
}

// A match with a single Highlights player can publish its direct URL in
// JSON-LD and leave the rendered video tag's src empty until Play is pressed.
function singlePlayerFixtureName(html,visible,page){
  for(const [,tag,section] of visible.matchAll(/(<section\b[^>]*>)([\s\S]*?)<\/section>/gi)){
    if(htmlAttribute(tag,'id')!=='highlights'||/<[^>]*\brole=["']tab(?:list|panel)?["']/i.test(section)||
       !/<video\b/i.test(section)||excluded.test(clean(section)))continue;
    const headingId=htmlAttribute(tag,'aria-labelledby');
    const hasHeading=[...section.matchAll(/(<h[1-6]\b[^>]*>)([\s\S]*?)<\/h[1-6]>/gi)]
      .some(([,heading,label])=>headingId&&headingId===htmlAttribute(heading,'id')&&normalLabel(label));
    if(!hasHeading)continue;
    const event=structuredRecords(html,'SportsEvent').find(event=>matchPage(event.url)===page);
    return clean(event?.name);
  }
  return '';
}

// Admin can inspect direct Normal Highlights MP4 URLs published on the source page.
export function licensedNormalMp4(html,page,{allowPublisherMp4=false,normalPanelUrls=[],singlePlayerName=''}={}){
  const source=matchPage(page);
  if(!source)return [];
  const urls=new Set(allowPublisherMp4?normalPanelUrls:[]);
  const blocked=new Set();
  const singlePlayerUrls=new Set();
  for(const video of structuredVideos(html)){
    const url=publicSourceUrl(video.contentUrl);
    if(!url)continue;
    if(video.isAccessibleForFree===false||video.requiresSubscription===true||
       video.drm||video.drm_key||video.drm_scheme||video.key_data||video.key_id||excluded.test(clean(video.name))){
      blocked.add(url);
      continue;
    }
    if(video.url&&matchPage(video.url)!==source)continue;
    if(!normalLabel(video.name)){
      const label=clean(video.name);
      if(allowPublisherMp4&&singlePlayerName&&/\s+highlights?$/i.test(label)&&
         label.replace(/\s+highlights?$/i,'').toLowerCase()===singlePlayerName.toLowerCase())singlePlayerUrls.add(url);
      continue;
    }
    if(!allowPublisherMp4&&(video.isAccessibleForFree!==true||
       !/^https:\/\/creativecommons\.org\/(?:licenses|publicdomain)\//i.test(video.license||'')))continue;
    const media=new URL(url);
    if(!allowPublisherMp4&&(media.origin!==new URL(source).origin||media.search))continue;
    urls.add(url);
  }
  if(singlePlayerUrls.size===1)urls.add(singlePlayerUrls.values().next().value);
  const lines=[];
  for(const url of urls){
    if(blocked.has(url))continue;
    const line=highlightLine({link:url,title:'Normal Highlights'});
    if(line?.stream_type==='mp4')lines.push({...line,source_page_url:source});
  }
  return uniqueLines(lines);
}

export function publicNormalMatchMetadata(html,page,options){
  page=matchPage(page);if(!page)return null;
  const visible=html.replace(/<script\b[\s\S]*?<\/script>/gi,'').replace(/<style\b[\s\S]*?<\/style>/gi,'');
  // A finished fixture alone does not establish Normal HL availability.
  const normal=[...visible.matchAll(/<(button|a)\b[^>]*>([\s\S]*?)<\/\1>/gi)].some(hit=>normalLabel(hit[2])) ||
    [...visible.matchAll(/\b(?:aria-label|title)\s*=\s*["']([^"']+)["']/gi)].some(hit=>normalLabel(hit[1]));
  const singlePlayerName=options?.allowPublisherMp4 ? singlePlayerFixtureName(html,visible,page) : '';
  if(!normal&&!singlePlayerName)return null;
  const match=new URL(page).pathname.match(/^\/match\/(.+)-(\d{4}-\d{2}-\d{2})-\d+\/$/i);
  const rawTitle=clean(visible.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i)?.[1]||'')
    .replace(/\s*(?:[|–—-]\s*DasFootball.*|\bHighlights(?:\s+and\s+Goals)?\b.*)$/i,'').trim();
  const title=/\bvs\.?\b/i.test(rawTitle)?rawTitle:match[1].replace(/-/g,' ').replace(/\b\w/g,c=>c.toUpperCase()).replace(/\bVs\b/,'vs');
  // Match date is distinct from a verified upload time.
  const normalPanelUrls=options?.allowPublisherMp4 ? normalPanelVideoUrls(visible,page) : [];
  const lines=licensedNormalMp4(html,page,{...options,normalPanelUrls,singlePlayerName});
  return {id:'dasfootball:'+page,provider:'dasfootball',title:title.slice(0,240),
    source_page_url:page,match_date:match[2],published_at:null,
    highlight_variant:'normal',source_page_only:lines.length===0,lines};
}
async function discoverNormalMatchPages(fetcher,query='',deadline=Date.now()+5500){
  const remaining=()=>Math.max(0,deadline-Date.now());
  if(remaining()<100)return [];
  const {text}=await readPublicSource('https://dasfootball.com/',{fetcher,kind:'html',timeoutMs:Math.min(1800,remaining()),allowedHosts:['dasfootball.com']});
  const words=query.toLowerCase().split(/\s+/).filter(Boolean);
  const pages=publicNormalMatchCandidates(text).filter(page=>words.every(word=>page.toLowerCase().includes(word))).slice(0,6);
  if(remaining()<100)return [];
  const rows=await Promise.all(pages.map(async page=>{
    try{
      const {text}=await readPublicSource(page,{fetcher,kind:'html',timeoutMs:Math.min(2200,remaining()),allowedHosts:['dasfootball.com']});
      return publicNormalMatchMetadata(text,page);
    }catch{return null;}
  }));
  return rows.filter(Boolean).sort((a,b)=>b.match_date.localeCompare(a.match_date));
}

// Dated pages expose a public Schema.org ItemList of highlighted fixtures.
// Legacy catalogue and its cursor stay intact.
export function parseDateHighlightMetadata(html,{now=Date.now()}={}){
  const rows=new Map();
  const record=video=>{
    if(video?.['@type']!=='VideoObject')return;
    const page=matchPage(video.url);
    const label=clean(video.name);
    if(!page||excluded.test(label)||!/\s+highlights?$/i.test(label))return;
    const title=label.replace(/\s+highlights?$/i,'').trim();
    if(!title||!/\s+vs\.?\s+/i.test(title))return;
    const parts=new URL(page).pathname.match(/-(\d{4}-\d{2}-\d{2})-(\d+)\/$/);
    if(!parts)return;
    const stamp=Date.parse(video.uploadDate||'');
    if(!Number.isFinite(stamp)||stamp>now)return;
    const about=Array.isArray(video.about)?video.about:[];
    const teams=about.filter(x=>x?.['@type']==='SportsTeam').map(x=>clean(x.name)).filter(Boolean);
    const description=clean(video.description);
    const league=description.match(/\bhighlights\s*,\s*([^,]{1,100})$/i)?.[1]?.trim()||null;
    const row={id:'dasfootball:'+page,provider:'dasfootball',title:title.slice(0,240),
      source_page_url:page,match_date:parts[1],match_id:parts[2],
      published_at:new Date(stamp).toISOString(),league,
      ...(teams.length===2?{home_team:teams[0],away_team:teams[1]}:{}),
      thumbnail_url:publicSourceUrl(Array.isArray(video.thumbnailUrl)?video.thumbnailUrl[0]:video.thumbnailUrl),
      highlight_variant:'normal',source_page_only:true,lines:[]};
    const old=rows.get(row.match_id);
    if(!old||old.published_at<row.published_at)rows.set(row.match_id,row);
  };
  function visit(value,depth=0){
    if(!value||typeof value!=='object'||depth>8||rows.size>=100)return;
    if(Array.isArray(value)){for(const item of value.slice(0,150))visit(item,depth+1);return;}
    if(value['@type']==='ItemList'&&/\bfootball highlights\b/i.test(clean(value.name))){
      if(Array.isArray(value.itemListElement))for(const item of value.itemListElement.slice(0,100)){
        record(item?.['@type']==='ListItem'?item.item:item);
      }
    }
    if(value['@graph'])visit(value['@graph'],depth+1);
  }
  for(const hit of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)){
    try{visit(JSON.parse(hit[1]));}catch{/* unrelated or invalid schema */}
  }
  return [...rows.values()].sort((a,b)=>b.published_at.localeCompare(a.published_at));
}
const dailyMetadataCache=new Map(),dailyMetadataFlights=new Map();
const myanmarDay=time=>new Date(time+390*60000).toISOString().slice(0,10);
function recentAdminHighlights(data,dates,now,query){
 const entries=data.entries.filter(row=>{
  const stamp=Date.parse(row.published_at||'');
  return Number.isFinite(stamp) ? stamp<=now&&dates.includes(myanmarDay(stamp)) : dates.includes(row.match_date);
 });
 const freshness=highlightCatalogueFreshness(entries,now);
 return {...data,entries,window_days:dates.length,
  ...(!query ? {latest_published_at:freshness.latest_published_at,publisher_age_hours:freshness.publisher_age_hours} : {}),
  has_more:Boolean(data.has_more&&(entries.length||query)&&!data.unavailable)};
}
async function dateMetadataPage(date,fetcher,force,now){
  const previous=dailyMetadataCache.get(date);
  if(!force&&previous&&now-previous.time<300000)return {...previous,stale:false};
  if(dailyMetadataFlights.has(date))return dailyMetadataFlights.get(date);
  const task=(async()=>{
    try{
      const {text}=await readPublicSource('https://dasfootball.com/?date='+date,
        {fetcher,kind:'html',timeoutMs:3000,allowedHosts:['dasfootball.com']});
      const rows=parseDateHighlightMetadata(text,{now});
      if(!rows.length&&previous?.rows.length)return {...previous,stale:true};
      const result={rows,time:now,stale:false};
      dailyMetadataCache.set(date,result);
      while(dailyMetadataCache.size>8)dailyMetadataCache.delete(dailyMetadataCache.keys().next().value);
      return result;
    }catch{return previous?{...previous,stale:true}:{rows:[],stale:true};}
  })();
  dailyMetadataFlights.set(date,task);
  try{return await task;}finally{if(dailyMetadataFlights.get(date)===task)dailyMetadataFlights.delete(date);}
}
async function adminDateCatalogue(fetcher,force,{offset,query,now}){
  // Date pages and old feed are fetched concurrently, not sequentially.
  // UTC+06:30 calendar matches the Admin's reported dated-page convention.
  const dates=[0,1,2].map(delta=>myanmarDay(now-delta*86400000));
  // The publisher groups fixtures by match date. Its previous date page
  // can contain the earliest Myanmar day's overnight match highlights.
  const sourceDates=[...dates,myanmarDay(now-3*86400000)];
  const recent=data=>recentAdminHighlights(data,dates,now,query);
  if(offset!==0)return recent(await catalogue(fetcher,force,{offset,query}));
  const [legacy,...pages]=await Promise.all([
    catalogue(fetcher,force,{offset,query}).then(recent),
    ...sourceDates.map(date=>dateMetadataPage(date,fetcher,force,now)),
  ]);
  const words=query.toLowerCase().split(/\s+/).filter(Boolean);
  const matches=new Map();
  for(const row of pages.flatMap(p=>p.rows)){
    if(!dates.includes(myanmarDay(Date.parse(row.published_at))))continue;
    if(!words.every(word=>row.title.toLowerCase().includes(word)))continue;
    const old=matches.get(row.match_id);
    if(!old||old.published_at<row.published_at)matches.set(row.match_id,row);
  }
  const modern=[...matches.values()].sort((a,b)=>b.published_at.localeCompare(a.published_at));
  if(!modern.length){
    if (offset === 0 && (legacy.unavailable || !legacy.entries.length ||
        (!query && (legacy.publisher_age_hours === null || legacy.publisher_age_hours >= 36)))) {
      const fallback=await catalogue(fetcher,force,{offset,query,includeNormal:true,legacy});
      return recent({...fallback,stale:Boolean(fallback.stale||pages.every(page=>page.stale))});
    }
    return legacy;
  }
  for(const row of modern)entryCache.set(normalCacheKey(row.id,true),row);
  // Deduplicate old article and new match metadata only on title AND fixture date.
  // Keep old entry (and its existing links) when the same fixture is already present.
  const key=(title,date)=>clean(title).toLowerCase().replace(/[^a-z0-9]+/g,'')+'|'+date;
  const oldFixtures=new Set(legacy.entries.map(row=>{
    const date=new URL(row.source_page_url).pathname.match(/-(\d{4}-\d{2}-\d{2})\/?$/)?.[1];
    return key(row.title,date||'');
  }));
  const entries=[...modern.filter(row=>!oldFixtures.has(key(row.title,row.match_date))),...legacy.entries]
    .sort((a,b)=>(Date.parse(b.published_at||'')||0)-(Date.parse(a.published_at||'')||0));
  const freshness=highlightCatalogueFreshness(entries,now);
  const warnings=[...freshness.warnings];
  if(legacy.unavailable||legacy.stale)warnings.push('Legacy catalogue refresh incomplete.');
  if(pages.some(p=>p.stale))warnings.push('One or more date pages could not be refreshed; cached metadata retained when available.');
  return recent({...legacy,...freshness,entries,warnings,unavailable:false,
    stale:Boolean(legacy.unavailable||legacy.stale||pages.some(p=>p.stale)),
    updated_at:pages.some(p=>!p.stale)?new Date(now).toISOString():legacy.updated_at});
}

async function catalogue(fetcher,force=false,{offset=0,query='',includeNormal=false,legacy=null}={}) {
  const prefix=(includeNormal?'admin|':'public|')+encodeURIComponent(query)+'|';
  const key=prefix+offset,previous=cache.get(key);
  if (!force && previous && Date.now()-Date.parse(previous.updated_at)<300000) return previous;
  if (inFlight.has(key)) return inFlight.get(key);
  const work=(async()=>{
    try {
      const useFallback=includeNormal&&offset===0;
      const deadline=Date.now()+6000;
      const timeoutMs=useFallback?3000:5500;
      let cards=[],hasMore=false,nextOffset=offset,legacyError;
      try {
        if(legacy){
          if(legacy.unavailable)throw Error(legacy.warnings?.[0]||'Legacy catalogue unavailable');
          hasMore=legacy.has_more;nextOffset=legacy.next_offset;
        }else if(query){
          let found=searchCache.get(query);
          if(force||!found||Date.now()-found.time>300000){
            const {text}=await readPublicSource('https://dasfootball.com/api/search/?q='+encodeURIComponent(query),{fetcher,kind:'json',timeoutMs,allowedHosts:['dasfootball.com']});
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
          const {text}=await readPublicSource('https://dasfootball.com/api/homepage-posts/?offset='+offset,{fetcher,kind:'json',timeoutMs,allowedHosts:['dasfootball.com']});
          const payload=JSON.parse(text);if(!Array.isArray(payload.cards)||typeof payload.hasMore!=='boolean')throw Error('Invalid highlights catalogue');
          cards=payload.cards;nextOffset=offset+cards.length;hasMore=payload.hasMore&&cards.length>0;
        }
      } catch(error) {
        if(!useFallback)throw error;
        legacyError=error;
      }
      const legacyEntries=legacy?.entries||[...new Map(cards.map(card=>cardEntry(card,force)).filter(Boolean).map(e=>[e.id,e])).values()];
      const freshness=!query&&offset===0?highlightCatalogueFreshness(legacyEntries):{warnings:[]};
      let normal=[];
      let fallbackFailed=false;
      if(useFallback&&(!legacyEntries.length||(!query&&(freshness.publisher_age_hours===null||freshness.publisher_age_hours>=36)))){
        try {
          normal=await discoverNormalMatchPages(fetcher,query,deadline);
        } catch {
          fallbackFailed=true;
        }
        // A partial discovery can omit a previously verified match. Keep
        // those cards while the main publisher catalogue is still stale.
        const previousNormal=(previous?.entries||[]).filter(row=>row.highlight_variant==='normal');
        const newestLegacyDate=freshness.latest_published_at?.slice(0,10);
        normal=[...new Map([...previousNormal,...normal].filter(row=>
          !newestLegacyDate||row.match_date>=newestLegacyDate).map(row=>[row.id,row])).values()]
          .sort((a,b)=>b.match_date.localeCompare(a.match_date)).slice(0,12);
        for(const row of normal)entryCache.set(row.id,row);
      }
      if(legacyError&&!normal.length)throw legacyError;
      if(!legacyEntries.length&&previous?.entries?.length){
        const entries=[...new Map([...previous.entries,...normal].map(row=>[row.id,row])).values()];
        const warning=legacyError?'Source refresh incomplete; retaining the last successful catalogue.':
          'Source returned an empty page; retaining the last successful catalogue.';
        return {...previous,entries,stale:true,warnings:[...new Set([...(previous.warnings||[]),warning])]};
      }
      if(normal.length)freshness.warnings.push('Normal HL match pages show match dates. Upload times and playback may be unverified.');
      if(fallbackFailed)freshness.warnings.push('Normal HL match pages could not be refreshed.');
      const entries=[...normal,...legacyEntries];
      const data={entries,...freshness,updated_at:new Date().toISOString(),has_more:hasMore&&nextOffset<5000,next_offset:nextOffset};
      if(legacyError||fallbackFailed)data.stale=true;
      // Invalidate subsequent cursors only after the first-page refresh succeeds.
      // A failed refresh must not erase the last known catalogue.
      if(force && offset===0) {
        for(const cachedKey of cache.keys())if(cachedKey.startsWith(prefix))cache.delete(cachedKey);
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

export async function footballHighlights(body,{fetcher=fetch,includeDateCatalogue=false,includeNormal=includeDateCatalogue,now=Date.now()}={}) {
  const provider=String(body.provider || 'dasfootball');
  if (provider!=='dasfootball') throw Error('Unsupported highlights provider');
  const action=String(body.action || 'catalog');
  if (!['catalog','details','check'].includes(action)) throw Error('Unsupported highlights action');
  if (action==='catalog') {
    const offset=Number(body.offset??0),query=clean(body.query).slice(0,80);
    if(!Number.isInteger(offset)||offset<0||offset>5000)throw Error('Invalid highlights offset');
    const data=includeDateCatalogue
      ? await adminDateCatalogue(fetcher,body.force===true,{offset,query,now})
      : await catalogue(fetcher,body.force===true,{offset,query,includeNormal});
    const entries=data.entries;
    return {ok:true,source:'highlights',provider,sources:highlightSources,...data,entries,total:entries.length};
  }
  const page=typeof body.entry_id==='string'&&body.entry_id.startsWith('dasfootball:')?publicSourceUrl(body.entry_id.slice(12)):null;
  const modernPage=matchPage(page);
  if(modernPage){
    const id='dasfootball:'+modernPage;
    const cacheKey=normalCacheKey(id,includeDateCatalogue);
    let entry=entryCache.get(cacheKey);
    const checked=Date.parse(entry?.links_checked_at||'');
    if(body.force===true||!entry||!Number.isFinite(checked)||Date.now()-checked>=300000){
      let fresh=null;
      try{
        const {text}=await readPublicSource(modernPage,{fetcher,kind:'html',timeoutMs:3500,allowedHosts:['dasfootball.com']});
        fresh=publicNormalMatchMetadata(text,modernPage,{allowPublisherMp4:includeDateCatalogue});
      }catch{/* Keep known fixture metadata if page fetch fails. */}
      if(!entry&&!fresh){
        // A cold isolate can lack the catalogue entry. An unavailable source
        // must not become a fabricated or cached media link.
        if(action!=='details')throw Error('Normal highlights were not confirmed by this page');
        const fixture=new URL(modernPage).pathname.match(/^\/match\/(.+)-(\d{4}-\d{2}-\d{2})-\d+\/$/i);
        const title=fixture[1].replace(/-/g,' ').replace(/\b\w/g,c=>c.toUpperCase()).replace(/\bVs\b/,'vs');
        console.warn('Highlights details unavailable: source metadata could not be confirmed');
        return {ok:true,source:'highlights',provider,entry:{
          id,provider,title:title.slice(0,240),source_page_url:modernPage,
          match_date:fixture[2],published_at:null,source_page_only:true,
          lines:[],details_status:'unavailable'
        }};
      }
      const lines=includeDateCatalogue&&fresh?.lines.length
        ? await resolveNormalQualities(fresh.lines,fetcher) : fresh?.lines||[];
      entry={...fresh,...entry,id,source_page_url:modernPage,
        source_page_only:lines.length===0,lines,links_checked_at:fresh?new Date().toISOString():null};
      entryCache.set(cacheKey,entry);
    }
    if(action==='check'){
      const line=entry.lines.find(item=>item.id===body.line_id);
      if(!line)throw Error('No authorized MP4 link found for this entry');
      const mediaFetch=async(url,options)=>{
        const valid=publicSourceUrl(url);
        if(!valid)throw Error('Invalid media URL');
        return fetcher(valid,options);
      };
      return {ok:true,source:'highlights',provider,check:await checkHighlightLine(line,{fetcher:mediaFetch})};
    }
    return {ok:true,source:'highlights',provider,entry};
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
