// A fixed public API fallback on an independent network. No database/service
// credentials, Admin/Auth/REST routes, arbitrary upstreams, or media relay.
const PUBLIC_ORIGIN = 'https://football-api.nyeinchanaung.us.ci';
const CORS = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET,HEAD,POST,OPTIONS',
 'Access-Control-Allow-Headers':'apikey,content-type,cache-control','X-Content-Type-Options':'nosniff'};
const UUID='[0-9a-fA-F-]{36}';
const SOURCE='(?:soco|yyzb|cola|fawa|repository)';
function route(path, method) {
 if (['GET','HEAD'].includes(method)) {
  if (['/matches','/channels','/tv-schedule'].includes(path))return {ttl:path==='/tv-schedule'?30:15,image:false};
  if (/^\/team-logos\/\d{1,12}$/.test(path)||new RegExp('^/channel-logos/'+UUID+'$').test(path))return {ttl:3600,image:true};
  if (new RegExp('^/sources/'+SOURCE+'/matches$').test(path))return {ttl:15,image:false};
  if (new RegExp('^/(?:matches|channels)/'+UUID+'/streams$').test(path))return {ttl:0,image:false};
 }
 if (method==='POST'&&new RegExp('^/sources/'+SOURCE+'/streams$').test(path))return {ttl:0,image:false};
 return null;
}
async function readBounded(body, limit) {
 const reader=body?.getReader();if(!reader)return new Uint8Array();
 const chunks=[];let size=0;
 try {for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>limit)throw Error('Response budget exceeded');chunks.push(value);}}
 finally {await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(size);let offset=0;
 for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
}
export function createViewerNetworkApi({apiKey,fetcher=globalThis.fetch,now=Date.now}={}) {
 const cache=new Map(),limits=new Map();let cachedBytes=0;
 const json=(body,status)=>Response.json(body,{status,headers:{...CORS,'Cache-Control':'no-store'}});
 return async function handle(request) {
  const incoming=new URL(request.url);
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers:CORS});
  // The key is the existing public publishable key, never a user/service JWT.
  if(!apiKey||(request.headers.get('apikey')||incoming.searchParams.get('apikey'))!==apiKey)
   return json({error:'Public API key required.'},401);
  const path=incoming.pathname.replace(/^\/(?:functions\/v1\/)?viewer-network-api(?=\/|$)/,'')||'/';
  if(path==='/health'&&request.method==='GET')return json({ok:true,service:'viewer-network-api'},200);
  const spec=route(path,request.method);if(!spec)return json({error:'Route not available.'},404);
  const upstream=new URL(path,PUBLIC_ORIGIN);
  const allowed=spec.image?['v']:['date','days','fresh','source_id','schedule_id','room_num'];
  for(const name of allowed)if(incoming.searchParams.has(name))upstream.searchParams.set(name,incoming.searchParams.get(name));
  const fresh=incoming.searchParams.get('fresh')==='1'||/(?:^|,)\s*no-cache\b/i.test(request.headers.get('Cache-Control')||'');
  const cacheUrl=new URL(upstream);cacheUrl.searchParams.delete('fresh');
  const cacheKey=cacheUrl.href;
  const reply=(entry)=>new Response(request.method==='HEAD'?null:entry.bytes,{status:200,headers:{...CORS,'Content-Type':entry.type,
   'Cache-Control':spec.ttl&&!fresh?`public, max-age=${spec.ttl}`:'no-store'}});
  const hit=cache.get(cacheKey);
  if(!fresh&&spec.ttl&&hit&&hit.until>now())return reply(hit);
  const ip=(request.headers.get('x-forwarded-for')||'anonymous').split(',')[0].slice(0,100);
  let budget=limits.get(ip);if(!budget||budget.until<=now())budget={count:0,until:now()+60000};
  limits.set(ip,budget);if(++budget.count>180)return json({error:'Please retry shortly.'},429);
  if(limits.size>1000)for(const [key,value] of limits)if(value.until<=now())limits.delete(key);
  if(limits.size>1000)limits.delete(limits.keys().next().value);
  const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),spec.image?8000:15000);
  try {
   const headers={Accept:spec.image?'image/png,image/jpeg,image/webp':'application/json'};
   let body;
   if(request.method==='POST'){
    const bytes=await readBounded(request.body,16384);body=new TextDecoder().decode(bytes);
    JSON.parse(body);headers['Content-Type']='application/json';
   }
   if(fresh)headers['Cache-Control']='no-cache';
   let response=await fetcher(upstream.href,{method:request.method==='HEAD'?'GET':request.method,headers,body,
    redirect:'manual',signal:controller.signal});
   if(!response.ok&&path==='/sources/soco/matches'&&request.method!=='POST'){
    await response.body?.cancel();
    // Recover only the one fixed public Soco feed. Never accept a caller URL
    // or publish raw JSONP/provider fields in the catalog response.
    const catalog=await fetcher('https://json.vnres.co/matches.json',{
      headers:{Accept:'application/javascript,application/json','User-Agent':'Mozilla/5.0',Origin:'https://m.sutbongtv.com',Referer:'https://m.sutbongtv.com/'},
      redirect:'manual',signal:controller.signal,
    });
    if(catalog.ok){
      const {socoCatalog}=await import('./soco_catalog.mjs');
      const raw=await readBounded(catalog.body,6*1024*1024);
      response=Response.json(socoCatalog(new TextDecoder().decode(raw),{now:now()}));
    }else{
      await catalog.body?.cancel();
      // A provider may reject this server network. Reuse a recent verified
      // public snapshot; an outage/error file must never become empty success.
      const base='https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/';
      const options={headers:{Accept:'application/json'},redirect:'manual',signal:controller.signal};
      const stamp=await fetcher(base+'source-status.json?t='+Math.floor(now()/60000),options);
      if(!stamp.ok){await stamp.body?.cancel();throw Error('Snapshot status unavailable');}
      const health=JSON.parse(new TextDecoder().decode(await readBounded(stamp.body,32768)));
      const updated=health?.sources?.soco?.last_successful_update_at;
      const age=now()-Date.parse(updated||'');
      if(!Number.isFinite(age)||age< -60000||age>15*60000)throw Error('Snapshot expired');
      const snapshotResponse=await fetcher(base+'sources/soco.json?t='+Math.floor(now()/60000),options);
      if(!snapshotResponse.ok){await snapshotResponse.body?.cancel();throw Error('Snapshot unavailable');}
      const snapshot=JSON.parse(new TextDecoder().decode(await readBounded(snapshotResponse.body,2097152)));
      if(snapshot?.ok!==true||!Array.isArray(snapshot.matches))throw Error('Invalid snapshot');
      const {socoCatalog}=await import('./soco_catalog.mjs');
      const publicData=socoCatalog(JSON.stringify({code:200,data:snapshot.matches.map(row=>({...row,hostName:row.home_team,guestName:row.away_team}))}),{now:now()});
      publicData.generated_at=updated;publicData.fallback_transport='github_snapshot';
      response=Response.json(publicData);
    }
   }
   if(!response.ok){await response.body?.cancel();return json({error:'Public source temporarily unavailable.'},response.status>=400&&response.status<600?response.status:502);}
   const type=response.headers.get('Content-Type')||'';
   if(spec.image?!/^image\/(?:png|jpe?g|webp)(?:;|$)/i.test(type):!/application\/json/i.test(type)){
    await response.body?.cancel();throw Error('Invalid public response');
   }
   const bytes=await readBounded(response.body,spec.image?1048576:2097152);
   const entry={bytes,type,until:now()+spec.ttl*1000};
   if(spec.ttl){
    const old=cache.get(cacheKey);if(old)cachedBytes-=old.bytes.byteLength;
    cache.delete(cacheKey);cache.set(cacheKey,entry);cachedBytes+=bytes.byteLength;
    while(cache.size>128||cachedBytes>8388608){const key=cache.keys().next().value;cachedBytes-=cache.get(key).bytes.byteLength;cache.delete(key);}
   }
   return reply(entry);
  }catch(_){return json({error:'Public source temporarily unavailable. Retry shortly.'},502);}
  finally {clearTimeout(timer);}
 };
}
