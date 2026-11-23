import {REPOSITORY_TREE_SOURCES} from './repository_trees.mjs';
// Absence proves removal only when every recorded originating repository was read.
export function confirmedRepositoryRemovals(snapshot,previous){
 // A partial snapshot without an explicit list of missing origins is
 // not evidence of *any* deletion. Treat the read as unverified.
 if(snapshot.complete===false && !snapshot.missingRepositories?.length)return [];
 const fresh=new Set((snapshot.entries||[]).map(r=>r.id));
 const missing=new Set(snapshot.missingRepositories||[]);
 return previous.filter(row=>{
  const origins=row.event_meta?.repositories;
  return !fresh.has(row.id)&&Array.isArray(origins)&&origins.length>0&&origins.every(repo=>typeof repo==='string'&&!missing.has(repo)&&REPOSITORY_TREE_SOURCES.includes(repo));
 }).map(row=>row.id);
}
export function unobservedRepositoryEntries(snapshot,previous){
 const missing=new Set(snapshot.missingRepositories||[]);
 if(snapshot.complete===false&&!missing.size)return previous;
 return previous.filter(row=>{
  const origins=row.event_meta?.repositories;
  return !Array.isArray(origins)||origins.length===0||origins.some(repo=>missing.has(repo)||!REPOSITORY_TREE_SOURCES.includes(repo));
 });
}
