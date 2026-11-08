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
 if(/^live[2-6]?\.totalsportek\.today$/.test(u.hostname)&&MATCH.test(u.pathname)&&!u.search)return u;
 if(u.hostname==='total.footybite.info.pl'&&/^\/best\/player[1-5]\.php$/.test(u.pathname)&&
   /^\?ch=\d{1,4}$/.test(u.search))return u;
 if(u.hostname==='universaltokenforall.st'&&/^\/player[1-5]\/channel\d{1,4}$/.test(u.pathname)&&!u.search)return u;
 if(u.hostname==='soccerstreamlinks.st'&&/^\/player\.php\/[a-z0-9-]{1,200}$/.test(u.pathname)&&!u.search)return u;
 if(u.hostname==='bestropes.st'&&/^\/player\.php\/[a-z0-9-]{1,200}$/.test(u.pathname)&&!u.search)return u;
 if(u.hostname==='sportsguru.st'&&u.pathname==='/guru/total.php'&&u.search.length<512)return u;
 if(u.hostname==='s3.vertex.st'&&u.pathname==='/ch'&&/^\?id=\d{1,6}$/.test(u.search))return u;
 if(['ch.nexa.st','ripple.kora.st','s1.virazo.sx'].includes(u.hostname)&&
   ['/ch','/stream'].includes(u.pathname)&&/^\?id=\d{1,6}$/.test(u.search))return u;
 const reviewedParents={
  'kumku.cfd':/^\/tot-\d{1,4}\/k\d{1,4}\.php$/,
  'rainostreams.lol':/^\/Rai-T\d{1,4}\/\d{1,4}\.html$/,
  'amaansports.sbs':/^\/tot-\d{1,4}\/k\d{1,4}\.php$/,
  'pianoplays.biz':/^\/Is-\d{1,4}\/lie\/\d{1,4}\.html$/,
  'iusman.lol':/^\/tot-\d{1,4}\/k\d{1,4}\.php$/,
  'ytstreams.club':/^\/YT\d{1,6}\/Nexa\/\d{1,4}\.html$/,
  '9soccer.biz':/^\/T\d{1,4}\/Ch\d{1,4}\/\d{1,4}\.html$/,
  'alphastreams.mom':/^\/20\d{2}\/\d{2}\/\d{2}\/[a-z0-9-]{1,200}\/$/,
  'dotplay.click':/^\/t\d{1,4}\/\d{1,4}\.php$/,
  'goodstream.click':/^\/st\d{1,4}\/\d{1,4}\.php$/,
 };
 if(reviewedParents[u.hostname]?.test(u.pathname)&&!u.search)return u;
 if(u.hostname==='matchli.st'&&['/embed.php','/embed-edge.php'].includes(u.pathname)&&/^\?code=[a-zA-Z0-9_-]{1,128}$/.test(u.search))return u;
 return null;
}
export function totalsportekMediaIdentity(value){
 const u=mediaUrl(value);if(!u)return null;
 for(const key of ['token','e','sig'])u.searchParams.delete(key);
 u.searchParams.sort();return u.href;
}
function mediaUrl(value){
 const u=url(value);
 if(!u)return null;
 if(u.hostname==='sha.sharpnessonline.store'&&/^\/simpch\d{1,4}\/index\.m3u8$/.test(u.pathname)&&
   [...u.searchParams.keys()].every(key=>key==='token'))return u;
 if(u.hostname==='hls.lshls.st'&&u.pathname==='/secure_hls.php'&&
   [...u.searchParams.keys()].every(key=>['path','e','sig'].includes(key))&&
   u.searchParams.has('path')&&u.searchParams.has('sig'))return u;
 return null;
}

