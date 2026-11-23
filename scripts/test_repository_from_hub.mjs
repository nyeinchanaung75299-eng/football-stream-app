import {test} from 'node:test';
import assert from 'node:assert/strict';
import {repositoryMatchesFromHub} from '../supabase/functions/_shared/repository_from_hub.mjs';
const entry={id:'hub-event',kind:'event',source_file:'provider_6/live_events.json',event_meta:{source_repository:'darkbyteprojects/iptv_png',
 home_team:'Newcastle',away_team:'Arsenal',league:'Premier League',source_category:'EPL',kickoff_at:'2026-11-22T17:30:00Z'},
 streams:[{id:'one',label:'HD',stream_url:'https://hub.example.org/one.m3u8',stream_type:'hls'}]};
test('Repository and Live 2 derive only committed Hub event data and merge cross-source duplicate lines',async()=>{
 const previousFetch=globalThis.fetch;globalThis.fetch=()=>{throw Error('Repository projection must not fetch a GitHub source');};
 try{
  const other={...entry,id:'other',event_meta:{...entry.event_meta,source_repository:'mdjamsad9/dudetvapi'}};
  const result=await repositoryMatchesFromHub([entry,other,{...entry,kind:'channel'}],{now:Date.parse('2026-11-22T17:00:00Z')});
  assert.equal(result.entries.length,1);assert.equal(result.entries[0].streams.length,1);assert.equal(result.entries[0].event_meta.repositories.length,2);
 }finally{globalThis.fetch=previousFetch;}
});
test('zero-line football fixtures remain importable metadata; combat and unknown failed origins do not leak into Live 2',async()=>{
 const empty={...entry,streams:[]};
 const combat={...entry,event_meta:{...entry.event_meta,source_category:'UFC',league:'UFC Fight Night'}};
 const result=await repositoryMatchesFromHub([empty,combat],{now:Date.parse('2026-11-22T17:00:00Z')});
 assert.equal(result.entries.length,1);assert.equal(result.entries[0].streams.length,0);
 const failed=await repositoryMatchesFromHub([entry],{complete:false,missingRepositories:['darkbyteprojects/iptv_png']});
 assert.equal(failed.entries.length,0);assert.equal(failed.complete,false);
 const unknown=await repositoryMatchesFromHub([entry],{complete:false});assert(unknown.missingRepositories.includes('darkbyteprojects/iptv_png'));
});

test('same league, UTC kickoff and both source team IDs merge aliases and retain committed DRM', async () => {
 const make = (repository, home, league, category, kickoff, streams = []) => ({
  ...entry, streams,
  event_meta: {
   ...entry.event_meta, source_repository: repository, home_team: home,
   away_team: 'Villarreal', league, source_category: category, kickoff_at: kickoff,
   home_logo_url: 'https://img.sofascore.com/api/v1/team/2817/image',
   away_logo_url: 'https://img.sofascore.com/api/v1/team/2819/image',
  },
 });
 const config = {
  id: 'dash', label: 'DASH', stream_type: 'dash',
  stream_url: 'https://example.org/fixture.mpd', key_id: '1'.repeat(32), key_data: '2'.repeat(32),
 };
 const kickoff = '2026-11-22T18:00:00Z';
 const rows = [
  make('mdjamsad9/dudetvapi','Barcelona','FC Barcelona vs Villarreal','LaLiga 🇪🇸',kickoff,[config]),
  make('dilzyking/allrounderlive','FC Barcelona','La Liga','Football',kickoff),
  make('Roshavarma/cfy','Barcelona CF','LaLiga','Football','2026-11-22T19:00:00Z'),
 ];
 const result = await repositoryMatchesFromHub(rows,{now:Date.parse('2026-11-22T17:00:00Z')});
 assert.equal(result.entries.length,2);
 const merged = result.entries.find(row=>row.event_meta.home_team==='FC Barcelona');
 assert.equal(merged.event_meta.league,'LaLiga');
 assert.equal(merged.event_meta.repositories.length,2);
 assert.equal(merged.streams[0].key_id,config.key_id);
 assert.equal(merged.streams[0].key_data,config.key_data);
});

