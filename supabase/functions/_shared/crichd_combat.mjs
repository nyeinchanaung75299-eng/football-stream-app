// Public schedule metadata only. The existing per-device browser/session and
// stream detector remain responsible for verification and player discovery.
import {readPublicSource, publicSourceUrl} from './public_source_media.mjs';
import {crichdUtcKickoff, crichdPublishedWatchLinks, explicitKickoff} from './experimental_football_sources.mjs';
import {combatClassification, combatCategories} from './combat_sports.mjs';
import {sourceHash} from './darkbyte_catalog.mjs';
const HOME='https://crichd.pk/sports/soccer-streams';
const text=value=>String(value??'').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,' ').replace(/<[^>]*>/g,' ').replace(/&amp;/g,'&').replace(/&#39;|&apos;/g,"'").replace(/&nbsp;/g,' ').replace(/\s+/g,' ').trim();
function sameSite(raw,base){const u=publicSourceUrl(raw?.replace(/&amp;/g,'&'),base);return u&&new URL(u).hostname==='crichd.pk'?u:null;}
const anchors=html=>[...String(html).matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)];
const href=hit=>hit[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1];
export function crichdCombatSections(html,base=HOME){
 const sections=new Map();
 for(const hit of anchors(html)){
  const url=sameSite(href(hit),base),classification=combatClassification(text(hit[2])+' '+(url||''));
  if(url&&/^\/sports\//.test(new URL(url).pathname)&&classification)sections.set(url,{url,...classification});
 }
 return [...sections.values()].slice(0,6);
}
export async function parseCrichdCombatEvents(html,section){
 const rows=new Map();
 for(const hit of anchors(html)){
  const page=sameSite(href(hit),section.url);if(!page||!/^\/event\/[a-z0-9-]+\/?$/i.test(new URL(page).pathname))continue;
  const name=text(hit[2]).replace(/\b(?:watch now|watch live|live stream)\b/gi,' ').replace(/\s+/g,' ').trim();
  if(name.length<3||/\b(?:football|soccer|cricket|basketball)\b/i.test(name))continue;
  const own=combatClassification(name),classification=own||combatClassification(section.category_name);
  if(!classification)continue;
  const pair=name.match(/^(.*?)\s+(?:vs?\.?|–|—)\s+(.+?)$/i);
  const id='crichd-combat-'+(await sourceHash(page)).slice(0,20),kickoff=explicitKickoff(hit[0]);
  rows.set(page,{source:'crichd',source_id:id,schedule_id:id,kind:'combat',combat_event_name:name,...classification,
   league:classification.category_name,home_team:pair?.[1]||name,away_team:pair?.[2]||'',home_logo:null,away_logo:null,
   page_url:page,match_time:kickoff,verified_kickoff:!!kickoff,kickoff_estimated:false,
   status:'UNVERIFIED',match_status:'UNVERIFIED',playback_verified:false,
   anchors:[{room_num:id,page_url:page,nick_name:'Open event source'}]});
 }
 return [...rows.values()];
}
export async function crichdCombatMatches({category='all',fetcher=fetch,now=Date.now}={}){
 const categories=category in combatCategories?[category]:Object.keys(combatCategories);
 const diagnostics={candidate_count:0,content_state:'no_published_combat_events',category_availability:{},failed_pages:0};
 const deadline=Date.now()+6500;
 async function read(url){const response=await readPublicSource(url,{fetcher,allowedHosts:['crichd.pk'],timeoutMs:Math.max(50,Math.min(2000,deadline-Date.now()))});
  if(/(?:performing security verification|just a moment|cf-chl-|challenge-platform)/i.test(response.text)&&!/\/event\//i.test(response.text))throw Error('Source verification required');
  return response.text;}
 let sections;
 try{sections=crichdCombatSections(await read(HOME));}catch(_){diagnostics.content_state='source_unavailable_or_verification_required';sections=[];diagnostics.failed_pages++;}
 const rows=new Map();
 for(const section of sections){
  if(Date.now()>=deadline)break;
  try{const html=await read(section.url);for(const row of await parseCrichdCombatEvents(html,section))rows.set(row.page_url,row);}
  catch(_){diagnostics.failed_pages++;}
 }
 const matches=[...rows.values()];
 for(let offset=0;offset<Math.min(matches.length,18)&&Date.now()<deadline;offset+=3){
  await Promise.all(matches.slice(offset,offset+3).map(async row=>{try{
   const html=await read(row.page_url),kickoff=explicitKickoff(html)||crichdUtcKickoff(text(html)),links=crichdPublishedWatchLinks(html,row.page_url);
   if(kickoff){row.match_time=kickoff;row.verified_kickoff=true;}
   if(links.length)row.anchors=links;
  }catch(_){diagnostics.failed_pages++;}}));
 }
 for(const key of Object.keys(combatCategories))diagnostics.category_availability[key]={published_section:sections.some(s=>s.category===key),event_count:matches.filter(row=>row.category===key).length};
 const selected=matches.filter(row=>categories.includes(row.category));
 diagnostics.candidate_count=selected.length;
 if(selected.length)diagnostics.content_state='matches_found';
 else if(diagnostics.failed_pages)diagnostics.content_state='source_unavailable_or_verification_required';
 return {ok:true,source:'crichd',sport:'combat',matches:selected,results:selected.length,diagnostics,generated_at:new Date(typeof now==='function'?now():now).toISOString()};
}
