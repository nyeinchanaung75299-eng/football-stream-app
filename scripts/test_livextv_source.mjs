import test from 'node:test';
import assert from 'node:assert/strict';
import {liveXtvPublishedMatches,liveXtvPublishedSources,liveXtvMatches,liveXtvStreams} from '../supabase/functions/_shared/livextv_source.mjs';
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
