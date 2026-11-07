// Local operator audit. Output files contain private source configurations;
// stdout deliberately contains counts only. No license or token API is called.
import {readFileSync,writeFileSync} from 'node:fs';
import {publicSourceUrl} from '../supabase/functions/_shared/darkbyte_catalog.mjs';
const folder=process.argv[2];if(!folder)throw new Error('Private audit directory required');
const snapshot=JSON.parse(readFileSync(folder+'/snapshot-private.json'));
const database=JSON.parse(readFileSync(folder+'/database-private.json'));
const entries=[...snapshot.entries,...database.lines.filter(l=>!l.key_data&&/\.mpd(?:$|\?)/i.test(l.stream_url)).map(l=>({...l,existing_line_id:l.id}))];
let cursor=0;
await Promise.all(Array.from({length:8},async()=>{
 while(cursor<entries.length){const row=entries[cursor++];
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),8000);
  try{
   if(!publicSourceUrl(row.stream_url))throw new Error('Invalid source');
   const response=await fetch(row.stream_url,{redirect:'error',signal:controller.signal,headers:{
    Accept:'application/dash+xml,application/xml',Range:'bytes=0-262143',
    ...(row.referer?{Referer:row.referer}:{}),...(row.origin?{Origin:row.origin}:{}),
   }});
   row.probe_http=response.status;
   if(!response.ok){await response.body?.cancel();continue;}
   const reader=response.body.getReader();let size=0,text='';const decoder=new TextDecoder();
   try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
    text+=decoder.decode(value,{stream:true});if(size>=262144)break;}}
   finally{await reader.cancel().catch(()=>{});}
   if(!/<(?:\w+:)?MPD\b/i.test(text)){row.manifest_status='not_mpd';continue;}
   const protectedMedia=/<(?:\w+:)?ContentProtection\b/i.test(text);
   const kids=[...text.matchAll(/(?:cenc:)?default_KID\s*=\s*["']([^"']+)/gi)].flatMap(m=>m[1].split(/\s+/)).map(k=>k.replace(/-/g,'').toLowerCase());
   row.manifest_status=protectedMedia?'encrypted':'clear';
   row.manifest_kids=[...new Set(kids)];
   row.configuration_status=!protectedMedia?'clear':row.key_data&&(!kids.length||kids.includes(String(row.key_id).replace(/-/g,'').toLowerCase()))?'configured':'requires_drm';
  }catch{row.manifest_status='unavailable';}
  finally{clearTimeout(timer);controller.abort();}
 }
}));
writeFileSync(folder+'/audited-private.json',JSON.stringify(entries),{mode:0o600});
console.log(JSON.stringify({audited:entries.length,statuses:entries.reduce((a,r)=>(a[r.manifest_status||'http_failed']=(a[r.manifest_status||'http_failed']||0)+1,a),{}),existingKeyless:entries.filter(r=>r.existing_line_id).map(r=>({id:r.existing_line_id,manifest:r.manifest_status||'http_failed',configuration:r.configuration_status||'unverified',http:r.probe_http||null}))}));
