import test from 'node:test';
import assert from 'node:assert/strict';
import {liveXtvPublishedMatches,liveXtvPublishedSources,liveXtvPublishedApiMatches,liveXtvMatches,liveXtvStreams} from '../supabase/functions/_shared/livextv_source.mjs';
import {isExperimentalFootballSource,experimentalMatches,experimentalStreams} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const index='https://livextv.pro/live';
const page='https://livextv.pro/watch/32410';
const htmlResponse=text=>new Response(text,{headers:{'content-type':'text/html; charset=utf-8'}});
const fixtureIndex=[
  '<article class="event-card" data-sport="Football">',
  ' <a href="/watch/32410"><h3>Estonia vs Bulgaria</h3>',
  ' <span>UEFA Nations League</span>',
  ' <time datetime="2026-11-16T19:45:00Z">19:45 UTC</time></a>',
  '</article>',
  '<article class="event-card"><a href="/watch/32411">',
  ' <h3>Los Angeles Lakers vs Chicago Bulls</h3>',
  ' <span>NBA Basketball</span></a></article>',
  '<article class="event-card"><a href="/watch/32412">',
  ' <h3>Eritrea vs Guinea</h3><span>AFCON Qualifying</span>',
  '</a></article>',
  '<a href="/watch/99999"><h3>Other Team vs Another Team</h3></a>',
].join('\n');
const watchPage=[
  '<a href="/watch/32410?s=1">HD | DAZN</a>',
  '<a href="/watch/32410?s=2">SD | DAZN</a>',
  '<a href="/watch/32499?s=1">Bad other match source</a>',
].join('\n');
const fetchPages=pages=>async url=>htmlResponse(pages[String(url)]??'<!doctype html><html></html>');

test('LiveXTV is an admin-only experimental provider',()=>{
  assert.equal(isExperimentalFootballSource('livextv'),true);
});
test('LiveXTV index accepts football cards and rejects NBA or unclassified rows',()=>{
  const list=liveXtvPublishedMatches(fixtureIndex);
  assert.deepEqual(list.map(x=>[x.home_team,x.away_team]),[
    ['Estonia','Bulgaria'],['Eritrea','Guinea'],
  ]);
  assert.equal(list[0].league,'UEFA Nations League');
  assert.equal(list[0].match_time,'2026-11-16T19:45:00.000Z');
  assert.equal(list[1].match_time,null);
  assert.equal(list[0].source,'livextv');
  assert.equal(list[0].anchors[0].nick_name,'Watch • inspect sources');
});
test('Only actually published event HD/SD source options appear',()=>{
  const choices=liveXtvPublishedSources(watchPage,page);
  assert.deepEqual(choices.map(x=>x.nick_name),['HD | DAZN','SD | DAZN']);
  assert.deepEqual(choices.map(x=>x.watch_url),[
    'https://livextv.pro/watch/32410?s=1',
    'https://livextv.pro/watch/32410?s=2',
  ]);
  assert.equal(new Set(choices.map(x=>x.room_num)).size,2);
  assert.deepEqual(liveXtvPublishedSources('<a href="?s=1">Live</a>',page),[]);
});
test('LiveXTV reads explicit Football SportsEvent JSON UTC times',()=>{
  const html='<script type="application/ld+json">'+JSON.stringify([
    {'@type':'SportsEvent',name:'Ghana vs Somalia',sport:'Football',
      url:'/watch/32413',startDate:'2026-11-17T15:00:00Z'},
    {'@type':'SportsEvent',name:'Jets vs Eagles',sport:'American Football',
      url:'/watch/32414',startDate:'2026-11-17T15:00:00Z'},
  ])+'</script>';
  const list=liveXtvPublishedMatches(html);
  assert.equal(list.length,1);
  assert.equal(list[0].home_team,'Ghana');
  assert.equal(list[0].match_time,'2026-11-17T15:00:00.000Z');
});
test('LiveXTV match list attaches real HD/SD choices to one published match',async()=>{
  const fetcher=fetchPages({[index]:fixtureIndex,[page]:watchPage});
  const list=await experimentalMatches('livextv',{fetcher});
  assert.equal(list.results,2);
  assert.deepEqual(list.matches[0].anchors.map(x=>x.nick_name),[
    'HD | DAZN','SD | DAZN']);
  assert.deepEqual(list.diagnostics.available_days_mmt,['2026-11-17']);
  assert.equal(list.diagnostics.missing_kickoff_count,1);
});
test('LiveXTV falls back to the public home index if /live is inaccessible',async()=>{
  const fetcher=async url=>String(url)===index
    ?new Response('Forbidden',{status:403,headers:{'content-type':'text/html'}})
    :htmlResponse(String(url)==='https://livextv.pro/'?fixtureIndex:watchPage);
  const list=await liveXtvMatches({fetcher});
  assert.equal(list.results,2);
  assert.equal(list.matches[0].home_team,'Estonia');
});

