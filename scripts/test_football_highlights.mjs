import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync,existsSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {highlightSources,highlightLine,parseDasHighlights,checkHighlightLine,footballHighlights} from '../supabase/functions/_shared/football_highlights.mjs';
const html = rows => '<script type="application/ld+json">'+JSON.stringify({'@type':'ItemList',itemListElement:rows})+'</script>';
const video = {'@type':'VideoObject',name:'Home vs Away',url:'https://dasfootball.com/home-vs-away-highlights-2026-11-12/',embedUrl:'https://cdn.example.org/highlight.mp4'};
const response = body => new Response(body,{headers:{'Content-Type':'text/html'}});

test('only native highlight media and safe non-secret headers are accepted',()=>{
  const line=highlightLine({link:'https://cdn.example.org/h.mp4|Referer=https://site.example.org/game&Origin=https://site.example.org&User-agent=Player&Cookie=secret&accountToken=secret'});
  assert.equal(line.stream_type,'mp4');assert.equal(line.referer,'https://site.example.org/game');
  assert.equal(line.user_agent,'Player');assert.equal(JSON.stringify(line).includes('secret'),false);
  for(const link of ['http://127.0.0.1/x.m3u8','http://0x7f000001/x.mp4','https://user:pass@cdn.example.org/a.mp4','https://cdn.example.org/player.html'])
    assert.equal(highlightLine({link}),null);
  assert.equal(highlightLine({link:'https://cdn.example.org/a.m3u8',drm_key:'configured-key'}),null);
});
test('DasFootball public structured videos provide real upload dates and native links only',()=>{
  const data=[{'@type':'ItemList',itemListElement:[{'@type':'VideoObject',name:'Home vs Away',
    url:'https://dasfootball.com/home-vs-away-highlights-2026-11-12/',embedUrl:'https://cdn.example.org/highlight.mp4',
    uploadDate:'2026-11-12T22:12:00Z',thumbnailUrl:['https://cdn.example.org/cover.jpg']},
    {'@type':'VideoObject',name:'Outside page',url:'https://other.example.org/highlights/',embedUrl:'https://cdn.example.org/x.mp4'}]}];
  const result=parseDasHighlights('<script type="application/ld+json">'+JSON.stringify(data)+'</script>');
  assert.equal(result.length,1);assert.equal(result[0].lines[0].stream_type,'mp4');
  assert.equal(result[0].published_at,'2026-11-12T22:12:00.000Z');
});
test('HTTP 200 HTML is invalid media, a real HLS manifest is reachable but never playback-verified',async()=>{
  const line=highlightLine({link:'https://cdn.example.org/a.m3u8'});
  const invalid=await checkHighlightLine(line,{fetcher:async()=>new Response('<html>Access denied</html>')});
  assert.equal(invalid.status,'invalid_media');
  const valid=await checkHighlightLine(line,{fetcher:async()=>new Response('#EXTM3U\n#EXTINF:5\npart.ts')});
  assert.equal(valid.status,'reachable');assert.equal(valid.playback_verified,false);
});
test('media probe validates MP4 signature and rejects a redirect into a private network',async()=>{
  const mp4=await checkHighlightLine(highlightLine({link:'https://cdn.example.org/a.mp4'}),{
    fetcher:async()=>new Response(new Uint8Array([0,0,0,24,102,116,121,112]))});
  assert.equal(mp4.status,'reachable');
  let calls=0;
  const denied=await checkHighlightLine(highlightLine({link:'https://cdn.example.org/a.m3u8'}),{
    fetcher:async()=>{calls++;return new Response(null,{status:302,headers:{location:'http://127.0.0.1/a.m3u8'}});}});
  assert.equal(denied.status,'failed');assert.equal(calls,1);
});
test('unextractable website players are excluded; a native embed URL survives a non-native content URL',()=>{
  const rows=parseDasHighlights(html([
    {...video,contentUrl:'https://dasfootball.com/player/',embedUrl:'https://cdn.example.org/a.mp4'},
    {...video,url:'https://dasfootball.com/other-highlights/',contentUrl:'https://youtube.com/watch?v=123',embedUrl:'https://youtube.com/embed/123'},
    {...video,url:'https://dasfootball.com/replay-highlights/',name:'FULL MATCH Home vs Away'},
  ]));
  assert.equal(rows.length,1);assert.equal(rows[0].lines[0].stream_url,'https://cdn.example.org/a.mp4');
});
test('repeated pages and duplicate native URLs appear once while distinct HLS and MP4 links survive',()=>{
  const rows=parseDasHighlights(html([video,{...video,contentUrl:video.embedUrl},
    {...video,contentUrl:'https://cdn.example.org/highlight.m3u8'}]));
  assert.equal(rows.length,1);assert.equal(rows[0].lines.length,2);
});
test('retired sources are removed and rejected before any network request',async()=>{
  assert.deepEqual(highlightSources.map(x=>x.id),['dasfootball']);
  let calls=0;const fetcher=async()=>{calls++;return response('');};
  for(const provider of ['darkbyte','hoofoot','reddit','soccerfullmatch','scorebat','https://private.example.org/'])
    await assert.rejects(footballHighlights({provider},{fetcher}),/Unsupported/);
  assert.equal(calls,0);
});
test('an initial source outage is explicit with no fabricated links or player fallback',async()=>{
  const result=await footballHighlights({provider:'dasfootball',force:true},{fetcher:async()=>new Response('denied',{status:503})});
  assert.equal(result.unavailable,true);assert.deepEqual(result.entries,[]);
});
test('catalogue calls coalesce; extraction checks only requested link bytes and retains successful data after a failed refresh',async()=>{
  let calls=0,failed=false;
  const fetcher=async target=>{calls++;if(target===video.embedUrl)return new Response(new Uint8Array([0,0,0,24,102,116,121,112]),{status:206});assert.equal(target,'https://dasfootball.com/');
    await new Promise(resolve=>setTimeout(resolve,5));
    return failed?new Response('unavailable',{status:503}):response(html([video]));};
  const a={provider:'dasfootball',force:true};
  const [one,two]=await Promise.all([footballHighlights(a,{fetcher}),footballHighlights(a,{fetcher})]);
  assert.equal(calls,1);assert.equal(one.total,1);assert.deepEqual(one,two);
  const details=await footballHighlights({provider:'dasfootball',action:'details',entry_id:one.entries[0].id},{fetcher});
  assert.equal(details.entry.lines[0].stream_url,video.embedUrl);assert.equal(calls,2);
  assert.equal(details.entry.lines[0].link_check.status,'reachable');
  await footballHighlights({provider:'dasfootball',action:'details',entry_id:one.entries[0].id},{fetcher});assert.equal(calls,2);
  failed=true;const stale=await footballHighlights(a,{fetcher});
  assert.equal(stale.stale,true);assert.equal(stale.entries.length,1);assert.equal(stale.updated_at,one.updated_at);
});
test('unpublished entry and line URLs cannot turn extraction into an arbitrary URL fetch',async()=>{
  let calls=0;const fetcher=async url=>{calls++;assert.equal(url,'https://dasfootball.com/');return response(html([video]));};
  await assert.rejects(footballHighlights({provider:'dasfootball',action:'check',entry_id:'https://private.example.org/video.mp4',line_id:'fake'},{fetcher}));
  assert.equal(calls,0); // The previous fresh public catalogue is reused.
});
test('Get links excludes unreachable URLs instead of returning website or video-player fallbacks',async()=>{
  const fetcher=async url=>url==='https://dasfootball.com/'?response(html([{...video,embedUrl:'https://cdn.example.org/deleted.mp4'}])):new Response('gone',{status:404});
  const data=await footballHighlights({force:true},{fetcher});
  const details=await footballHighlights({action:'details',entry_id:data.entries[0].id},{fetcher});
  assert.deepEqual(details.entry.lines,[]);
  const list=await footballHighlights({}, {fetcher});assert.deepEqual(list.entries,[]);
});
test('Highlights ships no player asset or player/browser-launch dependency',()=>{
  assert.equal(existsSync(new URL('../admin_app/web/highlight_player.html',import.meta.url)),false);
  const page=readFileSync(new URL('../admin_app/lib/screens/highlights_page.dart',import.meta.url),'utf8');
  assert.doesNotMatch(page,/url_launcher|stream_preview_page|stream_detector_service|launchUrl|highlight_player/);
});
test('highlight requests remain behind existing Admin authentication and role checks',async()=>{
  const path=new URL('../supabase/functions/source-match-list/index.ts',import.meta.url);
  let code=readFileSync(path,'utf8').replace(/^import .*jsr:.*;\n/gm,'')
    .replace(/(['"])(\.\.\/_shared\/[^'"]+\.mjs)\1/g,(_,q,p)=>JSON.stringify(new URL(p,path).href));
  let handler,role='viewer';
  const before=globalThis.Deno;
  globalThis.Deno={env:{get:()=> 'test-value'},serve:fn=>handler=fn};
  code='const createClient=()=>({auth:{getUser:async()=>({data:{user:{id:"test"}}})},from:()=>({select:()=>({eq:()=>({single:async()=>({data:{role:globalThis.__highlightTestRole}})})})})});\n'+code;
  try {
    await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(code)).toString('base64'));
    assert.equal((await handler(new Request('https://api.example.org/function',{method:'POST',body:'{"source":"highlights"}'}))).status,401);
    globalThis.__highlightTestRole=role;
    const request=()=>new Request('https://api.example.org/function',{method:'POST',headers:{authorization:'Bearer fixture'},body:'{"source":"highlights","provider":"dasfootball"}'});
    assert.equal((await handler(request())).status,403);
    globalThis.__highlightTestRole='admin';
    const response=await handler(request());assert.equal(response.status,200);assert.equal((await response.json()).source,'highlights');
  } finally {globalThis.Deno=before;delete globalThis.__highlightTestRole;}
});
