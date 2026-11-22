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
