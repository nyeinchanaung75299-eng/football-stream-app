// Read only the repository's published data. Never download its private
// builders, execute provider JavaScript, or call token/license APIs.
const API='https://api.github.com/repos/darkbyteprojects/iptv_png';
const RAW='https://raw.githubusercontent.com/darkbyteprojects/iptv_png/';
const clean=value=>String(value??'').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim();
const identity=value=>clean(value).normalize('NFKC').toLowerCase();
export async function sourceHash(value){
 const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value));
 return [...new Uint8Array(bytes)].map(b=>b.toString(16).padStart(2,'0')).join('');
}
export function publicSourceUrl(value,{httpsOnly=false}={}){
 if(typeof value!=='string'||value.length>4096||/[\r\n]/.test(value))return null;
 try{
  const u=new URL(value.trim().replace(/&amp;/g,'&'));
  if(!(httpsOnly?u.protocol==='https:':['http:','https:'].includes(u.protocol))||u.username||u.password)return null;
  const host=u.hostname.replace(/^\[|\]$/g,'').toLowerCase();
  if(host.includes(':')||/(^|\.)(localhost|local|internal|invalid|test)$/.test(host))return null;
  if(/^\d+\.\d+\.\d+\.\d+$/.test(host)){
   const [a,b]=host.split('.').map(Number);
   if(a===0||a===10||a===127||a>=224||a===169&&b===254||a===172&&b>=16&&b<=31||a===192&&b===168||a===100&&b>=64&&b<=127)return null;
  }
  return u;
 }catch{return null;}
}
function enabled(row){return row&&row.visible!==false&&![0,'0',false].includes(row.publish);}
export function configuration(item){
 const raw=item?.link??item?.url??item?.stream_url;
 if(typeof raw!=='string')return null;
 const [address,...extras]=raw.split('|');const media=publicSourceUrl(address);
 if(!media)return null;
 const params=new URLSearchParams(extras.join('|'));
 const headers={};for(const [key,value] of params){
  const field=key.toLowerCase();if(field==='referer'||field==='referrer')headers.referer=value;
  if(field==='origin')headers.origin=value;
 }
 for(const field of ['referer','origin']){
  const declared=item[field]??item.headers?.[field]??item.headers?.[field==='referer'?'Referer':'Origin'];
  if(typeof declared==='string')headers[field]=declared;
  const parsed=publicSourceUrl(headers[field]);
  headers[field]=parsed?(field==='origin'?parsed.origin:parsed.href):null;
  if(headers[field]?.length>2048)return null;
 }
 const ext=media.pathname.match(/\.(m3u8|mpd|mp4|flv)(?:$|\/)/i)?.[1]?.toLowerCase();
 if(/\.(html?|js)$/i.test(media.pathname)||item.webLink===address)return null;
 const pair=String(item.api??item.clearKey??'').match(/^([a-f\d]{32}):([a-f\d]{32})$/i);
 if((item.type==='1'||item.type===1)&&!pair)return null;
 return {stream_url:media.href,stream_type:pair?'dash':({m3u8:'hls',mpd:'dash',mp4:'mp4',flv:'flv'}[ext]||'auto'),
  referer:headers.referer,origin:headers.origin,key_id:pair?.[1]||null,key_data:pair?.[2]||null};
}
function formats(row){
 const candidates=[row.resolved_streams,row.streams,row.formats];
 return candidates.find(list=>Array.isArray(list)&&list.some(item=>item&&typeof item==='object'&&(item.link||item.url||item.stream_url)))||[];
}
export async function parseDarkbyteFile(path,payload){
 if(!/^provider_[1-6]\/(?:[a-zA-Z0-9_-]+\.json|categories\/[a-zA-Z0-9_-]+\.json)$/.test(path)||!Array.isArray(payload))
  throw new Error('Invalid published channel data.');
 const provider=Number(path.match(/^provider_(\d)/)[1]);
 const kind=/highlight/i.test(path)?'video':/live_events/i.test(path)?'event':'channel';
 const groups=new Map();
 for(const row of payload){
  if(!enabled(row))continue;
  const event=row.teamA&&row.teamB?clean(row.teamA.name)+' vs '+clean(row.teamB.name):null;
  const parent=clean(event||row.title||row.name);if(!parent)continue;
  if(row.playlist_url){
   const target=publicSourceUrl(row.playlist_url);if(!target)continue;
   const id='db:p'+provider+':playlist:'+(await sourceHash(target.href)).slice(0,28);
   groups.set(id,{id,provider,kind:'playlist',name:parent.slice(0,120),category:'Playlists',
    image_url:publicSourceUrl(row.image||row.logo,{httpsOnly:true})?.href||null,
    source_file:path,playlist_url:target.href,streams:[],unsupported_count:0});
   continue;
  }
  const category=clean(row.cat||row.category||(/sports|channels/.test(path)?'Sports':path.match(/categories\/([^/]+)\.json$/)?.[1]||'General TV')).slice(0,80);
  const original=formats(row);
  if(!original.length){
   const id='db:p'+provider+':'+kind+':'+(await sourceHash(provider+':'+kind+':'+identity(parent)+':'+clean(row.date))).slice(0,28);
   groups.set(id,{id,provider,kind,name:parent.slice(0,120),category,
    image_url:publicSourceUrl(row.image||row.logo||row.eventLogo,{httpsOnly:true})?.href||null,
    source_file:path,streams:[],unsupported_count:1});
  }
  for(const [index,item] of original.entries()){
   if(!enabled(item))continue;
   const label=clean(item.title||item.name||parent).slice(0,120);
   const base=[provider,kind,identity(parent),kind==='event'?clean(row.date)+' '+clean(row.time):'',identity(label)].join(':');
   const id='db:p'+provider+':'+kind+':'+(await sourceHash(base)).slice(0,28);
   const entry=groups.get(id)||{id,provider,kind,name:(kind==='event'?parent+' • '+label:label).slice(0,120),category,
    image_url:publicSourceUrl(item.logo||row.image||row.logo||row.eventLogo,{httpsOnly:true})?.href||null,
    source_file:path,streams:[],unsupported_count:0};
   const config=configuration(item);
   if(config&&!entry.streams.some(line=>line.stream_url===config.stream_url)){
    const lineId=(await sourceHash(identity(label)+':'+config.stream_type+':'+entry.streams.length)).slice(0,24);
    entry.streams.push({id:lineId,label:label.slice(0,100),...config});
   }else if(!config)entry.unsupported_count++;
   groups.set(id,entry);
  }
 }
 return [...groups.values()];
}
export async function readJson(target,{fetcher,signal,limit=3*1024*1024}){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),9000);
 try{
  const response=await fetcher(target,{redirect:'manual',signal:AbortSignal.any([signal,controller.signal]),
   headers:{Accept:'application/json','User-Agent':'NCA-Public-Channel-Sync/1.0'}});
  if(!response.ok){await response.body?.cancel().catch(()=>{});throw new Error('Published channel source unavailable.');}
  const reader=response.body?.getReader();if(!reader)throw new Error('Empty channel source.');
  const chunks=[];let size=0;
  try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;
   if(size>limit)throw new Error('Channel source exceeds size limit.');chunks.push(value);}}
  finally{await reader.cancel().catch(()=>{});}
  const bytes=new Uint8Array(size);let at=0;for(const value of chunks){bytes.set(value,at);at+=value.length;}
  return JSON.parse(new TextDecoder().decode(bytes));
 }finally{clearTimeout(timer);controller.abort();}
}
export async function fetchDarkbyteCatalog({fetcher=fetch,revision=null}={}){
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),28000);
 try{
  const options={fetcher,signal:controller.signal};
  const branch=await readJson(API+'/branches/main',options);const sha=branch?.commit?.sha;
  if(!/^[a-f\d]{40}$/.test(sha||''))throw new Error('Invalid source revision.');
  if(revision===sha)return {revision:sha,unchanged:true,entries:[],complete:true};
  const tree=await readJson(API+'/git/trees/'+sha+'?recursive=1',options);
  if(tree?.truncated||!Array.isArray(tree?.tree))throw new Error('Incomplete channel source tree.');
  const paths=tree.tree.filter(item=>item.type==='blob'&&/^provider_[1-6]\/(?:[a-zA-Z0-9_-]+\.json|categories\/[a-zA-Z0-9_-]+\.json)$/.test(item.path))
   .map(item=>item.path).sort((a,b)=>Number(a.includes('/categories/'))-Number(b.includes('/categories/'))||a.localeCompare(b));
  if(!paths.length||paths.length>250)throw new Error('Invalid channel source file list.');
  const entries=new Map(),files=new Array(paths.length);let next=0,failures=0;
  await Promise.all(Array.from({length:5},async()=>{
   while(next<paths.length&&!controller.signal.aborted){const index=next++,path=paths[index];
    try{
     const payload=await readJson(RAW+sha+'/'+path,options);
     files[index]=await parseDarkbyteFile(path,payload);
    }catch{failures++;}
   }
  }));
  // Merge in repository-path order, not HTTP completion order. Signed URL
  // rotations must never reorder a selected channel's managed line IDs.
  for(const parsed of files){
   for(const entry of parsed||[]){
      const old=entries.get(entry.id);
      if(!old)entries.set(entry.id,entry);
      else for(const line of entry.streams)if(!old.streams.some(item=>item.stream_url===line.stream_url)){
       old.streams.push({...line,id:(await sourceHash(identity(line.label)+':'+line.stream_type+':'+old.streams.length)).slice(0,24)});
      }
     }
   }
  if(!entries.size||controller.signal.aborted)throw new Error('Published channel data unavailable.');
  const list=[...entries.values()].sort((a,b)=>a.id.localeCompare(b.id));
  return {revision:sha,unchanged:false,entries:list,complete:failures===0,failed_files:failures};
 }finally{clearTimeout(timer);controller.abort();}
}
