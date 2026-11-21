// Read only committed JSON exports. Never run publisher tools or token APIs.
export const NEW_GITHUB_SOURCES=[
 {repository:'nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync',key:'smiptv',provider:9,name:'SM IPTV'},
 {repository:'dilzyking/allrounderlive',key:'allrounder',provider:10,name:'Allrounder Live'},
 {repository:'sm-monirulislam/Upcoming-and-Live-Sports-Data',key:'smsports',provider:11,name:'SM Sports Data'},
 {repository:'mdjamsad9/dudetvapi',key:'dudetv',provider:12,name:'DudeTV'},
];
export const LEGACY_GITHUB_SOURCES=[
 {repository:'Roshavarma/cfy',key:'cfy',provider:13,name:'CFY'},
 {repository:'rohmanabdu/lian',key:'lian',provider:14,name:'Lian'},
 {repository:'rohmanabdu/deqiaa',key:'deqiaa',provider:15,name:'Deqiaa'},
];
export const HUB_GITHUB_SOURCES=[...NEW_GITHUB_SOURCES,...LEGACY_GITHUB_SOURCES];
const clean=x=>String(x??'').replace(/[\u0000-\u001f\u007f]/g,' ').trim();
const list=x=>Array.isArray(x)?x:[];
export function publishedEventMeta(row){
 const e=row.eventInfo||{};
 const name=value=>clean(value&&typeof value==='object'?value.name:value);
 const utc=value=>{const text=clean(value).replace(/^(\d{4})\/(\d{2})\/(\d{2})/,'$1-$2-$3');
  const ms=/(?:Z|[+-]\d{2}:?\d{2})$/i.test(text)?Date.parse(text):NaN;return Number.isFinite(ms)?new Date(ms).toISOString():null;};
 return {home_team:name(row.teamA||e.teamA)||null,away_team:name(row.teamB||e.teamB)||null,
  home_logo_url:clean(row.teamA?.logo||e.teamAFlag)||null,away_logo_url:clean(row.teamB?.logo||e.teamBFlag)||null,
  unclassified_sports:row.unclassified_sports===true,
  league:clean(e.eventName||row.eventName)||null,source_category:clean(e.eventCat||row.category||row.cat)||null,
  source_status:clean(row.status||row.channel_status)||null,source_time:clean(e.startTime||row.startTime||[row.date,row.time].filter(Boolean).join(' '))||null,
  kickoff_at:utc(e.startTime||row.startTime),end_at:utc(e.endTime||row.endTime),source_civil_date:e.sourceCivilDate||null};
}
function media(row){
 if(!row||typeof row!=='object')return null;
 const drm=row.drm||{},kid=row.kid||row.key_id||drm.kid||drm.key_id||drm.keyId;
 const key=row.key_data||drm.key||drm.key_data||(kid?row.key:null);
 const pair=kid&&key?`${kid}:${key}`:row.api||row.clearKey||row.key;
 return {...row,title:row.title||row.name||row.channel_name||'Line',
  link:row.link||row.stream_url||row.url,
  api:typeof pair==='string'&&/^[a-f\d]{32}:[a-f\d]{32}$/i.test(pair)?pair:null,
  referer:row.referer||row.headers?.Referer||row.headers?.referer,
  origin:row.origin||row.headers?.Origin||row.headers?.origin};
}
function event(row,eventInfo,streams,category){
 return {...row,eventInfo,cat:category||eventInfo.eventCat||row.cat||row.category,
  resolved_streams:streams.map(media).filter(Boolean)};
}
export function normalizeGithubDocument(repository,path,payload,channels=new Map()){
 const source=HUB_GITHUB_SOURCES.find(x=>x.repository===repository);
 if(!source)throw Error('Unsupported connected GitHub source');
 if(['cfy','lian','deqiaa'].includes(source.key)){
  if(payload?._m3u){
   const rows=[];let row;
   for(const raw of payload._m3u.split(/\r?\n/)){
    const line=raw.trim();
    if(line.startsWith('#EXTINF:'))row={title:line.slice(line.indexOf(',')+1),cat:line.match(/group-title="([^"]*)"/i)?.[1]||'Sports',image:line.match(/tvg-logo="([^"]*)"/i)?.[1]};
    else if(row&&/^#KODIPROP:.*license_key=/i.test(line))row.api=line.slice(line.indexOf('=')+1);
    else if(row&&/^#EXTVLCOPT:http-referr?er=/i.test(line))row.referer=line.slice(line.indexOf('=')+1);
    else if(row&&line&&!line.startsWith('#')){
     const pair=row.title.match(/^(.+?)\s+(?:vs\.?|v\.?|versus)\s+(.+?)(?:\s+[-•]\s+.+)?$/i);
     rows.push({...row,resolved_streams:[media({...row,link:line})],...(pair?{eventInfo:{teamA:pair[1],teamB:pair[2],eventName:row.cat,eventCat:row.cat}}:{})});row=null;
    }
   }
   return rows;
  }
  const rows=[];
  const visit=value=>{
   if(Array.isArray(value)){value.forEach(visit);return;}
   if(!value||typeof value!=='object')return;
   if(value.teamA&&value.teamB||value.eventInfo?.teamA&&value.eventInfo?.teamB){
    rows.push(event(value,value.eventInfo||{teamA:value.teamA?.name||value.teamA,teamB:value.teamB?.name||value.teamB,eventCat:value.category,eventName:value.eventName},
     [value.resolved_streams,value.streams,value.channels_data,value.formats].find(x=>Array.isArray(x)&&x.length)||[],value.cat||value.category));return;
   }
   if(value.title&&(value.link||value.stream_url||value.url)){rows.push({...value,resolved_streams:[media(value)]});return;}
   Object.values(value).filter(x=>x&&typeof x==='object').forEach(visit);
  };visit(payload);return rows;
 }
 if(source.key==='smiptv'){
  if(!Array.isArray(payload?.channels))throw Error('Invalid SM IPTV channel export');
  return payload.channels.map(row=>{
   const title=clean(row.name),streams=list(row.servers).map(media).filter(Boolean);
   const match=title.replace(/^\[live\]\s*/i,'').match(/^(.+?)\s+(?:vs\.?|v\.?|versus)\s+(.+?)(?:\s+[-•]\s+.+)?$/i);
   return {...row,title,image:row.logo,cat:row.category,resolved_streams:streams,
    ...(match&&/live.?sports/i.test(row.category)?{eventInfo:{teamA:match[1],teamB:match[2],eventName:'Live Sports'},unclassified_sports:true}:{})};
  });
 }
 if(source.key==='allrounder'){
  if(!Array.isArray(payload))throw Error('Invalid Allrounder export');
  return payload.map(row=>event(row,{...row.event,eventCat:row.event?.category||row.cat,
   eventName:row.event?.name||row.title,startTime:row.event?.startTimeUTC,endTime:row.event?.endTimeUTC},list(row.dashStreams),row.cat));
 }
 if(source.key==='smsports'){
  if(!Array.isArray(payload?.matches))throw Error('Invalid SM Sports export');
  return payload.matches.map(row=>{
   const raw=row.eventInfo?.startTime||'',date=raw.match(/^(\d{2})\/(\d{2})\/(\d{4})\b/);
   const civil=date?`${date[3]}-${date[2]}-${date[1]}`:null;
   return event({...row,title:row.event_name},
    {...row.eventInfo,eventCat:row.Category,sourceCivilDate:civil,sourceTime:raw},list(row.streams),row.Category);
  });
 }
 if(!Array.isArray(payload))throw Error('Invalid DudeTV export');
 return payload.map(row=>{
  const decoded=row.decoded_channels||channels.get(String(row.id));
  const streams=list(decoded).length?list(decoded):list(row.formats).filter(x=>x&&typeof x==='object');
  return event(row,row.eventInfo||{},streams,row.cat);
 });
}
export async function readGithubDocuments(repository,tree,{fetcher=fetch,signal,fixturesOnly=false}={}){
 const source=HUB_GITHUB_SOURCES.find(x=>x.repository===repository);
 if(!source||!tree||tree.truncated||!/^[a-f\d]{40}$/.test(tree.sha||''))throw Error('Invalid source tree');
 const blobs=new Map(tree.tree.filter(x=>x.type==='blob').map(x=>[x.path,x]));
 const patterns={smiptv:/^output\/channels\.json$/,
  allrounder:/^api\/(?:football|cricket)\.json$/,
  smsports:/^Sports_data\.json$/,
  dudetv:/^public_decrypted\/(?:events_with_channels\.json|cats\/[\w-]+\.json)$/,
  cfy:/^api\/events\.json$/,lian:/^(?:hasill|finall(?:\.json)?|playlist_final\.json|(?:pl|pll)\/rama+a?2(?:\.json)?|config\d*\.json)$/,
  deqiaa:/^(?:hasill|finall(?:\.json)?|playlist_final\.json|(?:pl|pll)\/rama+a?2(?:\.json)?|config\d*\.json)$/};
 const paths=[...blobs.keys()].filter(path=>patterns[source.key].test(path)&&(!fixturesOnly||source.key!=='dudetv'||path.endsWith('/events_with_channels.json'))).sort();
 const required={smiptv:'output/channels.json',allrounder:'api/football.json',smsports:'Sports_data.json',dudetv:'public_decrypted/events_with_channels.json'};
 if(!paths.length||required[source.key]&&!paths.includes(required[source.key]))throw Error('Required published export missing');
 const data=new Map();let total=0;
 async function load(files){
  if(files.length>550)throw Error('Source file budget exceeded');
  let cursor=0;
  await Promise.all(Array.from({length:8},async()=>{while(cursor<files.length){
   const path=files[cursor++],blob=blobs.get(path);
   if(!blob||blob.size>3*1024*1024)throw Error('Source file exceeds budget');
   const response=await fetcher(`https://raw.githubusercontent.com/${repository}/${tree.sha}/${path}`,{redirect:'error',signal});
   if(!response.ok){await response.body?.cancel();throw Error('Published source file unavailable');}
   const reader=response.body.getReader(),chunks=[];let size=0;
   try{while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;total+=value.length;
    if(size>3*1024*1024||total>16*1024*1024)throw Error('Source data exceeds budget');chunks.push(value);}}
   finally{await reader.cancel().catch(()=>{});}
   const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
   const header=new TextEncoder().encode('blob '+size+'\0'),gitBlob=new Uint8Array(header.length+size);gitBlob.set(header);gitBlob.set(bytes,header.length);
   const digest=[...new Uint8Array(await crypto.subtle.digest('SHA-1',gitBlob))].map(x=>x.toString(16).padStart(2,'0')).join('');
   if(digest!==blob.sha)throw Error('Published source blob verification failed');
   const text=new TextDecoder().decode(bytes);
   data.set(path,text.trimStart().startsWith('#EXTM3U')?{_m3u:text}:JSON.parse(text));
  }}));
 }
 await load(paths);
 const channels=new Map();
 if(source.key==='dudetv'&&!fixturesOnly){
  const ids=new Set(paths.filter(p=>p.includes('/cats/')).flatMap(p=>list(data.get(p))).map(row=>String(row.id)).filter(id=>/^[a-zA-Z0-9_-]{1,64}$/.test(id)));
  const channelPaths=[...ids].map(id=>'public_decrypted/channels/'+id+'.json').filter(path=>blobs.has(path));
  await load(channelPaths);
  for(const path of channelPaths)channels.set(path.split('/').pop().replace('.json',''),data.get(path));
 }
 return paths.map(path=>({path,rows:normalizeGithubDocument(repository,path,data.get(path),channels)}));
}
