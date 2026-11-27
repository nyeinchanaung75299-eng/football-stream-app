import {test} from 'node:test';
import assert from 'node:assert/strict';
import {footballHighlights,highlightCatalogueFreshness,publicNormalMatchCandidates,publicNormalMatchMetadata,highlightLine,licensedNormalMp4,parseDateHighlightMetadata} from '../supabase/functions/_shared/football_highlights.mjs';
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

test('normal match metadata stays separate from the legacy catalogue and never invents a native link',async()=>{
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
 assert.equal(list.entries.length,1);
 assert.equal(list.entries[0].title,'Older fixture');
 assert.equal(calls.length,1);
 const details=await footballHighlights({action:'details',entry_id:'dasfootball:'+page},{fetcher});
 assert.equal(details.entry.source_page_url,page);
 assert.equal(details.entry.source_page_only,true);
 assert.deepEqual(details.entry.lines,[]);
 assert.equal(calls.length,2);
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

test('empty or failed first-page refresh retains last populated catalogue',async()=>{
 const query='unique-catalogue-preservation';
 let mode='populated';
 const fetcher=async address=>{
  assert(address.includes('/api/search/'));
  if(mode==='error')throw Error('Fixture upstream failed');
  return Response.json(mode==='empty'?[]:[{type:'article',slug:'catalogue-preservation-highlights',title:'Saved catalogue fixture'}]);
 };
 const first=await footballHighlights({query,force:true},{fetcher});
 assert.equal(first.entries.length,1);
 mode='empty';
 const empty=await footballHighlights({query,force:true},{fetcher});
 assert.equal(empty.stale,true);
 assert.deepEqual(empty.entries,first.entries);
 assert.equal(empty.updated_at,first.updated_at);
 mode='error';
 const failed=await footballHighlights({query,force:true},{fetcher});
 assert.equal(failed.stale,true);
 assert.deepEqual(failed.entries,first.entries);
});

test('dated JSON-LD ItemList supports the observed fixture shape, not media delivery',async()=>{
 const now=Date.parse('2026-11-24T19:00:00Z');
 const fixture=(name,slug,id,league,stamp='2026-11-23T22:44:35.930Z')=>({
  '@type':'VideoObject',name:name+' highlights',description:name+' highlights, '+league,
  url:'https://dasfootball.com/match/'+slug+'-2026-11-23-'+id+'/',
  uploadDate:stamp,about:name.split(' vs ').map(name=>({'@type':'SportsTeam',name})),
  contentUrl:'https://example.org/test-only.mp4'
 });
 const brentford=fixture('Brentford vs Everton','brentford-vs-everton',209637,'Premier League');
 const monza=fixture('Monza vs Fiorentina','monza-vs-fiorentina',210173,'Serie A');
 const levante=fixture('Levante UD vs Elche','levante-ud-vs-elche',213644,'La Liga');
 const extended={...brentford,name:'Brentford vs Everton Extended Highlights'};
 const badHost={...monza,url:'https://example.org/match/monza-vs-fiorentina-2026-11-23-210173/'};
 const future={...fixture('Future vs Team','future-vs-team',9,'League'),'uploadDate':'2026-11-27T00:00:00Z'};
 const html=rows=>'<script type="application/ld+json">'+JSON.stringify([
 {'@type':'WebSite',name:'Football highlights'},
 {'@type':'ItemList',name:'Football highlights Tuesday, 24 November 2026',numberOfItems:rows.length,itemListElement:rows}
 ])+'</script>';
 const data=html([brentford,monza,levante,{...brentford,url:brentford.url+'?ref=duplicate'},extended,badHost,future]);
 const parsed=parseDateHighlightMetadata(data,{now});
 assert.equal(parsed.length,3);
 assert.equal(parsed[0].league,'Premier League');
 assert.equal(parsed[0].match_date,'2026-11-23');
 assert.equal(parsed[0].match_id,'209637');
 assert.equal(parsed[0].home_team,'Brentford');
 assert(parsed.every(row=>row.source_page_only&&row.lines.length===0));
 assert(!JSON.stringify(parsed).includes('test-only.mp4'));
 const calls=[];
 let failDates=false;
 const fetcher=async address=>{
  calls.push(address);
  if(address.includes('/api/homepage-posts/')){
   const offset=Number(new URL(address).searchParams.get('offset'));
   return Response.json({cards:[{slug:'legacy-'+offset+'-highlights-2026-11-21',title:'Legacy '+offset,publishedAt:'2026-11-21T22:43:00Z'}],hasMore:offset===0});
  }
  if(address.includes('/api/search/'))return Response.json([]);
  if(address.includes('?date=')){
   if(failDates)throw Error('Fixture source unavailable');
   return new Response(address.endsWith('2026-11-24')?data:html([]),{headers:{'Content-Type':'text/html'}});
  }
  throw Error('Unexpected request '+address);
 };
 const result=await footballHighlights({force:true},{fetcher,includeDateCatalogue:true,now});
 assert.equal(result.entries.length,4);
 assert.equal(result.entries[0].title,'Brentford vs Everton');
 assert.equal(result.next_offset,1);
 assert.equal(result.has_more,true);
 assert.equal(calls.length,4);
 const second=await footballHighlights({force:true,offset:1},{fetcher,includeDateCatalogue:true,now});
 assert.equal(second.entries.length,1);
 assert.equal(second.has_more,false);
 assert.equal(calls.length,5);
 const search=await footballHighlights({force:true,query:'Brentford'},{fetcher,includeDateCatalogue:true,now});
 assert.equal(search.entries.length,1);
 assert.equal(search.entries[0].match_id,'209637');
 failDates=true;
 const fallback=await footballHighlights({force:true},{fetcher,includeDateCatalogue:true,now});
 assert.equal(fallback.entries.length,4);
 assert.equal(fallback.stale,true);
 assert(!JSON.stringify(fallback).includes('test-only.mp4'));
});

test('Admin reads the MP4 in the publisher’s Normal Highlights tab only',()=>{
 const page='https://dasfootball.com/match/test-home-vs-test-away-2026-11-23-99000008/';
 const normal='https://media.example.org/normal.mp4?expires=1000&signature=fixture';
 const extended='https://media.example.org/extended.mp4';
 const html=`
   <button role="tab" aria-controls="fixture-highlights">Highlights</button>
   <button aria-controls="fixture-extended" role="tab">Extended HL</button>
   <div role="tabpanel" id="fixture-highlights">
     <div><video><source src="${normal.replace('&','&amp;')}" type="video/mp4"></video></div>
   </div>
   <div id="fixture-extended" role="tabpanel"><video src="${extended}"></video></div>
   <script type="application/ld+json">${JSON.stringify({
    '@type':'VideoObject',name:'Test Home vs Test Away highlights',contentUrl:normal
   })}</script>`;
 const admin=publicNormalMatchMetadata(html,page,{allowPublisherMp4:true});
 assert.deepEqual(admin.lines.map(line=>line.stream_url),[normal]);
 assert.deepEqual(publicNormalMatchMetadata(html,page).lines,[]);
 const unavailable=html.replace('fixture-highlights">Highlights','missing-normal-panel">Highlights');
 assert.deepEqual(publicNormalMatchMetadata(unavailable,page,{allowPublisherMp4:true}).lines,[]);
});

test('Admin recovers a publisher-hosted Normal Highlights MP4 and revalidates it',async()=>{
 const now=Date.parse('2026-11-24T19:00:00Z');
 const page='https://dasfootball.com/match/test-home-vs-test-away-2026-11-23-99000001/';
 const media='https://media.example.org/clips/test-only.mp4?expires=99999&signature=fixture';
 const record={'@type':'VideoObject',name:'Test Home vs Test Away highlights',url:page,uploadDate:'2026-11-23T22:00:00Z',description:'Test Home vs Test Away highlights, Test League'};
 const schema=value=>'<script type="application/ld+json">'+JSON.stringify(value)+'</script>';
 const dated=schema({'@type':'ItemList',name:'Football highlights Tuesday, 24 November 2026',itemListElement:[record]});
 const published={'@type':'VideoObject',name:'Normal Highlights',url:page,contentUrl:media};
 let authorized=true,mediaRequests=0;
 const fetcher=async address=>{
   if(address.includes('/api/homepage-posts/'))return Response.json({cards:[],hasMore:false});
   if(address.includes('?date='))return new Response(dated,{headers:{'Content-Type':'text/html'}});
   if(address===page)return new Response('<button>Highlights</button>'+schema(authorized?published:{...published,requiresSubscription:true}),{headers:{'Content-Type':'text/html'}});
   if(address===media){mediaRequests++;return new Response(new Uint8Array([0,0,0,24,102,116,121,112]),{status:206});}
   throw Error('Unexpected fixture request');
 };
 const admin={fetcher,includeDateCatalogue:true,now};
 const catalog=await footballHighlights({force:true},admin);
 assert.equal(catalog.entries[0].source_page_only,true);
 const entry_id=catalog.entries[0].id;
 const detail=await footballHighlights({action:'details',entry_id},admin);
 assert.equal(detail.entry.source_page_only,false);
 assert.equal(detail.entry.league,'Test League');
 assert.equal(detail.entry.published_at,record.uploadDate.replace('Z','.000Z'));
 assert.equal(detail.entry.lines[0].stream_url,media);
 assert.equal(mediaRequests,0);
 const publicDetails=await footballHighlights({action:'details',entry_id},{fetcher});
 assert.deepEqual(publicDetails.entry.lines,[]);
 const check=await footballHighlights({action:'check',entry_id,line_id:detail.entry.lines[0].id},admin);
 assert.equal(check.check.status,'reachable');
 assert.equal(check.check.playback_verified,false);
 assert.equal(mediaRequests,1);
 authorized=false;
 const denied=await footballHighlights({action:'details',entry_id,force:true},admin);
 assert.equal(denied.entry.source_page_only,true);
 assert.equal(denied.entry.lines.length,0);
 await assert.rejects(footballHighlights({action:'check',entry_id,line_id:detail.entry.lines[0].id},admin),/No authorized MP4/);
 assert.equal(mediaRequests,1);
});

test('Admin first-page catalogue finds confirmed Normal HL when the post feed is old and retains it during outages', async () => {
  const root = 'https://dasfootball.com/';
  const page = root + 'match/newcastle-vs-arsenal-2026-11-23-123/';
  const other = root + 'match/everton-vs-chelsea-2026-11-23-124/';
  const calls = [];
  let mode = 'stale';
  const fetcher = async url => {
    calls.push(url);
    if (url.includes('/api/homepage-posts/')) {
      if (mode === 'outage') return new Response('', {status: 503});
      const publishedAt = mode === 'fresh' ? new Date().toISOString() : '2020-01-01T00:00:00Z';
      return Response.json({
        cards: [{slug: 'legacy-highlights', title: 'Legacy post', publishedAt}],
        hasMore: true,
      });
    }
    if (url === root) {
      if (mode === 'outage') return new Response('', {status: 403});
      return new Response(`<a href="${page}">Match</a><a href="${other}">Other</a>`, {headers: {"content-type": "text/html"}});
    }
    if (url === page) return new Response('<button>Normal Highlights</button>', {headers: {"content-type": "text/html"}});
    if (url === other) return new Response('<button>Extended Highlights</button>', {headers: {"content-type": "text/html"}});
    throw Error('Unexpected request');
  };
  const admin = {fetcher, includeNormal: true};
  const first = await footballHighlights({force: true}, admin);
  assert.deepEqual(first.entries.map(row => row.highlight_variant), ['normal', undefined]);
  assert.equal(first.entries[0].published_at, null);
  assert.equal(first.entries[0].source_page_only, true);
  assert.equal(first.latest_published_at, '2020-01-01T00:00:00.000Z');
  assert.equal(first.next_offset, 1);
  assert.equal(first.has_more, true);

  calls.length = 0;
  const pageTwo = await footballHighlights({offset: first.next_offset}, admin);
  assert.equal(pageTwo.entries.length, 1);
  assert.equal(calls.length, 1);
  assert.match(calls[0], /offset=1$/);

  mode = 'outage';
  const cached = await footballHighlights({force: true}, admin);
  assert.equal(cached.stale, true);
  assert.equal(cached.updated_at, first.updated_at);
  assert.deepEqual(cached.entries, first.entries);

  mode = 'fresh';
  calls.length = 0;
  const fresh = await footballHighlights({force: true}, admin);
  assert.deepEqual(fresh.entries.map(row => row.title), ['Legacy post']);
  assert.equal(calls.length, 1);
});
