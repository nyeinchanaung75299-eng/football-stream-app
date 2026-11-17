import test from 'node:test';
import assert from 'node:assert/strict';
import {
  experimentalFootballSites, isExperimentalFootballSource,
  experimentalMatches, experimentalStreams, explicitKickoff,
  configuredRoxiePublicMedia, crichdUtcKickoff, crichdPublishedWatchLinks,
} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const home = 'https://roxiestreams.su/soccer';
const pages = (records) => async url => new Response(
  records[String(url)] ?? '<html></html>',
  {headers:{'content-type':'text/html'}},
);

test('Only configured football providers are enabled',async()=>{
  assert.deepEqual(Object.keys(experimentalFootballSites),['roxie','crichd']);
  assert.equal(isExperimentalFootballSource('crichd'),true);
  assert.equal(isExperimentalFootballSource('roxie'),true);
  for(const source of [
    'camel','xoilac','livetv','livextv','rojadirecta','vipbox',
    'viprow','score088','sports808','streamfree','ppv',
  ]) {
    assert.equal(isExperimentalFootballSource(source),false);
    let fetched=false;
    await assert.rejects(experimentalMatches(source,{fetcher:async()=>{
      fetched=true;return new Response('');
    }}),/Unsupported source/);
    assert.equal(fetched,false);
  }
});

test('Published RoxieStreams SportsEvent supplies trusted match and UTC kickoff',async()=>{
  const fixture={'@type':'SportsEvent',sport:'Soccer',
    name:'Arsenal vs Chelsea',url:'/football/arsenal-chelsea',
    startDate:'2026-11-11T19:00:00Z'};
  const r=await experimentalMatches('roxie',{fetcher:pages({
    [home]:'<script type="application/ld+json">'+JSON.stringify(fixture)+'</script>',
  })});
  assert.equal(r.results,1);
  assert.equal(r.matches[0].home_team,'Arsenal');
  assert.equal(r.matches[0].away_team,'Chelsea');
  assert.equal(r.matches[0].match_time,'2026-11-11T19:00:00.000Z');
  assert.deepEqual(r.diagnostics.available_days_mmt,['2026-11-12']);
});

test('Unrelated page metadata and foreign fixtures do not become football streams',async()=>{
  for(const payload of [
    {'@type':'WebSite',name:'Sport'},
    {'@type':'SportsEvent',sport:'Soccer',name:'Arsenal vs Chelsea',
      url:'https://foreign.invalid/event',startDate:'2026-11-11T19:00:00Z'},
  ]) {
    const r=await experimentalMatches('roxie',{fetcher:pages({
      [home]:'<script type="application/ld+json">'+JSON.stringify(payload)+'</script>',
    })});
    assert.equal(r.results,0);
  }
});

test('No URL means schedule-only and never fabricates a playable line',async()=>{
  const fixture={'@type':'SportsEvent',sport:'Football',
    homeTeam:{name:'Arsenal'},awayTeam:{name:'Chelsea'},
    startDate:'2026-11-11T19:00:00Z'};
  const r=await experimentalMatches('roxie',{fetcher:pages({
    [home]:'<script type="application/ld+json">'+JSON.stringify(fixture)+'</script>',
  })});
  assert.equal(r.results,1);
  assert.equal(r.matches[0].schedule_only,true);
  assert.equal(r.matches[0].page_url,null);
  const lines=await experimentalStreams('roxie',{room_num:'missing'},{
    fetcher:pages({[home]:'<html></html>'}),
  });
  assert.equal(lines.line_count,0);
});

test('Roxie literal configuration is read without evaluating player JS',async()=>{
 const html="<button onclick=\"getRandomStream('live.m3u8','admin2')\">Stream 1</button>"+
 "<script>function getRandomStream(streamPath, subdomain = 'admin2'){return `https://${subdomain}.media.example.org/${streamPath}`;}</script>";
 const r=await configuredRoxiePublicMedia('roxie',html,'https://roxiestreams.su/soccer-streams-1');
 assert.equal(r.length,1);assert.equal(r[0].url,'https://admin2.media.example.org/live.m3u8');
 assert.equal((await configuredRoxiePublicMedia('camel',html,'https://www.camel1.tv/')).length,0);
});
test('Roxie table clock follows published Pacific timezone including daylight saving',async()=>{
 for(const [date,utc] of [['November 13, 2026 9:00 AM','2026-11-13T17:00:00.000Z'],['July 13, 2026 9:00 AM','2026-07-13T16:00:00.000Z']]) {
  const html='<tr><td>Moldova vs Kazakhstan</td><td class="event-start-time">'+date+'</td><td><a href="/soccer/moldova-vs-kazakhstan">Moldova vs Kazakhstan</a></td></tr>';
  const r=await experimentalMatches('roxie',{fetcher:async()=>new Response(html,{headers:{'content-type':'text/html'}})});assert.equal(r.matches[0].match_time,utc);
 }
});
test('Roxie refuses non-publisher and credentialed player page URLs',async()=>{
 let calls=0;const fetcher=async()=>{calls++;return new Response('');};
 for (const page_url of [undefined,'https://foreign.example.org/live','http://127.0.0.1/secret',
  'https://user:pass@roxiestreams.su/live']) {
  const r=await experimentalStreams('roxie',{page_url},{fetcher});
  assert.equal(r.line_count,0);
 }
 assert.equal(calls,0);
});

