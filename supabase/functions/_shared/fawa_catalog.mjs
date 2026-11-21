import {fawaScheduleTimezoneConfirmed,fawaMyanmarTimeLabel} from './fawa_schedule_time.mjs';
const clean=s=>String(s??'').replace(/<[^>]*>/g,' ').replace(/&amp;/gi,'&').replace(/&quot;/gi,'"').replace(/&#(?:39|x27);/gi,"'").replace(/&nbsp;/gi,' ').replace(/\s+/g,' ').trim();
export function isFawaFootball(league){
 const text=clean(league);
 if(/american|australian\s*rules|gaelic|\bncaa\b|\bnfl\b|\bnba\b|\bwnba\b|\bnbl\b|basket|cricket|boxing|\bbkfc\b|\bufc\b|\bmma\b|hockey|tennis|rugby|volley|baseball|motogp|formula|snooker|darts/i.test(text))return false;
 return /football|soccer|\buefa\b|\bfifa\b|premier|bundesliga|la\s*liga|serie\s*[abc]\b|ligue|j\s*league|a-league|k\s*league|\bliga\b|primera|\bcopa\b|champions|europa|\bfa\s*cup\b|eredivisie|super\s*lig|pro\s*league/i.test(text);
}
export function fawaClock(label){
 const m=clean(label).match(/(?:^|\s)(\d{1,2}):(\d{2})$/);
 return m&&Number(m[1])<24&&Number(m[2])<60?Number(m[1])*60+Number(m[2]):null;
}
export function parseFawaCatalog(html){
 const confirmed=fawaScheduleTimezoneConfirmed(html),groups=new Map();
 const add=(name,href,playing)=>{
  name=clean(name).replace(/\s*---\s*CH\s*\d+\s*$/i,'').trim();
  const teams=name.split(/\s+vs\s+/i);if(teams.length!==2)return;
  const league=clean(playing).replace(/\s+(?:\d{1,2}:\d{2}|--:--)\s*$/,'').trim();
  if(!isFawaFootball(league))return;
  let page;try{page=new URL(href,'http://www.fawanews.sc/');}catch{return;}
  if(!['http:','https:'].includes(page.protocol)||page.username||page.password||!['fawanews.sc','www.fawanews.sc'].includes(page.hostname)||!page.pathname.endsWith('.html'))return;
  const key=name.toLowerCase(),clock=fawaClock(playing);
  const row=groups.get(key)||{source:'fawa',source_id:key,page_url:page.href,league,home_team:teams[0].trim(),away_team:teams[1].trim(),
   home_logo:null,away_logo:null,match_time:null,time_label:fawaMyanmarTimeLabel(playing,confirmed),source_time_label:clean(playing),source_timezone:confirmed?'GMT+1':'unverified',
   schedule_minutes:confirmed&&clock!==null?clock+330:null,sport:'football',schedule_date_verified:false,hot:false,anchors:[]};
  if(!row.anchors.some(a=>a.page_url===page.href))row.anchors.push({uid:href,nick_name:row.anchors.length?'CH '+(row.anchors.length+1):'Main',room_num:href,page_url:page.href,icon:null});
  groups.set(key,row);
 };
 for(const hit of String(html).matchAll(/<div\s+class=["']user-item__name["'][^>]*>([\s\S]*?)<\/div>/gi)){
  const before=html.slice(Math.max(0,hit.index-1800),hit.index);
  const links=[...before.matchAll(/href=["']([^"']+\.html)["']/gi)];
  const after=html.slice(hit.index+hit[0].length,hit.index+hit[0].length+900);
  const playing=after.match(/class=["']user-item__playing["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
  if(links.length&&playing)add(hit[1],clean(links.at(-1)[1]),playing);
 }
 // Unknown sport metadata is deliberately not relabelled as Football.
 if(!groups.size)for(const hit of String(html).matchAll(/<a\b[^>]*href=["']([^"']+\.html(?:\?[^"']*)?)["'][^>]*>([\s\S]{0,2200}?)<\/a>/gi)){
  const playing=hit[2].match(/class=["']user-item__playing["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
  const name=hit[2].match(/class=["']user-item__name["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
  if(playing&&name)add(name,clean(hit[1]),playing);
 }
 return [...groups.values()].sort((a,b)=>(a.schedule_minutes??99999)-(b.schedule_minutes??99999)||a.source_id.localeCompare(b.source_id));
}
