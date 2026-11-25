import {REPOSITORY_TREE_SOURCES} from './repository_trees.mjs';
// Explicit operator retirement is not a temporary source outage.
const retired=new Set(['rohmanabdu/lian','rohmanabdu/deqiaa']);
const observed=(repo,missing)=>typeof repo==='string'&&(retired.has(repo)||(!missing.has(repo)&&REPOSITORY_TREE_SOURCES.includes(repo)));
// Absence proves removal only when every active recorded origin was observed.
export function confirmedRepositoryRemovals(snapshot,previous){
 if(snapshot.complete===false&&!snapshot.missingRepositories?.length)return [];
 const fresh=new Set((snapshot.entries||[]).map(r=>r.id));
 const missing=new Set(snapshot.missingRepositories||[]);
 return previous.filter(row=>{
  const origins=row.event_meta?.repositories;
  return !fresh.has(row.id)&&Array.isArray(origins)&&origins.length>0&&origins.every(repo=>observed(repo,missing));
 }).map(row=>row.id);
}
export function unobservedRepositoryEntries(snapshot,previous){
 const missing=new Set(snapshot.missingRepositories||[]);
 if(snapshot.complete===false&&!missing.size)return previous;
 return previous.filter(row=>{
  const origins=row.event_meta?.repositories;
  return !Array.isArray(origins)||origins.length===0||origins.some(repo=>!observed(repo,missing));
 });
}

const FIXTURE_SCOPE_SUFFIX=':darkbyte-fixtures-ok-v1';
const DARKBYTE_REPOSITORY='darkbyteprojects/iptv_png';
// Only a fully observed set of fixture files plus exclusively highlight
// failures proves that football fixtures are complete. Never decode or
// interpret unsupported highlight payloads, or hide their Hub failure.
export function darkbyteFixtureScopeVerified(tree,failedPaths){
 if(!Array.isArray(failedPaths)||!failedPaths.length||!failedPaths.every(path=>/^provider_[1-6]\/highlights\.json$/.test(path)))return false;
 const paths=new Set((tree?.tree||[]).filter(x=>x.type==='blob').map(x=>x.path));
 return !tree?.truncated&&Array.from({length:6},(_,i)=>'provider_'+(i+1)+'/live_events.json').every(path=>paths.has(path));
}
export function scopedHubRevision(revision,verified){
 return verified?revision+FIXTURE_SCOPE_SUFFIX:revision;
}
export function repositoryFixtureScope(state){
 const missing=Array.isArray(state.unavailable_repositories)?state.unavailable_repositories:[];
 const scoped=state.status==='partial'&&typeof state.revision==='string'&&/^[a-f0-9]{64}:darkbyte-fixtures-ok-v1$/.test(state.revision)&&missing.includes(DARKBYTE_REPOSITORY);
 const remaining=scoped?missing.filter(repo=>repo!==DARKBYTE_REPOSITORY):missing;
 return {complete:state.status==='ok'||(scoped&&remaining.length===0),missingRepositories:remaining};
}
