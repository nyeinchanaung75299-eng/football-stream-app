// Read-only LiveXTV football metadata from publicly published pages.
// Never execute player JS, synthesize tokens, bypass challenges, or claim
// that an observed Watch page proves HLS playback.
import {readPublicSource,publicSourceUrl,discoverPublicMedia} from './public_source_media.mjs';

const ROOT='https://livextv.pro/live';
const allowedHost=host=>host==='livextv.pro'||host==='www.livextv.pro';
const titleText=value=>String(value??'')
  .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,' ')
  .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi,' ')
  .replace(/<[^>]*>/g,' ').replace(/&nbsp;|&#160;/gi,' ')
  .replace(/&amp;/gi,'&').replace(/&quot;/gi,'"')
  .replace(/&#39;|&apos;/gi,"'").replace(/\s+/g,' ').trim();
const attr=(html,name)=>html.match(new RegExp('(?:^|\\s)'+name+'\\s*=\\s*(?:"([^"]*)"|\\x27([^\\x27]*)\\x27)','i'))?.[1] ??
  html.match(new RegExp('(?:^|\\s)'+name+'\\s*=\\s*\\x27([^\\x27]*)\\x27','i'))?.[1] ?? null;

function publicWatch(value,base=ROOT) {
  const url=publicSourceUrl(value,base);
  if(!url)return null;
  const parsed=new URL(url);
  if(!allowedHost(parsed.hostname)|| !/^\/watch\/[1-9]\d{0,11}\/?$/.test(parsed.pathname)||
     [...parsed.searchParams.keys()].length>1||
     [...parsed.searchParams.keys()].some(x=>x!=='s')||
     (parsed.searchParams.has('s')&&!/^[1-9]\d?$/.test(parsed.searchParams.get('s')??'')))return null;
  return parsed;
}
function canonical(value,base=ROOT) {
  const target=publicWatch(value,base);
  if(!target)return null;
  target.search='';return target.href;
}
function hash(value) {
  let n=2166136261;
  for(let i=0;i<value.length;i++)n=Math.imul(n^value.charCodeAt(i),16777619);
  return (n>>>0).toString(36);
}
function sportLabel(s) {
  return /\b(?:american football|nfl|nba|ncaaf|ncaab|basketball|hockey|nhl|baseball|mlb|cricket|tennis|ufc|mma|boxing|rugby|wrestling|golf|esports)\b/i.test(s)?'other':
    /\b(?:soccer|football|uefa|afcon|caf qualifying|africa cup|fifa world cup|world cup qualifying|premier league|la liga|serie a|bundesliga|ligue 1|copa america|champions league|europa league|international friendly|fa cup)\b/i.test(s)?'football':'unknown';
}
function teamPair(name) {
  const cleaned=titleText(name).replace(/^\s*(?:Live|in \d+[hm]|Replay|Watch)\s+/i,'')
    .replace(/\s*(?:[·|•]\s*.*)$/,'').trim();
  const match=cleaned.match(/^(.{2,65}?)\s+(?:vs?\.?|[-–—])\s+(.{2,65})$/i);
  if(!match)return null;
  return {home:match[1].trim(),away:match[2].trim()};
}
function eventTime(value) {
  if(value==null)return null;
  if(typeof value==='number' || (/^\d{10,13}$/.test(String(value)))) {
    const n=Number(value),ms=n<1e12?n*1000:n;
    return ms>=1577836800000 && ms<=4102444800000?new Date(ms).toISOString():null;
  }
  const text=String(value);
  if(!/20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})/i.test(text))return null;
  const date=new Date(text);
  return Number.isNaN(date.getTime())?null:date.toISOString();
}
function matchRow(page,teams,{league='Football',kickoff=null,live=false,logoHome=null,logoAway=null}={}) {
  const id=hash(page);
  return {source:'livextv',source_id:id,schedule_id:id,
    league,home_team:teams.home,away_team:teams.away,
    home_logo:logoHome,away_logo:logoAway,match_time:kickoff,
    verified_kickoff:!!kickoff,kickoff_source:kickoff?'explicit':'none',
    status:live?'LIVE':kickoff?'NS':'UNVERIFIED',
    match_status:live?'LIVE':kickoff?'SCHEDULED':'UNVERIFIED',
    hot:live,page_url:page,
    anchors:[{room_num:hash(page+':watch'),page_url:page,nick_name:'Watch • inspect sources'}]};
}
function leagueFrom(s) {
  return titleText(s).match(/\b(?:UEFA Nations League|AFCON Qualifying|Africa Cup of Nations|UEFA Champions League|UEFA Europa League|World Cup Qualifying|Premier League|La Liga|Serie A|Bundesliga|Ligue 1|Men's International Friendly|Copa America)\b/i)?.[0]||'Football';
}
function pairFromMarkup(html) {
  for(const key of ['data-title','title','aria-label']){
    const value=attr(html,key);
    const teams=value&&teamPair(value);
    if(teams)return teams;
  }
  for(const m of html.matchAll(/<(?:h1|h2|h3|h4|strong|span)\b[^>]*>([\s\S]*?)<\/(?:h1|h2|h3|h4|strong|span)>/gi)) {
    const teams=teamPair(m[1]);if(teams)return teams;
  }
  return teamPair(html);
}
function kickoffFromMarkup(html) {
  for(const hit of html.matchAll(/\b(?:datetime|data-(?:start|kickoff|timestamp|start-time))=["']([^"']+)["']/gi)) {
    const time=eventTime(hit[1]);if(time)return time;
  }
  return null;
}
function nearestCard(html,position) {
  for(const tag of ['article','li','section','div']) {
    const start=html.lastIndexOf('<'+tag,position);
    if(start<0||position-start>2500)continue;
    const head=html.slice(start,Math.min(start+450,html.length));
    const className=attr(head,'class')??'';
    if(tag==='div'&&!/(?:event|match|fixture|game)[\w-]*(?:card|item|row)|(?:card|item)[\w-]*(?:event|match|fixture|game)/i.test(className))continue;
    const end=html.indexOf('</'+tag+'>',position);
    if(end<0||end-start>3800)continue;
    const candidate=html.slice(start,end+tag.length+3);
    if([...candidate.matchAll(/\/watch\/\d+/g)].length<=3)return candidate;
  }
  return '';
}
// Exported pure parsers are tested with event-specific fixtures.
export function liveXtvPublishedMatches(html) {
  const output=new Map();
  for(const match of String(html).matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
    const href=attr(match[1],'href');
    const page=href&&canonical(href,ROOT);
    if(!page||output.has(page))continue;
    const card=nearestCard(html,match.index??0);
    // Event-specific football evidence is mandatory on a multi-sport site.
    const own=card||match[0];
    const explicitSport=attr(own.slice(0,550),'data-sport') ||
      attr(own.slice(0,550),'data-category') || '';
    const markedSport=sportLabel(explicitSport);
    if(markedSport==='other' ||
       (markedSport!=='football' && sportLabel(titleText(own))!=='football'))continue;
    const teams=pairFromMarkup(own)??pairFromMarkup(match[0]);
    if(!teams)continue;
    const kickoff=kickoffFromMarkup(own);
    const live=/\bLIVE\b/i.test(titleText(own).slice(0,140));
    output.set(page,matchRow(page,teams,{league:leagueFrom(own),kickoff,live}));
  }
  // Some public pages publish structured SportsEvent JSON instead of HTML anchors.
  for(const script of String(html).matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)) {
    const type=attr(script[1],'type')||'';
    const id=attr(script[1],'id')||'';
    if(!/^(?:application\/(?:ld\+json|json)|text\/json)$/i.test(type)&&
       !/^(?:__NEXT_DATA__|__INITIAL_STATE__)$/i.test(id))continue;
    let data;
    try {data=JSON.parse(script[2]);}catch{continue;}
    const queue=[data];
    for(let i=0;i<queue.length&&i<2500;i++){
      const node=queue[i];
      if(!node||typeof node!=='object')continue;
      if(Array.isArray(node)){queue.push(...node.slice(0,80));continue;}
      const typeName=String(node['@type']??node.type??'');
      const sport=String(node.sport?.name??node.sport??node.category?.name??node.category??'');
      const link=node.url??node.href??node.page_url??node.eventUrl??node.watchUrl??node.link;
      const page=typeof link==='string'?canonical(link,ROOT):null;
      const teams=teamPair(node.name??node.title??node.eventName??node.matchName)||
        (node.homeTeam&&node.awayTeam ? {
          home:titleText(node.homeTeam.name??node.homeTeam),
          away:titleText(node.awayTeam.name??node.awayTeam)} : null);
      const competition=String(node.league?.name??node.competition?.name??node.tournament?.name??'');
      const ownSport=sportLabel(sport||competition);
      // Do not infer football from a team name or a different SportsEvent.
      if(page&&teams&&teams.home&&teams.away&&!output.has(page)&&
         ownSport==='football'&&
         (!typeName||/(?:event|match|fixture|game)/i.test(typeName))) {
        const kickoff=eventTime(node.startDate??node.startTime??node.kickoff_at??node.startTimestamp);
        output.set(page,matchRow(page,teams,{
          league:titleText(node.league?.name??node.competition?.name??node.tournament?.name??'')||'Football',
          kickoff,live:node.isLive===true||node.live===true}));
      }
      queue.push(...Object.values(node).filter(x=>x&&typeof x==='object').slice(0,50));
    }
  }
  return [...output.values()].sort((a,b)=>(a.match_time??'9999').localeCompare(b.match_time??'9999'));
}
export function liveXtvPublishedSources(html,page) {
  const origin=publicWatch(page);
  if(!origin)return [];
  const result=new Map();
  const add=(href,label)=>{
    const url=publicWatch(href,page);
    if(!url||url.pathname!==origin.pathname||!url.searchParams.has('s'))return;
    const index=Number(url.searchParams.get('s'));
    const text=titleText(label);
    if(!text||!/\b(?:hd|sd|uhd|4k|stream|server|source|dazn|sports|link)\b/i.test(text))return;
    if(!result.has(index))result.set(index,{
      room_num:hash(origin.pathname+':'+index),
      page_url:origin.origin+origin.pathname,
      watch_url:url.href,nick_name:text,
    });
  };
  for(const hit of String(html).matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi))
    add(attr(hit[1],'href'),hit[2]);
  for(const hit of String(html).matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/gi))
    add(attr(hit[1],'data-href')||attr(hit[1],'data-url'),hit[2]);
  return [...result.entries()].sort((a,b)=>a[0]-b[0]).map(([,entry])=>entry).slice(0,12);
}
export async function liveXtvMatches({fetcher=fetch}={}) {
  // The home page also publishes the public football catalog. If /live
  // is unavailable or returned only JS shells, try that public fallback.
  let matches=[];
  let firstError=null;
  let successfulIndexes=0;
  let movedIndex=false;
  let browserRenderedIndex=false;
  // A source-specific public football listing can publish real fixtures when
  // the generic /live or homepage serves only navigation/redirect markup.
  // Never follow an unverified "new home" link to an unrelated domain.
  for(const location of [ROOT,'https://livextv.pro/sport/football','https://livextv.pro/']) {
    try{
      const listing=await readPublicSource(location,{fetcher,timeoutMs:4000,
        allowedHosts:['livextv.pro']});
      successfulIndexes++;
      matches=liveXtvPublishedMatches(listing.text);
      if(!matches.length) {
        if(/we['’]?ve moved|livextv has a new home|update your bookmark/i.test(listing.text))
          movedIndex=true;
        if(/<script\b|__next|__nuxt/i.test(listing.text))
          browserRenderedIndex=true;
      }
      if(matches.length)break;
    }catch(err){firstError??=err;}
  }
  if(!matches.length && successfulIndexes===0 && firstError) {
    // All public listing endpoints failed; return the actual load error.
    throw firstError;
  }
  // Read a limited number of detail pages for explicit HD/SD source labels,
  // not for credentials, private APIs, or stream extraction.
  for(let i=0;i<Math.min(matches.length,9);i+=3) {
    await Promise.all(matches.slice(i,i+3).map(async row=>{
      try{
        const detail=await readPublicSource(row.page_url,{fetcher,timeoutMs:1500,
          allowedHosts:['livextv.pro']});
        const options=liveXtvPublishedSources(detail.text,row.page_url);
        if(options.length)row.anchors=options;
        if(!row.match_time) {
          const time=kickoffFromMarkup(detail.text);
          if(time) {
            row.match_time=time;row.verified_kickoff=true;row.kickoff_source='explicit';
            if(row.status==='UNVERIFIED'){row.status='NS';row.match_status='SCHEDULED';}
          }
        }
      }catch{ /* Leave the public Watch page to an explicit operator tap. */ }
    }));
  }
  const days=[...new Set(matches.filter(m=>m.match_time).map(m=>
    new Date(Date.parse(m.match_time)+390*60*1000).toISOString().slice(0,10)))].sort();
  return {ok:true,source:'livextv',matches,results:matches.length,
    diagnostics:{candidate_count:matches.length,
      content_state:matches.length?'matches_found':
        movedIndex?'source_moved_or_unavailable':
        browserRenderedIndex?'browser_render_or_unsupported_markup':
        'no_confirmed_public_football_fixtures',
      confirmed_kickoff_count:matches.filter(m=>m.verified_kickoff).length,
      missing_kickoff_count:matches.filter(m=>!m.match_time).length,
      available_days_mmt:days,
      note:'Only explicit timezone kickoffs are converted to MMT. Unknown times are not guessed.'},
    generated_at:new Date().toISOString()};
}
export async function liveXtvStreams(body,{fetcher=fetch}={}) {
  const watch=canonical(body?.page_url);
  if(!watch)return {ok:true,source:'livextv',ready:false,lines:[],line_count:0,
    message:'Select a published LiveXTV Watch page.'};
  let html;
  try {
    html=(await readPublicSource(watch,{fetcher,timeoutMs:3000,
      allowedHosts:['livextv.pro']})).text;
  }catch(err) {
    return {ok:true,source:'livextv',ready:false,lines:[],line_count:0,
      diagnostic_code:'watch_page_unavailable',
      message:'The public Watch page was unavailable for server-side inspection.'};
  }
  const choices=liveXtvPublishedSources(html,watch);
  const selected=body?.watch_url==null?watch:publicWatch(body.watch_url,watch)?.href;
  if(!selected||selected!==watch&&!choices.some(x=>x.watch_url===selected)) {
    return {ok:true,source:'livextv',ready:false,lines:[],line_count:0,
      diagnostic_code:'source_not_published',message:'Selected source is not published for this match.'};
  }
  const result=await discoverPublicMedia(selected,{fetcher,firstHtml:selected===watch?html:null,
    deadline:Date.now()+4500,initialAllowedHosts:['livextv.pro']});
  const lines=result.lines.map((item,i)=>({
    ...item,label:'LiveXTV • public media '+(i+1),
    stream_type:item.stream_type||(/\.mpd$/i.test(new URL(item.url).pathname)?'dash':
      /\.mp4$/i.test(new URL(item.url).pathname)?'mp4':'hls'),
    health_status:'unknown',discovery_mode:'public_html',
  }));
  const denied=result.failures.some(x=>/401|403/.test(x));
  return {ok:true,source:'livextv',ready:lines.length>0,lines,line_count:lines.length,
    ...(choices.length?{published_sources:choices}:{}),
    diagnostics:{pages_checked:result.pagesChecked,access_denied:denied,
      playback_verified:false,failures:result.failures},
    message:lines.length?'Public media candidates (playback not verified).':
      denied?'Player denied server inspection (401/403).':
      'No public HLS URL found. Video may require interactive browser playback.'};
}
