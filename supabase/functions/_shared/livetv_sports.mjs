// Only public Sports exports are consumed. Source scripts are never executed.
import {configuration,publicSourceUrl,readJson,sourceHash} from './darkbyte_catalog.mjs';
const API='https://api.github.com/repos/bugsfreeweb/LiveTVCollector';
const RAW='https://raw.githubusercontent.com/bugsfreeweb/LiveTVCollector/';
const clean=v=>String(v??'').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim();
const norm=v=>clean(v).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase()
 .replace(/\([^)]*\)/g,' ').replace(/\b(?:full\s*hd|fhd|uhd|hd|sd|4k|8k|\d{3,4}p|hevc|h264|h265)\b/g,' ')
 .replace(/[^a-z0-9+]+/g,' ').replace(/\s+/g,' ').trim();
const countries={UK:'UK',USA:'US',Australia:'AU',Malaysia:'MY',Canada:'CA',Brazil:'BR',
 India:'IN',Bangladesh:'BD',Indonesia:'ID',Italy:'IT',Portugal:'PT',Spain:'ES',France:'FR',
 Russia:'RU',Turkey:'TR',Mexico:'MX',Thailand:'TH',Vietnam:'VN',Pakistan:'PK',Nepal:'NP',
 Peru:'PE',Venezuela:'VE',Israel:'IL',Bahrain:'BH',Egypt:'EG',China:'CN'};
const explicit=[['UK',/🇬🇧|\b(?:uk|united kingdom)\b/i],['US',/🇺🇸|\b(?:us|usa|united states)\b/i],
 ['AU',/🇦🇺|\baustralia\b/i],['MY',/🇲🇾|\bmalaysia\b/i],['CA',/🇨🇦|\bcanada\b/i],
 ['BR',/🇧🇷|\bbra[sz]il\b/i],['IN',/🇮🇳|\bindia\b/i],['BD',/🇧🇩|\bbangladesh\b/i],
 ['DE',/🇩🇪|\bgermany\b/i],['IT',/🇮🇹|\bitaly\b/i],['PT',/🇵🇹|\bportugal\b/i],
 ['ES',/🇪🇸|\bspain\b/i],['FR',/🇫🇷|\bfrance\b/i],['SK',/🇸🇰|\bSK\s*[·|]/i],
 ['CZ',/🇨🇿|\bCZ\s*[·|]/i],['BA',/🇧🇦|\bBA\s*[·|]/i]];