test('Selecting SD never mixes media from HD and keeps health unknown',async()=>{
  const sd=page+'?s=2',media='https://video.example.org/public/live.m3u8';
  const fetcher=fetchPages({[page]:watchPage,[sd]:'<video src="'+media+'"></video>'});
  const result=await experimentalStreams('livextv',{page_url:page,watch_url:sd},{fetcher});
  assert.deepEqual(result.lines.map(x=>x.url),[media]);
  assert.equal(result.lines[0].health_status,'unknown');
  assert.equal(result.lines[0].stream_type,'hls');
  assert.equal(result.lines[0].referer,sd);
  assert.equal(result.diagnostics.playback_verified,false);
});
test('External, private, and unpublished LiveXTV targets are rejected',async()=>{
  const fetcher=fetchPages({[page]:watchPage});
  const unsupported=await liveXtvStreams(
    {page_url:page,watch_url:page+'?s=3'},{fetcher});
  assert.equal(unsupported.line_count,0);
  assert.equal(unsupported.diagnostic_code,'source_not_published');
  for(const p of ['https://127.0.0.1/watch/32410',
    'https://not-livextv.pro/watch/32410','https://livextv.pro:8443/watch/32410',
    'https://livextv.pro/watch/32410?auth=secret',
    'https://livextv.pro/watch/32410?s=1&s=2']){
    const result=await liveXtvStreams({page_url:p},{fetcher});
    assert.equal(result.line_count,0);
  }
});
test('Player 403 never means confirmed video failure or successful HLS',async()=>{
  const fetcher=async()=>new Response('Forbidden',{status:403,
    headers:{'content-type':'text/html'}});
  const result=await liveXtvStreams({page_url:page},{fetcher});
  assert.equal(result.line_count,0);
  assert.equal(result.diagnostic_code,'watch_page_unavailable');
  assert.equal(result.ready,false);
});


test('LiveXTV card explicit sport and JSON league identify published football events',()=>{
  const card='<div class="event-card" data-sport="football"><a href="/watch/32789"><h3>Ghana vs Mali</h3></a></div>';
  const json='<script type="application/json">'+JSON.stringify({events:[{
    type:'SportsEvent',title:'Kenya vs Tanzania',league:{name:'AFCON Qualifying'},
    href:'/watch/32790',startDate:'2026-11-17T19:00:00Z',
  }]})+'</script>';
  const matches=liveXtvPublishedMatches(card+json);
  assert.deepEqual(matches.map(m=>m.home_team).sort(),['Ghana','Kenya']);
});
test('LiveXTV JS shell reports unavailable public fixture data rather than confirmed empty day',async()=>{
  const fetcher=async()=>htmlResponse('<html><script src="/app.js"></script></html>');
  const catalog=await liveXtvMatches({fetcher});
  assert.equal(catalog.results,0);
  assert.equal(catalog.diagnostics.content_state,'browser_render_or_unsupported_markup');
});

test('LiveXTV reads public football index when generic pages cannot publish fixtures',async()=>{
  const footballIndex='https://livextv.pro/sport/football';
  const fetcher=fetchPages({
    [index]:"<h1>We've moved.</h1><p>LiveXTV has a new home.</p>",
    [footballIndex]:fixtureIndex,
    'https://livextv.pro/':"<h1>We've moved.</h1>",
    [page]:watchPage,
  });
  const list=await liveXtvMatches({fetcher});
  assert.equal(list.results,2);
  assert.equal(list.diagnostics.content_state,'matches_found');
  assert.deepEqual(list.matches.map(m=>m.home_team),['Estonia','Eritrea']);
});

test('LiveXTV moved landing page is not reported as verified empty fixtures',async()=>{
  const fetcher=async()=>htmlResponse("<h1>We've moved.</h1><p>LiveXTV has a new home. Update your bookmark.</p>");
  const list=await liveXtvMatches({fetcher});
  assert.equal(list.results,0);
  assert.deepEqual(list.matches,[]);
  assert.equal(list.diagnostics.content_state,'source_moved_or_unavailable');
  assert.equal(list.diagnostics.confirmed_kickoff_count,0);
});

test('LiveXTV distinguishes a denied index from a readable moved homepage',async()=>{
  const fetcher=async url=>String(url)===index
    ?new Response('Forbidden',{status:403,headers:{'content-type':'text/html'}})
    :htmlResponse("<h1>We've moved.</h1><p>Update your bookmark.</p>");
  const list=await liveXtvMatches({fetcher});
  assert.equal(list.results,0);
  assert.equal(list.diagnostics.content_state,'source_moved_or_unavailable');
});

