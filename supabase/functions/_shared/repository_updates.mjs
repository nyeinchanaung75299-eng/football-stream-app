import {fetchRepositoryMpds,mpdIdentity} from './repository_mpd.mjs';
import {probeChannelMedia} from './channel_media_probe.mjs';
import {sourceHash} from './darkbyte_catalog.mjs';
const config=row=>JSON.stringify([row.stream_url,row.referer||'',row.origin||'',row.key_id||'',row.key_data||'']);
// Re-check a bounded number of changed configurations each run. Unchanged
// working lines do not download their manifests on every source refresh.
export async function repositoryChannelUpdates(imports,{fetcher=fetch,maxProbes=12}={}){
 const snapshot=await fetchRepositoryMpds({fetcher,deduplicate:false});
 const unique=new Map();
 for(const row of snapshot.entries)unique.set(row.repository+'\n'+row.source_file+'\n'+config(row),{...row,configuration_status:'unverified'});
 const entries=[...unique.values()],pairs=snapshot.entries.filter(r=>r.key_id&&r.key_data);
 let probed=0,repaired=0;
 const tasks=[];
 for(const saved of [...imports].sort((a,b)=>
  Number(b.channel_lines?.configuration_status==='requires_drm')-Number(a.channel_lines?.configuration_status==='requires_drm') ||
  String(a.metadata?.last_source_check||'').localeCompare(String(b.metadata?.last_source_check||'')))){
  const line=saved.channel_lines;if(!line)continue;
  let candidates=entries.filter(r=>r.repository===saved.repository&&r.source_file===saved.source_file&&mpdIdentity(r.stream_url)===mpdIdentity(line.stream_url));
  if(!candidates.length)candidates=entries.filter(r=>r.repository===saved.repository&&r.source_file===saved.source_file&&r.name.toLowerCase()===line.channels?.name?.toLowerCase());
  if(candidates.length!==1)continue;
  const row=candidates[0];
  if(config(row)===config(line)&&['configured','clear'].includes(line.configuration_status)){row.configuration_status=line.configuration_status;continue;}
  if(tasks.length>=maxProbes)continue;tasks.push(row);
 }
 let cursor=0;
 await Promise.all(Array.from({length:6},async()=>{while(cursor<tasks.length){const row=tasks[cursor++];
  const check=await probeChannelMedia(row,{fetcher,includeKids:true});probed++;
  if(check.manifest_status!=='valid')continue;
  if(check.drm_status==='missing_configuration'){
   const matching=pairs.filter(p=>check.manifest_kids?.includes(p.key_id.toLowerCase()));
   const keys=[...new Set(matching.map(p=>p.key_id.toLowerCase()+':'+p.key_data.toLowerCase()))];
   if(keys.length===1){row.key_id=matching[0].key_id;row.key_data=matching[0].key_data;row.configuration_status='configured';repaired++;}
  }else if(check.drm_status==='configured')row.configuration_status='configured';
  else if(check.drm_status==='not_required')row.configuration_status='clear';
 }}));
 return {entries,revision:await sourceHash(JSON.stringify(snapshot.revisions)),probed,repaired,complete:true};
}
