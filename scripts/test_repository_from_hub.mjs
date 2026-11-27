import {test} from 'node:test';
import assert from 'node:assert/strict';
import {repositoryMatchesFromHub,reconcilePriorRepositoryFixtures} from '../supabase/functions/_shared/repository_from_hub.mjs';
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

test('retired origins are not projected from old Hub snapshots',async()=>{
 const rows=['rohmanabdu/lian','rohmanabdu/deqiaa'].map(repository=>({...entry,event_meta:{...entry.event_meta,source_repository:repository}}));
 const result=await repositoryMatchesFromHub(rows);
 assert.deepEqual(result.entries,[]);
});


test('dated aliases use ordered team IDs, exact kickoff and reviewed league across all providers',async()=>{
 const logo=id=>'https://img.sofascore.com/api/v1/team/'+id+'/image';
 const make=(home,away,homeId,awayId,league,category,repository,kickoff='2026-11-25T17:45:00Z')=>({
  ...entry,streams:[],event_meta:{...entry.event_meta,source_repository:repository,
   home_team:home,away_team:away,home_logo_url:logo(homeId),away_logo_url:logo(awayId),
   league,source_category:category,kickoff_at:kickoff}
 });
 const dark='darkbyteprojects/iptv_png',other='dilzyking/allrounderlive';
 for(const [home,away,shortHome,shortAway,h,a,league,category] of [
  ['Sabah FK','FC Barcelona','Sabah','Barcelona',267828,2817,'UEFA Champions League','UCL'],
  ['SK Slavia Praha','Villarreal','Slavia Praha','Villarreal',2216,2819,'UEFA Champions League','UCL'],
  ['Sporting CP','Manchester United','Sporting','Man Utd',3001,35,'UEFA Champions League','UCL'],
  ['Al-Taawoun','Al Nahda SC','Al-Taawoun','Al-Nahda',56021,40648,'AFC Champions League Two','AFC Champions League 2'],
  ['Example FC','Example Town SC','Example','Example Town',100,101,'Example Regional League','Football']
 ]){
  const first=make(home,away,h,a,league,'Football',other);
  const second=make(shortHome,shortAway,h,a,home+' vs '+away,category,dark);
  if(category==='Football')second.event_meta.league=league;
  const projected=await repositoryMatchesFromHub([first,second]);
  assert.equal(projected.entries.length,1,home+' vs '+away);
  assert.equal(projected.entries[0].event_meta.repositories.length,2);
  const sameRepo=await repositoryMatchesFromHub([first,{...second,event_meta:{...second.event_meta,source_repository:other}}]);
  assert.equal(sameRepo.entries.length,1);
 }
 const senior=make('Sporting CP','Manchester United',3001,35,'UEFA Champions League','Football',other);
 const distinct=[
  make('Sporting U19','Manchester United U19',3001,35,'UEFA Champions League','Football',dark),
  make('Sporting Women','Manchester United Women',3001,35,'UEFA Champions League','Football',dark),
  make('Sporting B','Manchester United B',3001,35,'UEFA Champions League','Football',dark),
  make('Sporting','Manchester United',3001,35,'UEFA Europa League','Football',dark),
  make('Sporting','Manchester United',3001,35,'UEFA Champions League','Football',dark,'2026-11-25T18:45:00Z'),
  make('Sporting','Manchester United',99999,35,'UEFA Champions League','Football',dark),
 ];
 for(const candidate of distinct){
  const projected=await repositoryMatchesFromHub([senior,candidate]);
  assert.equal(projected.entries.length,2,candidate.event_meta.home_team+' '+candidate.event_meta.league);
 }
});

