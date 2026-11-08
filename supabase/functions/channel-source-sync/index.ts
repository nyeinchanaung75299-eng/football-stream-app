import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "jsr:@supabase/supabase-js@2";
import {fetchDarkbyteCatalog,sourceHash} from "../_shared/darkbyte_catalog.mjs";
import {fetchLiveTvSports,sportsNeedsDrm} from "../_shared/livetv_sports.mjs";
import {fetchRepositoryMatches} from '../_shared/repository_matches.mjs';
import {repositoryChannelUpdates} from '../_shared/repository_updates.mjs';

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info"};
const json=(body:unknown,status=200)=>Response.json(body,{status,headers:{...cors,"Cache-Control":"no-store"}});
const stateColumns="id,enabled,revision,last_checked_at,last_success_at,status,entry_count";
const check=async(query:any)=>{const {data,error}=await query;if(error)throw new Error("Channel source operation failed");return data;};
function same(a:string,b:string){if(a.length!==b.length)return false;let n=0;for(let i=0;i<a.length;i++)n|=a.charCodeAt(i)^b.charCodeAt(i);return n===0;}
async function access(req:Request,client:any){
 const pulse=req.headers.get("x-nca-channel-source-key");
 if(pulse){
  if(!/^[a-f\d]{64}$/i.test(pulse))return null;
  const row=await check(client.from("channel_source_sync_auth").select("secret_sha256").eq("id",1).maybeSingle());
  return row&&same(await sourceHash(pulse),row.secret_sha256)?"scheduler":null;
 }
 const auth=req.headers.get("authorization")||"";
 if(!/^Bearer \S+$/.test(auth))return null;
 const {data,error}=await client.auth.getUser(auth.slice(7));
 if(error||!data?.user?.id)return null;
 const profile=await check(client.from("profiles").select("role").eq("id",data.user.id).maybeSingle());
 return profile?.role==="admin"?"admin":null;
}
async function synchronize(client:any,force:boolean,source:string){
 const begun=await check(client.rpc("begin_connected_channel_source_sync",{p_source:source,p_force:force}));
 if(begun.skipped||begun.busy)return {ok:true,...begun};
 try{
  if(source==='repository-imports'){
   const imported=await check(client.from('channel_repository_imports').select('repository,source_file,metadata,channel_lines(stream_url,referer,origin,key_id,key_data,configuration_status,channels(name))').limit(5000));
   const snapshot=await repositoryChannelUpdates(imported);
   const result=await check(client.rpc('refresh_repository_channel_imports',{p_entries:snapshot.entries}));
   await check(client.from('channel_source_state').update({revision:snapshot.revision,last_checked_at:new Date().toISOString(),last_success_at:new Date().toISOString(),status:'ok',entry_count:imported.length,lease_id:null,lease_until:null}).eq('id',source).eq('lease_id',begun.lease));
   return {ok:true,...result,probed:snapshot.probed,repaired:snapshot.repaired};
  }
  const channels=source==='livetv'?await check(client.from('channels').select('id,name,epg_id,epg_source,is_active').eq('is_active',true).limit(1000)):[];
  const snapshot=source==='repository'?await fetchRepositoryMatches({revision:begun.revision}):source==='livetv'?await fetchLiveTvSports({revision:force?null:begun.revision,channels}):await fetchDarkbyteCatalog({revision:begun.revision});
  return await check(client.rpc("commit_connected_channel_source_sync",{
   p_source:source,p_lease:begun.lease,p_revision:snapshot.revision,p_entries:snapshot.entries,
   p_complete:snapshot.complete,p_unchanged:snapshot.unchanged,
  }));
 }catch{
  await client.from("channel_source_state").update({status:"unavailable",last_checked_at:new Date().toISOString(),
   lease_id:null,lease_until:null}).eq("id",source).eq("lease_id",begun.lease);
  throw new Error("The published channel source is unavailable. Saved channels were kept.");
 }
}
export async function channelSourceRequest(req:Request,client:any){
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json({error:"POST only"},405);
 let role;
 try{role=await access(req,client);}catch{return json({error:"Could not verify Admin access"},503);}
 if(!role)return json({error:"Admin authorization required"},403);
 const body=await req.json().catch(()=>({}));
 const action=String(body.action||"catalog");
 const source=['livetv','repository','repository-imports'].includes(body.source)?body.source:'darkbyte';
 if(role==="scheduler"&&action!=="sync")return json({error:"Scheduler can only sync"},403);
 try{
  if(action==="sync")return json(await synchronize(client,role==="admin",source));
  if(action==='state')return json({ok:true,state:await check(client.from('channel_source_state').select(stateColumns).eq('id',source).single())});
  if(action==="catalog"){
   const page=Math.max(0,Math.min(1000,Number(body.page)||0));
   let query=client.from("channel_source_catalog")
    .select("id,provider,kind,name,category,image_url,stream_count,unsupported_count,playlist_url,updated_at,epg_id,epg_source,region,event_meta",{count:"exact"})
    .eq("source_id",source)
    .eq("is_present",true);
   if([1,2,3,4,5,6].includes(Number(body.provider)))query=query.eq("provider",Number(body.provider));
   if(["channel","event","video","playlist"].includes(body.kind))query=query.eq("kind",body.kind);
   const search=String(body.query||"").trim().slice(0,120).replace(/[\\%_]/g,"\\$&");
   if(search)query=query.ilike("name","%"+search+"%");
   const {data,error,count}=await query.order("name").order("id").range(page*100,page*100+99);
   if(error)throw new Error("Catalog unavailable");
   const ids=(data||[]).map((row:any)=>row.id);
   const linked=ids.length?await check(client.from("channel_source_links")
    .select("entry_id,channel_id,follow_updates,source_missing,last_synced_at").in("entry_id",ids)):[];
   const byId=new Map(linked.map((row:any)=>[row.entry_id,row]));
   const state=await check(client.from("channel_source_state").select(stateColumns).eq("id",source).single());
   return json({ok:true,state,total:count||0,page,entries:(data||[]).map((row:any)=>({...row,connection:byId.get(row.id)||null}))});
  }
  if(action==="settings"){
   if(typeof body.enabled!=="boolean")return json({error:"Invalid sync setting"},400);
   await check(client.from("channel_source_state").update({enabled:body.enabled}).eq("id",source));
   return json({ok:true});
  }
  const id=String(body.entry_id||"");
  if(!(source==='repository'?/^repo:match:[a-f\d]{28}$/:source==='livetv'?/^ltv:channel:[a-f\d]{28}$/:/^db:p[1-6]:(channel|event|video|playlist):[a-f\d]{28}$/).test(id))return json({error:"Invalid source entry"},400);
  if(action==="details"){
   const entry=await check(client.from("channel_source_catalog").select("id,name,kind,streams,playlist_url,is_present,event_meta").eq("id",id).eq('source_id',source).single());
   return json({ok:true,entry});
  }
  if(action==='add_match'){
   const match=String(body.match_id||''),lineId=String(body.source_line_id||'');
   if(!/^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i.test(match)||!lineId||lineId.length>100)
    return json({error:'Invalid match or source line'},400);
   const entry=await check(client.from('channel_source_catalog').select('streams').eq('id',id).eq('source_id',source).eq('is_present',true).single());
   const line=(entry.streams||[]).find((item:any)=>item.id===lineId);
   if(!line)return json({error:'Source line unavailable'},404);
   if(line.configuration_status==='requires_drm'||await sportsNeedsDrm([line]))return json({ok:false,code:'drm_required',error:'This line needs a DRM configuration.'});
   return json({ok:true,...await check(client.rpc('add_connected_source_line_to_match',{
    p_entry_id:id,p_source_line_id:lineId,p_match_id:match,
   }))});
  }
  if(action==="import"){
   if(source==='repository')return json({error:'Repository fixtures are added to a match, not published as TV channels'},400);
   if(source==='livetv'){
    const entry=await check(client.from('channel_source_catalog').select('streams').eq('id',id).eq('source_id',source).single());
    if(await sportsNeedsDrm(entry.streams||[]))return json({ok:false,error:'This source needs a DRM configuration that is not provided. The saved channel was kept.',code:'drm_required'});
   }
   const target=body.channel_id==null?null:String(body.channel_id);
   if(target&&!/^[a-f\d]{8}-[a-f\d-]{27}$/i.test(target))return json({error:"Invalid channel"},400);
   return json({ok:true,...await check(client.rpc(source==='livetv'?"import_connected_channel_source_entry":"link_channel_source_entry",{
    p_entry_id:id,p_target_channel_id:target,p_refresh_only:false,
   }))});
  }
  if(action==="follow"){
   if(typeof body.enabled!=="boolean")return json({error:"Invalid follow setting"},400);
   await check(client.from("channel_source_links").update({follow_updates:body.enabled}).eq("entry_id",id));
   if(body.enabled)await check(client.rpc(source==='livetv'?"import_connected_channel_source_entry":"link_channel_source_entry",{p_entry_id:id,p_refresh_only:true}));
   return json({ok:true});
  }
  if(action==="unlink"){
   await check(client.from("channel_source_links").delete().eq("entry_id",id));
   return json({ok:true});
  }
  return json({error:"Unsupported channel source action"},400);
 }catch{return json({error:"Could not complete the channel source request. Saved channels were kept."},503);}
}
Deno.serve(async(req:Request)=>{
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return json({error:"Server not configured"},503);
 const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 return channelSourceRequest(req,client);
});
