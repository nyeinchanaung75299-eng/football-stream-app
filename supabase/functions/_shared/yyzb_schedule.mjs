// The website's live rooms and future schedule are separate exports.
// match_all alone drops fixtures once they move into the live catalogue.
export async function loadYyzbSchedules(fetchText,{now=Date.now()}={}){
 const sources=['https://json.ncctrials.com/matches.json','https://json.ncctrials.com/match_all.json'];
 const results=await Promise.allSettled(sources.map(async url=>{
  const raw=(await fetchText(url+'?v='+now)).trim();
  const text=raw.startsWith('{')||raw.startsWith('[')?raw:raw.slice(raw.indexOf('(')+1,raw.lastIndexOf(')'));
  const payload=JSON.parse(text);
  if(!payload||typeof payload!=='object'||payload.code!=null&&Number(payload.code)!==0&&Number(payload.code)!==200)throw Error('Invalid YYZB schedule');
  return payload.data??payload;
 }));
 const data=results.filter(r=>r.status==='fulfilled').map(r=>r.value);
 if(!data.length)throw Error('YYZB schedules unavailable');
 return {data,partial:data.length!==sources.length};
}