test('generic football league is corroborated only by a unique exact dated named fixture',async()=>{
 const logo=id=>'https://img.sofascore.com/api/v1/team/'+id+'/image';
 const make=(home,away,league,{homeId=267828,awayId=2817,kickoff='2026-11-25T17:45:00Z',repository='Roshavarma/cfy'}={})=>({
  ...entry,streams:[],event_meta:{...entry.event_meta,source_repository:repository,
   home_team:home,away_team:away,home_logo_url:logo(homeId),away_logo_url:logo(awayId),
   league,source_category:'Football',kickoff_at:kickoff}
 });
 for(const [longHome,longAway,shortHome,shortAway,league,h,a] of [
  ['Sabah FK','FC Barcelona','Sabah','Barcelona','UEFA Champions League',267828,2817],
  ['SK Slavia Praha','Villarreal','Slavia Praha','Villarreal','UEFA Champions League',2216,2819],
  ['Al-Taawoun','Al Nahda SC','Al-Taawoun','Al-Nahda','AFC Champions League Two',56021,40648]
 ]){
  const generic=make(longHome,longAway,'Football',{homeId:h,awayId:a});
  const named=make(shortHome,shortAway,league,{homeId:h,awayId:a,repository:'dilzyking/allrounderlive'});
  for(const rows of [[generic,named],[named,generic]]){
   const projected=await repositoryMatchesFromHub(rows);
   assert.equal(projected.entries.length,1);
   assert.equal(projected.entries[0].event_meta.league,league);
  }
 }
 const generic=make('Sabah FK','FC Barcelona','Football');
 const named=make('Sabah','Barcelona','UEFA Champions League');
 for(const distinct of [
  make('Sabah','Barcelona','UEFA Champions League',{homeId:99999}),
  make('Sabah','Barcelona','UEFA Champions League',{kickoff:'2026-11-25T18:45:00Z'}),
  make('Sabah U19','Barcelona U19','UEFA Champions League'),
  make('Sabah Women','Barcelona Women','UEFA Champions League'),
  make('Sabah B','Barcelona B','UEFA Champions League'),
 ]){
  assert.equal((await repositoryMatchesFromHub([generic,distinct])).entries.length,2);
 }
 const conflicting=make('Sabah Club','Barcelona Club','UEFA Europa League');
 assert.equal((await repositoryMatchesFromHub([generic,named,conflicting])).entries.length,3);
});

test('partial Hub data combines verified duplicates into the previously mapped fixture',()=>{
 const event_meta={...entry.event_meta,home_logo_url:'https://img.sofascore.com/api/v1/team/20/image',
  away_logo_url:'https://img.sofascore.com/api/v1/team/40/image',league:'Premier League',repositories:['darkbyteprojects/iptv_png']};
 const previous={id:'older',event_meta,streams:entry.streams,repository_match_imports:{entry_id:'older'}};
 const fresh={id:'newer',event_meta:{...event_meta,fixture_key:'newer'},streams:[{stream_url:'https://hub.example.org/two.m3u8',stream_type:'hls'}]};
 const otherLeague={...previous,id:'other',event_meta:{...event_meta,league:'FA Cup'}};
 const result=reconcilePriorRepositoryFixtures([fresh],[previous,fresh,otherLeague],{partial:true});
 assert.deepEqual(result.superseded,['newer']);
 assert.deepEqual(result.entries.map(row=>[row.id,row.streams.length]),[['older',2]]);
 const linkedTwice=reconcilePriorRepositoryFixtures([fresh],[previous,{...fresh,channel_source_match_links:[{entry_id:'newer'}]}],{partial:true});
 assert.deepEqual(linkedTwice.superseded,[]);
});

test('explicit finished status with a source ID and civil date starts retention without inventing UTC kickoff',async()=>{
 const fixture={...entry,id:'explicit-final',event_meta:{...entry.event_meta,kickoff_at:null,source_status:'FINISHED',source_civil_date:'2026-08-28'}};
 const [row]=(await repositoryMatchesFromHub([fixture])).entries;
 assert.equal(row.event_meta.source_finished,true);
 assert.equal(row.event_meta.kickoff_at,null);
 assert.equal(row.event_meta.finished_source_date,'2026-08-28');
 assert.equal(row.event_meta.finished_at,undefined);
 assert.equal(row.event_meta.fixture_key,row.id);
 const [invalid]=(await repositoryMatchesFromHub([{...fixture,event_meta:{...fixture.event_meta,source_civil_date:'2026-02-31'}}])).entries;
 assert.equal(invalid.event_meta.source_finished,undefined);
});
