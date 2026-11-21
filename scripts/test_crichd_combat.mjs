import {test} from 'node:test';
import assert from 'node:assert/strict';
import {crichdCombatMatches,crichdCombatSections,parseCrichdCombatEvents} from '../supabase/functions/_shared/crichd_combat.mjs';
const home='https://crichd.pk/sports/soccer-streams',ufc='https://crichd.pk/sports/ufc-streams-free';
test('CricHD discovers only actually published same-site combat sections',()=>{
 const sections=crichdCombatSections('<a href="/sports/ufc-streams-free">UFC</a><a href="/sports/ufc-streams-free">UFC</a><a href="https://other.example.org/sports/boxing">Boxing</a><a href="/sports/soccer">Football</a>');
 assert.equal(sections.length,1);assert.equal(sections[0].url,ufc);assert.equal(sections[0].category,'ufc');
});
test('real combat event and numbered watch URLs preserve detector identity, unknown clocks and unverified playback',async()=>{
 const pages={
  [home]:'<a href="/sports/ufc-streams-free">UFC</a>',
  [ufc]:'<a href="/event/ufc-323-fighter-a-vs-fighter-b">UFC 323 Fighter A vs Fighter B</a><a href="/event/ufc-323-fighter-a-vs-fighter-b">UFC 323 Fighter A vs Fighter B</a><a href="/event/football-a-vs-b">Football A vs B</a>',
  'https://crichd.pk/event/ufc-323-fighter-a-vs-fighter-b':'Nov 22, 2026 at 10:00 PM UTC<table><tr><td>Link 2</td><td><a href="https://playerbee.top/bravo/ufc/99">Watch</a></td></tr></table>',
 };
 const calls=[];const data=await crichdCombatMatches({fetcher:async url=>{calls.push(String(url));assert(url in pages);return new Response(pages[url],{headers:{'Content-Type':'text/html'}});}});
 assert.equal(data.results,1);const row=data.matches[0];assert.equal(row.category,'ufc');assert.equal(row.match_time,'2026-11-22T22:00:00.000Z');assert.equal(row.playback_verified,false);
 assert.equal(row.anchors[0].watch_url,'https://playerbee.top/bravo/ufc/99');assert.equal(row.anchors[0].nick_name,'Link 2');
 assert.equal(data.diagnostics.category_availability.one.published_section,false);assert.equal(calls.length,3);
 const unknown=await parseCrichdCombatEvents('<a href="/event/ufc-night">UFC Fight Night</a>',{url:ufc,category_name:'UFC'});
 assert.equal(unknown[0].match_time,null);assert.equal(unknown[0].anchors[0].watch_url,undefined);
});
test('source verification is reported without challenge requests or invented events',async()=>{
 let calls=0;const data=await crichdCombatMatches({fetcher:async()=>{calls++;return new Response('Performing security verification',{status:403});}});
 assert.equal(calls,1);assert.equal(data.results,0);assert.equal(data.diagnostics.content_state,'source_unavailable_or_verification_required');
});
test('a genuinely empty UFC schedule does not create other combat categories',async()=>{
 const data=await crichdCombatMatches({category:'boxing',fetcher:async url=>new Response(url===home?'<a href="/sports/ufc-streams-free">UFC</a>':'No events available.',{headers:{'Content-Type':'text/html'}})});
 assert.equal(data.results,0);assert.equal(data.diagnostics.content_state,'no_published_combat_events');assert.equal(data.diagnostics.category_availability.ufc.published_section,true);assert.equal(data.diagnostics.category_availability.boxing.published_section,false);
});
