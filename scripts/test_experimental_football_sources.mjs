import test from 'node:test';
import assert from 'node:assert/strict';
import {
  experimentalFootballSites, isExperimentalFootballSource,
  experimentalMatches, experimentalStreams, explicitKickoff,
} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const home = 'https://www.rojadirectavivo.me/live-football';
const pages = (records) => async url => new Response(
  records[String(url)] ?? '<html></html>',
  {headers:{'content-type':'text/html'}},
);

test('The maintained experimental provider is only Rojadirecta',async()=>{
  assert.deepEqual(Object.keys(experimentalFootballSites),['rojadirecta']);
  assert.equal(isExperimentalFootballSource('rojadirecta'),true);
  for(const source of [
    'camel','xoilac','livetv','crichd','roxie','vipbox',
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

test('Published Rojadirecta SportsEvent supplies trusted match and UTC kickoff',async()=>{
  const fixture={'@type':'SportsEvent',sport:'Soccer',
    name:'Arsenal vs Chelsea',url:'/football/arsenal-chelsea',
    startDate:'2026-11-11T19:00:00Z'};
  const r=await experimentalMatches('rojadirecta',{fetcher:pages({
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
    const r=await experimentalMatches('rojadirecta',{fetcher:pages({
      [home]:'<script type="application/ld+json">'+JSON.stringify(payload)+'</script>',
    })});
    assert.equal(r.results,0);
  }
});

test('No URL means schedule-only and never fabricates a playable line',async()=>{
  const fixture={'@type':'SportsEvent',sport:'Football',
    homeTeam:{name:'Arsenal'},awayTeam:{name:'Chelsea'},
    startDate:'2026-11-11T19:00:00Z'};
  const r=await experimentalMatches('rojadirecta',{fetcher:pages({
    [home]:'<script type="application/ld+json">'+JSON.stringify(fixture)+'</script>',
  })});
  assert.equal(r.results,1);
  assert.equal(r.matches[0].schedule_only,true);
  assert.equal(r.matches[0].page_url,null);
  const lines=await experimentalStreams('rojadirecta',{room_num:'missing'},{
    fetcher:pages({[home]:'<html></html>'}),
  });
  assert.equal(lines.line_count,0);
});

test('Rojadirecta event game ID binds only its own published player reference',async()=>{
  const html='<details class="game-item-details" data-game-id="42"><summary>'+
    '<span class="game-teams">Moldova - Kazakhstan</span></summary>'+
    '<div class="game-links-container"></div></details>'+
    '<script>window.LINKS_DATA = '+JSON.stringify({
      42:[{link:'https://player.example.org/event'}],
      99:[{link:'https://other.example.org/unrelated'}],
    })+';</script>';
  const r=await experimentalMatches('rojadirecta',{fetcher:pages({[home]:html})});
  assert.equal(r.results,1);
  assert.equal(r.matches[0].anchors.length,1);
  assert.equal(r.matches[0].anchors[0].page_url,'https://player.example.org/event');
  assert.equal(r.matches[0].match_time,null);
});

test('Kickoff is used only when publisher gives explicit timezone',()=>{
  assert.equal(explicitKickoff('Nov 12 20:00'),null);
  assert.equal(explicitKickoff('2026-11-12T20:00:00+06:30'),'2026-11-12T13:30:00.000Z');
});
