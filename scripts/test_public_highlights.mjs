import {test} from 'node:test';
import assert from 'node:assert/strict';
import {footballHighlights,highlightCatalogueFreshness,publicNormalMatchCandidates,publicNormalMatchMetadata,highlightLine,licensedNormalMp4} from '../supabase/functions/_shared/football_highlights.mjs';
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

test('highlights search accepts published post cards without leaking team results',async()=>{
 const calls=[];
 const fetcher=async url=>{
  calls.push(url);
  return Response.json([
   {type:'article',slug:'liverpool-manchester-united-match-highlights-2026-11-22',title:'Liverpool vs Manchester United'},
   {type:'post',href:'/manchester-city-liverpool-highlights-2026-11-22/',title:'Manchester City vs Liverpool'},
   {slug:'juventus-venezia-highlights-2026-11-22',title:'Juventus vs Venezia'},
   {type:'team',slug:'manchester-united-highlights-2026-11-22',title:'Manchester United team'},
   {type:'post',slug:'liverpool-full-match-2026-11-22',title:'Liverpool FULL MATCH'},
  ]);
 };
 const data=await footballHighlights({query:'nov2026-variant-highlights',force:true},{fetcher});
 assert.equal(calls.length,1);
 assert.equal(data.entries.length,3);
 assert(data.entries.every(row=>row.source_page_url.startsWith('https://dasfootball.com/')));
});

test('highlight freshness never mistakes the refresh clock for a new publisher date',()=>{
 const now=Date.parse('2026-11-24T08:00:00Z');
 const old=highlightCatalogueFreshness([{published_at:'2026-11-21T22:43:00Z'},{published_at:'invalid'},{published_at:'2026-11-25T00:00:00Z'}],now);
 assert.equal(old.latest_published_at,'2026-11-21T22:43:00.000Z');
 assert.equal(old.publisher_age_hours,57);
 assert.equal(old.warnings.length,1);
 assert.equal(highlightCatalogueFreshness([{published_at:'2026-11-24T06:00:00Z'}],now).warnings.length,0);
 assert.equal(highlightCatalogueFreshness([],now).latest_published_at,null);
});

test('new match URL catalogue lists Normal HL metadata and never invents a native link',async()=>{
 const page='https://dasfootball.com/match/brentford-vs-everton-2026-11-23-209637/';
 const extended='https://dasfootball.com/match/other-vs-team-2026-11-23-209638/';
 const home='<a href="'+page+'">Brentford vs Everton</a><a href="'+page+'?ref=home">duplicate</a><a href="'+extended+'">Other fixture</a><a href="https://other.example.org/match/team-vs-team-2026-11-23-9/">untrusted</a>';
 const normalHtml='<title>Brentford vs Everton | DasFootball</title><h2>Highlights</h2><button><svg></svg>Highlights</button><button>Extended HL</button>';
 assert.deepEqual(publicNormalMatchCandidates(home),[page,extended]);
 const normal=publicNormalMatchMetadata(normalHtml,page);
 assert.equal(normal.title,'Brentford vs Everton');
 assert.equal(normal.match_date,'2026-11-23');
 assert.equal(normal.published_at,null);
 assert.equal(normal.highlight_variant,'normal');
 assert.deepEqual(normal.lines,[]);
 assert.equal(publicNormalMatchMetadata('<h2>Highlights</h2><button>Extended HL</button>',extended),null);
 assert.equal(highlightLine({title:'Extended HL',link:'https://example.org/extended.mp4'}),null);
 const calls=[];
 const fetcher=async address=>{
  calls.push(address);
  if(address.includes('/api/homepage-posts/'))return Response.json({cards:[{slug:'old-normal-highlights',title:'Older fixture',publishedAt:'2020-01-01T00:00:00Z'}],hasMore:false});
  if(address==='https://dasfootball.com/')return new Response(home,{headers:{'Content-Type':'text/html'}});
  if(address===page)return new Response(normalHtml,{headers:{'Content-Type':'text/html'}});
  if(address===extended)return new Response('<button>Extended HL</button>',{headers:{'Content-Type':'text/html'}});
  throw Error('Unexpected request: '+address);
 };
 const list=await footballHighlights({force:true},{fetcher});
 assert.equal(list.entries.length,2);
 assert.equal(list.entries[0].source_page_url,page);
 assert.equal(list.entries[0].source_page_only,true);
 const details=await footballHighlights({action:'details',entry_id:list.entries[0].id},{fetcher});
 assert.equal(details.entry.source_page_url,page);
 assert.deepEqual(details.entry.lines,[]);
 assert.equal(calls.length,4);
});

test('normal match MP4 requires explicit reusable public media metadata, never Extended HL',()=>{
 const page='https://dasfootball.com/match/brentford-vs-everton-2026-11-23-209637/';
 const sample='https://dasfootball.com/media/test-fixture.mp4';
 const record={'@type':'VideoObject',name:'Normal Highlights',url:page,contentUrl:sample,isAccessibleForFree:true,license:'https://creativecommons.org/licenses/by/4.0/'};
 const html=rows=>'<button>Highlights</button><script type="application/ld+json">'+JSON.stringify({'@graph':rows})+'</script>';
 assert.equal(licensedNormalMp4(html([record]),page)[0].stream_url,sample);
 assert.deepEqual(licensedNormalMp4(html([{...record,name:'Extended HL'},{...record,license:null},{...record,requiresSubscription:true},{...record,contentUrl:sample+'?token=x'},{...record,contentUrl:'https://other.example.org/media.mp4'},{...record,isAccessibleForFree:false}]),page),[]);
 const entry=publicNormalMatchMetadata(html([record]),page);
 assert.equal(entry.source_page_only,false);
 assert.equal(entry.lines[0].stream_type,'mp4');
 assert.equal(entry.lines[0].playback_verified,false);
});
