import {footballHighlights} from './football_highlights.mjs';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET, OPTIONS','Access-Control-Allow-Headers':'apikey, content-type'};
const pick=(row,fields)=>Object.fromEntries(fields.filter(key=>row[key]!==undefined).map(key=>[key,row[key]]));
function publicEntry(entry,details=false){
 const row=pick(entry,['id','title','provider','league','thumbnail_url','published_at','duration']);
 row.link_count=entry.lines?.length||0;
 if(details)row.lines=(entry.lines||[]).map(line=>({...pick(line,['id','label','stream_url','stream_type','referer','origin','user_agent','health_status']),playback_verified:false}));
 return row;
}
export async function publicHighlightsRequest(request,{fetcher=fetch}={}){
 const reply=(data,status=200)=>Response.json(data,{status,headers:{...cors,'Cache-Control':'no-store'}});
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(request.method!=='GET')return reply({error:'GET only'},405);
 const params=new URL(request.url).searchParams,action=params.get('action')||'catalog';
 if(!['catalog','details'].includes(action)||(params.get('entry_id')||'').length>4096||(params.get('query')||'').length>80)
  return reply({error:'Invalid highlights request'},400);
 try{
  const data=await footballHighlights({action,provider:'dasfootball',offset:params.get('offset')||0,query:params.get('query')||'',entry_id:params.get('entry_id'),force:params.get('refresh')==='1'},{fetcher});
  return reply({ok:true,source:'highlights',provider:'dasfootball',
   ...pick(data,['has_more','next_offset','total','updated_at','stale','unavailable','warnings']),
   ...(action==='catalog'?{entries:(data.entries||[]).map(row=>publicEntry(row))}:{entry:publicEntry(data.entry,true)})});
 }catch{return reply({error:'Highlights temporarily unavailable'},503);}
}
