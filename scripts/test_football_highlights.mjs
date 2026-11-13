import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {highlightLine,parseDarkbyteHighlights,mergeHighlightEntries,parseDasHighlights,
  parseHoofootHighlights,parseRedditHighlights,checkHighlightLine,footballHighlights} from '../supabase/functions/_shared/football_highlights.mjs';

test('only native highlight media and safe non-secret headers are accepted',()=>{
  const line=highlightLine({link:'https://cdn.example.org/h.mp4|Referer=https://site.example.org/game&Origin=https://site.example.org&User-agent=Player&Cookie=secret&accountToken=secret'});
  assert.equal(line.stream_type,'mp4');assert.equal(line.referer,'https://site.example.org/game');
  assert.equal(line.user_agent,'Player');assert.equal(JSON.stringify(line).includes('secret'),false);
  for(const link of ['http://127.0.0.1/x.m3u8','http://0x7f000001/x.mp4','https://user:pass@cdn.example.org/a.mp4','https://cdn.example.org/player.html'])
    assert.equal(highlightLine({link}),null);
  assert.equal(highlightLine({link:'https://cdn.example.org/a.m3u8',drm_key:'configured-key'}),null);
});
test('DarkByte highlights exclude other sports and replay parts, preserving highlights and extended clips',()=>{
  const formats=['HIGHLIGHTS','Extended in EN.','FULL MATCH','1st half','Ceremony'].map((title,i)=>({title,link:`https://cdn.example.org/${i}.m3u8`}));
  const rows=[{title:'Home vs Away',cat:'UCL',formats,eventInfo:{startTime:'2026/10/20 19:00:00 +0000'}},
    {title:'WWE Smackdown',cat:'WWE',formats},{title:'F1',cat:'F1',formats},{title:'Rugby',cat:'Rugby',formats}];
  const result=parseDarkbyteHighlights('provider_6/highlights.json',rows);
  assert.equal(result.length,1);assert.equal(result[0].lines.length,2);
  assert.equal(result[0].published_at,null);assert.equal(result[0].lines[0].playback_verified,false);
});
test('duplicate DarkByte feeds merge once without losing distinct playback headers',()=>{
  const one=parseDarkbyteHighlights('provider_2/categories/Fifa_Highlight.json',[
    {title:'Home vs Away',resolved_streams:[{link:'https://cdn.example.org/a.m3u8'}]}]);
  const two=parseDarkbyteHighlights('provider_5/categories/FIFA_WC26_Highlights.json',[
    {name:'Home vs Away',streams:[{link:'https://cdn.example.org/a.m3u8'},
      {link:'https://cdn.example.org/a.m3u8|Referer=https://site.example.org/'}]}]);
  const merged=mergeHighlightEntries([...one,...two]);
  assert.equal(merged.length,1);assert.equal(merged[0].lines.length,2);assert.equal(merged[0].source_files.length,2);
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
test('Hoofoot discovers highlight pages, not category menus or external ads',()=>{
  const html='<a href="/full-matches/uefa/home-vs-away-highlights-november-12-2026/">Watch</a>'.repeat(2)+
    '<a href="https://ad.example.org/home-highlights-now/">Ad</a><a href="/full-matches/uefa/">Menu</a>';
  const rows=parseHoofootHighlights(html);assert.equal(rows.length,1);assert.equal(rows[0].title,'Home Vs Away');
  assert.deepEqual(rows[0].lines,[]);
});
test('Reddit native video is HLS; external links stay website-only and non-goal soccer posts are excluded',()=>{
  const result=parseRedditHighlights({data:{children:[
    {data:{id:'native',title:'Home [1]-0 Away Goal',permalink:'/r/soccer/comments/native/goal/',created_utc:1794520000,media:{reddit_video:{hls_url:'https://v.redd.it/123/HLSPlaylist.m3u8'}}}},
    {data:{id:'embed',title:'Home 2-0 Away',permalink:'/r/soccer/comments/embed/goal/',url:'https://youtube.com/watch?v=123'}},
    {data:{id:'news',title:'Manager interview',permalink:'/r/soccer/comments/news/interview/'}}
  ]}},'soccer');
  assert.equal(result.length,2);assert.equal(result[0].lines[0].stream_type,'hls');assert.equal(result[1].lines.length,0);
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
test('unknown providers and unpublished entry/line IDs cannot become arbitrary URL fetches',async()=>{
  let calls=0;const fetcher=async()=>{calls++;return Response.json([]);};
  await assert.rejects(footballHighlights({provider:'https://private.example.org/'},{fetcher}));
  await assert.rejects(footballHighlights({provider:'soccerfullmatch',action:'check',entry_id:'fake',line_id:'https://cdn.example.org/a.mp4'},{fetcher}));
  assert.equal(calls,0);
});
test('catalogue calls coalesce and a failed refresh keeps the last successful source snapshot',async()=>{
  let calls=0,failed=false;
  const fetcher=async()=>{calls++;await new Promise(resolve=>setTimeout(resolve,5));
    if(failed) return new Response('unavailable',{status:503});
    return Response.json([{title:'Home vs Away',name:'Home vs Away',cat:'UCL',formats:[{link:'https://cdn.example.org/a.m3u8'}]}]);};
  const a={provider:'darkbyte',force:true};
  const [one,two]=await Promise.all([footballHighlights(a,{fetcher}),footballHighlights(a,{fetcher})]);
  assert.equal(calls,3);assert.equal(one.total,1);assert.deepEqual(one,two);
  failed=true;const stale=await footballHighlights(a,{fetcher});
  assert.equal(stale.stale,true);assert.equal(stale.entries.length,1);assert.equal(stale.updated_at,one.updated_at);
});
test('unavailable Reddit feed is explicit, with no fabricated video links',async()=>{
  const result=await footballHighlights({provider:'reddit',force:true},{fetcher:async()=>new Response('denied',{status:403})});
  assert.equal(result.unavailable,true);assert.deepEqual(result.entries,[]);assert.match(result.warnings[0],/Reddit/);
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
    const request=()=>new Request('https://api.example.org/function',{method:'POST',headers:{authorization:'Bearer fixture'},body:'{"source":"highlights","provider":"scorebat"}'});
    assert.equal((await handler(request())).status,403);
    globalThis.__highlightTestRole='admin';
    const response=await handler(request());assert.equal(response.status,200);assert.equal((await response.json()).source,'highlights');
  } finally {globalThis.Deno=before;delete globalThis.__highlightTestRole;}
});
