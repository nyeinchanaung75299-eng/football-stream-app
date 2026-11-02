// Safe, one-off catalog audit: print aggregate counts/status only. Never log
// upstream payloads, room URLs, headers, stream tokens or individual records.
import { sourceMatchRows } from '../supabase/functions/_shared/source_match_rows.mjs';

function football(row) {
  const id = Number(row?.categoryId ?? row?.category_id);
  if (id === 1) return true;
  const kind = [
    row?.categoryName, row?.subCateName, row?.leagueName, row?.sportName,
  ].map(x => String(x ?? '').toLowerCase()).join(' ');
  return /football|soccer|足球/.test(kind) ||
    (!Number.isFinite(id) &&
      (row?.hostName != null || row?.homeName != null) &&
      (row?.guestName != null || row?.awayName != null));
}
function decode(s) {
  const v = s.replace(/^\uFEFF/, '').trim().replace(/;\s*$/, '');
  const probes=[v];
  const a=v.indexOf('('), b=v.lastIndexOf(')');
  if(a>=0&&b>a)probes.push(v.slice(a+1,b));
  const assign=v.match(/^[\w.$]+\s*=\s*([\s\S]+)$/);
  if(assign)probes.push(assign[1]);
  for(const item of probes){try{return JSON.parse(item)}catch{}}
  return null;
}
const endpoints = [
  ['upstream', 'https://json.vnres.co/matches.json'],
  ['cloudflare', 'https://football-api.nyeinchanaung.us.ci/sources/soco/matches'],
  ['supabase', 'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/soco-links?viewer_public=1&action=matches&source=soco'],
];
for(const [kind, url] of endpoints) {
  try {
    const response=await fetch(url, {
      headers:{Accept:'application/json'},
      signal:AbortSignal.timeout(11000),
    });
    if(!response.ok) {
      console.log(JSON.stringify({source:kind,http_status:response.status}));
      continue;
    }
    const length=Number(response.headers.get('content-length')||0);
    if(length>12_000_000) {
      console.log(JSON.stringify({source:kind,error:'payload_too_large'}));
      continue;
    }
    const rawText=await response.text();
    if(rawText.length>12_000_000) {
      console.log(JSON.stringify({source:kind,error:'payload_too_large'}));
      continue;
    }
    const payload=decode(rawText);
    if(!payload||typeof payload!=='object'){
      console.log(JSON.stringify({source:kind,error:'invalid_json'}));
      continue;
    }
    if(kind==='upstream'){
      const all=sourceMatchRows(payload?.data??payload,()=>true);
      const selected=sourceMatchRows(payload?.data??payload,football);
      const categories={};
      for(const x of all){
        const c=String(x?.categoryId??x?.category_id??'missing');
        categories[c]=(categories[c]||0)+1;
      }
      console.log(JSON.stringify({
        source:kind,http_status:response.status,
        total_identified_fixtures:all.length,
        selected_football:selected.length,
        top_category_ids:Object.entries(categories).sort((a,b)=>b[1]-a[1]).slice(0,10),
        response_keys:Object.keys(payload).slice(0,10),
      }));
    }else{
      const matches=payload.matches;
      console.log(JSON.stringify({
        source:kind,http_status:response.status,
        parsed_matches:Array.isArray(matches)?matches.length:null,
        ok:payload.ok??null,
        error_code:typeof payload.code==='string'?payload.code:null,
      }));
    }
  }catch(error){
    console.log(JSON.stringify({
      source:kind,
      error:error?.name==='TimeoutError'?'timeout':'request_unavailable',
    }));
  }
}
