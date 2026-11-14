import {writeFile} from 'node:fs/promises';
import {execFileSync,execFile} from 'node:child_process';
import {promisify} from 'node:util';
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
export function socoBrowserCatalog(html,{now=Date.now()}={}) {
 const pre=html.match(/<pre\b[^>]*>([\s\S]*?)<\/pre>/i)?.[1];
 if(!pre||pre.length>6*1024*1024)throw Error('Missing public catalog');
 const text=pre.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&');
 return socoCatalog(text,{now});
}
export async function fetchSocoPublishedSnapshot({fetcher=globalThis.fetch,lastSuccessful,now=Date.now(),runBrowser}={}) {
 try {return await fetchSocoSnapshot(fetcher);}catch(error){
  const age=now-Date.parse(lastSuccessful||'');
  // Only the scheduled publisher opens a browser; never a Viewer request.
  // Reuse a recent successful snapshot instead of spending time every run.
  if(Number.isFinite(age)&&age>=0&&age<8*60000)throw error;
  const run=runBrowser??(async()=>{
   const {stdout}=await promisify(execFile)(process.env.SOCO_CHROME_PATH||'google-chrome',[
    '--headless','--no-sandbox','--disable-gpu','--disable-background-networking',
    '--blink-settings=scriptEnabled=false','--timeout=10000','--dump-dom',
    'https://json.vnres.co/matches.json',
   ],{timeout:15000,maxBuffer:6*1024*1024,encoding:'utf8'});
   return stdout;
  });
  return socoBrowserCatalog(await run(),{now});
 }
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
 try{
  if(!process.argv[2])throw Error('Output path required');
  let lastSuccessful;
  try {lastSuccessful=JSON.parse(execFileSync('git',['show','origin/feed:public/source-status.json'],{encoding:'utf8',stdio:['ignore','pipe','ignore']}))?.sources?.soco?.last_successful_update_at;}catch{}
  const data=await fetchSocoPublishedSnapshot({lastSuccessful});
  await writeFile(process.argv[2],JSON.stringify(data));
  console.log('Soco public fixtures: '+data.matches.length);
 }catch{console.error('Soco public snapshot unavailable');process.exitCode=1;}
}
