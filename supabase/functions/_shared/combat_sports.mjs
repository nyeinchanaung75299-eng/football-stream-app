import {sourceHash} from './darkbyte_catalog.mjs';
import {repositoryLineIdentity} from './repository_matches.mjs';
const clean=x=>String(x??'').replace(/<[^>]*>/g,' ').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim();
const norm=x=>clean(x).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
export const combatCategories={ufc:'UFC',mma:'MMA',boxing:'Boxing',one:'ONE Championship'};
export function combatClassification(value){
 const text=typeof value==='string'?value:[value.source_category,value.league,value.name,value.discipline].filter(Boolean).join(' ');
 const one=/\bone\s+(?:championship|friday\s+fights|fight\s+night)\b/i.test(text),ufc=/\bufc\b/i.test(text),boxing=/\bboxing\b/i.test(text),mma=/\bmma\b|mixed\s+martial\s+arts/i.test(text);
 if(one&&ufc)return null;
 if(!one&&ufc&&boxing)return null;
 const category=one?'one':ufc?'ufc':boxing?'boxing':mma?'mma':null;
 if(!category)return null;
 const specific=typeof value==='object'?[value.discipline,value.league].filter(Boolean).join(' '):text;
 const precise=/muay\s*thai|kickboxing/i.test(specific)?specific:text;
 const disciplines=[...(/\bmma\b|mixed\s*martial\s*arts/i.test(precise)?['MMA']:[]),...(/muay\s*thai/i.test(precise)?['Muay Thai']:[]),...(/kickboxing/i.test(precise)?['Kickboxing']:[]),...(boxing&&!/kickboxing/i.test(precise)?['Boxing']:[])];
 return {category,category_name:combatCategories[category],discipline:one?(disciplines.length>1?'Mixed disciplines':disciplines[0]||'Unknown'):category==='boxing'?'Boxing':'MMA'};
}
export function combatMatchesQuery(row,query){
 const fold=value=>clean(value).normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 const text=fold([row.name,row.event_name,...(row.source_names||[])].join(' '));
 return fold(query).split(/\s+/).filter(Boolean).every(term=>text.includes(term));
}
export function combatTimeStatus(meta,now=Date.now()){
 const start=Date.parse(meta.kickoff_at||''),end=Date.parse(meta.end_at||'');
 if(!Number.isFinite(start))return 'unknown';
 let status=now<start?'upcoming':Number.isFinite(end)&&end>start?(now<end?'live':'finished'):'unknown';
 const stated=clean(meta.source_status).toLowerCase();
 if((stated==='live'&&status==='upcoming')||(['ended','finished'].includes(stated)&&['live','upcoming'].includes(status))||(['upcoming','scheduled'].includes(stated)&&status==='finished'))status='unknown';
 return status;
}
export async function combatEventsFromHub(rows,{now=Date.now()}={}){
 const groups=new Map();
 for(const row of rows){
  if(row.kind!=='event')continue;
  const meta=row.event_meta||{},classification=combatClassification({...meta,name:row.name});
  if(!classification)continue;
  const home=clean(meta.home_team),away=clean(meta.away_team),pair=home&&away&&norm(home)!==norm(away)?norm(home)+':'+norm(away):null;
  const name=clean(meta.league||row.name||classification.category_name);
  const start=Date.parse(meta.kickoff_at||''),stamp=Number.isFinite(start)?new Date(start).toISOString().slice(0,16):null;
  const numbered=/\b(?:ufc|one)\s*\d+\b/i.test(name);
  // Unknown dates and generic titles cannot prove two source events identical.
  const identity=[classification.category,classification.discipline,pair||norm(name),stamp|| (numbered?norm(name):row.id)].join(':');
  let entry=groups.get(identity);
  if(!entry){entry={id:'combat:'+(await sourceHash(identity)).slice(0,28),name:pair?home+' vs '+away:name,event_name:name,
   ...classification,home_team:home||null,away_team:away||null,kickoff_at:Number.isFinite(start)?new Date(start).toISOString():null,
   source_time:meta.source_time||null,end_at:meta.end_at||null,status:combatTimeStatus(meta,now),
   source_names:[],source_entries:[],lines:[],video_status:'not_checked',playback_verified:false};groups.set(identity,entry);}
  const source=clean(meta.source_name||meta.source_repository||'Darkbyte Provider '+row.provider);
  if(!entry.source_names.includes(source))entry.source_names.push(source);
  entry.source_entries.push(row.id);
  for(const line of row.streams||[]){
   const fingerprint=repositoryLineIdentity(line);
   if(entry.lines.some(x=>x._identity===fingerprint))continue;
   entry.lines.push({...line,id:(await sourceHash(fingerprint)).slice(0,24),source_name:source,_identity:fingerprint,
    health_status:'unknown',playback_verified:false});
  }
 }
 return [...groups.values()].map(entry=>({...entry,stream_count:entry.lines.length,lines:entry.lines.map(({_identity,...line})=>line)}))
  .sort((a,b)=>(a.kickoff_at||'9999').localeCompare(b.kickoff_at||'9999')||a.id.localeCompare(b.id));
}