export function sportsRegion(name,country=''){
 const found=explicit.filter(([,pattern])=>pattern.test(name));
 return found.length===1?found[0][0]:found.length>1?'':countries[country]||'';
}
function channelName(value){return norm(value).replace(/\b(?:uk|us|usa|australia|malaysia|canada|brazil|india|bangladesh|germany|italy|portugal|spain|france)\b/g,' ').replace(/\s+/g,' ').trim();}
export function verifiedSportsGuide(name,region,channels){
 if(!region)return null;
 const key=channelName(name);
 if(!key)return null;
 const found=channels.filter(row=>row.is_active!==false&&row.epg_id&&row.epg_source&&
  channelName(row.name)===key&&(sportsRegion(row.name)||({UK1:'UK',US2:'US',AU1:'AU',MY1:'MY',CZ1:'CZ',SK1:'SK',MX1:'MX',CA1:'CA'}[row.epg_source]))===region);
 const unique=new Map(found.map(row=>[row.epg_source+':'+row.epg_id,row]));
 return unique.size===1?[...unique.values()][0]:null;
}
export function sportsGroup(group){
 const value=clean(group);
 return /\bsports?\b|\besportes\b/i.test(value)&&
  !/\besports?\b|\b(?:kids|news|music|movies|series|comedy|culture|entertainment|general|public|travel)\b/i.test(value);
}
// A reachable MPD can still require a license configuration. Do not import
// known encrypted DASH as a keyless native line or attempt license extraction.
export async function sportsNeedsDrm(streams,{fetcher=fetch}={}){
 const candidates=streams.filter(line=>line.stream_type==='dash'&&!(line.key_id&&line.key_data));
 const checked=await Promise.all(candidates.slice(0,12).map(async line=>{
  const url=publicSourceUrl(line.stream_url);if(!url)return false;
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),5000);let reader;
  try{
   const response=await fetcher(url.href,{redirect:'manual',signal:controller.signal,headers:{
    ...(line.referer?{Referer:line.referer}:{}),...(line.origin?{Origin:line.origin}:{})}});
   if(!response.ok){await response.body?.cancel().catch(()=>{});return false;}
   reader=response.body?.getReader();if(!reader)return false;
   let size=0,text='';const decoder=new TextDecoder();
   while(size<256*1024){const chunk=await reader.read();if(chunk.done)break;
    size+=chunk.value.length;text+=decoder.decode(chunk.value,{stream:true});
    if(/<ContentProtection\b/i.test(text))return true;}
   return false;
  }catch{return false;}
  finally{controller.abort();clearTimeout(timer);await reader?.cancel().catch(()=>{});}
 }));
 return checked.some(Boolean);
}
export async function parseLiveTvSports(path,payload,channels=[]){
 if(!/^LiveTV\/[^/]+\/LiveTV\.json$/.test(path)&&!/^SpecialLinks\/(?:BEIN_SPORTS|INTERNATIONAL_SPORTS|SPORTS_NETWORKS)\/[^/]+\/SpecialLinks\.json$/.test(path))throw Error('Unexpected Sports export');
 const country=path.split('/')[1],groups=payload?.channels;
 const rows=Array.isArray(payload)?payload:Object.entries(groups||{}).flatMap(([group,list])=>
  Array.isArray(list)?list.map(row=>({...row,group:row.group||group})):[]);
 const entries=new Map();
 for(const row of rows){
  if(!sportsGroup(row.group))continue;
  const name=clean(row.name).slice(0,120);if(!name)continue;
  const config=configuration(row);if(!config)continue;
  const region=sportsRegion(name+' '+row.group,country),guide=verifiedSportsGuide(name,region,channels);
  const identity=channelName(name)||clean(name).normalize('NFKC').toLowerCase();
  const id='ltv:channel:'+(await sourceHash((region||country)+':'+identity)).slice(0,28);
  const image=publicSourceUrl(row.logo,{httpsOnly:true})?.href;
  const entry=entries.get(id)||{id,provider:7,kind:'channel',name,category:'Sports • '+(region||country),
   image_url:image&&image.length<=2048?image:null,source_file:path,
   streams:[],unsupported_count:0,epg_id:guide?.epg_id||null,epg_source:guide?.epg_source||null,
   epg_channel_id:guide?.id||null,region};
  if(!entry.streams.some(line=>line.stream_url===config.stream_url))entry.streams.push({
   id:(await sourceHash(entry.id+':'+entry.streams.length)).slice(0,24),label:'LiveTVCollector '+(entry.streams.length+1),...config});
  entries.set(id,entry);
 }
 return [...entries.values()];
}
export async function fetchLiveTvSports({fetcher=fetch,revision=null,channels=[]}={}){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),35000);
 try{
  const options={fetcher,signal:controller.signal,limit:4*1024*1024};
  const branch=await readJson(API+'/branches/main',options),sha=branch?.commit?.sha;
  if(!/^[a-f\d]{40}$/.test(sha||''))throw Error('Invalid Sports source revision');
  if(revision===sha)return {revision:sha,unchanged:true,entries:[],complete:true};
  const tree=await readJson(API+'/git/trees/'+sha+'?recursive=1',options);
  if(tree?.truncated||!Array.isArray(tree?.tree))throw Error('Incomplete Sports source');
  const paths=tree.tree.filter(row=>row.type==='blob'&&(/^LiveTV\/[^/]+\/LiveTV\.json$/.test(row.path)||
   /^SpecialLinks\/(?:BEIN_SPORTS|INTERNATIONAL_SPORTS|SPORTS_NETWORKS)\/[^/]+\/SpecialLinks\.json$/.test(row.path)))
   .map(row=>row.path).sort();
  if(!paths.length||paths.length>80)throw Error('Invalid Sports export list');
  let next=0,failures=0;const files=new Array(paths.length);
  await Promise.all(Array.from({length:5},async()=>{while(next<paths.length&&!controller.signal.aborted){
   const index=next++,path=paths[index];try{files[index]=await parseLiveTvSports(path,await readJson(RAW+sha+'/'+path,options),channels);}catch{failures++;}
  }}));
  const entries=new Map();
  for(const rows of files)for(const entry of rows||[]){const old=entries.get(entry.id);
   if(!old)entries.set(entry.id,entry);else for(const line of entry.streams)if(!old.streams.some(row=>row.stream_url===line.stream_url))
    old.streams.push({...line,id:(await sourceHash(entry.id+':'+old.streams.length)).slice(0,24),label:'LiveTVCollector '+(old.streams.length+1)});
  }
  if(!entries.size||controller.signal.aborted)throw Error('Sports source unavailable');
  return {revision:sha,unchanged:false,entries:[...entries.values()],complete:failures===0};
 }finally{clearTimeout(timer);controller.abort();}
}
