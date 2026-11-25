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
