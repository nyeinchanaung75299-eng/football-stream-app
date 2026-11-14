import {writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {socoCatalog} from '../supabase/functions/_shared/soco_catalog.mjs';
export async function fetchSocoSnapshot(fetcher=globalThis.fetch) {
 const response=await fetcher('https://json.vnres.co/matches.json',{
  headers:{Accept:'application/javascript,application/json','User-Agent':'Mozilla/5.0',Origin:'https://m.sutbongtv.com',Referer:'https://m.sutbongtv.com/'},
  redirect:'manual',signal:AbortSignal.timeout(12000),
 });
 if(!response.ok){await response.body?.cancel();throw Error('Public Soco catalog unavailable');}
 const reader=response.body.getReader();const decoder=new TextDecoder();let size=0,text='';
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>6*1024*1024)throw Error('Public catalog exceeds budget');text+=decoder.decode(value,{stream:true});}
  text+=decoder.decode();
 }finally{await reader.cancel().catch(()=>{});}
 return socoCatalog(text);
}
export async function fetchSocoPublishedSnapshot({fetcher=globalThis.fetch,accountId,apiToken,lastSuccessful,now=Date.now()}={}) {
 try {return await fetchSocoSnapshot(fetcher);}catch(error){
  const age=now-Date.parse(lastSuccessful||'');
  // One publisher owns browser refreshes. Reuse the last successful public
  // snapshot between runs instead of spending browser time per Viewer visit.
  if(Number.isFinite(age)&&age>=0&&age<8*60000)throw error;
  if(!apiToken||!/^[a-f0-9]{32}$/.test(accountId||''))throw error;
  const response=await fetcher('https://api.cloudflare.com/client/v4/accounts/'+accountId+'/browser-rendering/content',{
   method:'POST',headers:{Authorization:'Bearer '+apiToken,'Content-Type':'application/json'},redirect:'manual',
   signal:AbortSignal.timeout(10000),body:JSON.stringify({url:'https://json.vnres.co/matches.json',
    gotoOptions:{waitUntil:'domcontentloaded',timeout:2500},actionTimeout:2000,
    rejectResourceTypes:['image','media','font','stylesheet'],setJavaScriptEnabled:false}),
  });
  if(!response.ok){await response.body?.cancel();throw Error('Browser metadata unavailable');}
  const payload=await response.json();if(payload.success!==true||typeof payload.result!=='string')throw Error('Invalid browser metadata');
  const pre=payload.result.match(/<pre\b[^>]*>([\s\S]*?)<\/pre>/i)?.[1];
  if(!pre||pre.length>6*1024*1024)throw Error('Missing public catalog');
  const text=pre.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&');
  return socoCatalog(text,{now});
 }
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
 try{
  if(!process.argv[2])throw Error('Output path required');
  let lastSuccessful;
  try {lastSuccessful=JSON.parse(execFileSync('git',['show','origin/feed:public/source-status.json'],{encoding:'utf8',stdio:['ignore','pipe','ignore']}))?.sources?.soco?.last_successful_update_at;}catch{}
  const data=await fetchSocoPublishedSnapshot({accountId:process.env.CLOUDFLARE_ACCOUNT_ID,
    apiToken:process.env.CLOUDFLARE_BROWSER_API_TOKEN||process.env.CLOUDFLARE_API_TOKEN,lastSuccessful});
  await writeFile(process.argv[2],JSON.stringify(data));
  console.log('Soco public fixtures: '+data.matches.length);
 }catch{console.error('Soco public snapshot unavailable');process.exitCode=1;}
}
