import test from 'node:test';
import assert from 'node:assert/strict';
import {parseLiveTvSports,sportsGroup,verifiedSportsGuide,fetchLiveTvSports,sportsNeedsDrm} from '../supabase/functions/_shared/livetv_sports.mjs';
const guide=[{id:'existing-uk',name:'TNT Sports 1 (NITRO)',epg_id:'TNT.Sports.1.uk',epg_source:'UK1',is_active:true},
 {id:'existing-au',name:'beIN SPORTS 1 Australia',epg_id:'beINSports1.au',epg_source:'AU1',is_active:true}];
test('HTTP 200 encrypted DASH is distinguished from native playback without probing a license endpoint',async()=>{
 let calls=0;const fetcher=async url=>{calls++;assert.equal(url,'https://video.example.org/live.mpd');return new Response('<MPD><ContentProtection schemeIdUri="urn:uuid:fixture"/></MPD>');};
 assert.equal(await sportsNeedsDrm([{stream_type:'dash',stream_url:'https://video.example.org/live.mpd'}],{fetcher}),true);
 assert.equal(await sportsNeedsDrm([{stream_type:'hls',stream_url:'https://video.example.org/live.m3u8'}],{fetcher}),false);
 assert.equal(await sportsNeedsDrm([{stream_type:'dash',stream_url:'https://video.example.org/live.mpd',key_id:'configured',key_data:'configured'}],{fetcher}),false);
 assert.equal(calls,1);
});
test('Sports-only selection excludes mixed general, kids, news and esports groups',()=>{
 for(const value of ['Sports','UK SPORTS','TR | beIN SPORT','All Sports 🌎;Tennis🎾','Esportes'])assert(sportsGroup(value));
 for(const value of ['News;Sports','Kids;Sports','Entertainment;Sports','eSports Live','Movies','General;Sports'])assert(!sportsGroup(value));
});
test('verified EPG keeps country and numbered channels separate and rejects ambiguous guides',()=>{
 assert.equal(verifiedSportsGuide('TNT Sports 1 HD','UK',guide)?.id,'existing-uk');
 assert.equal(verifiedSportsGuide('TNT Sports 2','UK',guide),null);
 assert.equal(verifiedSportsGuide('beIN SPORTS 1','UK',guide),null);
 assert.equal(verifiedSportsGuide('beIN SPORTS 1 🇦🇺','AU',guide)?.id,'existing-au');
 assert.equal(verifiedSportsGuide('TNT Sports 1','',guide),null);
 assert.equal(verifiedSportsGuide('TNT Sports 1','UK',[...guide,{...guide[0],epg_id:'different.uk'}]),null);
});
test('source URL rotations retain channel identity and private media headers without importing non-sports',async()=>{
 const make=token=>({channels:{Sports:[{name:'TNT Sports 1 HD',url:'https://video.example.org/live.m3u8?token='+token+'|Referer=https%3A%2F%2Fplayer.example.org%2Fwatch',logo:'https://images.example.org/tnt.png'},
  {name:'Private',url:'http://127.0.0.1/internal.m3u8'}],News:[{name:'News',url:'https://video.example.org/news.m3u8'}]}});
 const [a]=await parseLiveTvSports('LiveTV/UK/LiveTV.json',make('one'),guide);
 const [b]=await parseLiveTvSports('LiveTV/UK/LiveTV.json',make('two'),guide);
 assert.equal(a.id,b.id);assert.equal(a.streams[0].id,b.streams[0].id);
 assert.equal(a.epg_channel_id,'existing-uk');assert.equal(a.epg_source,'UK1');
 assert.equal(a.streams[0].referer,'https://player.example.org/watch');
 assert.notEqual(a.streams[0].stream_url,b.streams[0].stream_url);
 assert.equal((await parseLiveTvSports('LiveTV/UK/LiveTV.json',make('one'),guide)).length,1);
 await assert.rejects(parseLiveTvSports('BugsfreeMain/TV-UK.py',make('one'),guide));
});
test('repository sync uses pinned public exports and reports a partial source failure',async()=>{
 const sha='a'.repeat(40),calls=[];
 const fetcher=async value=>{const url=String(value);calls.push(url);
  if(url.endsWith('/branches/main'))return Response.json({commit:{sha}});
  if(url.includes('/git/trees/'))return Response.json({tree:[{type:'blob',path:'LiveTV/UK/LiveTV.json'},
   {type:'blob',path:'LiveTV/USA/LiveTV.json'},{type:'blob',path:'BugsfreeMain/TV-UK.py'},
   {type:'blob',path:'LiveTV/Movies/Movies.json'}]});
  assert(url.includes('/'+sha+'/'));
  if(url.includes('/USA/'))return new Response('unavailable',{status:503});
  return Response.json({channels:{Sports:[{name:'TNT Sports 1',url:'https://video.example.org/live.m3u8'}]}});
 };
 const result=await fetchLiveTvSports({fetcher,channels:guide});assert.equal(result.entries.length,1);assert.equal(result.complete,false);assert.equal(calls.length,4);
 calls.length=0;assert.equal((await fetchLiveTvSports({fetcher,revision:sha})).unchanged,true);assert.equal(calls.length,1);
});
