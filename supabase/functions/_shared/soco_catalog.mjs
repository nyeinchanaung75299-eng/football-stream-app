import {sourceMatchRows,isFootballSourceRow} from './source_match_rows.mjs';
import {sourceFootballNames} from './football_names.mjs';
import {sourceLogo} from './source_team_logos.mjs';

function parse(text) {
 const value=String(text).replace(/^\uFEFF/,'').trim().replace(/;\s*$/,'');
 const candidates=[value];const first=value.indexOf('('),last=value.lastIndexOf(')');
 if(first>=0&&last>first)candidates.push(value.slice(first+1,last));
 for(const candidate of candidates){try{return JSON.parse(candidate);}catch{}}
 throw Error('Invalid public Soco catalog');
}
function time(value) {
 if(value==null||value==='')return null;
 const n=Number(value);const date=Number.isFinite(n)&&n>0?new Date(n<1e12?n*1000:n):new Date(String(value));
 return Number.isFinite(date.getTime())?date.toISOString():null;
}
export function socoCatalog(text,{now=Date.now()}={}) {
 const payload=parse(text);
 if(payload?.code!=null&&Number(payload.code)!==200)throw Error('Soco catalog unavailable');
 const matches=sourceMatchRows(payload?.data??payload,row=>isFootballSourceRow(row,{allowUnclassified:true})).map(row=>{
  const id=row.scheduleId??row.schedule_id??row.fixtureId??row.matchId??row.match_id??row.gameId??row.eventId??row.id;
  const anchors=Array.isArray(row.anchors)?row.anchors:Array.isArray(row.anchorList)?row.anchorList:[];
  return {
   source:'soco',source_id:String(id??''),schedule_id:id,
   ...sourceFootballNames(row,false),home_logo:sourceLogo(row,'home','soco'),away_logo:sourceLogo(row,'away','soco'),
   match_time:time(row.matchTime??row.match_time??row.startTime??row.kickoff),
   hot:row.hot===true||String(row.hot??row.isHot??'0')==='1',
   status:row.status??null,match_status:row.matchStatus??row.match_status??null,
   anchors:anchors.map((anchor,index)=>({
    uid:anchor.uid??anchor.id??null,nick_name:'Soco Server '+(index+1),
    room_num:String(anchor?.anchor?.roomNum??anchor?.anchor?.room_num??anchor?.room?.roomNum??anchor?.roomNum??anchor?.room_num??anchor?.roomId??'').trim(),
   })).filter(anchor=>anchor.room_num),
  };
 }).filter(row=>row.source_id&&(!row.match_time||now-Date.parse(row.match_time)<=4*3600000));
 matches.sort((a,b)=>(Date.parse(a.match_time??0)-Date.parse(b.match_time??0))||a.home_team.localeCompare(b.home_team));
 return {ok:true,source:'soco',matches,results:matches.length,generated_at:new Date(now).toISOString()};
}
