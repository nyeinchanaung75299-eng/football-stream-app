import {socoCatalog} from './soco_catalog.mjs';
const KEY='soco-public-metadata-v1';
const MAX_AGE=15*60000;
async function boundedText(response,limit=6*1024*1024){
 const reader=response.body.getReader(),decoder=new TextDecoder();let size=0,text='';
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>limit)throw Error('Catalog exceeds budget');text+=decoder.decode(value,{stream:true});}
  return text+decoder.decode();
 }finally{await reader.cancel().catch(()=>{});}
}
export async function readSocoSnapshot(env,{now=Date.now()}={}){
 if(!env.SOURCE_SNAPSHOTS)return null;
 try{
  const data=await env.SOURCE_SNAPSHOTS.get(KEY,'json');
  const age=now-Date.parse(data?.generated_at||'');
  if(data?.ok!==true||!Array.isArray(data.matches)||!Number.isFinite(age)||age<0||age>MAX_AGE)return null;
  // Keep the actual successful acquisition time; reads never make a snapshot newer.
  return data;
 }catch{return null;}
}
export async function refreshSocoSnapshot(env,{fetcher=fetch,now=Date.now()}={}){
 if(!env.SOURCE_SNAPSHOTS)return {ok:false,reason:'storage_missing'};
 let data,transport='http';
 try{
  const response=await fetcher('https://json.vnres.co/matches.json',{
   headers:{Accept:'application/javascript,application/json','User-Agent':'Mozilla/5.0'},
   redirect:'manual',signal:AbortSignal.timeout(6000),
  });
  if(!response.ok){await response.body?.cancel();throw Error('Catalog unavailable');}
  data=socoCatalog(await boundedText(response),{now});
 }catch{
  if(!env.BROWSER)return {ok:false,reason:'browser_missing'};
  const budgetKey='browser-budget-'+new Date(now).toISOString().slice(0,10);
  let spent=Number(await env.SOURCE_SNAPSHOTS.get(budgetKey))||0;
  // At most five minutes of measured browser wall time per day for this
  // publisher. Reserve before starting, including failures. No per-viewer scan.
  if(spent+6000>300000)return {ok:false,reason:'daily_browser_budget'};
  await env.SOURCE_SNAPSHOTS.put(budgetKey,String(spent+6000),{expirationTtl:172800});
  const started=Date.now();
  try{
   transport='browser';
   const response=await env.BROWSER.quickAction('content',{
    url:'https://json.vnres.co/matches.json',
    gotoOptions:{waitUntil:'domcontentloaded',timeout:2500},actionTimeout:2000,
    rejectResourceTypes:['image','media','font','stylesheet'],setJavaScriptEnabled:false,
   });
   if(!response.ok){await response.body?.cancel();return {ok:false,reason:'browser_http_'+response.status};}
   const payload=JSON.parse(await boundedText(response));
   if(payload.success!==true||typeof payload.result!=='string')return {ok:false,reason:'browser_response'};
   const pre=payload.result.match(/<pre\b[^>]*>([\s\S]*?)<\/pre>/i)?.[1];
   if(!pre)return {ok:false,reason:'browser_catalog_missing'};
   const text=pre.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&');
   data=socoCatalog(text,{now});
  }catch{return {ok:false,reason:'browser_unavailable'};}
  finally{
   spent+=Math.max(1000,Date.now()-started);
   await env.SOURCE_SNAPSHOTS.put(budgetKey,String(spent),{expirationTtl:172800});
  }
 }
 // Only normalized public football metadata is stored. Failed refreshes retain
 // the previous timestamp; successful empty lists replace previous matches.
 await env.SOURCE_SNAPSHOTS.put(KEY,JSON.stringify(data),{expirationTtl:1800});
 return {ok:true,results:data.matches.length,transport,generated_at:data.generated_at};
}
