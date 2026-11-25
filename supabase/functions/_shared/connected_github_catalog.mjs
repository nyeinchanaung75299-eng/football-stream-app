import {fetchDarkbyteCatalog,configuration,publicSourceUrl,sourceHash,isDarkbyteHighlightPath} from './darkbyte_catalog.mjs';
import {readRepositoryTrees} from './repository_trees.mjs';
import {darkbyteFixtureScopeVerified,scopedHubRevision} from './repository_snapshot_removals.mjs';
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
 // Highlights are intentionally outside the Stream Hub scope. Exclude old
 // highlight rows even when the associated source is temporarily unavailable.
 const retained=previous.filter(row=>!(row.event_meta?.source_repository===legacy&&row.kind==='video'&&isDarkbyteHighlightPath(row.source_file)));
 const scopeChanged=retained.length!==previous.length;
 previous=retained;
 const repositories=[legacy,...HUB_GITHUB_SOURCES.map(x=>x.repository)];
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),55000);
 try{
  const trees=await readRepositoryTrees(repositories,{fetcher,signal:controller.signal,allowMissing:true,isolateFailures:true});
  const digest=await sourceHash('catalog-v5-no-highlights:'+trees.map(x=>x?.sha||'missing').join(':'));
  let complete=trees.every(Boolean);
  let partialDarkbytePaths=[],darkbyteFixturesVerified=false;
  const failed=new Set(repositories.filter((_,i)=>!trees[i]));
  const fresh=repositories.every((repo,i)=>{const saved=previous.filter(row=>row.event_meta?.source_repository===repo);return saved.length&&saved.every(row=>row.event_meta?.source_revision===trees[i]?.sha&&row.event_meta?.catalog_schema_version===3&&!row.event_meta?.source_partial_fresh);});
  if(!scopeChanged&&complete&&fresh&&digest===revision)return {revision:digest,unchanged:true,complete:true,entries:[],missingRepositories:[]};
  if(!trees.some(Boolean))throw Error('No connected GitHub source available');
  const batches=await Promise.all(repositories.map(async(repo,index)=>{
   const tree=trees[index],old=previous.filter(row=>row.event_meta?.source_repository===repo);
   if(!tree)return old;
   if(old.length&&old.every(row=>row.event_meta?.source_revision===tree.sha&&row.event_meta?.catalog_schema_version===3&&!row.event_meta?.source_partial_fresh))return old;
   try{if(repo===legacy){
    const snapshot=await fetchDarkbyteCatalog({fetcher,tree,includeHighlights:false});
    if(!snapshot.complete){
     complete=false;
     failed.add(repo);
     partialDarkbytePaths=snapshot.failed_paths;
     darkbyteFixturesVerified=darkbyteFixtureScopeVerified(tree,partialDarkbytePaths);
     console.warn('Darkbyte exports partially available',{failed_paths:partialDarkbytePaths});
    }
    const fresh=snapshot.entries.map(row=>({...row,event_meta:{...row.event_meta,repositories:[repo],source_repository:repo,source_revision:tree.sha,catalog_schema_version:3,source_partial_fresh:!snapshot.complete}}));
    const freshIds=new Set(fresh.map(row=>row.id));
    // A failed published file is not evidence of removal. Keep its entries
    // and their original revisions until that file can be read again.
    return snapshot.complete ? fresh : [...fresh,...old.filter(row=>partialDarkbytePaths.includes(row.source_file)&&!freshIds.has(row.id))
     .map(row=>({...row,event_meta:{...row.event_meta,source_partial_fresh:false}}))];
   }
   const source=HUB_GITHUB_SOURCES.find(x=>x.repository===repo);
   const documents=await readGithubDocuments(repo,tree,{fetcher,signal:controller.signal});
   return await githubCatalogEntries(source,documents,tree.sha);
   }catch(error){
    if(repo===legacy)darkbyteFixturesVerified=false;
    console.warn('Published repository data failed',{repository:repo,code:error?.code||error?.name||'invalid_export'});
    complete=false;failed.add(repo);return old;
   }
  }));
  const snapshotRevision=partialDarkbytePaths.length?await sourceHash(digest+':'+partialDarkbytePaths.join(',')):digest;
  return {revision:scopedHubRevision(snapshotRevision,darkbyteFixturesVerified),unchanged:false,complete,entries:batches.flat(),missingRepositories:repositories.filter(repo=>failed.has(repo))};
 }finally{clearTimeout(timer);controller.abort();}
}