export function totalsportekPlayers(markup,pageValue){
 const page=matchPage(String(pageValue));if(!page)return [];
 const out=[],seen=new Set();
 for(const hit of String(markup).matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)){
  const target=url(attr(hit[1],'href'));if(!target||seen.has(target.href)||target.origin===ROOT||
    /^[\d.]+$|:|(^|\.)(localhost|local|internal|test|invalid)$/.test(target.hostname))continue;
  const own=/^live[2-6]?\.totalsportek\.today$/.test(target.hostname)&&
    target.pathname.replace(/\/$/,'')===page.pathname.replace(/\/$/,'');
  if(!own&&!/\bnocolor\b/.test(attr(hit[1],'class')))continue;
  const column=hit[2].match(/<div\b[^>]*class=["'][^"']*\bcol-md-3\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i)?.[1];
  const label=plain(column||hit[2]).replace(/&#(?:x[\da-f]+|\d+);?/gi,'').trim().slice(0,100);
  if(!label)continue;
  seen.add(target.href);out.push({label,url:target.href});if(out.length>=80)break;
 }
 return out;
}

async function html(page,{fetcher,signal,referer,headOnly=false,redirects=0}){
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),5000);
 const combined=AbortSignal.any([signal,controller.signal]);
 try{
  const response=await fetcher(page.href,{redirect:'manual',signal:combined,headers:{
   Accept:'text/html','User-Agent':'Mozilla/5.0',...(referer?{Referer:referer}:{}),
  }});
  if([301,302,307,308].includes(response.status)&&page.hostname==='matchli.st'&&
    page.pathname==='/embed.php'&&redirects===0){
   let next=null;try{next=playerPage(new URL(response.headers.get('Location')||'',page).href);}catch{}
   await response.body?.cancel().catch(()=>{});
   if(next?.origin===page.origin&&next.pathname==='/embed-edge.php'&&next.search===page.search){
    return await html(next,{fetcher,signal,referer,headOnly,redirects:1});
   }
   throw new Error('Unsupported Totalsportek player redirect.');
  }
  if(!response.ok){controller.abort();await response.body?.cancel().catch(()=>{});throw new Error('Totalsportek page unavailable (HTTP '+response.status+').');}
  const reader=response.body?.getReader();if(!reader)throw new Error('Totalsportek page is empty.');
  let size=0;const chunks=[];let head='';const decoder=new TextDecoder();
  try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
   if(headOnly){
    const available=Math.max(0,128*1024-(size-value.length));
    head+=decoder.decode(value.subarray(0,available),{stream:true});
    const end=head.toLowerCase().indexOf('</head>');if(end>=0)return head.slice(0,end+7);
   }
   if(size>(headOnly?128*1024:2*1024*1024))throw new Error('Totalsportek page exceeds size limit.');
   if(!headOnly)chunks.push(value);}
  }finally{await reader.cancel().catch(()=>{});}
  if(headOnly)return head+decoder.decode();
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  return new TextDecoder().decode(bytes);
 }finally{clearTimeout(timer);controller.abort();}
}

