// Published fixture data only. Never call tokenApi, license servers or builders.
import {configuration,publicSourceUrl,readJson,sourceHash} from './darkbyte_catalog.mjs';
import {mpdIdentity,MPD_REPOSITORIES} from './repository_mpd.mjs';
import {englishFootballName} from './football_names.mjs';
const clean=x=>String(x??'').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim();
const team=x=>englishFootballName(clean(x),'team');
const key=x=>clean(x).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
const football=/football|soccer|premier\s*league|bundesliga|serie\s*a|la\s*liga|ligue\s*1|champions\s*league|europa\s*league|eredivisie|efl|\bfa\s*cup\b/i;
const otherSport=/cricket|badminton|tennis|basketball|volleyball|motogp|motorsport|formula|\bufc\b|boxing|\bnfl\b|\bnba\b|rugby|hockey|baseball/i;
const logo=x=>publicSourceUrl(x,{httpsOnly:true})?.href||null;

export function repositoryKickoff(value){
 const text=clean(value).replace(/^(\d{4})\/(\d\d)\/(\d\d)/,'$1-$2-$3');
 // A wall clock without a published offset must not be presented as UTC.
 if(!/(?:Z|[+-]\d{2}:?\d{2})$/i.test(text))return null;
 const ms=Date.parse(text);return Number.isFinite(ms)?new Date(ms).toISOString():null;
}
export function repositoryLineIdentity(line){
 return JSON.stringify([mpdIdentity(line.stream_url),line.stream_type,line.referer||'',line.origin||'',
  (line.key_id||'').toLowerCase(),(line.key_data||'').toLowerCase(),line.drm_type||'',line.license_url||'']);
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
   if(otherSport.test(category)||!football.test(category))continue;
   const a=team(typeof home==='object'?home?.name:e.teamA||home),b=team(typeof away==='object'?away?.name:e.teamB||away);
   if(!a||!b||key(a)===key(b))continue;
   const candidates=[row.resolved_streams,row.streams,row.channels_data,row.formats].find(x=>Array.isArray(x)&&x.length)||[];
   rows.push({...context,home_team:a,away_team:b,home_logo_url:logo(home?.logo||e.teamAFlag),away_logo_url:logo(away?.logo||e.teamBFlag),
    kickoff_at:repositoryKickoff(e.startTime||row.startTime),end_at:repositoryKickoff(e.endTime),
    league:clean(e.eventName||row.eventName||category).slice(0,120),football_proven:true,
    streams:candidates.filter(x=>x?.visible!==false&&![0,'0',false].includes(x?.publish)).map(nativeLine).filter(Boolean)});
  }
 }
 return rows;
}
export async function mergeRepositoryMatches(rows,{now=Date.now()}={}){
 const grouped=new Map(),known=new Map();
 for(const row of rows)if(row.football_proven&&row.kickoff_at){const pair=key(row.home_team)+':'+key(row.away_team);const list=known.get(pair)||[];list.push(row);known.set(pair,list);}
 for(const row of rows){
  const home=key(row.home_team),away=key(row.away_team);if(!home||!away||home===away)continue;
  const peers=known.get(home+':'+away)||[];
  if(!row.football_proven&&!peers.length)continue;
  const dates=[...new Set(peers.map(r=>r.kickoff_at.slice(0,10)))];
  const kickoff=row.kickoff_at||(dates.length===1?peers[0].kickoff_at:null);
  if(kickoff&&(Date.parse(row.end_at||kickoff)+6*3600000<now||Date.parse(kickoff)>now+14*86400000))continue;
  const date=kickoff?.slice(0,10)||'undated';
  const id='repo:match:'+(await sourceHash(home+':'+away+':'+date)).slice(0,28);
  let entry=grouped.get(id);
  if(!entry){entry={id,provider:8,kind:'event',name:(row.home_team+' vs '+row.away_team).slice(0,120),category:'Football',
   source_file:'reviewed repository fixtures',image_url:null,streams:[],unsupported_count:0,
   event_meta:{home_team:row.home_team,away_team:row.away_team,home_logo_url:null,away_logo_url:null,kickoff_at:kickoff,league:row.league,repositories:[]}};grouped.set(id,entry);}
  const meta=entry.event_meta;
  meta.home_logo_url ||= row.home_logo_url;meta.away_logo_url ||= row.away_logo_url;
  if(row.league&&row.league!=='Football')meta.league=row.league;
  if(!meta.repositories.includes(row.repository))meta.repositories.push(row.repository);
  for(const line of row.streams){
   const identity=repositoryLineIdentity(line);
   if(entry.streams.some(l=>l._identity===identity))continue;
   entry.streams.push({...line,id:(await sourceHash(identity)).slice(0,24),_identity:identity});
  }
 }
 return [...grouped.values()].map(entry=>({...entry,streams:entry.streams.map(({_identity,...line})=>line)}));
}
export async function fetchRepositoryMatches({fetcher=fetch,revision=null}={}){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),45000);
 try{
  const opts={fetcher,signal:controller.signal,limit:3*1024*1024};
  const trees=await Promise.all(MPD_REPOSITORIES.map(repo=>readJson('https://api.github.com/repos/'+repo+'/git/trees/HEAD?recursive=1',opts)));
  const revisions=trees.map(tree=>{if(tree.truncated||!Array.isArray(tree.tree)||!/^[a-f\d]{40}$/.test(tree.sha||''))throw Error('Incomplete repository tree');return tree.sha;});
  const digest=await sourceHash(revisions.join(':'));
  // Rebuild even unchanged snapshots so finished fixtures age out naturally.
  const tasks=[];
  for(const [i,repo] of MPD_REPOSITORIES.entries())for(const item of trees[i].tree){
   const path=item.path;
   if(item.type!=='blob')continue;
   const match=repo==='darkbyteprojects/iptv_png'?/^provider_[1-6]\/live_events\.json$/.test(path):repo==='Roshavarma/cfy'?path==='api/events.json':/^(?:hasill|finall(?:\.json)?|playlist_final\.json|(?:pl|pll)\/rama+a?2(?:\.json)?)$/.test(path);
   if(match){if(item.size>3*1024*1024)throw Error('Repository fixture file exceeds budget');tasks.push({repository:repo,revision:revisions[i],source_file:path,blob_sha:item.sha});}
  }
  if(!tasks.length||tasks.length>50)throw Error('Invalid repository fixture list');
  let cursor=0;const parsed=new Array(tasks.length);
  await Promise.all(Array.from({length:5},async()=>{while(cursor<tasks.length){const i=cursor++,task=tasks[i];
   const response=await fetcher('https://raw.githubusercontent.com/'+task.repository+'/'+task.revision+'/'+task.source_file,{redirect:'error',signal:controller.signal});
   if(!response.ok){await response.body?.cancel();throw Error('Repository fixture file unavailable');}
   const bytes=new Uint8Array(await response.arrayBuffer());if(bytes.length>3*1024*1024)throw Error('Repository fixture file too large');
   const header=new TextEncoder().encode('blob '+bytes.length+'\0'),blob=new Uint8Array(header.length+bytes.length);blob.set(header);blob.set(bytes,header.length);
   const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-1',blob))].map(b=>b.toString(16).padStart(2,'0')).join('');
   if(hash!==task.blob_sha)throw Error('Repository file did not match its published Git blob');
   parsed[i]=parseRepositoryMatches(new TextDecoder().decode(bytes),{...task,publisher_blob_verified:true});
  }}));
  return {revision:digest,unchanged:false,entries:await mergeRepositoryMatches(parsed.flat()),complete:true};
 }finally{clearTimeout(timer);controller.abort();}
}
