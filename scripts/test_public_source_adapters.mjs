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

test('Camel Flight fixtures bind published IDs to Unix kickoffs without league-nav false matches',async()=>{
 const row={id:'fixture-42',match_time:start,home_team:{name:'Moldova'},away_team:{name:'Kazakhstan'},competition:{name:'Nations League'}};
 const frame='0:'+JSON.stringify(['$',{hotTeamMatches:[row]}])+'\n';
 const html='<a href="/league/1-liga-vs-rs-7">1 Liga vs RS 7</a><a href="/football/match-moldova-vs-kazakhstan/fixture-42"></a>'+
 '<script>self.__next_f.push('+JSON.stringify([1,frame])+')</script>';
 const r=await experimentalMatches('camel',{fetcher:async()=>response(html)});
 assert.equal(r.matches.length,1);assert.equal(r.matches[0].home_team,'Moldova');
 assert.equal(r.matches[0].match_time,new Date(start*1000).toISOString());
});
test('Xoilac uses actual match card and full ICT permalink date across MMT midnight',async()=>{
 const html='<a href="/league/one-vs-two">One vs Two</a><div class="wlb-card"><a class="wlb-card__phu" '+
 'href="https://xoilacls.tv/truc-tiep/moldova-vs-kazakhstan-luc-0010-ngay-14-11-2026/" aria-label="Moldova vs Kazakhstan"></a></div>';
 const r=await experimentalMatches('xoilac',{fetcher:async()=>response(html)});
 assert.equal(r.matches.length,1);assert.equal(r.matches[0].match_time,'2026-11-13T17:10:00.000Z');
 assert.deepEqual(r.diagnostics.available_days_mmt,['2026-11-13']);
});
test('VIP time content attribute is a kickoff, not a wall clock in the team name',async()=>{
 const r=await experimentalMatches('viprow',{fetcher:async()=>response('<a href="/football/moldova-vs-kazakhstan"><time content="2026-11-13T17:00+00:00">17:00</time> Moldova v Kazakhstan</a>')});
 assert.equal(r.matches[0].match_time,'2026-11-13T17:00:00.000Z');
 assert.equal(r.matches[0].home_team,'Moldova');
});
test('Roxie table clock follows published Pacific timezone including daylight saving',async()=>{
 for(const [date,utc] of [['November 13, 2026 9:00 AM','2026-11-13T17:00:00.000Z'],['July 13, 2026 9:00 AM','2026-07-13T16:00:00.000Z']]) {
  const html='<tr><td>Moldova vs Kazakhstan</td><td class="event-start-time">'+date+'</td><td><a href="/soccer/moldova-vs-kazakhstan">Moldova vs Kazakhstan</a></td></tr>';
  const r=await experimentalMatches('roxie',{fetcher:async()=>response(html)});assert.equal(r.matches[0].match_time,utc);
 }
});
test('Score088 follows its page-published public event API and two player hops, including MP4',async()=>{
 const id='live-moldova-vs-kazakhstan-live-stream-2026-11-13',page='https://www.score088tv.live/football/'+id;
 const data={props:{pageProps:{matchId:id,homeTeam:'Moldova',awayTeam:'Kazakhstan'}}};
 const calls=[];
 const r=await experimentalStreams('score088',{page_url:page},{fetcher:async url=>{
  calls.push(String(url));
  if(url===page)return response('<script id="__NEXT_DATA__" type="application/json">'+JSON.stringify(data)+'</script>');
  if(String(url).startsWith('https://api.footypaper.top/'))return response({id,urls:['https://player.example.org/event']},'application/json');
  if(url==='https://player.example.org/event')return response('<iframe src="https://video.example.org/embed"></iframe>');
  if(url==='https://video.example.org/embed')return response('<video src="https://cdn.example.org/match.mp4?token=public"></video>');
  return response('');
 }});
 assert.equal(r.lines.length,1);assert.equal(r.lines[0].stream_type,'mp4');
 assert.equal(r.lines[0].referer,'https://video.example.org/embed');
 assert.ok(calls.some(u=>u.startsWith('https://api.footypaper.top/')));
});
test('public player script config can publish HLS without executing the script',async()=>{
 const r=await discoverPublicMedia('https://player.example.org/embed',{fetcher:async url=>
  response(url.endsWith('.js')?'throw Error("must never execute");const file="https:\\u002f\\u002fcdn.example.org\\u002flive.m3u8?x=1\\u0026y=2";':'<script src="/player.js"></script>',url.endsWith('.js')?'text/javascript':'text/html')});
 assert.equal(r.lines[0].url,'https://cdn.example.org/live.m3u8?x=1&y=2');
});
test('Rojadirecta joins only the football row game ID to embedded public player links',async()=>{
 const html='<details class="game-item-details" data-game-id="42"><summary><span class="game-teams">Moldova - Kazakhstan</span></summary><div class="game-links-container"></div></details>'+
 '<script>window.LINKS_DATA = '+JSON.stringify({'42':[{link:'https://player.example.org/event'},{link:'acestream://not-native'}],'99':[{link:'https://other.example.org/unrelated'}]})+';</script>';
 const r=await experimentalMatches('rojadirecta',{fetcher:async()=>response(html)});
 assert.equal(r.matches.length,1);assert.equal(r.matches[0].anchors.length,1);
 assert.equal(r.matches[0].anchors[0].page_url,'https://player.example.org/event');
 assert.equal(r.matches[0].schedule_only,false);
 assert.equal(r.matches[0].match_time,null,'No timezone is invented for this provider');
});
