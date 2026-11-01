import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "jsr:@supabase/supabase-js@2";
import {findVerifiedGuideMatches,isAuthorizedKeylessLine} from "../_shared/nca_epg_auto_match.mjs";

// Server-side guide reconciliation. Cron and verified NCA administrators only.
// Never return playback credentials, DRM keys or channel stream URLs.
const SOURCES=[
 "https://football-api.nyeinchanaung.us.ci",
 "https://nca-network-backup-test.vercel.app",
 "https://football-public-api-nyeinchanaung75299-eng.workers.dev",
];
const json=(data,status=200)=>Response.json(data,{status,headers:{"Cache-Control":"no-store"}});
const hex=bytes=>Array.from(bytes,x=>x.toString(16).padStart(2,"0")).join("");
async function hash(value){return hex(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))));}
function equal(a,b){
 if(typeof a!=="string"||typeof b!=="string"||a.length!==b.length)return false;
 let d=0;for(let i=0;i<a.length;i++)d|=a.charCodeAt(i)^b.charCodeAt(i);return d===0;
}
async function authorize(req,admin){
 const pulse=req.headers.get("x-nca-auto-map-key");
 if(pulse){
  if(!/^[0-9a-f]{64}$/i.test(pulse))return false;
  const {data,error}=await admin.from("nca_epg_auto_sync_auth").select("secret_sha256").eq("id",1).maybeSingle();
  return !error && !!data?.secret_sha256 && equal(await hash(pulse),data.secret_sha256);
 }
 const auth=req.headers.get("authorization")||"";
 if(!/^Bearer \S+$/.test(auth))return false;
 const {data,error}=await admin.auth.getUser(auth.slice(7));
 if(error||!data?.user?.id)return false;
 const {data:profile,error:roleError}=await admin.from("profiles").select("role")
  .eq("id",data.user.id).maybeSingle();
 return !roleError&&profile?.role==="admin";
}
const checked=async(query,label)=>{
 const {data,error}=await query;
 if(error)throw new Error(label+" failed");
 return data||[];
};
async function guideFromNCA(now){
 const date=new Date(now.getTime()+390*60000).toISOString().slice(0,10);
 for(const base of SOURCES){
  try{
   const response=await fetch(base+"/tv-schedule?date="+date+"&days=8",{
    method:"GET",headers:{Accept:"application/json"},signal:AbortSignal.timeout(19000),
   });
   if(!response.ok)continue;
   const guide=await response.json();
   if(guide?.ok===true&&Array.isArray(guide.channels)&&guide.channels.length>0)return guide;
  }catch{ /* Another fixed NCA public guide relay may still work. */ }
 }
 throw new Error("NCA public TV schedule currently unavailable");
}
async function recordRun(admin,result,counts){
 await admin.from("nca_epg_auto_sync_runs").insert({
  result,guide_channels:counts.guideChannels||0,guide_matches:counts.candidates||0,
  mapped:counts.mapped||0,added_lines:counts.addedLines||0,
 });
}
async function reconcile(req,admin,body){
 const now=new Date();
 const dryRun=body?.dry_run===true;
 const selectedId=typeof body?.match_id==="string"?body.match_id:null;
 if(selectedId&&!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(selectedId))
  return json({error:"Invalid match ID"},400);
 const guide=await guideFromNCA(now);
 const [matches,channels,lines,links]=await Promise.all([
  checked(admin.from("matches")
   .select("id,home_team,away_team,kickoff_at,publish_state,is_active,deleted_at")
   .eq("is_active",true).eq("publish_state","published").is("deleted_at",null)
   .gte("kickoff_at",new Date(now.getTime()-90*60000).toISOString())
   .lte("kickoff_at",new Date(now.getTime()+8*86400000).toISOString()).limit(350),
   "Match list"),
  checked(admin.from("channels").select("id,name,epg_id,epg_source,is_active").eq("is_active",true).limit(500),"Channel list"),
  checked(admin.from("channel_lines")
   .select("id,channel_id,label,stream_type,stream_url,referer,origin,key_id,key_data,is_active,sort_order")
   .eq("is_active",true).limit(500),"Channel lines"),
  checked(admin.from("stream_links").select("id,match_id,channel_line_id,sort_order")
   .not("channel_line_id","is",null).limit(1500),"Existing match links"),
 ]);
 const matchRows=selectedId?matches.filter(m=>m.id===selectedId):matches;
 const candidates=findVerifiedGuideMatches(matchRows,guide,channels,now).slice(0,350);
 const directByChannel=new Map();
 for(const line of lines){
  if(!isAuthorizedKeylessLine(line))continue;
  if(!directByChannel.has(line.channel_id))directByChannel.set(line.channel_id,[]);
  directByChannel.get(line.channel_id).push(line);
 }
 const existing=new Set(links.map(l=>l.match_id+":"+l.channel_line_id));
 const latestSort=new Map();
 for(const link of links)latestSort.set(link.match_id,Math.max(latestSort.get(link.match_id)||0,Number(link.sort_order)||0));
 const summary={ok:true,dryRun,guideChannels:guide.channels.filter(ch=>ch.matchedEPG===true).length,
  candidates:candidates.length,mapped:0,eligibleDirectLines:0,addedLines:0,skippedProtected:0,
  unmatchedMatches:matchRows.length-new Set(candidates.map(c=>c.match_id)).size};
 const guideUpdatedAt=Number.isFinite(Date.parse(guide.updated_at))?
  new Date(guide.updated_at).toISOString():now.toISOString();
 for(const item of candidates){
  const possible=directByChannel.get(item.channel_id)||[];
  if(!possible.length)summary.skippedProtected++;
  if(dryRun){
   summary.mapped++;
  }else{
   const {error}=await admin.from("nca_epg_auto_match_channels").upsert({
    match_id:item.match_id,channel_id:item.channel_id,
    programme_title:item.programme_title,programme_start:item.programme_start,
    guide_updated_at:guideUpdatedAt,last_verified_at:now.toISOString(),
   },{onConflict:"match_id,channel_id"});
   if(error)throw new Error("EPG mapping update failed");
   summary.mapped++;
  }
  const c=channels.find(c=>c.id===item.channel_id);
  for(const line of possible.slice(0,5)){
   const key=item.match_id+":"+line.id;
   if(existing.has(key))continue;
   summary.eligibleDirectLines++;
   if(dryRun)continue;
   const n=(latestSort.get(item.match_id)||0)+1;
   const {data,error}=await admin.from("stream_links").insert({
    match_id:item.match_id,channel_id:item.channel_id,channel_line_id:line.id,
    label:(c?.name||"TV Channel").slice(0,85)+(line.label?" • "+String(line.label).slice(0,32):""),
    resolution:String(line.label||"Auto EPG").slice(0,90),
    stream_type:line.stream_type||"auto",
    stream_url:line.stream_url,referer:line.referer||null,origin:line.origin||null,
    key_id:null,key_data:null,use_webview:false,send_notification:false,
    is_active:true,sort_order:n,
   }).select("id").single();
   if(error){
    if(error.code==="23505"){existing.add(key);continue;}
    throw new Error("Safe direct TV match attachment failed");
   }
   const {error:provenanceError}=await admin.from("nca_epg_auto_stream_links").insert({
    stream_link_id:data.id,match_id:item.match_id,channel_line_id:line.id,
   });
   if(provenanceError)throw new Error("Automatic link provenance failed");
   latestSort.set(item.match_id,n);existing.add(key);summary.addedLines++;
  }
 }
 await recordRun(admin,dryRun?"dry_run":"ok",summary);
 return json(summary);
}
Deno.serve(async req=>{
 if(req.method!=="POST")return json({error:"POST only"},405);
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key)return json({error:"Server not configured"},503);
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 if(!await authorize(req,admin))return json({error:"Admin authorization required"},403);
 const body=await req.json().catch(()=>({}));
 try{return await reconcile(req,admin,body);}
 catch{
  await recordRun(admin,"error",{}).catch(()=>{});
  return json({error:"Could not verify TV guide or sync match channels. No existing lines were removed."},503);
 }
});