test('corroborates an offset-free source clock and keeps one line per complete DRM pair', async () => {
 const lineup = {
  source_category:'Football', league:'Premier League',
  home_logo_url:'https://img.sofascore.com/api/v1/team/44/image',
  away_logo_url:'https://img.sofascore.com/api/v1/team/35/image',
  away_team:'Manchester United',
 };
 const dash = {
  stream_type:'dash', stream_url:'https://live.example.org/one.mpd',
  key_id:'a'.repeat(32), key_data:'b'.repeat(32), label:'Shared channel name',
 };
 const result = await repositoryMatchesFromHub([
  {...entry, streams:[dash], event_meta:{...lineup, home_team:'Liverpool FC',
   source_repository:'dilzyking/allrounderlive', kickoff_at:'2026-11-22T16:30:00Z'}},
  {...entry, streams:[
   {...dash, stream_url:'https://other.example.org/two.mpd', label:'Different channel name'},
   {...dash, key_data:'c'.repeat(32)},
  ], event_meta:{...lineup, home_team:'Liverpool',
   source_repository:'darkbyteprojects/iptv_png', source_time:'22/11/2026 16:30:00'}},
 ], {now:Date.parse('2026-11-22T17:00:00Z')});
 assert.equal(result.entries.length,1);
 assert.equal(result.entries[0].event_meta.home_team,'Liverpool FC');
 assert.equal(result.entries[0].streams.length,2);
 assert.equal(result.entries[0].streams[0].label,result.entries[0].streams[1].label);
});

test('Feyenoord vs FC Porto and Porto merge without losing distinct HLS lines',async()=>{
 const at='2026-11-24T20:00:00Z',now=Date.parse('2026-11-24T19:00:00Z');
 const make=(repository,away_team,streams)=>({...entry,streams,event_meta:{...entry.event_meta,
  source_repository:repository,home_team:'Feyenoord',away_team,league:'UEFA Champions League',
  source_category:'Football',kickoff_at:at}});
 const stream=(url)=>({label:'HD',stream_type:'hls',stream_url:url});
 const result=await repositoryMatchesFromHub([
  make('dilzyking/allrounderlive','FC Porto',[]),
  make('darkbyteprojects/iptv_png','Porto',[stream('https://fixtures.example.org/a.m3u8'),
   stream('https://fixtures.example.org/a.m3u8'),stream('https://fixtures.example.org/b.m3u8')]),
 ],{now});
 assert.equal(result.entries.length,1);
 assert.equal(result.entries[0].streams.length,2);
 assert.deepEqual(new Set(result.entries[0].event_meta.repositories),
  new Set(['dilzyking/allrounderlive','darkbyteprojects/iptv_png']));
});
test('Bodø/Glimt mojibake, undated alias and same kickoff collapse into one match',async()=>{
 const now=Date.parse('2026-11-24T16:00:00Z'),kickoff='2026-11-24T17:45:00Z';
 const make=(home,source,kickoff_at,streams=[])=>({...entry,streams,event_meta:{...entry.event_meta,
  home_team:home,away_team:'LASK',source_repository:source,source_category:'Football',
  league:'UEFA Champions League',kickoff_at,source_time:'24/11/2026 17:45:00'}});
 const line=(url)=>({stream_type:'hls',stream_url:url,label:'HD'});
 const result=await repositoryMatchesFromHub([
  make('BodÃ¸/Glimt','darkbyteprojects/iptv_png',kickoff,[line('https://fixtures.example.org/a.m3u8')]),
  make('Bodø/Glimt','dilzyking/allrounderlive',kickoff,[line('https://fixtures.example.org/b.m3u8')]),
  make('Bodo Glimt','sm-monirulislam/Upcoming-and-Live-Sports-Data',null),
 ],{now});
 assert.equal(result.entries.length,1);
 assert.equal(result.entries[0].name,'Bodø/Glimt vs LASK Linz');
 assert.equal(result.entries[0].streams.length,2);
});
test('a shared channel remains available separately for different fixtures',async()=>{
 const now=Date.parse('2026-11-24T16:00:00Z');
 const channel={stream_type:'hls',stream_url:'https://fixtures.example.org/bein.m3u8',label:'beIN'};
 const make=(home,away)=>({...entry,streams:[channel],event_meta:{...entry.event_meta,
  home_team:home,away_team:away,source_repository:'darkbyteprojects/iptv_png',
  source_category:'Football',league:'Football',kickoff_at:'2026-11-24T18:00:00Z'}});
 const result=await repositoryMatchesFromHub([
  make('Liverpool','Manchester United'),make('Real Madrid','Barcelona'),
 ],{now});
 assert.equal(result.entries.length,2);
 assert(result.entries.every(row=>row.streams.length===1));
});
