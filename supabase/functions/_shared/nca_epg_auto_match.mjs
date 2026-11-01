// Safe matching of football fixtures with public TV guide metadata.
// No playback URLs, licence keys or DRM fields are read here.
const norm=v=>String(v||"").normalize("NFD").replace(/[\u0300-\u036f]/g,"")
 .toLowerCase().replace(/[^a-z0-9]+/g," ").replace(/\s+/g," ").trim();
const uuid=v=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v||"");
const replay=/\b(replay|repeat|re run|rebroadcast|recorded|highlights?|mini match|classic|recap|review|preview|magazine|z zaznam|zaznam|aufzeichnung|ripetizione|rediffusion|resumen|souhrn)\b/;
const other=/\b(aflw?|australian rules|nfl|nba|wnba|basketball|baseball|mlb|nhl|ice hockey|cricket|rugby|nrl|formula one|formula 1|motogp|motorsport|tennis|badminton|snooker|boxing|mma|ufc|esports)\b/;
const aliasMap={
 "rc strasbourg alsace":["strasbourg"],"olympique lyonnais":["lyon"],
 "olympique de marseille":["marseille"],"a s roma":["roma","as roma"],
 "s s c napoli":["napoli"],"ac milan":["milan"],"inter milan":["inter"],
 "racing santander":["racing de santander"],
 "real betis balompie":["real betis","betis"],
 "fc bayern munchen":["bayern munich","bayern"],
 "fc bayern munich":["bayern munich","bayern"],
 "bayer 04 leverkusen":["leverkusen"],"vfb stuttgart":["stuttgart"],
 "borussia dortmund":["dortmund"],"newcastle united":["newcastle"],
 "newcastle utd":["newcastle"],"juventus f c":["juventus"],
 "athletic club":["athletic bilbao"],"sevilla fc":["sevilla"]
};
function teamAliases(name){
 const n=norm(name);if(n.length<4)return [];
 const short=n.replace(/^(?:1 |a |s |r |u )?(?:fc|afc|ac|sc|cf|cd|sv|rc|ssc) /,"")
  .replace(/ (?:fc|afc|cf|sc|football club|balompie)$/,"");
 return [...new Set([n,short,...(aliasMap[n]||[])].map(norm).filter(x=>x.length>=4))];
}
const contains=(body,variants)=>variants.some(alias=>(" "+body+" ").includes(" "+alias+" "));
export function findVerifiedGuideMatches(matches,guide,channels,now=new Date()){
 const available=new Set(channels.filter(c=>c.is_active===true&&uuid(c.id)&&
  c.epg_id&&c.epg_source).map(c=>c.id));
 const candidates=[],seen=new Set();
 const guideRows=Array.isArray(guide?.channels)?guide.channels:[];
 const earliest=now.getTime()-90*60000,latest=now.getTime()+8*86400000;
 for(const match of matches){
  if(!uuid(match.id)||match.is_active!==true||match.publish_state!=="published"||match.deleted_at)continue;
  const kickoff=Date.parse(match.kickoff_at);
  if(!Number.isFinite(kickoff)||kickoff<earliest||kickoff>latest)continue;
  const home=teamAliases(match.home_team),away=teamAliases(match.away_team);
  if(!home.length||!away.length)continue;
  for(const channel of guideRows){
   if(channel?.matchedEPG!==true||!available.has(channel.id))continue;
   let chosen=null;
   for(const pg of Array.isArray(channel.programmes)?channel.programmes:[]){
    if(pg?.stream_ambiguous===true)continue;
    const start=Number(pg?.start),gap=(start-kickoff)/60000;
    if(!Number.isFinite(start)||start<1e12||gap < -90||gap>75)continue;
    const body=norm([pg.title,pg.subtitle,pg.description].join(" "));
    if(!body||replay.test(body)||other.test(body)||!/\b(v|vs|versus)\b/.test(body))continue;
    if(!contains(body,home)||!contains(body,away))continue;
    if(!chosen||Math.abs(gap)<Math.abs(chosen.gap)){
     chosen={match_id:match.id,channel_id:channel.id,
      programme_title:String(pg.title||"").slice(0,180),
      programme_start:new Date(start).toISOString(),gap};
    }
   }
   if(chosen){const key=chosen.match_id+":"+chosen.channel_id;
    if(!seen.has(key)){candidates.push(chosen);seen.add(key);}
   }
  }
 }
 return candidates;
}
export function isAuthorizedKeylessLine(line){
 if(line?.is_active!==true||line?.key_id||line?.key_data||!uuid(line?.id)||!uuid(line?.channel_id))return false;
 if(typeof line.stream_url!=="string"||line.stream_url.length>4096||/[\r\n]/.test(line.stream_url))return false;
 try{const u=new URL(line.stream_url);
  return (u.protocol==="http:"||u.protocol==="https:")&&!!u.hostname&&!u.username&&!u.password;
 }catch{return false;}
}
