import {test} from 'node:test';
import assert from 'node:assert/strict';
import {footballHighlights} from '../supabase/functions/_shared/football_highlights.mjs';
import {publicHighlightsRequest} from '../supabase/functions/_shared/public_highlights.mjs';
test('publisher cursor pages remain finite, preserve metadata and drop duplicate cards',async()=>{
 const fetcher=async address=>{
  const offset=Number(new URL(address).searchParams.get('offset'));
  return Response.json({cards:offset===0?[{slug:'page-first-highlights',title:'Page First',categoryName:'League A'},{slug:'page-first-highlights',title:'Page First'}]:[{slug:'page-second-highlights',title:'Page Second'}],hasMore:offset===0});
 };
 const one=await footballHighlights({action:'catalog',force:true,offset:0},{fetcher});
 assert.equal(one.entries.length,1);assert.equal(one.next_offset,2);assert.equal(one.has_more,true);
 const two=await footballHighlights({action:'catalog',force:true,offset:one.next_offset},{fetcher});
 assert.equal(two.entries.length,1);assert.equal(two.has_more,false);assert.equal(two.next_offset,3);
});
test('public highlights is read-only, strips unlisted fields and never forwards Admin headers',async()=>{
 const fetcher=async(address,options)=>{
  assert.equal(options.headers.Authorization,undefined);assert.equal(options.headers.Cookie,undefined);
  return Response.json({cards:[{slug:'public-safe-highlights',title:'Public Safe',categoryName:'League A',admin_secret:'do-not-expose',authorization:'private'}],hasMore:false});
 };
 const response=await publicHighlightsRequest(new Request('https://api.example.org/highlights?refresh=1',{headers:{Authorization:'Bearer Admin-secret',Cookie:'private'}}),{fetcher});
 const text=await response.text();assert.equal(response.status,200);assert(!text.includes('secret'));assert(!text.includes('authorization'));assert(!text.includes('Cookie'));
 const data=JSON.parse(text);assert.equal(data.source,'highlights');assert.equal(data.entries[0].league,'League A');assert.equal(data.has_more,false);
 assert.equal((await publicHighlightsRequest(new Request('https://api.example.org/highlights?action=check'))).status,400);
 assert.equal((await publicHighlightsRequest(new Request('https://api.example.org/highlights',{method:'POST'}))).status,405);
});
test('server search filters published articles and paginates without live-match URLs',async()=>{
 const rows=Array.from({length:12},(_,i)=>({type:'article',title:'Search fixture '+i,href:'/search-fixture-'+i+'-highlights/'}));
 const fetcher=async address=>{assert(address.includes('/api/search/'));return Response.json([...rows,{type:'team',href:'/teams/arsenal/',title:'Arsenal'}]);};
 const one=await footballHighlights({force:true,query:'unique-search-test'},{fetcher});
 const two=await footballHighlights({query:'unique-search-test',offset:one.next_offset},{fetcher});
 assert.equal(one.entries.length,9);assert.equal(two.entries.length,3);assert.equal(two.has_more,false);
});
test('a publisher-linked public Streamable export resolves native media without authentication',async()=>{
 const slug='public-streamable-highlights',entry_id='dasfootball:https://dasfootball.com/'+slug+'/';
 const calls=[];
 const fetcher=async(address,options)=>{
  calls.push(address);assert.equal(options.headers?.Authorization,undefined);
  if(address.includes('/api/homepage-posts/'))return Response.json({cards:[{slug,title:'Public Streamable'}],hasMore:false});
  if(address===entry_id.slice(12))return new Response('<script type="application/ld+json">'+JSON.stringify({'@type':'VideoObject',name:'Public Streamable',embedUrl:'https://streamable.com/e/abc123'})+'</script>',{headers:{'Content-Type':'text/html'}});
  if(address==='https://api.streamable.com/videos/abc123')return Response.json({files:{mp4:{url:'//cdn-cf.streamable.com/video/mp4/abc123.mp4',height:720,duration:90}}});
  assert.equal(address,'https://cdn-cf.streamable.com/video/mp4/abc123.mp4');
  return new Response(new Uint8Array([0,0,0,24,102,116,121,112]),{status:206});
 };
 await footballHighlights({force:true},{fetcher});
 const data=await footballHighlights({action:'details',entry_id},{fetcher});
 assert.equal(data.entry.lines.length,1);assert.equal(data.entry.lines[0].playback_verified,false);assert.equal(data.entry.lines[0].link_check.status,'reachable');
 assert.equal(calls.length,4);
});
test('refreshing the first Highlights page invalidates later cached cursors',async()=>{
 let generation=0;const calls=[];
 const fetcher=async address=>{const offset=Number(new URL(address).searchParams.get('offset')||0);calls.push(offset);
  return Response.json({cards:Array.from({length:9},(_,i)=>({slug:`fresh-${generation}-${offset+i}-highlights`,title:`Generation ${generation} clip ${offset+i}`})),hasMore:offset===0});};
 await footballHighlights({force:true},{fetcher});
 await footballHighlights({offset:9},{fetcher});generation=1;
 await footballHighlights({force:true},{fetcher});
 const later=await footballHighlights({offset:9},{fetcher});
 assert(later.entries.every(row=>row.title.startsWith('Generation 1')));assert.deepEqual(calls,[0,9,0,9]);
});
