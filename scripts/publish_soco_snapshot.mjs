import {writeFile} from 'node:fs/promises';
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
if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
 try{
  if(!process.argv[2])throw Error('Output path required');
  const data=await fetchSocoSnapshot();await writeFile(process.argv[2],JSON.stringify(data));
  console.log('Soco public fixtures: '+data.matches.length);
 }catch{console.error('Soco public snapshot unavailable');process.exitCode=1;}
}
