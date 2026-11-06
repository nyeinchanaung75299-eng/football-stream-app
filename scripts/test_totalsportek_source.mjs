import test from 'node:test';
import assert from 'node:assert/strict';
import {parseTotalsportekMatches,totalsportekKickoff,totalsportekMatches,totalsportekStreams} from '../supabase/functions/_shared/totalsportek_source.mjs';
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
  '<div class="league-header"><span>NBA</span></div>'+card('','888');
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
test('literal wrapper chain resolves a signed HLS URL with its original referer and expiry',async()=>{
 const f=fixture();const result=await totalsportekStreams({page_url:page},{fetcher:f.fetcher,now:Date.parse('2026-11-06')});
 assert.equal(result.lines.length,1);assert.equal(result.lines[0].stream_type,'hls');
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
