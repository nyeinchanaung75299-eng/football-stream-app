import {sourceMatchRows,isFootballSourceRow} from './source_match_rows.mjs';
// Use YYZB's own website catalogue and its football category. No NCA Live
// selections or separate all-sport/score schedule is combined with this feed.
export async function loadYyzbFootballCatalogue(fetchText,{now=Date.now()}={}){
 const raw=(await fetchText('https://json.ncctrials.com/matches.json?v='+now)).trim();
 const text=raw.startsWith('{')||raw.startsWith('[')?raw:raw.slice(raw.indexOf('(')+1,raw.lastIndexOf(')'));
 const payload=JSON.parse(text);
 if(!payload||typeof payload!=='object'||payload.code!=null&&Number(payload.code)!==0&&Number(payload.code)!==200)throw Error('Invalid YYZB football catalogue');
 return {data:sourceMatchRows(payload.data??payload,isFootballSourceRow)};
}
