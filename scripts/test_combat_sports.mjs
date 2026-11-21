import {test} from 'node:test';
import assert from 'node:assert/strict';
import {combatClassification,combatEventsFromHub,combatTimeStatus,combatMatchesQuery} from '../supabase/functions/_shared/combat_sports.mjs';
const base={id:'source-event-a',provider:1,kind:'event',name:'Jiří Procházka vs Navajo Stirling',event_meta:{home_team:'Jiří Procházka',away_team:'Navajo Stirling',league:'UFC 323',source_category:'MMA',source_repository:'source-a',kickoff_at:'2026-11-22T17:00:00Z',end_at:'2026-11-22T19:00:00Z'},streams:[{label:'HD',stream_type:'hls',stream_url:'https://combat.example.org/live.m3u8'}]};
test('UFC, other MMA, Boxing and ONE retain their own categories and published disciplines',()=>{
 assert.equal(combatClassification('UFC Fight Night').category,'ufc');
 assert.equal(combatClassification('Mixed Martial Arts').category,'mma');
 assert.equal(combatClassification('Boxing').category,'boxing');
 assert.equal(combatClassification('ONE Championship Muay Thai').discipline,'Muay Thai');
 assert.equal(combatClassification({source_category:'MMA',league:'ONE Championship Kickboxing'}).discipline,'Kickboxing');
 assert.equal(combatClassification('ONE Championship').discipline,'Unknown');
 assert.equal(combatClassification('Football Premier League'),null);
 assert.equal(combatClassification({source_category:'Football',league:'Premier League Boxing Day'}),null);
 assert.equal(combatClassification('UFC Boxing'),null);
});
test('safe event identity merges sources and lines but does not conflate dates, fighters or disciplines',async()=>{
 const duplicate={...base,id:'source-event-b',event_meta:{...base.event_meta,home_team:'Jiri Prochazka',source_repository:'source-b'},streams:[...base.streams,{label:'ALT',stream_type:'hls',stream_url:'https://combat.example.org/alt.m3u8'}]};
 const different={...base,id:'different-day',event_meta:{...base.event_meta,kickoff_at:'2026-11-23T17:00:00Z'}};
 const rows=await combatEventsFromHub([base,duplicate,different],{now:Date.parse('2026-11-22T16:00:00Z')});
 assert.equal(rows.length,2);assert.equal(rows[0].stream_count,2);assert.equal(rows[0].source_names.length,2);
 assert.equal(rows[0].status,'upcoming');assert.equal(rows[0].video_status,'not_checked');assert.equal(rows[0].playback_verified,false);
 assert(combatMatchesQuery(rows[0],'Jiri source-b'));
 const one=await combatEventsFromHub(['MMA','Muay Thai','Kickboxing'].map((discipline,i)=>({...base,id:'one-'+i,event_meta:{...base.event_meta,league:'ONE Championship '+discipline,source_category:discipline}})));
 assert.equal(one.length,3);assert.equal(new Set(one.map(x=>x.discipline)).size,3);
});
test('unknown clocks remain Unknown and unspecific undated events never merge by brand alone',async()=>{
 assert.equal(combatTimeStatus({source_status:'LIVE',source_time:'22/11/2026 08:00 PM'}),'unknown');
 assert.equal(combatTimeStatus(base.event_meta,Date.parse('2026-11-22T18:00:00Z')),'live');
 assert.equal(combatTimeStatus(base.event_meta,Date.parse('2026-11-22T20:00:00Z')),'finished');
 const unknown={...base,event_meta:{...base.event_meta,league:'MMA',kickoff_at:null,end_at:null}};
 const rows=await combatEventsFromHub([unknown,{...unknown,id:'other-unknown'}]);
 assert.equal(rows.length,2);assert(rows.every(x=>x.status==='unknown'));
});
