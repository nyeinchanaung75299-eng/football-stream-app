// Published fixture data only. Never call tokenApi, license servers or builders.
import {configuration,publicSourceUrl,sourceHash} from './darkbyte_catalog.mjs';
import {readRepositoryTrees} from './repository_trees.mjs';
import {mpdIdentity,MPD_REPOSITORIES} from './repository_mpd.mjs';
import {englishFootballName} from './football_names.mjs';
import {NEW_GITHUB_SOURCES,readGithubDocuments} from './github_source_formats.mjs';
const clean=x=>String(x??'').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim();
// Source names can contain already-corrupted UTF-8 (e.g. BodÃ¸/Glimt).
// Repair only known mojibake sequences, never try to infer unrelated teams.
const repairName=x=>clean(x).replace(/Ã¸/g,'ø').replace(/Ã˜/g,'Ø').replace(/Ã¶/g,'ö')
 .replace(/Ã¼/g,'ü').replace(/Ã©/g,'é').replace(/Ã±/g,'ñ').replace(/Ã¥/g,'å');
const key=x=>repairName(x).normalize('NFKD').replace(/[\u0300-\u036f]/g,'')
 .replace(/[øØ]/g,'o').replace(/[æÆ]/g,'ae').replace(/ß/g,'ss')
 .toLowerCase().replace(/[^a-z0-9]/g,'');
const aliases=new Map(Object.entries({manutd:'Manchester United',manchesterutd:'Manchester United',manunited:'Manchester United',
 mancity:'Manchester City',spurs:'Tottenham Hotspur',tottenham:'Tottenham Hotspur',psg:'Paris Saint-Germain',
 intermilan:'Inter Milan',inter:'Inter Milan',bayernmunchen:'Bayern Munich',newcastleutd:'Newcastle United',
 porto:'FC Porto',fcporto:'FC Porto',ceuta:'AD Ceuta',adceuta:'AD Ceuta',
 bodoglimt:'Bodø/Glimt',liverpool:'Liverpool FC',liverpoolfc:'Liverpool FC',
 lask:'LASK Linz',lasklinz:'LASK Linz'}));
