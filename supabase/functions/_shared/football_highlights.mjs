// Read-only, public highlight discovery. Website pages and HTTP reachability
// are never labelled as decoded/playable video. No page JS or login is run.
import {publicSourceUrl, readPublicSource} from './public_source_media.mjs';

export const highlightSources = [
  {id:'darkbyte',name:'DarkByte',url:'https://github.com/darkbyteprojects/iptv_png',mode:'feed'},
  {id:'dasfootball',name:'DasFootball',url:'https://dasfootball.com/',mode:'feed'},
  {id:'hoofoot',name:'Hoofoot',url:'https://hoofoot.net/',mode:'feed'},
  {id:'reddit',name:'Reddit',url:'https://www.reddit.com/r/footballhighlights/',mode:'feed'},
  {id:'soccerfullmatch',name:'SoccerFullMatch',url:'https://soccerfullmatch.com/',mode:'website'},
  {id:'scorebat',name:'ScoreBat',url:'https://www.scorebat.com/',mode:'website'},
];
const files = ['provider_2/categories/Fifa_Highlight.json',
  'provider_5/categories/FIFA_WC26_Highlights.json','provider_6/highlights.json'];
const rawBase = 'https://raw.githubusercontent.com/darkbyteprojects/iptv_png/main/';
const cache = new Map(), inFlight = new Map();
const clean = value => String(value || '').replace(/<[^>]*>/g,' ').replace(/&amp;/gi,'&')
  .replace(/&quot;/gi,'"').replace(/&#39;|&apos;/gi,"'").replace(/\s+/g,' ').trim();
const excluded = /\b(?:full\s*match|(?:1st|2nd|first|second)\s*half|extra\s*time|ceremony|half\s*time\s*show|interview|press\s*conference)\b/i;
const identity = value => clean(value).normalize('NFKD').toLowerCase()
  .replace(/\bversus\b|\bv\b\.?/g,'vs').replace(/[^a-z\d]+/g,' ').trim();
const sourceFor = id => highlightSources.find(source=>source.id===id);

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
function record(provider,title,page,extra={}) {
  return {id:provider+':'+(page || identity(title)),provider,title:clean(title).slice(0,240),
    source_page_url:publicSourceUrl(page),thumbnail_url:null,published_at:null,lines:[],...extra};
}
export function parseDarkbyteHighlights(path, rows) {
  if (!files.includes(path) || !Array.isArray(rows)) throw Error('Invalid highlights feed');
  const groups=new Map();
  for (const row of rows.slice(0,1000)) {
    if (!row || row.publish===0 || row.publish==='0' || row.visible===false) continue;
    if (path==='provider_6/highlights.json' && !/^(?:UCL|FIFA World Cup|UEFA Super Cup|Football|Soccer)$/i.test(clean(row.cat))) continue;
    const title=clean(row.title || row.name); if (!title || excluded.test(title)) continue;
    const original=[row.resolved_streams,row.streams,row.formats].find(items=>Array.isArray(items)&&items.some(x=>x&&typeof x==='object')) || [];
    const lines=uniqueLines(original.map(item=>highlightLine(item)));
    if (!lines.length) continue;
    const key=identity(title);
    const entry=groups.get(key) || record('darkbyte',title,null,{
      id:'darkbyte:'+key,source_page_url:'https://github.com/darkbyteprojects/iptv_png/blob/main/'+path,
      thumbnail_url:publicSourceUrl(row.image || row.logo || row.eventInfo?.eventBanner),
      // Event kickoff is not the highlight's upload time. Do not invent dates.
      source_files:[path],lines:[],
    });
    entry.lines=uniqueLines([...entry.lines,...lines]);groups.set(key,entry);
  }
  return [...groups.values()];
}
export function mergeHighlightEntries(entries) {
  const result=new Map(),lineOwners=new Map();
  for (const row of entries) {
    const key=row.provider==='darkbyte'?'darkbyte:'+identity(row.title):row.id;
    const shared=row.provider==='darkbyte'?(row.lines || []).map(line=>lineOwners.get(line.id)).find(Boolean):null;
    const previous=result.get(key) || shared;
    if (!previous) result.set(key,{...row,lines:uniqueLines(row.lines || [])});
    else {
      previous.lines=uniqueLines([...previous.lines,...(row.lines || [])]);
      previous.source_files=[...new Set([...(previous.source_files || []),...(row.source_files || [])])];
      previous.thumbnail_url ||= row.thumbnail_url;
    }
    const owner=previous || result.get(key);
    if (row.provider==='darkbyte') for(const line of owner.lines) lineOwners.set(line.id,owner);
  }
  return [...result.values()];
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
  return mergeHighlightEntries(structuredVideos(html).slice(0,150).map(video=>{
    const page=publicSourceUrl(video.url,'https://dasfootball.com/');
    if (!page || new URL(page).hostname!=='dasfootball.com' || !/highlights/i.test(new URL(page).pathname)) return null;
    const line=highlightLine({link:video.contentUrl || video.embedUrl,title:'Highlights'});
    const date=Date.parse(video.uploadDate || '');
    return record('dasfootball',video.name,page,{
      thumbnail_url:publicSourceUrl(Array.isArray(video.thumbnailUrl)?video.thumbnailUrl[0]:video.thumbnailUrl),
      published_at:Number.isFinite(date)?new Date(date).toISOString():null,lines:line?[line]:[],
    });
  }).filter(row=>row?.title));
}
export function parseHoofootHighlights(html) {
  const rows=[];
  for (const hit of html.matchAll(/<a\b([^>]*href=["'][^"']+["'][^>]*)>([\s\S]*?)<\/a>/gi)) {
    const href=hit[1].match(/\bhref=["']([^"']+)["']/i)?.[1];
    const page=publicSourceUrl(href,'https://hoofoot.net/');
    if (!page || new URL(page).hostname!=='hoofoot.net' || !/\/[^/]+-highlights-[^/]+\/?$/.test(new URL(page).pathname)) continue;
    const slug=new URL(page).pathname.split('/').filter(Boolean).pop().split('-highlights-')[0];
    const title=slug.replace(/-/g,' ').replace(/\b\w/g,c=>c.toUpperCase());
    const image=hit[2].match(/<img\b[^>]*(?:src|data-src)=["']([^"']+)["']/i)?.[1];
    rows.push(record('hoofoot',title,page,{thumbnail_url:publicSourceUrl(image,'https://hoofoot.net/')}));
  }
  return mergeHighlightEntries(rows).slice(0,100);
}
export function parseRedditHighlights(payload,subreddit) {
  if (!Array.isArray(payload?.data?.children)) throw Error('Invalid Reddit feed');
  return payload.data.children.flatMap(({data:post})=>{
    if (!post || post.over_18 || post.stickied || post.removed_by_category || excluded.test(post.title || '')) return [];
    if (subreddit==='soccer' && !/\b(?:goal|highlights?)\b|\[\d+\]|\d+\s*[-–]\s*\d+/i.test(post.title || '')) return [];
    const page=publicSourceUrl(post.permalink,'https://www.reddit.com/');
    if (!page || new URL(page).hostname!=='www.reddit.com' || !post.id) return [];
    const video=post.media?.reddit_video || post.secure_media?.reddit_video || post.crosspost_parent_list?.[0]?.media?.reddit_video;
    const direct=video?.hls_url || video?.fallback_url;
    const line=direct?highlightLine({link:direct,title:'Reddit video'}):null;
    const thumb=publicSourceUrl(post.thumbnail);
    const timestamp=Number(post.created_utc);
    return [record('reddit',post.title,page,{id:'reddit:'+String(post.id),thumbnail_url:thumb,
      published_at:timestamp>0?new Date(timestamp*1000).toISOString():null,lines:line?[line]:[],
      external_url:publicSourceUrl(post.url),subreddit})];
  });
}

async function read(url,fetcher,kind='json') {
  // GitHub Raw serves JSON files as text/plain; JSON.parse still validates the body.
  const readKind=kind==='json' && new URL(url).hostname==='raw.githubusercontent.com'?'text':kind;
  return readPublicSource(url,{fetcher,kind:readKind,timeoutMs:5500});
}
async function fetchCatalogue(provider,fetcher) {
  const failures=[];let entries=[];
  if (provider==='darkbyte') {
    const results=await Promise.allSettled(files.map(async path=>parseDarkbyteHighlights(path,
      JSON.parse((await read(rawBase+path,fetcher)).text))));
    for (const result of results) result.status==='fulfilled'?entries.push(...result.value):failures.push('One DarkByte highlights file is unavailable.');
    if (failures.length===files.length) throw Error('DarkByte highlights are unavailable.');
  } else if (provider==='dasfootball') entries=parseDasHighlights((await read('https://dasfootball.com/',fetcher,'html')).text);
  else if (provider==='hoofoot') entries=parseHoofootHighlights((await read('https://hoofoot.net/',fetcher,'html')).text);
  else if (provider==='reddit') {
    const results=await Promise.allSettled(['footballhighlights','soccer'].map(async sub=>parseRedditHighlights(
      JSON.parse((await read('https://www.reddit.com/r/'+sub+'/new.json?limit=100&raw_json=1',fetcher)).text),sub)));
    for (const result of results) result.status==='fulfilled'?entries.push(...result.value):failures.push('Reddit declined the public feed. Open Reddit to browse.');
    if (failures.length===2) throw Error('Reddit public feed is unavailable. Open Reddit to browse.');
  }
  return {entries:mergeHighlightEntries(entries),warnings:[...new Set(failures)],updated_at:new Date().toISOString()};
}
async function catalogue(provider,fetcher,force=false) {
  const previous=cache.get(provider);
  if (!force && previous && Date.now()-Date.parse(previous.updated_at)<300000) return previous;
  if (inFlight.has(provider)) return inFlight.get(provider);
  const work=fetchCatalogue(provider,fetcher).then(data=>{cache.set(provider,data);return data;}).catch(error=>
    previous?{...previous,stale:true,warnings:[clean(error.message)]}:
      {entries:[],updated_at:null,unavailable:true,warnings:[clean(error.message)]});
  inFlight.set(provider,work);
  try {return await work;}
  finally {if (inFlight.get(provider)===work) inFlight.delete(provider);}
}

async function details(entry,fetcher) {
  if (entry.provider!=='hoofoot' && entry.provider!=='dasfootball') return entry;
  const {text}=await read(entry.source_page_url,fetcher,'html');
  if (entry.provider==='dasfootball') {
    const found=parseDasHighlights(text).find(row=>row.source_page_url===entry.source_page_url);
    return found?{...entry,...found}:entry;
  }
  const lines=[];const tabs=[...text.matchAll(/<button\b[^>]*data-token=["']([^"']+)["'][^>]*>([\s\S]*?)<\/button>/gi)]
    .filter(hit=>!excluded.test(clean(hit[2]))).slice(0,5);
  let failures=0;
  await Promise.all(tabs.map(async hit=>{
    try {
      const token=hit[1],label=clean(hit[2]) || 'Highlights';
      let media;
      if (/^r2:[a-z\d_-]{1,80}$/i.test(token)) {
        const base='https://cdn.dailyvid.click/videos/'+token.slice(3)+'/';
        const data=JSON.parse((await read(base+'index.json',fetcher)).text);
        // Use only the ordinary public index. Encrypted/custom formats remain website-only.
        if (data.type==='hls') {
          const path=data.master || 'master.m3u8';
          if (/^[\w.-]+\.m3u8$/.test(path)) media=base+path;
        }
      } else if (token.length<4096) {
        const data=JSON.parse((await read('https://hoofoot.net/api/resolve?v='+encodeURIComponent(token),fetcher)).text);
        if (data.type==='mp4' || data.type==='m3u8') media=data.url;
      }
      const line=highlightLine({link:media,title:label,referer:entry.source_page_url,origin:'https://hoofoot.net'});
      if (line) lines.push(line);
    } catch (_) {failures++;}
  }));
  return {...entry,lines:uniqueLines(lines),detail_warning:failures?'Some Hoofoot media could not be resolved. Open the original player.':
    lines.length?null:'This highlight currently uses the original website player.'};
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
  const provider=String(body.provider || 'darkbyte');const source=sourceFor(provider);
  if (!source) throw Error('Unsupported highlights provider');
  const action=String(body.action || 'catalog');
  if (!['catalog','details','check'].includes(action)) throw Error('Unsupported highlights action');
  const data=source.mode==='website'?{entries:[],warnings:['Open this source website to browse highlights.'],updated_at:null}:
    await catalogue(provider,fetcher,body.force===true);
  if (action==='catalog') return {ok:true,source:'highlights',provider,sources:highlightSources,...data,total:data.entries.length};
  const original=data.entries.find(row=>row.id===body.entry_id);
  if (!original) throw Error('This highlight is no longer in the source. Refresh the list.');
  const entry=await details(original,fetcher);
  if (action==='details') return {ok:true,source:'highlights',provider,entry};
  const line=entry.lines.find(item=>item.id===body.line_id);
  if (!line) throw Error('This video link changed. Reopen the highlight.');
  return {ok:true,source:'highlights',provider,check:await checkHighlightLine(line,{fetcher})};
}