test('Roxie public media resolver returns unverified HLS only',async()=>{
 const page='https://roxiestreams.su/soccer/moldova-vs-kazakhstan';
 const html='<video src="https://cdn.example.org/live.m3u8"></video>';
 const result=await experimentalStreams('roxie',{page_url:page},
  {fetcher:pages({[page]:html})});
 assert.equal(result.lines.length,1);
 assert.equal(result.lines[0].stream_type,'hls');
 assert.equal(result.diagnostics.playback_verified,false);
});
test('Kickoff is used only when publisher gives explicit timezone',()=>{
  assert.equal(explicitKickoff('Nov 12 20:00'),null);
  assert.equal(explicitKickoff('2026-11-12T20:00:00+06:30'),'2026-11-12T13:30:00.000Z');
});

test('CricHD football match cards use publisher UTC times for MMT display',async()=>{
  const page = 'https://crichd.pk/event/england-vs-spain';
  const root = 'https://crichd.pk/sports/soccer-streams';
  const result = await experimentalMatches('crichd',{fetcher:pages({
    [root]: '<a href="/event/england-vs-spain">England Spain</a><a href="/leagues/">Browse all leagues</a>',
    [page]: '<h2>Nations League</h2><h3>Nov 15, 2026 at 07:45 PM UTC</h3>',
  })});
  assert.equal(result.results,1);
  assert.equal(result.matches[0].home_team,'England');
  assert.equal(result.matches[0].away_team,'Spain');
  assert.equal(result.matches[0].match_time,'2026-11-15T19:45:00.000Z');
  assert.deepEqual(result.diagnostics.available_days_mmt,['2026-11-16']);
  assert.equal(result.matches[0].anchors[0].page_url,page);
});

test('CricHD match tap follows explicitly published Watch page for public HLS only',async()=>{
  const matchPage = 'https://crichd.pk/event/england-vs-spain';
  const playerPage = 'https://playerbee.top/charlie/england-vs-spain/3669';
  const result = await experimentalStreams('crichd',{page_url:matchPage},{
    fetcher:pages({
      [matchPage]: '<a href="'+playerPage+'">Watch</a>',
      [playerPage]: '<video src="https://cdn.example.org/live/stream.m3u8"></video>',
    }),
  });
  assert.equal(result.lines.length,1);
  assert.equal(result.browser_player_url,playerPage);
  assert.equal(result.lines[0].stream_type,'hls');
  assert.equal(result.lines[0].referer,'https://playerbee.top/');
  assert.equal(result.lines[0].origin,'https://playerbee.top');
  assert.equal(result.diagnostics.playback_verified,false);
});

test('CricHD rejects a clock with no UTC and foreign match pages',async()=>{
  assert.equal(crichdUtcKickoff('Nov 16, 2026 at 07:45 PM'),null);
  assert.equal(crichdUtcKickoff('Nov 16, 2026 at 07:45 PM UTC'),'2026-11-16T19:45:00.000Z');
  const result=await experimentalMatches('crichd',{fetcher:pages({
    'https://crichd.pk/sports/soccer-streams':
      '<a href="https://foreign.example.com/event/england-vs-spain">England Spain</a>',
  })});
  assert.equal(result.results,0);
});

