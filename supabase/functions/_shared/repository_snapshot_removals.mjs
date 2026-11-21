// Absence proves removal only when every recorded originating repository was read.
export function confirmedRepositoryRemovals(snapshot,previous){
 const fresh=new Set((snapshot.entries||[]).map(r=>r.id));
 const missing=new Set(snapshot.missingRepositories||[]);
 return previous.filter(row=>{
  const origins=row.event_meta?.repositories;
  return !fresh.has(row.id)&&Array.isArray(origins)&&origins.length>0&&origins.every(repo=>typeof repo==='string'&&!missing.has(repo)&&['rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy'].includes(repo));
 }).map(row=>row.id);
}
export function unobservedRepositoryEntries(snapshot,previous){
 const missing=new Set(snapshot.missingRepositories||[]);
 return previous.filter(row=>{
  const origins=row.event_meta?.repositories;
  return !Array.isArray(origins)||origins.length===0||origins.some(repo=>missing.has(repo)||!['rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy'].includes(repo));
 });
}
