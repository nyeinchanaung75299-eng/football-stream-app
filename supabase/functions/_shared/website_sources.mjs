// Public source adapters: literal page metadata only; no script execution,
// credentials, login bypass or arbitrary caller-supplied fetch destinations.
const ROOTS = {xoilac:'https://xoilaczcb.tv/', camel:'https://www.camel1.tv/'};
const decode = value => String(value || '').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&nbsp;/g,' ');
const plain = value => decode(value).replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();
function attribute(html,name){return decode(html.match(new RegExp('\\b'+name+'=(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))','i'))?.slice(1).find(v=>v!==undefined)||'');}
function literalJson(text,start){
 let depth=0,quoted=false,escaped=false;
 for(let i=start;i<text.length;i++){
  const c=text[i];
  if(quoted){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c==='"')quoted=false;continue;}
  if(c==='"'){quoted=true;continue;}if(c==='{'||c==='[')depth++;
  if((c==='}'||c===']')&&--depth===0)return JSON.parse(text.slice(start,i+1));
 }
 throw new Error('Source metadata is incomplete.');
}
function publicPage(source,value){
 if(typeof value!=="string"||value.length>2048)return null;
 try{const u=new URL(value,ROOTS[source]);
  if(u.protocol!=='https:'||u.username||u.password||u.port)return null;
  if(source==='xoilac'&&u.hostname==='xoilaczcb.tv'&&/^\/truc-tiep\/[a-z0-9-]+\/(?:link\/\d+\/?)?$/.test(u.pathname))return u;
  if(source==='camel'&&u.hostname==='www.camel1.tv'&&/^\/football\/match-[a-z0-9-]+\/(?:live\/)?[a-z0-9]+\/?$/.test(u.pathname))return u;
 }catch{}return null;
}
export function parseXoilac(html,now=Date.now()){
 const out=[],seen=new Set();
 for(const block of String(html).split(/(?=<div\s+class="grid-matches__item )/)){
  const tag=block.slice(0,block.indexOf('>')+1);
  if(attribute(tag,'data-sport')!=='football')continue;
  const anchor=block.match(/<a\b[^>]*\bclass="redirectPopup"[^>]*>/)?.[0];
  if(!anchor)continue;
  const url=publicPage('xoilac',attribute(anchor,'href'));if(!url||seen.has(url.href))continue;
  const title=attribute(anchor,'title');const names=title.match(/^(.*?)\s+vs\s+(.*?)\s+lúc\b/iu);if(!names)continue;
  const time=Number(attribute(tag,'data-runtime'))*1000;if(!Number.isFinite(time)||now-time>4*3600000||![1,2,3,4,5,6,7].includes(Number(attribute(tag,'data-status'))))continue;
  seen.add(url.href);const id=attribute(tag,'data-fid')||url.pathname.split('/')[2];
  const league=plain(block.match(/class="grid-match__league"[^>]*>[\s\S]*?<span\b[^>]*>([\s\S]*?)<\/span>/)?.[1]||'Football');
  const logo=side=>attribute(block.match(new RegExp('class="[^"\\n]*team--'+side+'[^"\\n]*"[\\s\\S]*?<img\\b[^>]*>'))?.[0]||'','src')||null;
  out.push({source:'xoilac',source_id:id,schedule_id:id,league,home_team:plain(names[1]),away_team:plain(names[2]),home_logo:logo('home'),away_logo:logo('away'),match_time:new Date(time).toISOString(),hot:attribute(tag,'data-hot')==='1',status:Number(attribute(tag,'data-status'))>1?'LIVE':'UPCOMING',page_url:url.href,anchors:[{room_num:id,nick_name:'Xoilac',page_url:url.href}]});
  if(out.length>=500)break;
 }
 return out;
}
export function parseCamel(html,now=Date.now()){
 const chunks=[];for(const m of String(html).matchAll(/self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)/g)){
  try{chunks.push(JSON.parse(m[1]));}catch{}
 }
 const text=chunks.join('\n');const marker='"matchData":';const at=text.indexOf(marker);
 if(at<0)throw new Error('Camel1 public match metadata unavailable.');
 const data=literalJson(text,at+marker.length);const out=[],seen=new Set();
 const hrefs=[...String(html).matchAll(/href="([^"<>]+\/([a-z0-9]{8,}))"/g)];
 for(const key of ['living_group','hot_group','obs_group']){
  for(const group of Array.isArray(data[key])?data[key]:[]){for(const row of group.match||[]){
   const id=String(row.id||'');const time=Number(row.match_time)*1000;
   if(!id||seen.has(id)||row.is_blocked||!Number.isFinite(time)||now-time>4*3600000)continue;
   const href=hrefs.find(m=>m[2]===id&&m[1].startsWith('/football/match-'))?.[1];
   const url=href&&publicPage('camel',href);if(!url)continue;
   seen.add(id);const team=x=>plain(x?.name_en||x?.name||'');
   out.push({source:'camel',source_id:id,schedule_id:id,league:plain(group.competition?.name_en||group.competition?.name||'Football'),home_team:team(row.home_team),away_team:team(row.away_team),home_logo:row.home_team?.logo||null,away_logo:row.away_team?.logo||null,match_time:new Date(time).toISOString(),status:Number(row.status_id)>1&&Number(row.status_id)<8?'LIVE':'UPCOMING',page_url:url.href,requires_login:true,anchors:[{room_num:id,nick_name:'Open Camel1',page_url:url.href}]});
  }}
 }
 return out.slice(0,500);
}
async function boundedFetch(url,fetcher,redirects=0){
 const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),6500);
 try{
  const response=await fetcher(String(url),{redirect:'manual',signal:controller.signal,headers:{Accept:'text/html,application/json', 'User-Agent':'NCA-Source/1.0'}});
  if(response.status>=300 && response.status<400){
   const next=new URL(response.headers.get('Location')||'',String(url));
   const current=new URL(String(url));
   const sameRoute=next.pathname.replace(/\/$/,'')===current.pathname.replace(/\/$/,'');
   const camelHome=current.hostname==='www.camel1.tv'&&['/','/en','/en/'].includes(next.pathname);
   void response.body?.cancel().catch(()=>{});
   if(!response.headers.get('Location')||redirects>=2||next.origin!==current.origin||next.username||next.password||next.search||(!sameRoute&&!camelHome))throw new Error('Unsupported source redirect.');
   return await boundedFetch(next,fetcher,redirects+1);
  }
  if(!response.ok){void response.body?.cancel().catch(()=>{});throw new Error('Source returned HTTP '+response.status+'.');}
  const reader=response.body?.getReader();if(!reader)throw new Error('Empty source response.');
  let bytes=0;const chunks=[];
  try{while(true){const {done,value}=await reader.read();if(done)break;bytes+=value.length;if(bytes>3*1024*1024)throw new Error('Source page is too large.');chunks.push(value);}}finally{void reader.cancel().catch(()=>{});}
  const all=new Uint8Array(bytes);let offset=0;for(const chunk of chunks){all.set(chunk,offset);offset+=chunk.length;}return new TextDecoder().decode(all);
 }finally{clearTimeout(timer);controller.abort();}
}
export async function websiteMatches(source,{fetcher=fetch,now=Date.now()}={}){
 if(!ROOTS[source])throw new Error('Unsupported source.');
 const html=await boundedFetch(ROOTS[source],fetcher);
 return source==='xoilac'?parseXoilac(html,now):parseCamel(html,now);
}
export async function websiteStreams(source,body,{fetcher=fetch}={}){
 if(source==='camel')return {ok:false,source,requires_login:true,error:'Camel1 requires sign-in on its own website. Open Camel1 to watch.',lines:[]};
 const page=publicPage('xoilac',body.page_url);if(!page)throw new Error('Invalid Xoilac match page.');
 const html=await boundedFetch(page,fetcher);const found=html.match(/\b(?:var|let|const)\s+list_stream\s*=\s*(\[)/);
 if(!found)return {ok:true,source,lines:[],live_status:false};
 const groups=literalJson(html,found.index+found[0].length-1);const targets=[];
 for(const group of groups)for(const value of Array.isArray(group)?group:[]){
  try{const u=new URL(value);if(u.protocol==='https:'&&u.hostname==='xlz.domainkqt.cc'&&!u.port&&!u.username&&!u.password&&/^\/ajax\/chanel\/type\/\d+\/link\/[a-zA-Z0-9_-]+\/?$/.test(u.pathname)&&!u.search)targets.push(u.href);}catch{}
 }
 const lines=[];const failures=[];
 await Promise.all([...new Set(targets)].slice(0,4).map(async(target,index)=>{
  try{
   const player=await boundedFetch(target,fetcher);const literal=player.match(/\bvar\s+urlStream\s*=\s*("(?:[^"\\]|\\.)*")\s*;/);
   if(!literal)return;const u=new URL(JSON.parse(literal[1]));
   if(u.protocol!=='https:'||u.username||u.password||u.port||!/^live\d*\.quickscoreboardz\.com$/.test(u.hostname))return;
   const type=u.pathname.match(/\.(m3u8|mpd|flv|mp4)$/i)?.[1]?.toLowerCase();if(!type)return;
   lines.push({id:'xoilac:'+index,label:'Xoilac '+(index+1),url:u.href,stream_type:{m3u8:'hls',mpd:'dash',flv:'flv',mp4:'mp4'}[type],referer:target,origin:new URL(target).origin,health_status:'unknown'});
  }catch(error){failures.push(error instanceof Error?error.message:'Source player unavailable.');}
 }));
 if(!lines.length&&failures.length)throw new Error('Xoilac player unavailable. '+failures[0]);
 return {ok:true,source,lines,live_status:lines.length>0};
}
