import test from 'node:test';
import assert from 'node:assert/strict';
import {publicSourceUrl,readPublicSource,discoverPublicMedia} from '../supabase/functions/_shared/public_source_media.mjs';
import {publicFootballFeedMatches,publicFootballFeedPlayer,configuredPublicMedia} from '../supabase/functions/_shared/public_football_feeds.mjs';
import {experimentalMatches,experimentalStreams} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const start=Date.parse('2026-11-13T17:00:00Z')/1000;
const event={id:42,name:'Moldova vs. Kazakhstan',tag:'Nations League',starts_at:start,ends_at:start+7200,
  iframe:'https://players.example.org/42',substreams:[{id:43,iframe:'https://players.example.org/43'}]};
const feed={success:true,streams:[{category:'Football',streams:[event]},
  {category:'American Football',streams:[{...event,id:99,name:'UCLA vs Illinois'}]}]};
const response=(value,type='text/html')=>new Response(typeof value==='string'?value:JSON.stringify(value),{headers:{'content-type':type}});

test('Provider public feed excludes American football and retains stable player IDs',async()=>{
 const r=await publicFootballFeedMatches('ppv',{now:()=>start*1000,fetcher:async()=>response(feed,'application/json')});
 assert.equal(r.matches.length,1);assert.equal(r.matches[0].home_team,'Moldova');
 assert.equal(r.matches[0].match_time,'2026-11-13T17:00:00.000Z');
 assert.deepEqual(r.matches[0].anchors.map(x=>x.room_num),['42:42','42:43']);
});
test('Published API player is selected by ID and ignores a forged client URL',async()=>{
 const r=await publicFootballFeedPlayer('livextv',{room_num:'42:43',page_url:'https://unrelated.example.org/'},
  {fetcher:async()=>response(feed,'application/json')});
 assert.equal(r,'https://players.example.org/43');
 const removed=await publicFootballFeedPlayer('ppv',{room_num:'42:404'},
  {fetcher:async()=>response(feed,'application/json')});assert.equal(removed,null);
});
test('Provider feed drops expired fixtures',async()=>{
 const r=await publicFootballFeedMatches('ppv',{now:()=>start*1000+10*3600000,
  fetcher:async()=>response(feed,'application/json')});assert.equal(r.matches.length,0);
});
test('Two public player hops discover HLS and preserve final player referer',async()=>{
 const pages={'https://site.example.org/event':'<iframe src="https://embed.example.org/frame"></iframe>',
  'https://embed.example.org/frame':'<iframe src="/inner"></iframe>',
  'https://embed.example.org/inner':'<script>const source={file:"https://cdn.example.org/live.m3u8"}</script>'};
 const r=await discoverPublicMedia('https://site.example.org/event',{fetcher:async u=>response(pages[u]||'')});
 assert.equal(r.lines.length,1);assert.equal(r.lines[0].referer,'https://embed.example.org/inner');
 assert.equal(r.lines[0].origin,'https://embed.example.org');assert.equal(r.pagesChecked,3);
});
test('Player discovery ignores iframe cycles and chat links',async()=>{
 let calls=0;const r=await discoverPublicMedia('https://site.example.org/a',{fetcher:async()=>{
 calls++;return response('<iframe src="/a"></iframe><iframe src="https://www.youtube.com/chat"></iframe>');}});
 assert.equal(calls,1);assert.equal(r.lines.length,0);
});
test('Private IPs, encoded IPs, IPv6, credentials and private redirects never fetch a target',async()=>{
 for(const value of ['http://127.0.0.1/live.m3u8','http://10.0.0.1/live.m3u8','http://2130706433/live.m3u8',
  'http://[::1]/live.m3u8','http://host.internal/live.m3u8','https://user:pass@cdn.example.org/a.m3u8'])assert.equal(publicSourceUrl(value),null);
 let calls=0;await assert.rejects(readPublicSource('https://site.example.org/a',{fetcher:async()=>{
 calls++;return new Response(null,{status:302,headers:{location:'http://127.0.0.1/a'}});}}));assert.equal(calls,1);
});
test('Provider redirect outside its domain is rejected before fetching the next site',async()=>{
 let calls=0;await assert.rejects(readPublicSource('https://site.example.org/a',{allowedHosts:['site.example.org'],fetcher:async()=>{
 calls++;return new Response(null,{status:302,headers:{location:'https://unrelated.example.org/a'}});}}));assert.equal(calls,1);
});
test('Next hydration joins a published slug to names, kickoff and badges',async()=>{
 const state={props:{pageProps:{initialMatches:[{slug:'moldova-kaz',homeTeam:'Moldova',awayTeam:'Kazakhstan',
  competition:'Nations League',matchTime:'2026-11-13T17:00:00Z',homeTeamLogo:'https://cdn.example.org/moldova.png'}]}}};
 const html='<a href="/football/moldova-kaz">Watch</a><script id="__NEXT_DATA__" type="application/json">'+JSON.stringify(state)+'</script>';
 const r=await experimentalMatches('score088',{fetcher:async()=>response(html)});
 assert.equal(r.results,1);assert.equal(r.matches[0].home_team,'Moldova');
 assert.equal(r.matches[0].match_time,'2026-11-13T17:00:00.000Z');assert.equal(r.matches[0].home_logo,'https://cdn.example.org/moldova.png');
});
test('Score hydration does not invent an unpublished event page',async()=>{
 const html='<script id="__NEXT_DATA__" type="application/json">'+JSON.stringify({props:{pageProps:{initialMatches:[{
 slug:'missing',homeTeam:'Moldova',awayTeam:'Kazakhstan',matchTime:'2026-11-13T17:00:00Z'}]}}})+'</script>';
 const r=await experimentalMatches('score088',{fetcher:async()=>response(html)});assert.equal(r.results,0);
});
test('A display clock prefix is not a team name',async()=>{
 const r=await experimentalMatches('vipbox',{fetcher:async()=>response('<a href="/football/moldova-vs-kazakhstan"><time datetime="2026-11-13T17:00:00Z">17:00</time> Moldova vs Kazakhstan</a>')});
 assert.equal(r.matches[0].home_team,'Moldova');
});
test('Roxie literal configuration is read without evaluating player JS',async()=>{
 const html="<button onclick=\"getRandomStream('live.m3u8','admin2')\">Stream 1</button>"+
 "<script>function getRandomStream(streamPath, subdomain = 'admin2'){return `https://${subdomain}.media.example.org/${streamPath}`;}</script>";
 const r=await configuredPublicMedia('roxie',html,'https://roxiestreams.su/soccer-streams-1');
 assert.equal(r.length,1);assert.equal(r[0].url,'https://admin2.media.example.org/live.m3u8');
 assert.equal((await configuredPublicMedia('camel',html,'https://www.camel1.tv/')).length,0);
});
test('Missing match-page input does not fetch an undefined URL',async()=>{
 let calls=0;const r=await experimentalStreams('camel',{}, {fetcher:async()=>{calls++;return response('');}});
 assert.equal(r.line_count,0);assert.equal(calls,0);
});
test('StreamFree uses soccer fixtures and excludes American football',async()=>{
 const r=await publicFootballFeedMatches('streamfree',{now:()=>start*1000,fetcher:async url=>
  response(url.endsWith('/streams')?{streams:{soccer:[{name:'Kazakhstan vs Moldova',stream_key:'kaz-mda',match_timestamp:start}],football:[{name:'UCLA vs Illinois',stream_key:'nfl',match_timestamp:start}]}}:
   {fixtures:{today:{fixtures:[{category:'soccer',event_name:'Kazakhstan at Moldova',date_unix:start,competition:'Nations League'},
    {category:'football',event_name:'UCLA at Illinois',date_unix:start}]}}},'application/json')});
 assert.equal(r.matches.length,1);assert.equal(r.matches[0].home_team,'Moldova');
 assert.equal(r.matches[0].anchors[0].page_url,'https://strmfree.st/player/soccer/kaz-mda');
});
