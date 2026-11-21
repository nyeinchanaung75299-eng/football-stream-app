import {fetchDarkbyteCatalog,configuration,publicSourceUrl,sourceHash} from './darkbyte_catalog.mjs';
import {readRepositoryTrees} from './repository_trees.mjs';
import {HUB_GITHUB_SOURCES,readGithubDocuments,publishedEventMeta} from './github_source_formats.mjs';
import {mpdIdentity} from './repository_mpd.mjs';
const legacy='darkbyteprojects/iptv_png';
const clean=x=>String(x??'').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').trim();
export async function githubCatalogEntries(source,documents,revision){
 const entries=new Map();
 for(const doc of documents)for(const row of doc.rows){
  if(row.visible===false||[false,0,'0'].includes(row.publish))continue;
  const e=row.eventInfo||{},home=clean(e.teamA),away=clean(e.teamB);
  const kind=home&&away||e.eventName||e.startTime?'event':'channel',name=clean(home&&away?home+' vs '+away:row.title||row.name||e.eventName);
  if(!name)continue;
  const stable=String(row.id??[name,row.cat,e.startTime||''].join(':'));
  const id='gh:'+source.key+':'+(await sourceHash(kind+':'+stable)).slice(0,28);
  const entry=entries.get(id)||{id,provider:source.provider,kind,name:name.slice(0,120),category:clean(row.cat||row.category||'General TV').slice(0,80),
   source_file:doc.path,image_url:publicSourceUrl(row.image||row.logo||e.eventLogo,{httpsOnly:true})?.href||null,
   streams:[],unsupported_count:0,event_meta:{...publishedEventMeta(row),repositories:[source.repository],source_repository:source.repository,
    source_revision:revision,source_name:source.name,catalog_schema_version:3}};
  const media=Array.isArray(row.resolved_streams)?row.resolved_streams:[];
  if(!media.length)entry.unsupported_count++;
  for(const line of media){
   if(line.visible===false||[false,0,'0'].includes(line.publish))continue;
   const c=configuration(line);if(!c){entry.unsupported_count++;continue;}
   const identity=JSON.stringify([mpdIdentity(c.stream_url),c.stream_type,c.referer,c.origin,c.key_id,c.key_data]);
   const lineId=(await sourceHash(identity)).slice(0,24);
   if(entry.streams.some(x=>x.id===lineId))continue;
   entry.streams.push({...c,id:lineId,label:clean(line.title||line.name||name).slice(0,100),
    configuration_status:c.key_data?'configured':'unverified'});
  }
  entries.set(id,entry);
 }
 return [...entries.values()];
}
// Reuse each unchanged repository's persisted rows. A rotating sports feed must
// not cause hundreds of unchanged DudeTV channel JSONs to be fetched again.
export async function fetchConnectedGithubCatalog({fetcher=fetch,revision=null,previous=[]}={}){
 const repositories=[legacy,...HUB_GITHUB_SOURCES.map(x=>x.repository)];
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),55000);
 try{
  const trees=await readRepositoryTrees(repositories,{fetcher,signal:controller.signal,allowMissing:true,isolateFailures:true});
  const digest=await sourceHash('catalog-v3:'+trees.map(x=>x?.sha||'missing').join(':'));
  let complete=trees.every(Boolean);
  const failed=new Set(repositories.filter((_,i)=>!trees[i]));
  const fresh=repositories.every((repo,i)=>{const saved=previous.filter(row=>row.event_meta?.source_repository===repo);return saved.length&&saved.every(row=>row.event_meta?.source_revision===trees[i]?.sha&&row.event_meta?.catalog_schema_version===3);});
  if(complete&&fresh&&digest===revision)return {revision:digest,unchanged:true,complete:true,entries:[],missingRepositories:[]};
  if(!trees.some(Boolean))throw Error('No connected GitHub source available');
  const batches=await Promise.all(repositories.map(async(repo,index)=>{
   const tree=trees[index],old=previous.filter(row=>row.event_meta?.source_repository===repo);
   if(!tree)return old;
   if(old.length&&old.every(row=>row.event_meta?.source_revision===tree.sha&&row.event_meta?.catalog_schema_version===3))return old;
   try{if(repo===legacy){
    const snapshot=await fetchDarkbyteCatalog({fetcher,tree});
    if(!snapshot.complete)throw Error('Incomplete Darkbyte export');
    return snapshot.entries.map(row=>({...row,event_meta:{...row.event_meta,repositories:[repo],source_repository:repo,source_revision:tree.sha,catalog_schema_version:3}}));
   }
   const source=HUB_GITHUB_SOURCES.find(x=>x.repository===repo);
   const documents=await readGithubDocuments(repo,tree,{fetcher,signal:controller.signal});
   return await githubCatalogEntries(source,documents,tree.sha);
   }catch{complete=false;failed.add(repo);return old;}
  }));
  return {revision:digest,unchanged:false,complete,entries:batches.flat(),missingRepositories:repositories.filter(repo=>failed.has(repo))};
 }finally{clearTimeout(timer);controller.abort();}
}