test('CricHD exposes exactly its published Link 1 / Link 2 Watch buttons',async()=>{
  const root='https://crichd.pk/sports/soccer-streams';
  const page='https://crichd.pk/event/england-vs-spain';
  const watch1='https://playerbee.top/charlie/england-vs-spain/1';
  const watch2='https://playerbee.top/charlie/england-vs-spain/2';
  const detail='<p>Nov 15, 2026 at 07:45 PM UTC</p><table>'+
    '<tr><th>Streamer</th><th>Channel</th><th>Link</th></tr>'+
    '<tr><td>✓</td><td>Link 1</td><td><a href="'+watch1+'">Watch</a></td></tr>'+
    '<tr><td>✓</td><td>Link 2</td><td><a href="'+watch2+'"><b>Watch</b></a></td></tr>'+
    '<tr><td>✓</td><td>Link 3</td><td>Unavailable</td></tr>'+
    '</table>';
  const links=crichdPublishedWatchLinks(detail,page);
  assert.deepEqual(links.map(a=>a.nick_name),['Link 1','Link 2']);
  assert.deepEqual(links.map(a=>a.watch_url),[watch1,watch2]);
  assert.equal(new Set(links.map(a=>a.room_num)).size,2);
  const data=await experimentalMatches('crichd',{fetcher:pages({
    [root]:'<a href="/event/england-vs-spain">England vs Spain</a>',
    [page]:detail,
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].match_time,'2026-11-15T19:45:00.000Z');
  assert.deepEqual(data.matches[0].anchors.map(a=>a.nick_name),['Link 1','Link 2']);
  assert.ok(data.matches[0].anchors.every(a=>a.page_url===page));
});

test('CricHD selected Link 2 cannot resolve media from Link 1',async()=>{
  const page='https://crichd.pk/event/england-vs-spain';
  const watch1='https://playerbee.top/charlie/england-vs-spain/1';
  const watch2='https://playerbee.top/charlie/england-vs-spain/2';
  const detail='<table>'+
    '<tr><td>Link 1</td><td><a href="'+watch1+'">Watch</a></td></tr>'+
    '<tr><td>Link 2</td><td><a href="'+watch2+'">Watch</a></td></tr>'+
    '</table>';
  const seen=[];
  const fetcher=async url=>{
    seen.push(String(url));
    return new Response({
      [page]:detail,
      [watch1]:'<video src="https://media.example.org/one.m3u8"></video>',
      [watch2]:'<video src="https://media.example.org/two.m3u8"></video>',
    }[url]??'',{headers:{'content-type':'text/html'}});
  };
  const result=await experimentalStreams('crichd',
    {page_url:page,watch_url:watch2},{fetcher});
  assert.deepEqual(result.lines.map(l=>l.url),['https://media.example.org/two.m3u8']);
  assert.equal(result.browser_player_url,watch2);
  assert.equal(result.lines[0].referer,'https://playerbee.top/');
  assert.equal(result.lines[0].origin,'https://playerbee.top');
  assert.equal(seen.includes(watch1),false);
  const blocked=await experimentalStreams('crichd',
    {page_url:page,watch_url:'https://playerbee.top/not-published'},{fetcher});
  assert.equal(blocked.line_count,0);
  assert.match(blocked.message,/not published/);
});

test('CricHD Link 1 preserves the observed Cowboys vs 49ers PlayerBee page',async()=>{
  // A user-observed public Watch URL, not a hardcoded HLS link or a claim
  // that the Cowboys NFL fixture is listed in the Soccer category.
  const fixture='https://crichd.pk/event/test-home-vs-test-away';
  const watch='https://playerbee.top/charlie/cowboys-vs-49ers/3688';
  const html='<table><tr><td>Streamer</td><td>Link 1</td>'+
    '<td><a href="'+watch+'">Watch</a></td></tr></table>';
  const anchors=crichdPublishedWatchLinks(html,fixture);
  assert.equal(anchors.length,1);
  assert.equal(anchors[0].nick_name,'Link 1');
  assert.equal(anchors[0].watch_url,watch);
  const result=await experimentalStreams('crichd',
    {page_url:fixture,watch_url:watch},{
      fetcher:async url=>String(url)===watch
        ? new Response('Forbidden',{status:403,headers:{'content-type':'text/html'}})
        : new Response(html,{headers:{'content-type':'text/html'}}),
    });
  assert.equal(result.browser_player_url,watch);
  assert.equal(result.line_count,0);
  assert.equal(result.diagnostics.access_denied,true);
});

test('CricHD 403 player does not erase published numbered Watch choices',async()=>{
  const page='https://crichd.pk/event/england-vs-spain';
  const watch='https://playerbee.top/charlie/england-vs-spain/1';
  const detail='<tr><td>Link 1</td><td><a href="'+watch+'">Watch</a></td></tr>';
  const fetcher=async url=>String(url)===watch
    ?new Response('Forbidden',{status:403,headers:{'content-type':'text/html'}})
    :new Response(detail,{headers:{'content-type':'text/html'}});
  const result=await experimentalStreams('crichd',
    {page_url:page,watch_url:watch},{fetcher});
  assert.equal(result.line_count,0);
  assert.equal(result.browser_player_url,watch);
  assert.equal(result.diagnostics.access_denied,true);
  assert.equal(crichdPublishedWatchLinks(detail,page)[0].nick_name,'Link 1');
});

test('Roxie fast path uses published HLS config without crawling extra players',async()=>{
  const page='https://roxiestreams.su/soccer/england-vs-spain';
  const html=[
    'function getRandomStream(streamPath, subdomain = "edge") {',
    '  return `https://${subdomain}.roxiecdn.example.org/${streamPath}`;',
    '}',
    'const video = getRandomStream("football.m3u8");',
  ].join('\n');
  const calls=[];
  const fetcher=async url=>{
    calls.push(String(url));
    if(String(url)!==page)throw Error('Unexpected crawl');
    return new Response(html,{headers:{'content-type':'text/html'}});
  };
  const result=await experimentalStreams('roxie',{page_url:page},{fetcher});
  assert.equal(result.lines.length,1);
  assert.equal(result.lines[0].url,'https://edge.roxiecdn.example.org/football.m3u8');
  assert.equal(result.lines[0].health_status,'unknown');
  assert.equal(result.diagnostics.playback_verified,false);
  assert.deepEqual(calls,[page]);
});