export function parseTotalsportekMatches(markup){
 const rows=[],seen=new Set();let league='Football';
 const tokens=/<div\b[^>]*class=["'][^"']*\bleague-header\b[^"']*["'][^>]*>([\s\S]{0,1800}?)<\/div>|<a\b([^>]*class=["'][^"']*\bmodern-match-card\b[^"']*["'][^>]*)>([\s\S]{0,5000}?)<\/a>/gi;
 for(const hit of String(markup).matchAll(tokens)){
  if(hit[1]!==undefined){league=plain(hit[1].match(/<span\b[^>]*>([\s\S]*?)<\/span>/i)?.[1]||'Football');continue;}
  if(/\b(?:f1|formula\s*1|motogp|tennis|golf|rugby|nhl|nba|nfl|ncaa|ncaaf|cfl|american\s+football|college\s+football|wwe|cricket|boxing|baseball|basketball|hockey|ufc|mma|cycling|volleyball)\b/i.test(league))continue;
  const page=matchPage(attr(hit[2],'href'));if(!page||seen.has(page.href))continue;
  const body=hit[3];if(/btn-highlight|Match\s*<\/span>\s*<span>\s*Ended/i.test(body))continue;
  const team=side=>body.match(new RegExp('<div\\b[^>]*class=["\'][^"\']*team-'+side+'[^"\']*["\'][^>]*>([\\s\\S]*?)<\\/div>','i'))?.[1]||'';
  const home=team('left'),away=team('right'),homeName=plain(home),awayName=plain(away);
  if(!homeName||!awayName)continue;
  const id=page.pathname.match(MATCH)[1];
  const logo=block=>url(attr(block.match(/<img\b[^>]*>/i)?.[0]||'','src'))?.href||null;
  const live=/Match\s*<\/span>\s*<span>\s*Started/i.test(body);
  const timeLabel=plain(body.match(/class=["']match-time["'][^>]*>([\s\S]*?)<\/div>/i)?.[1]);
  const countdown=timeLabel.match(/^(?:(\d+)\s*days?\s*)?(?:(\d+)\s*hr\s*)?(?:(\d+)\s*m\s*)?from now$/i);
  const countdownMinutes=countdown&&countdown.slice(1).some(Boolean)
   ?Number(countdown[1]||0)*1440+Number(countdown[2]||0)*60+Number(countdown[3]||0):null;
  seen.add(page.href);
  rows.push({source:'totalsportek',source_id:id,schedule_id:id,league,home_team:homeName,away_team:awayName,
   home_logo:logo(home),away_logo:logo(away),page_url:page.href,
   // The listing publishes relative countdowns, not exact kickoff timestamps.
   // Keep the time unknown until the selected event page supplies UK date/time.
   match_time:null,time_label:timeLabel,countdown_minutes:countdownMinutes,is_live:live,status:live?'LIVE':'SCHEDULED',hot:false,
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
  if(body.metadata_only===true||body.metadata_only==='1'){
   const head=await html(page,{fetcher,signal:controller.signal,headOnly:true});
   return {ok:true,source:'totalsportek',metadata_only:true,lines:[],match_time:totalsportekKickoff(head)};
  }
  const event=await html(page,{fetcher,signal:controller.signal});
  const externalPlayers=totalsportekPlayers(event,page.href);
  const players=[];
  const chosen=body.player_url?externalPlayers.find(item=>item.url===body.player_url):null;
  if(body.player_url&&!chosen)throw new Error('The selected player is not published for this match.');
  for(const item of externalPlayers){
   const target=playerPage(item.url);
   // Only follow the provider's own published wrappers for this exact event.
   if(!target||!/^live[2-6]?\.totalsportek\.today$/.test(target.hostname)||target.pathname.replace(/\/$/,'')!==page.pathname.replace(/\/$/,''))continue;
   if(!players.some(p=>p.href===target.href))players.push(target);
  }
  if(chosen){players.length=0;const target=playerPage(chosen.url);if(target)players.push(target);}
  async function resolve(target,referer,depth,visited){
   if(depth>7||visited.has(target.href)||controller.signal.aborted)return;
   const nextVisited=new Set(visited);nextVisited.add(target.href);
   const text=await html(target,{fetcher,signal:controller.signal,referer});
   if(target.hostname==='bestropes.st'){
    const literal=text.match(/\b(?:const|let|var)\s+SERVER_DATA\s*=\s*(\{[^\r\n]{1,16384}\})\s*;/);
    let next=null;try{next=literal&&playerPage(JSON.parse(literal[1]).u);}catch{}
    if(next?.hostname==='s3.vertex.st')await resolve(next,target.href,depth+1,nextVisited);
    return;
   }
   if(target.hostname==='soccerstreamlinks.st'){
    if(!text.includes('_player_data'))return;
    const dataUrl=new URL(target);dataUrl.searchParams.set('_player_data','1');
    const data=JSON.parse(await html(dataUrl,{fetcher,signal:controller.signal,referer:target.href}));
    const next=playerPage(data?.u);if(next?.hostname==='s3.vertex.st')await resolve(next,target.href,depth+1,nextVisited);
    return;
   }
   if(['s3.vertex.st','ch.nexa.st','ripple.kora.st','s1.virazo.sx'].includes(target.hostname)){
    if(!text.includes('api/player.php?id='))return;
    const endpoint=new URL('/api/player.php',target);endpoint.searchParams.set('id',target.searchParams.get('id'));
    const data=JSON.parse(await html(endpoint,{fetcher,signal:controller.signal,referer:target.href}));
    const next=playerPage(data?.url);if(next?.hostname==='matchli.st')await resolve(next,target.href,depth+1,nextVisited);
    return;
   }
   if(target.hostname==='matchli.st'){
    const literal=text.match(/window\.PP_STABLE_CONFIG\s*=\s*(\{[^\r\n]{1,16384}\})\s*;/);
    let media=null;try{media=literal&&mediaUrl(JSON.parse(literal[1]).src);}catch{}
    const identity=media&&totalsportekMediaIdentity(media.href);
    if(media&&!seen.has(identity)){
     const exp=Number(media.searchParams.get('e'));
     const expiry=Number.isFinite(exp)&&exp>0?new Date(exp*1000).toISOString():null;
     if(expiry&&Date.parse(expiry)<=now)return;
     seen.add(identity);lines.push({id:'totalsportek:'+page.pathname.match(MATCH)[1]+':soccerstreams:'+lines.length,
      label:'SoccerStreamLinks',url:media.href,stream_type:'hls',
      referer:target.href,origin:target.origin,health_status:'unknown',expires_at:expiry});
    }
    return;
   }
   if(target.hostname==='universaltokenforall.st'){
    const literal=text.match(/\b(?:let|const|var)\s+streamUrl\s*=\s*("(?:\\.|[^"\\])*")/);
    let media=null;try{media=literal&&mediaUrl(JSON.parse(literal[1]));}catch{}
    const identity=media&&totalsportekMediaIdentity(media.href);
    if(media&&!seen.has(identity)){
     let expiry=null;
     try{
      const payload=media.searchParams.get('token')?.split('.')[0]||'';
      const exp=Number(JSON.parse(atob(payload.replace(/-/g,'+').replace(/_/g,'/'))).exp);
      if(Number.isFinite(exp)&&exp>0)expiry=new Date(exp*1000).toISOString();
     }catch{}
     if(expiry&&Date.parse(expiry)<=now)return;
     seen.add(identity);const channel=target.pathname.match(/channel(\d+)/)?.[1]||'';
     lines.push({id:'totalsportek:'+page.pathname.match(MATCH)[1]+':'+channel,
      label:'Channel '+channel,url:media.href,stream_type:'hls',
      referer:target.href,origin:target.origin,health_status:'unknown',expires_at:expiry});
    }
    return;
   }
   const frames=[...text.matchAll(/<iframe\b[^>]*\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)')[^>]*>/gi)]
    .map(m=>{try{return playerPage(new URL(m[1]||m[2],target).href);}catch{return null;}}).filter(Boolean).slice(0,4);
   for(const frame of frames)await resolve(frame,target.href,depth+1,nextVisited);
  }
  // Resolve the two verified literal player families first. Large unsupported
  // wrappers must not consume the request budget before those chains start.
  const rank=target=>target.hostname==='live3.totalsportek.today'?0:
    target.hostname==='live6.totalsportek.today'?1:2;
  let index=0;const selected=players.sort((a,b)=>rank(a)-rank(b)).slice(0,6);
  await Promise.all(Array.from({length:Math.min(3,selected.length)},async()=>{
   while(index<selected.length){const target=selected[index++];
    try{await resolve(target,page.href,0,new Set());}catch{failed++;}
   }
  }));
  if(!lines.length&&failed&&!externalPlayers.length)throw new Error('Totalsportek player servers are temporarily unavailable.');
  lines.sort((a,b)=>a.id.localeCompare(b.id));
  if(chosen)for(const line of lines)line.label=chosen.label+' • '+line.label;
  return {ok:true,source:'totalsportek',lines,external_players:chosen?[]:externalPlayers,live_status:null,match_time:totalsportekKickoff(event),
   ...(lines.length?{}:{message:'Totalsportek has no supported direct video line for this match right now. Its website may offer an external player.'})};
 }finally{clearTimeout(timer);controller.abort();}
}
