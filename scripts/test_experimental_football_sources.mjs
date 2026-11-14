import test from 'node:test';
import assert from 'node:assert/strict';
import {
  experimentalFootballSites, isExperimentalFootballSource,
  experimentalMatches, experimentalStreams, explicitKickoff,
  configuredRoxiePublicMedia,
} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const home = 'https://roxiestreams.su/soccer';
const pages = (records) => async url => new Response(
  records[String(url)] ?? '<html></html>',
  {headers:{'content-type':'text/html'}},
);

test('The maintained experimental provider is only RoxieStreams',async()=>{
  assert.deepEqual(Object.keys(experimentalFootballSites),['roxie']);
  assert.equal(isExperimentalFootballSource('roxie'),true);
  for(const source of [
    'camel','xoilac','livetv','crichd','rojadirecta','vipbox',
    'viprow','score088','sports808','livextv','streamfree','ppv',
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
 assert.equal((await configuredPublicMedia('camel',html,'https://www.camel1.tv/')).length,0);
});
test('Roxie table clock follows published Pacific timezone including daylight saving',async()=>{
 for(const [date,utc] of [['November 13, 2026 9:00 AM','2026-11-13T17:00:00.000Z'],['July 13, 2026 9:00 AM','2026-07-13T16:00:00.000Z']]) {
  const html='<tr><td>Moldova vs Kazakhstan</td><td class="event-start-time">'+date+'</td><td><a href="/soccer/moldova-vs-kazakhstan">Moldova vs Kazakhstan</a></td></tr>';
  const r=await experimentalMatches('roxie',{fetcher:async()=>new Response(html)});assert.equal(r.matches[0].match_time,utc);
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