const apiIndex='https://api.ppv.st/api/streams';
const jsonResponse=data=>new Response(JSON.stringify(data),{
  headers:{'content-type':'application/json'},
});
const publishedApiSample={
  success:true,streams:[
    {category:'American Football',streams:[
      {id:90001,name:'Bills vs Patriots',starts_at:1795134600,
        ends_at:1795145400,category_name:'American Football'}]},
    {category:'Football',streams:[
      {id:32372,name:'Orlando City SC vs. FC Cincinnati',tag:'MLS',
        starts_at:1795134600,ends_at:1795145400,always_live:0,
        category_name:'Football',iframe:'https://example.test/private-stream',
        poster:'https://example.test/poster.png'},
      {id:32373,name:'Ghana vs Mali',tag:'International Friendly',
        starts_at:1795138200,ends_at:1795149000,always_live:0,
        category_name:'Football'},
      {id:32374,name:'Retired vs Fixture',tag:'Football',
        starts_at:Math.floor(Date.parse('2026-11-16T00:00:00Z')/1000),
        ends_at:Math.floor(Date.parse('2026-11-16T03:00:00Z')/1000),
        category_name:'Football'},
      {id:32375,name:'Always Live vs Channel',tag:'Football',
        starts_at:1795134600,ends_at:1795145400,always_live:1,
        category_name:'Football'},
      {id:'not-a-number',name:'Invalid vs Fixture',tag:'Football',
        starts_at:1795134600,ends_at:1795145400,
        category_name:'Football'},
    ]},
  ],
};

test('LiveXTV reads verified public Football event JSON, no embeds or other sports',()=>{
  const rows=liveXtvPublishedApiMatches(publishedApiSample,{
    nowMs:Date.parse('2026-11-17T00:00:00Z'),
  });
  assert.equal(rows.length,2);
  assert.deepEqual(rows.map(x=>x.home_team),['Orlando City SC','Ghana']);
  assert.deepEqual(rows.map(x=>x.away_team),['FC Cincinnati','Mali']);
  assert.equal(rows[0].league,'MLS');
  assert.equal(rows[0].page_url,'https://livextv.pro/watch/32372');
  assert.equal(rows[0].match_time,'2026-11-20T00:30:00.000Z');
  assert.equal(new Date(Date.parse(rows[0].match_time)+390*60000).toISOString().slice(11,16),'07:00');
  assert.equal(rows[0].verified_kickoff,true);
  assert.equal(rows[0].status,'NS');
  assert.equal(rows[0].anchors[0].page_url,rows[0].page_url);
  assert.equal(JSON.stringify(rows).includes('private-stream'),false);
  assert.equal(JSON.stringify(rows).includes('poster.png'),false);
});

test('LiveXTV uses public Football JSON first, without unnecessary HTML/player visits',async()=>{
  const requested=[];
  const fetcher=async (url,options)=>{
    requested.push({url:String(url),accept:options.headers.Accept});
    if(String(url)!==apiIndex)throw Error('Unexpected HTML or player request');
    return jsonResponse(publishedApiSample);
  };
  const result=await liveXtvMatches({fetcher,nowMs:Date.parse('2026-11-17T00:00:00Z')});
  assert.equal(result.results,2);
  assert.equal(result.diagnostics.fixture_source,'public_event_json');
  assert.equal(result.diagnostics.confirmed_kickoff_count,2);
  assert.deepEqual(result.diagnostics.available_days_mmt,['2026-11-20']);
  assert.deepEqual(requested,[{url:apiIndex,accept:'application/json'}]);
});

test('LiveXTV public JSON keeps 79 upcoming event titles when the publisher lists 79',()=>{
  const list=Array.from({length:79},(_,i)=>({
    id:40000+i,name:'Team '+i+' vs Team '+(i+100),
    starts_at:1795134600+i*60,ends_at:1795145400+i*60,
    always_live:0,category_name:'Football',tag:'Football',
  }));
  const rows=liveXtvPublishedApiMatches({success:true,streams:[
    {category:'Football',streams:list},
  ]},{nowMs:Date.parse('2026-11-17T00:00:00Z')});
  assert.equal(rows.length,79);
  assert.equal(new Set(rows.map(x=>x.page_url)).size,79);
});

test('LiveXTV malformed or denied JSON falls back to published public HTML',async()=>{
  const requests=[];
  const fetcher=async url=>{
    requests.push(String(url));
    if(String(url)===apiIndex)return jsonResponse({success:false,streams:[]});
    if(String(url)===index)return htmlResponse(fixtureIndex);
    return htmlResponse(watchPage);
  };
  const result=await liveXtvMatches({fetcher});
  assert.equal(result.results,2);
  assert.equal(result.diagnostics.fixture_source,'public_html');
  assert.equal(requests[0],apiIndex);
  assert.equal(requests[1],index);
});

test('LiveXTV rejects malformed JSON category and old or unclassified events',()=>{
  const now=Date.parse('2026-11-17T00:00:00Z');
  assert.deepEqual(liveXtvPublishedApiMatches({success:false,streams:[]},{nowMs:now}),[]);
  assert.deepEqual(liveXtvPublishedApiMatches({success:true,streams:null},{nowMs:now}),[]);
  const groups={success:true,streams:[{category:'Football',streams:[
    {id:1201,name:'Lions vs Tigers',starts_at:'unknown',category_name:'Football'},
    {id:1202,name:'Lions vs Tigers',starts_at:1795134600,category_name:'Basketball'},
    {id:1203,name:'Bad Title',starts_at:1795134600,category_name:'Football'},
  ]}]};
  assert.deepEqual(liveXtvPublishedApiMatches(groups,{nowMs:now}),[]);
});
