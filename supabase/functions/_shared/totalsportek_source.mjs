// Public football metadata and literal, published player configurations only.
// Never execute provider scripts, refresh tokens, or fetch arbitrary iframe URLs.
const ROOT='https://totalsportekl.is';
const MATCH=/^\/[a-z0-9-]+-vs-[a-z0-9-]+\/(\d{1,10})\/?$/i;
const decode=s=>String(s||'').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&nbsp;/g,' ');
const plain=s=>decode(s).replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();
const attr=(tag,key)=>decode(tag.match(new RegExp('\\b'+key+'\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')','i'))?.slice(1).find(x=>x!==undefined)||'');
function url(value,base=ROOT){
 if(typeof value!=='string'||!value||value.length>4096)return null;
 try{const u=new URL(decode(value),base);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port?u:null;}catch{return null;}
}
function matchPage(value){const u=url(value);return u&&u.origin===ROOT&&MATCH.test(u.pathname)&&!u.search?u:null;}
function playerPage(value){
 const u=url(value);if(!u)return null;
 if(/^live[2-6]\.totalsportek\.today$/.test(u.hostname)&&MATCH.test(u.pathname)&&!u.search)return u;
 if(u.hostname==='total.footybite.info.pl'&&/^\/best\/player[1-5]\.php$/.test(u.pathname)&&
   /^\?ch=\d{1,4}$/.test(u.search))return u;
 if(u.hostname==='universaltokenforall.st'&&/^\/player[1-5]\/channel\d{1,4}$/.test(u.pathname)&&!u.search)return u;
 return null;
}
function mediaUrl(value){
 const u=url(value);
 return u&&u.hostname==='sha.sharpnessonline.store'&&/^\/simpch\d{1,4}\/index\.m3u8$/.test(u.pathname)&&
  [...u.searchParams.keys()].every(key=>key==='token')?u:null;
}

async function html(page,{fetcher,signal,referer}){
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),5000);
 const combined=AbortSignal.any([signal,controller.signal]);
 try{
  const response=await fetcher(page.href,{redirect:'manual',signal:combined,headers:{
   Accept:'text/html','User-Agent':'Mozilla/5.0',...(referer?{Referer:referer}:{}),
  }});
  if(!response.ok){controller.abort();await response.body?.cancel().catch(()=>{});throw new Error('Totalsportek page unavailable (HTTP '+response.status+').');}
  const reader=response.body?.getReader();if(!reader)throw new Error('Totalsportek page is empty.');
  let size=0;const chunks=[];
  try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
   if(size>2*1024*1024)throw new Error('Totalsportek page exceeds size limit.');chunks.push(value);}
  }finally{await reader.cancel().catch(()=>{});}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  return new TextDecoder().decode(bytes);
 }finally{clearTimeout(timer);controller.abort();}
}

