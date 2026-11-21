export function selectRenewedLine(lines,selector){
 const compatible=(Array.isArray(lines)?lines:[]).filter(l=>l&&typeof(l.url??l.stream_url)==='string'&&l.stream_type===selector.stream_type&&
  (!selector.resolution||!l.resolution||String(l.resolution)===String(selector.resolution)));
 const exact=compatible.filter(l=>(selector.id!=null&&String(l.id)===String(selector.id))||(selector.label&&l.label===selector.label));
 return exact.length===1?exact[0]:(!selector.id&&!selector.label&&compatible.length===1)?compatible[0]:null;
}
export async function refreshImportedSources(metadata,{rpc,resolve,now=Date.now()}){
 const rows=(metadata?.imported_sources??[]).filter(r=>r.source!=='playz'&&r.link_id&&r.config_hash&&
  (!r.last_attempt_at||now-Date.parse(r.last_attempt_at)>120000)&&
  ((r.expires_at&&Date.parse(r.expires_at)<now+30000)||now-Date.parse(r.last_resolved_at)>900000)).slice(0,2);
 // The database lease coalesces requests across isolates. Do not share
 // request-owned fetch promises at module scope in the Workers runtime.
 const results=await Promise.all(rows.map(async row=>{
   try{
    const lease=await rpc('claim_imported_source_refresh',{p_link_id:row.link_id,p_expected_hash:row.config_hash});
    if(!lease?.refresh_lease)return false;
    const response=await resolve({...row,refresh_lease:lease.refresh_lease});
    const line=selectRenewedLine(response?.lines,row.selector??{});
    if(!line)return false;
    return await rpc('apply_imported_source_refresh',{p_link_id:row.link_id,p_expected_hash:row.config_hash,p_lease:lease.refresh_lease,p_config:line})===true;
   }catch{ return false; /* Verification-gated/unavailable sources remain manual. */ }
 }));
 return results.some(Boolean);
}
