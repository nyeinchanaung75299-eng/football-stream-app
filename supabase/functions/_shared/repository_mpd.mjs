// Parse published data only. Do not run repository builders, player scripts,
// license servers or token endpoints. Credentials remain private Admin data.
import {configuration,publicSourceUrl,sourceHash} from './darkbyte_catalog.mjs';
import {readRepositoryTrees,REPOSITORY_TREE_SOURCES} from './repository_trees.mjs';
import {NEW_GITHUB_SOURCES,readGithubDocuments} from './github_source_formats.mjs';

export const MPD_REPOSITORIES = REPOSITORY_TREE_SOURCES;
const clean = x => String(x ?? '').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim();
const transient = /^(token|access_token|auth|authorization|sig|signature|expires?|exp|e|hdnts|hdnea|aws_sessionid|x-amz-.+)$/i;
export function mpdIdentity(value) {
 const u=publicSourceUrl(String(value).split('|')[0]);if(!u)return null;
 u.hash='';for(const key of [...u.searchParams.keys()])if(transient.test(key))u.searchParams.delete(key);
 u.searchParams.sort();return u.href;
}
function stream(item, context) {
 // type=1 without a key is intentionally retained as needing configuration.
 const c=configuration({...item,type:null});
 if(!c || !/\.mpd(?:$|\/)/i.test(new URL(c.stream_url).pathname))return null;
 const drm=String(item.drm_type||'').toLowerCase();
 return {...context,...c,stream_type:'dash',name:clean(item.title||item.name||context.name).slice(0,120),
  category:clean(context.category||'Sports').slice(0,80),
  image_url:publicSourceUrl(item.logo||context.image_url,{httpsOnly:true})?.href||null,
  configuration_status:c.key_id&&c.key_data?'configured':drm&&drm!=='none'?'requires_drm':'unverified',
  drm_type:drm||null,license_url:publicSourceUrl(item.license_url)?.href||null};
}
export function parseMpdData(text,context={}) {
 const out=[];
 if(String(text).trimStart().startsWith('#EXTM3U')) {
  let row=null;
  for(const raw of String(text).split(/\r?\n/)) {
   const line=raw.trim();
   if(line.startsWith('#EXTINF:')) {
    const attr=k=>line.match(new RegExp('\\b'+k+'="([^"]*)"','i'))?.[1];
    row={title:line.slice(line.indexOf(',')+1),logo:attr('tvg-logo'),
     category:attr('group-title')||'Sports',epg_id:attr('tvg-id')||null};
   } else if(row && line.startsWith('#KODIPROP:')) {
    const [,key,value]=line.match(/^#KODIPROP:([^=]+)=(.*)$/)||[];
    if(key?.endsWith('.license_type'))row.drm_type=value;
    if(key?.endsWith('.license_key')) {
     if(/^[a-f\d]{32}:[a-f\d]{32}$/i.test(value))row.api=value;
     else row.license_url=value;
    }
   } else if(row && /^#EXTVLCOPT:http-referr?er=/i.test(line))row.referer=line.slice(line.indexOf('=')+1);
   else if(row && line && !line.startsWith('#')) {
    const parsed=stream({...row,link:line},{...context,name:row.title,category:row.category,epg_id:row.epg_id});
    if(parsed)out.push(parsed);row=null;
   }
  }
 } else {
  let data;try{data=JSON.parse(text);}catch{return [];}
  function visit(value,parent={}) {
   if(Array.isArray(value)){for(const row of value)visit(row,parent);return;}
   if(!value||typeof value!=='object')return;
   const next={...context,...parent,name:clean(value.title||value.name||parent.name),
    category:clean(value.cat||value.category||parent.category||'Sports'),
    image_url:value.logo||value.image||parent.image_url};
   if(value.link||value.url||value.stream_url){const parsed=stream(value,next);if(parsed)out.push(parsed);}
   for(const [key,child] of Object.entries(value)) {
    if(child&&typeof child==='object'&&!['headers','teamA','teamB','eventInfo'].includes(key))visit(child,next);
   }
  }
  visit(data);
 }
 return out.filter(x=>x.name);
}
export async function uniqueMpdEntries(entries) {
 const byUrl=new Map();
 for(const row of entries) {
  const identity=mpdIdentity(row.stream_url);if(!identity)continue;
  const old=byUrl.get(identity);
  // Prefer a complete published ClearKey pair, without multiplying a feed
  // when two repositories publish the same CDN manifest or rotate its token.
  if(!old || (!old.key_data&&row.key_data))byUrl.set(identity,{...row,identity});
 }
 const output=[];
 for(const row of byUrl.values())output.push({...row,fingerprint:await sourceHash(row.identity)});
 return output;
}
export async function fetchRepositoryMpds({fetcher=fetch,deduplicate=true,allowMissing=false}={}) {
 async function read(url,max=3*1024*1024) {
  const response=await fetcher(url,{redirect:'error',signal:AbortSignal.timeout(15000),headers:{Accept:'application/json','User-Agent':'NCA-Published-MPD-Import/1.0'}});
  if(!response.ok)throw Object.assign(new Error('Published repository unavailable: HTTP '+response.status),{code:'repository_http_'+response.status});
  const reader=response.body.getReader();let n=0;const chunks=[];
  try{while(true){const {done,value}=await reader.read();if(done)break;n+=value.length;if(n>max)throw new Error('Repository data too large');chunks.push(value);}}
  finally{await reader.cancel().catch(()=>{});}
  const data=new Uint8Array(n);let offset=0;for(const chunk of chunks){data.set(chunk,offset);offset+=chunk.length;}
  return new TextDecoder().decode(data);
 }
 const entries=[],revisions={},files=[];
 const trees=await readRepositoryTrees(MPD_REPOSITORIES,{fetcher,allowMissing,isolateFailures:allowMissing});
 const missingRepositories=MPD_REPOSITORIES.filter((_,i)=>trees[i]===null);
 if(missingRepositories.length===MPD_REPOSITORIES.length)throw Error('No published repository available');
 for(const [repoIndex,repo] of MPD_REPOSITORIES.entries()) {
  const tree=trees[repoIndex];
  if(tree===null){revisions[repo]=null;continue;}
  try{
  if(tree.truncated||!Array.isArray(tree.tree)||!/^[a-f\d]{40}$/.test(tree.sha||''))throw new Error('Incomplete repository tree');
  revisions[repo]=tree.sha;
  if(NEW_GITHUB_SOURCES.some(source=>source.repository===repo)){
   const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),45000);
   try{for(const doc of await readGithubDocuments(repo,tree,{fetcher,signal:controller.signal})){
    const parsed=parseMpdData(JSON.stringify(doc.rows),{repository:repo,revision:tree.sha,source_file:doc.path});
    files.push({repository:repo,path:doc.path,mpds:parsed.length});entries.push(...parsed);
   }}finally{clearTimeout(timer);controller.abort();}
   continue;
  }
  const paths=tree.tree.filter(x=>x.type==='blob'&&x.size<=3*1024*1024&&(
   repo==='darkbyteprojects/iptv_png'?/^provider_[1-6]\/(?:[\w-]+\.json|categories\/[\w-]+\.json)$/.test(x.path):
   repo==='Roshavarma/cfy'&&x.path==='api/events.json'
  )).map(x=>x.path).sort();
  if(!paths.length||paths.length>250)throw new Error('Invalid published file list');
  let index=0;
  await Promise.all(Array.from({length:4},async()=>{
   while(index<paths.length){const path=paths[index++];
    const text=await read('https://raw.githubusercontent.com/'+repo+'/'+tree.sha+'/'+path);
    const parsed=parseMpdData(text,{repository:repo,revision:tree.sha,source_file:path});
    files.push({repository:repo,path,mpds:parsed.length});entries.push(...parsed);
   }
  }));
  }catch(error){
   if(!allowMissing)throw error;
   revisions[repo]=null;missingRepositories.push(repo);
   for(let i=entries.length-1;i>=0;i--)if(entries[i].repository===repo)entries.splice(i,1);
   for(let i=files.length-1;i>=0;i--)if(files[i].repository===repo)files.splice(i,1);
  }
 }
 if(missingRepositories.length===MPD_REPOSITORIES.length)throw Error('No published repository available');
 entries.sort((a,b)=>MPD_REPOSITORIES.indexOf(a.repository)-MPD_REPOSITORIES.indexOf(b.repository)||a.source_file.localeCompare(b.source_file)||a.name.localeCompare(b.name));
 return {revisions,files,raw_count:entries.length,entries:deduplicate?await uniqueMpdEntries(entries):entries,
  complete:missingRepositories.length===0,missingRepositories};
}