export function parseTotalsportekMatches(markup){
 const rows=[],seen=new Set();let league='Football';
 const tokens=/<div\b[^>]*class=["'][^"']*\bleague-header\b[^"']*["'][^>]*>([\s\S]{0,1800}?)<\/div>|<a\b([^>]*class=["'][^"']*\bmodern-match-card\b[^"']*["'][^>]*)>([\s\S]{0,5000}?)<\/a>/gi;
 for(const hit of String(markup).matchAll(tokens)){
  if(hit[1]!==undefined){league=plain(hit[1].match(/<span\b[^>]*>([\s\S]*?)<\/span>/i)?.[1]||'Football');continue;}
  if(/\b(?:f1|formula\s*1|motogp|tennis|golf|rugby|nhl|nba|nfl|wwe|cricket|boxing|baseball|basketball|hockey|ufc|mma|cycling|volleyball)\b/i.test(league))continue;
  const page=matchPage(attr(hit[2],'href'));if(!page||seen.has(page.href))continue;
  const body=hit[3];if(/btn-highlight|Match\s*<\/span>\s*<span>\s*Ended/i.test(body))continue;
  const team=side=>body.match(new RegExp('<div\\b[^>]*class=["\'][^"\']*team-'+side+'[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/div>','i'))?.[1]||'';
  const home=team('left'),away=team('right'),homeName=plain(home),awayName=plain(away);
  if(!homeName||!awayName)continue;
  const id=page.pathname.match(MATCH)[1];
  const logo=block=>url(attr(block.match(/<img\b[^>]*>/i)?.[0]||'','src'))?.href||null;
  const live=/Match\s*<\/span>\s*<span>\s*Started/i.test(body);
  const timeLabel=plain(body.match(/class=["']match-time["'][^>]*>([\s\S]*?)<\/div>/i)?.[1]);
  seen.add(page.href);
  rows.push({source:'totalsportek',source_id:id,schedule_id:id,league,home_team:homeName,away_team:awayName,
   home_logo:logo(home),away_logo:logo(away),page_url:page.href,
   // The listing publishes relative countdowns, not exact kickoff timestamps.
   // Keep the time unknown until the selected event page supplies UK date/time.
   match_time:null,time_label:timeLabel,is_live:live,status:live?'LIVE':'SCHEDULED',hot:false,
   anchors:[{room_num:id,nick_name:'Totalsportek',page_url:page.href}],
  });
  if(rows.length>=160)break;
 }
 return rows;
}

export function totalsportekKickoff(markup){
 const description=attr(String(markup).match(/<meta\b[^>]*name=["']description["'][^>]*>/i)?.[0]||'','content');
 const match=description.match(/\b(20\d{2})-(\d{2})-(\d{2}),\s*(\d{1,2}):(\d{2})\s*uk time/i);
 if(!match)return null;
 const [,y,m,d,h,min]=match.map(Number);if(m<1||m>12||d<1||d>31||h>23||min>59)return null;
 const wall=Date.UTC(y,m-1,d,h,min);
 const checked=new Date(wall);if(checked.getUTCMonth()!==m-1||checked.getUTCDate()!==d)return null;
 const zone=new Intl.DateTimeFormat('en',{timeZone:'Europe/London',timeZoneName:'shortOffset'}).formatToParts(new Date(wall)).find(x=>x.type==='timeZoneName')?.value||'GMT';
 const offset=zone.match(/GMT([+-])(\d{1,2})(?::(\d{2}))?/);
 const minutes=offset?(offset[1]==='-'?-1:1)*(Number(offset[2])*60+Number(offset[3]||0)):0;
 return new Date(wall-minutes*60000).toISOString();
}

export async function totalsportekMatches({fetcher=fetch}={}){
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),6500);
 try{return parseTotalsportekMatches(await html(new URL(ROOT+'/football/'),{fetcher,signal:controller.signal}));}
 finally{clearTimeout(timer);controller.abort();}
}

export async function totalsportekStreams(body,{fetcher=fetch,now=Date.now()}={}){
 const page=matchPage(body.page_url);if(!page)throw new Error('Invalid Totalsportek football match page.');
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),10000);
 const lines=[],seen=new Set();let failed=0;
 try{
  const event=await html(page,{fetcher,signal:controller.signal});
  const players=[];
  for(const hit of event.matchAll(/<a\b[^>]*\bhref\s*=\s*(?:"([^"]+)"|'([^']+)')[^>]*>/gi)){
   const target=playerPage(hit[1]||hit[2]);
   // Only follow the provider's own published wrappers for this exact event.
   if(!target||!/^live[2-6]\.totalsportek\.today$/.test(target.hostname)||target.pathname.replace(/\/$/,'')!==page.pathname.replace(/\/$/,''))continue;
   if(!players.some(p=>p.href===target.href))players.push(target);
  }
  async function resolve(target,referer,depth,visited){
   if(depth>3||visited.has(target.href)||controller.signal.aborted)return;
   const nextVisited=new Set(visited);nextVisited.add(target.href);
   const text=await html(target,{fetcher,signal:controller.signal,referer});
   if(target.hostname==='universaltokenforall.st'){
    const literal=text.match(/\b(?:let|const|var)\s+streamUrl\s*=\s*("(?:\\.|[^"\\])*")/);
    let media=null;try{media=literal&&mediaUrl(JSON.parse(literal[1]));}catch{}
    if(media&&!seen.has(media.origin+media.pathname)){
     let expiry=null;
     try{
      const payload=media.searchParams.get('token')?.split('.')[0]||'';
      const exp=Number(JSON.parse(atob(payload.replace(/-/g,'+').replace(/_/g,'/'))).exp);
      if(Number.isFinite(exp)&&exp>0)expiry=new Date(exp*1000).toISOString();
     }catch{}
     if(expiry&&Date.parse(expiry)<=now)return;
     seen.add(media.origin+media.pathname);const channel=target.pathname.match(/channel(\d+)/)?.[1]||'';
     lines.push({id:'totalsportek:'+page.pathname.match(MATCH)[1]+':'+channel,
      label:'Totalsportek • Channel '+channel,url:media.href,stream_type:'hls',
      referer:target.href,origin:target.origin,health_status:'unknown',expires_at:expiry});
    }
    return;
   }
   const frames=[...text.matchAll(/<iframe\b[^>]*\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)')[^>]*>/gi)]
    .map(m=>playerPage(m[1]||m[2])).filter(Boolean).slice(0,2);
   for(const frame of frames)await resolve(frame,target.href,depth+1,nextVisited);
  }
  let index=0;const selected=players.slice(0,5);
  await Promise.all(Array.from({length:Math.min(3,selected.length)},async()=>{
   while(index<selected.length){const target=selected[index++];
    try{await resolve(target,page.href,0,new Set());}catch{failed++;}
   }
  }));
  if(!lines.length&&failed)throw new Error('Totalsportek player servers are temporarily unavailable.');
  lines.sort((a,b)=>a.id.localeCompare(b.id));
  return {ok:true,source:'totalsportek',lines,live_status:null,match_time:totalsportekKickoff(event)};
 }finally{clearTimeout(timer);controller.abort();}
}