const team=x=>{
 const value=englishFootballName(repairName(x),'team');
 const suffix=value.match(/\s+(?:(?:Women|Ladies|U\d{1,2}|Reserves|II|B)\s*)+$/i)?.[0]||'';
 const base=suffix?value.slice(0,-suffix.length):value;
 return (aliases.get(key(base))||base)+suffix;
};
const competition=row=>row.competition_tag||(/\bwomen(?:'s)?\b|\bladies\b|\bwsl\b|femenin|frauen|femminile/i.test([row.league,row.home_team,row.away_team].join(' '))?'women':'');
const football=/football|soccer|premier\s*league|bundesliga|serie\s*a|la\s*liga|ligue\s*1|champions\s*league|europa\s*league|eredivisie|efl|\bfa\s*cup\b|\bepl\b|\bwsl\b|scottish\s+premiership|brasileir[aã]o|(?:con\.?|conmebol)\s+sudamericana|super\s+lig\b|ta[cç]a\s+de\s+portugal/i;
const otherSport=/american\s*football|mixed\s*martial\s*arts|cricket|badminton|tennis|basketball|volleyball|motogp|motorsport|formula|\bf1\b|\bufc\b|boxing|\bnfl\b|\bnba\b|\bnhl\b|\bwwe\b|\bwbbl\b|rugby|hockey|baseball/i;
const logo=x=>publicSourceUrl(x,{httpsOnly:true})?.href||null;

export function repositoryKickoff(value){
 const text=clean(value).replace(/^(\d{4})\/(\d\d)\/(\d\d)/,'$1-$2-$3');
 // A wall clock without a published offset must not be presented as UTC.
 if(!/(?:Z|[+-]\d{2}:?\d{2})$/i.test(text))return null;
 const ms=Date.parse(text);return Number.isFinite(ms)?new Date(ms).toISOString():null;
}
export function repositoryLineIdentity(line){
 if(line.stream_type==='dash')return JSON.stringify([mpdIdentity(line.stream_url),
  (line.key_id||'').toLowerCase(),(line.key_data||'').toLowerCase()]);
 return JSON.stringify([mpdIdentity(line.stream_url),line.stream_type,line.referer||'',line.origin||'',
  (line.key_id||'').toLowerCase(),(line.key_data||'').toLowerCase(),line.drm_type||'',line.license_url||'']);
}
// Keep the original line ID for saved mappings, while the match list
// treats a complete, identical DRM pair as a single playback choice.
export function repositoryDisplayLineIdentity(line){
 const kid=String(line.key_id||'').toLowerCase(),data=String(line.key_data||'').toLowerCase();
 if(line.stream_type==='dash'&&/^[a-f0-9]{32}$/.test(kid)&&/^[a-f0-9]{32}$/.test(data))
  return JSON.stringify(['clearkey',kid,data]);
 return repositoryLineIdentity(line);
}
function nativeLine(row){
 const c=configuration({...row,type:null});if(!c||c.stream_type==='auto')return null;
 const drm=clean(row.drm_type).toLowerCase();
 return {...c,label:clean(row.title||row.name||'Line').slice(0,100),
  drm_type:c.key_data?'clearkey':drm||null,license_url:publicSourceUrl(row.license_url)?.href||null,
  configuration_status:c.key_data?'configured':drm&&drm!=='none'||String(row.type)==='1'&&c.stream_type==='dash'?'requires_drm':'unverified'};
}
function jsonEvents(value,out=[]){
 if(Array.isArray(value)){for(const item of value)jsonEvents(item,out);return out;}
 if(!value||typeof value!=='object')return out;
 if(value.teamA&&value.teamB||value.eventInfo?.teamA&&value.eventInfo?.teamB){out.push(value);return out;}
 for(const child of Object.values(value))if(child&&typeof child==='object')jsonEvents(child,out);
 return out;
}
export function parseRepositoryMatches(text,context){
 const rows=[];
 // Some repositories intentionally publish a tiny HTML landing page in
 // `finall`. It contains no native fixture data. Only accept that as empty
 // after its contents have been verified against the pinned Git blob SHA.
 if(context.publisher_blob_verified&&/^<(?:!doctype\s+html|html)\b/i.test(String(text).trimStart()))return rows;
 if(String(text).trimStart().startsWith('#EXTM3U')){
  let row;
  for(const raw of String(text).split(/\r?\n/)){
   const line=raw.trim();
   if(line.startsWith('#EXTINF:')){
    const attr=k=>line.match(new RegExp('\\b'+k+'="([^"]*)"','i'))?.[1];
    row={title:line.slice(line.indexOf(',')+1),group:attr('group-title'),image:attr('tvg-logo')};
   }else if(row&&line.startsWith('#KODIPROP:')){
    const [,name,value]=line.match(/^#KODIPROP:([^=]+)=(.*)$/)||[];
    if(name?.endsWith('.license_type'))row.drm_type=value;
    if(name?.endsWith('.license_key')){if(/^[a-f\d]{32}:[a-f\d]{32}$/i.test(value))row.api=value;else row.license_url=value;}
   }else if(row&&/^#EXTVLCOPT:http-referr?er=/i.test(line))row.referer=line.slice(line.indexOf('=')+1);
   else if(row&&line&&!line.startsWith('#')){
    const title=clean(row.title),parts=title.match(/^(?:\d{1,2}:\d{2}\s*(?:WIB|WITA|WIT)\s*)?(.+?)\s+(?:vs\.?|v\.?|versus)\s+(.+?)(?:\s+(?:Football|Soccer)\b.*|\s*\([^)]*\d{4}[^)]*\).*)?$/i);
    const config=nativeLine({...row,link:line});
    const clock=title.match(/(\d{1,2}):(\d{2})\s*WIB/i),date=title.match(/(\d{2})[-/](\d{2})[-/](\d{4})/);
    const kickoff=clock&&date?repositoryKickoff(`${date[3]}-${date[2]}-${date[1]}T${clock[1].padStart(2,'0')}:${clock[2]}:00+0700`):null;
    if(parts&&config&&!otherSport.test(title+' '+row.group))rows.push({...context,home_team:team(parts[1].replace(/^(?:Football|Soccer)\s+/i,'')),away_team:team(parts[2].split(/\s[-•]\s/)[0]),
     home_logo_url:null,away_logo_url:null,kickoff_at:kickoff,league:clean(row.group)||'Football',
     football_proven:football.test(title+' '+row.group),streams:[config]});
    row=null;
   }
  }
 }else{
  let payload;try{payload=JSON.parse(text);}catch{throw Error('Invalid published fixture data');}
  for(const row of jsonEvents(payload)){
   if(row.visible===false||[0,'0',false].includes(row.publish))continue;
   const e=row.eventInfo||{},home=row.teamA,away=row.teamB;
   const category=clean([e.eventCat,row.cat,row.category,e.eventName,row.eventName].filter(Boolean).join(' '));
   // Provider 6 publishes English football as EPL/Championship rather than
   // eventCat=Football. Keep the ambiguous Championship alias source-scoped.
   const providerFootball=context.source_file==='provider_6/live_events.json'&&/^Championship(?:\s|$)/i.test(clean(row.cat));
   const unclassified=context.repository===NEW_GITHUB_SOURCES[0].repository&&row.unclassified_sports===true;
   if(otherSport.test(category)||!football.test(category)&&!providerFootball&&!unclassified)continue;
   const a=team(typeof home==='object'?home?.name:e.teamA||home),b=team(typeof away==='object'?away?.name:e.teamB||away);
   if(!a||!b||key(a)===key(b))continue;
   const candidates=[row.resolved_streams,row.streams,row.channels_data,row.formats].find(x=>Array.isArray(x)&&x.length)||[];
   rows.push({...context,home_team:a,away_team:b,home_logo_url:logo(home?.logo||e.teamAFlag),away_logo_url:logo(away?.logo||e.teamBFlag),
    kickoff_at:repositoryKickoff(e.startTime||row.startTime),end_at:repositoryKickoff(e.endTime),
    source_civil_date:e.sourceCivilDate||null,source_time:e.sourceTime||null,
    league:clean(e.eventName||row.eventName||category).slice(0,120),football_proven:!unclassified,
    competition_tag:competition({league:category,home_team:a,away_team:b}),
    streams:candidates.filter(x=>x?.visible!==false&&![0,'0',false].includes(x?.publish)).map(nativeLine).filter(Boolean)});
  }
 }
 return rows;
}
export async function mergeRepositoryMatches(rows,{now=Date.now()}={}){
 rows=rows.map(row=>({...row,home_team:team(row.home_team),away_team:team(row.away_team)}));
 const grouped=new Map(),known=new Map();
 for(const row of rows)if(row.football_proven&&row.kickoff_at){const pair=key(row.home_team)+':'+key(row.away_team)+':'+competition(row);const list=known.get(pair)||[];list.push(row);known.set(pair,list);}
 for(const row of rows){
  const home=key(row.home_team),away=key(row.away_team);if(!home||!away||home===away)continue;
  const peers=(known.get(home+':'+away+':'+competition(row))||[]).filter(peer=>!row.source_civil_date||
   Math.abs(Date.parse(peer.kickoff_at.slice(0,10))-Date.parse(row.source_civil_date))<=86400000);
  if(!row.football_proven&&!peers.length)continue;
  const exactTimes=[...new Set(peers.map(r=>r.kickoff_at))].sort();
  const kickoff=row.kickoff_at||(exactTimes.length===1?exactTimes[0]:null);
  if(kickoff&&(Date.parse(row.end_at||kickoff)+6*3600000<now||Date.parse(kickoff)>now+14*86400000))continue;
  const date=kickoff?.slice(0,10)||row.source_civil_date||'undated';
  const sameDayTimes=exactTimes.filter(time=>time.startsWith(date));
  // Keep the established ID for the first kickoff. A second fixture between
  // the same teams on the same UTC date needs its own ID and stream list.
  const extraKickoff=kickoff&&sameDayTimes.length>1&&kickoff!==sameDayTimes[0]?':'+kickoff:'';
  const id='repo:match:'+(await sourceHash(home+':'+away+':'+date+(competition(row)?':'+competition(row):'')+extraKickoff)).slice(0,28);
  let entry=grouped.get(id);
  if(!entry){entry={id,provider:8,kind:'event',name:(row.home_team+' vs '+row.away_team).slice(0,120),category:'Football',
   source_file:'reviewed repository fixtures',image_url:null,streams:[],unsupported_count:0,
   event_meta:{home_team:row.home_team,away_team:row.away_team,home_logo_url:null,away_logo_url:null,kickoff_at:kickoff,
    source_civil_date:row.source_civil_date||null,source_time:row.source_time||null,league:row.league,repositories:[]}};grouped.set(id,entry);}
  const meta=entry.event_meta;
  meta.home_logo_url ||= row.home_logo_url;meta.away_logo_url ||= row.away_logo_url;
  if(row.league&&!/\s(?:vs\.?|versus)\s/i.test(row.league)&&row.league!=='Football'&&!/^live\s*(?:events?|sports)$/i.test(row.league))meta.league=row.league;
  if(!meta.repositories.includes(row.repository))meta.repositories.push(row.repository);
  for(const line of row.streams){
   const identity=repositoryDisplayLineIdentity(line);
   if(entry.streams.some(l=>l._identity===identity))continue;
   entry.streams.push({...line,id:(await sourceHash(repositoryLineIdentity(line))).slice(0,24),_identity:identity});
  }
 }
 return [...grouped.values()].map(entry=>({...entry,streams:entry.streams.map(({_identity,...line})=>line)}));
}
// During a partial source outage, retain previously saved unique lines for
// matching fixtures, while allowing newly published lines to be added. Never
// treat a partial refresh as an authoritative deletion of older match media.
export function preserveRepositoryMatchLines(entries,oldEntries){
 const previous=new Map(oldEntries.map(row=>[row.id,row]));
 return entries.map(entry=>{
  const old=previous.get(entry.id);
  if(!old)return entry;
  const seen=new Set(entry.streams.map(repositoryDisplayLineIdentity));
  const kept=[];
  for(const line of old.streams||[]){
   const identity=repositoryDisplayLineIdentity(line);
   if(!seen.has(identity)){kept.push(line);seen.add(identity);}
  }
  const oldMeta=old.event_meta||{},fresh=entry.event_meta||{};
  return {...entry,streams:[...entry.streams,...kept],
   event_meta:{...oldMeta,...fresh,
    home_logo_url:fresh.home_logo_url||oldMeta.home_logo_url||null,
    away_logo_url:fresh.away_logo_url||oldMeta.away_logo_url||null,
    kickoff_at:fresh.kickoff_at||oldMeta.kickoff_at||null,
    repositories:[...new Set([...(oldMeta.repositories||[]),...(fresh.repositories||[])])]}}
 });
}

export async function fetchRepositoryMatches({fetcher=fetch,revision=null}={}){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),45000);
 try{
  const opts={fetcher,signal:controller.signal,limit:3*1024*1024};
  const trees=await readRepositoryTrees(MPD_REPOSITORIES,{...opts,allowMissing:true,isolateFailures:true});
  const failed=new Set(MPD_REPOSITORIES.filter((_,i)=>trees[i]===null));
  const revisions=trees.map(tree=>{if(tree===null)return 'missing';if(tree.truncated||!Array.isArray(tree.tree)||!/^[a-f\d]{40}$/.test(tree.sha||''))throw Error('Incomplete repository tree');return tree.sha;});
  const digest=await sourceHash(revisions.join(':'));
  // Rebuild even unchanged snapshots so finished fixtures age out naturally.
  const tasks=[];
  for(const [i,repo] of MPD_REPOSITORIES.entries())for(const item of (trees[i]?.tree||[])){
   const path=item.path;
   if(item.type!=='blob')continue;
   const match=repo==='darkbyteprojects/iptv_png'?/^provider_[1-6]\/live_events\.json$/.test(path):repo==='Roshavarma/cfy'?path==='api/events.json':/^(?:hasill|finall(?:\.json)?|playlist_final\.json|(?:pl|pll)\/rama+a?2(?:\.json)?)$/.test(path);
   if(match){if(item.size>3*1024*1024)throw Error('Repository fixture file exceeds budget');tasks.push({repository:repo,revision:revisions[i],source_file:path,blob_sha:item.sha});}
  }
  if((!tasks.length&&!NEW_GITHUB_SOURCES.some(source=>trees[MPD_REPOSITORIES.indexOf(source.repository)]))||tasks.length>50)throw Error('Invalid repository fixture list');
  let cursor=0;const parsed=new Array(tasks.length);
  await Promise.all(Array.from({length:5},async()=>{while(cursor<tasks.length){const i=cursor++,task=tasks[i];
   try{
   const response=await fetcher('https://raw.githubusercontent.com/'+task.repository+'/'+task.revision+'/'+task.source_file,{redirect:'error',signal:controller.signal});
   if(!response.ok){await response.body?.cancel();throw Object.assign(Error('Repository fixture file unavailable'),{code:'repository_file_http_'+response.status});}
   const bytes=new Uint8Array(await response.arrayBuffer());if(bytes.length>3*1024*1024)throw Error('Repository fixture file too large');
   const header=new TextEncoder().encode('blob '+bytes.length+'\0'),blob=new Uint8Array(header.length+bytes.length);blob.set(header);blob.set(bytes,header.length);
   const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-1',blob))].map(b=>b.toString(16).padStart(2,'0')).join('');
   if(hash!==task.blob_sha)throw Error('Repository file did not match its published Git blob');
   parsed[i]=parseRepositoryMatches(new TextDecoder().decode(bytes),{...task,publisher_blob_verified:true});
   }catch{failed.add(task.repository);parsed[i]=[];}
  }}));
  for(const source of NEW_GITHUB_SOURCES){
   const tree=trees[MPD_REPOSITORIES.indexOf(source.repository)];if(!tree)continue;
   try{
   for(const doc of await readGithubDocuments(source.repository,tree,{fetcher,signal:controller.signal,fixturesOnly:true})){
    parsed.push(parseRepositoryMatches(JSON.stringify(doc.rows),{repository:source.repository,revision:tree.sha,source_file:doc.path}));
   }
   }catch{failed.add(source.repository);}
  }
  const missingRepositories=MPD_REPOSITORIES.filter(repo=>failed.has(repo));
  if(missingRepositories.length===MPD_REPOSITORIES.length)throw Error('No published fixture source available');
  return {revision:digest,unchanged:false,entries:await mergeRepositoryMatches(parsed.flat().filter(row=>!failed.has(row.repository))),
   complete:missingRepositories.length===0,missingRepositories};
 }finally{clearTimeout(timer);controller.abort();}
}
