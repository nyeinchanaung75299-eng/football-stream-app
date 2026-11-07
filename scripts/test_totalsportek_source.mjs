import test from 'node:test';
import assert from 'node:assert/strict';
import {parseTotalsportekMatches,totalsportekKickoff,totalsportekMatches,totalsportekStreams,totalsportekPlayers} from '../supabase/functions/_shared/totalsportek_source.mjs';
const page='https://totalsportekl.is/Home-vs-Away/12345';
const card=(extra='',id='12345')=>`<a href="/Home-vs-Away/${id}" class="modern-match-card"><div class="team-name team-left">Home<img src="/images/teams/Home.png"></div><div class="match-time"><span>Match</span><span>Started</span></div><span class="btn-live">Live Streams</span><div class="team-name team-right">Away<img src="/images/teams/Away.png"></div>${extra}</a>`;
const listing='<div class="league-header"><span>Premier League</span></div>'+card();
const wrapper='https://live3.totalsportek.today/Home-vs-Away/12345';
const player='https://total.footybite.info.pl/best/player3.php?ch=15';
const config='https://universaltokenforall.st/player3/channel15';
const token=btoa(JSON.stringify({exp:2000000000}))+'.public-signature';
const media='https://sha.sharpnessonline.store/simpch15/index.m3u8?token='+token;
const event=`<meta name="description" content="Watch Home vs Away, 2026-11-06, 20:00 uk time"><a href="${wrapper}">Watch</a>`;
function fixture(overrides={}){
 const pages={
  [page]:event,
  [wrapper]:`<iframe src="${player}"></iframe><iframe src="http://127.0.0.1/private"></iframe>`,
  [player]:`<iframe src="${config}"></iframe>`,
  [config]:`let streamUrl = ${JSON.stringify(media).replace(/\//g,'\\/')};`,
  ...overrides,
 };
 const calls=[];
 return {calls,fetcher:async(input,init)=>{
  calls.push({url:String(input),init});
  assert.ok(Object.hasOwn(pages,String(input)),'unexpected fetch destination');
  return new Response(pages[String(input)]);
 }};
}
test('lists football fixtures once, excludes ended events and nonfootball sports, keeps unknown kickoff honest',()=>{
 const html=listing+card()+card('<span class="btn-highlight">Highlights</span>','999')+
  '<div class="league-header"><span>NBA</span></div>'+card('','888')+
  '<div class="league-header"><span>NCAA</span></div>'+card('','889')+
  '<div class="league-header"><span>American Football</span></div>'+card('','890');
 const rows=parseTotalsportekMatches(html);
 assert.equal(rows.length,1);assert.equal(rows[0].home_team,'Home');assert.equal(rows[0].source,'totalsportek');
 assert.equal(rows[0].match_time,null);assert.equal(rows[0].anchors.length,1);
 assert.equal(rows[0].home_logo,'https://totalsportekl.is/images/teams/Home.png');
});
test('selected event kickoff uses London timezone including summer time',()=>{
 assert.equal(totalsportekKickoff(event),'2026-11-06T20:00:00.000Z');
 assert.equal(totalsportekKickoff(event.replace('2026-11-06','2026-07-06')),'2026-07-06T19:00:00.000Z');
 assert.equal(totalsportekKickoff('<meta name="description" content="Unknown time">'),null);
 assert.equal(totalsportekKickoff(event.replace('2026-11-06','2026-02-30')),null);
});
test('countdowns order fixtures without manufacturing exact kickoff times',()=>{
 const rows=parseTotalsportekMatches(listing.replace('<span>Match</span><span>Started</span>', '1day 3hr 26m <br>from now'));
 assert.equal(rows[0].countdown_minutes,1646);
 assert.equal(rows[0].time_label,'1day 3hr 26m from now');
 assert.equal(rows[0].match_time,null);
});
test('metadata-only lookup reads the published kickoff without fetching any player',async()=>{
 const f=fixture({[page]:'<head>'+event+'</head><body>'+'x'.repeat(200000)+'</body>'});
 const result=await totalsportekStreams({page_url:page,metadata_only:true},{fetcher:f.fetcher});
 assert.equal(result.match_time,'2026-11-06T20:00:00.000Z');
 assert.equal(result.metadata_only,true);assert.deepEqual(result.lines,[]);
 assert.equal(f.calls.length,1);
});
test('metadata stops at the head instead of waiting for a stalled player body',async()=>{
 let cancelled=false;
 const fetcher=async()=>new Response(new ReadableStream({
  start(controller){controller.enqueue(new TextEncoder().encode('<head>'+event+'</head>'));},
  cancel(){cancelled=true;},
 }));
 const result=await totalsportekStreams({page_url:page,metadata_only:true},{fetcher});
 assert.equal(result.match_time,'2026-11-06T20:00:00.000Z');assert.equal(cancelled,true);
});
test('literal wrapper chain resolves a signed HLS URL with its original referer and expiry',async()=>{
 const f=fixture();const result=await totalsportekStreams({page_url:page},{fetcher:f.fetcher,now:Date.parse('2026-11-06')});
 assert.equal(result.lines.length,1);assert.equal(result.lines[0].stream_type,'hls');
 assert.equal(result.lines[0].label,'Channel 15');
 assert.equal(result.lines[0].origin,'https://universaltokenforall.st');
 assert.equal(result.lines[0].expires_at,new Date(2000000000000).toISOString());
 assert.equal(result.live_status,null);assert.equal(result.lines[0].health_status,'unknown');
 assert.equal(f.calls.length,4);assert.equal(f.calls[2].init.headers.Referer,wrapper);
});
test('refuses caller-selected non-provider URLs before fetching',async()=>{
 for(const value of ['http://127.0.0.1/','https://totalsportekl.is@evil.invalid/Home-vs-Away/12345',
  'https://totalsportekl.is/account/12345',page+'?url=http://localhost/',page+':123']){
  await assert.rejects(()=>totalsportekStreams({page_url:value},{fetcher:()=>{throw Error('must not fetch');}}),/Invalid Totalsportek/);
 }
});
test('third-party arbitrary iframes and URL-looking script strings are never followed',async()=>{
 const f=fixture({[wrapper]:'<iframe src="https://unlisted.invalid/player"></iframe><script>var x="https://evil.invalid/live.m3u8";</script>'});
 const result=await totalsportekStreams({page_url:page},{fetcher:f.fetcher});
 assert.deepEqual(result.lines,[]);assert.equal(f.calls.length,2);
});
test('external-player pages are not misreported as native video lines',async()=>{
 const f=fixture({[page]:'<a href="https://hadcrak.cyou/home-vs-away/">Stream</a>'});
 const result=await totalsportekStreams({page_url:page},{fetcher:f.fetcher});
 assert.deepEqual(result.lines,[]);assert.equal(result.live_status,null);
 assert.match(result.message,/no supported direct video line/);
 assert.equal(f.calls.length,1);
});
test('does not evaluate config JavaScript or accept media on untrusted hosts',async()=>{
 for(const body of ['let streamUrl = makeToken();',`let streamUrl = "http://127.0.0.1/live.m3u8";`,
  `let streamUrl = "https://sha.sharpnessonline.store.evil.invalid/simpch15/index.m3u8";`]){
  const f=fixture({[config]:body});assert.deepEqual((await totalsportekStreams({page_url:page},{fetcher:f.fetcher})).lines,[]);
 }
});
test('expired signed lines are omitted instead of imported as permanently active',async()=>{
 const f=fixture();assert.deepEqual((await totalsportekStreams({page_url:page},{fetcher:f.fetcher,now:2100000000000})).lines,[]);
});
test('upstream errors, redirects and unbounded HTML do not become empty successful schedules',async()=>{
 for(const status of [302,403,500])await assert.rejects(()=>totalsportekMatches({fetcher:async()=>new Response('',{status})}));
 await assert.rejects(()=>totalsportekMatches({fetcher:async()=>new Response('x'.repeat(2*1024*1024+1))}),/size limit/);
});
test('a failing player does not hide a separate working published player',async()=>{
 const second=wrapper.replace('live3','live4');
 const f=fixture({[page]:event+`<a href="${second}">Watch</a>`,[second]:'<iframe src="https://not-supported.invalid/player"></iframe>'});
 assert.equal((await totalsportekStreams({page_url:page},{fetcher:f.fetcher})).lines.length,1);
});
test('published website choices retain their labels and are never imported as native media',async()=>{
 const event=`<a class="nocolor w-100" href="https://external.example.org/event/12345"><div class="col-md-3 col-5">Other player <span class="golden-tick">&#xF058</span></div><div>HD Watch</div></a>`;
 const choices=totalsportekPlayers(event+event+`<a href="https://ads.example.org/">Ad</a>`+
   `<a class="nocolor" href="http://127.0.0.1/private">Private</a>`,page);
 assert.deepEqual(choices,[{label:'Other player',url:'https://external.example.org/event/12345'}]);
 const f=fixture({[page]:event});const result=await totalsportekStreams({page_url:page},{fetcher:f.fetcher});
 assert.deepEqual(result.lines,[]);assert.deepEqual(result.external_players,choices);assert.equal(f.calls.length,1);
});
test('distinct published Totalsportek player families produce two native lines plus every website choice',async()=>{
 const second=wrapper.replace('live3','live6');
 const soccer='https://soccerstreamlinks.st/player.php/home-vs-away-football';
 const vertex='https://s3.vertex.st/ch?id=24';
 const config='https://matchli.st/embed.php?code=published-code';
 const hls='https://hls.lshls.st/secure_hls.php?path=football/master.m3u8&e=2000000000&sig=original-signature';
 const f=fixture({[page]:event+`<a href="${second}">SoccerStreamLinks</a>`,
  [second]:`<iframe src="${soccer}"></iframe>`,[soccer]:`const endpoint='_player_data';`,
  [soccer+'?_player_data=1']:JSON.stringify({u:vertex}),
  [vertex]:`fetch('api/player.php?id='+id)`,
  ['https://s3.vertex.st/api/player.php?id=24']:JSON.stringify({url:config}),
  [config]:`window.PP_STABLE_CONFIG=${JSON.stringify({src:hls})};`,
 });
 const original=f.fetcher;
 f.fetcher=async(input,init)=>String(input)===config
   ? new Response('',{status:302,headers:{Location:config.replace('/embed.php','/embed-edge.php')}})
   : String(input)===config.replace('/embed.php','/embed-edge.php')
     ? new Response(`window.PP_STABLE_CONFIG=${JSON.stringify({src:hls})};`)
     : original(input,init);
 const result=await totalsportekStreams({page_url:page},{fetcher:f.fetcher,now:Date.parse('2026-11-07')});
 assert.equal(result.lines.length,2);assert.equal(result.external_players.length,2);
 const line=result.lines.find(line=>line.label.includes('SoccerStreamLinks'));
 assert.equal(line.url,hls);assert.equal(line.referer,config);assert.equal(line.origin,'https://matchli.st');
 assert.equal(line.expires_at,'2033-05-18T03:33:20.000Z');
 // A public JSON endpoint cannot select an arbitrary next destination.
 const unsafe=fixture({[page]:`<a href="${second}">Watch</a>`,[second]:`<iframe src="${soccer}"></iframe>`,
  [soccer]:`const endpoint='_player_data';`,[soccer+'?_player_data=1']:JSON.stringify({u:'http://127.0.0.1/private'})});
 assert.deepEqual((await totalsportekStreams({page_url:page},{fetcher:unsafe.fetcher})).lines,[]);
 assert.equal(unsafe.calls.length,4);
});
test('a selected published website player can resolve through the existing native player config',async()=>{
 const website='https://sportsguru.st/guru/total.php?ch=15';
 const f=fixture({[page]:event+`<a class="nocolor" href="${website}">SportsGuru</a>`,
  [website]:`<iframe src="${config}"></iframe>`});
 const result=await totalsportekStreams({page_url:page,player_url:website},{fetcher:f.fetcher});
 assert.equal(result.lines.length,1);assert.equal(result.lines[0].label,'SportsGuru • Channel 15');
 assert.equal(result.lines[0].url,media);assert.deepEqual(result.external_players,[]);
 assert(!f.calls.some(item=>item.url===wrapper),'do not scan unrelated players for a selected request');
 const invalid=fixture();
 await assert.rejects(()=>totalsportekStreams({page_url:page,player_url:'https://sportsguru.st/guru/total.php?ch=99'},
  {fetcher:invalid.fetcher}),/not published/);
 assert.equal(invalid.calls.length,1);
});
