import test from 'node:test';
import assert from 'node:assert/strict';
import {publicSourceUrl,readPublicSource,discoverPublicMedia} from '../supabase/functions/_shared/public_source_media.mjs';
import {experimentalMatches,experimentalFootballSites} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const response=(value,type='text/html')=>new Response(value,{headers:{'content-type':type}});

test('Retired football source adapters have no active provider configuration',()=>{
 assert.deepEqual(Object.keys(experimentalFootballSites),['rojadirecta']);
});

test('Rojadirecta binds a game only to its own public player ID',async()=>{
 const html='<details class="game-item-details" data-game-id="42"><summary>'+
  '<span class="game-teams">Moldova - Kazakhstan</span></summary>'+
  '<div class="game-links-container"></div></details>'+
  '<script>window.LINKS_DATA = '+JSON.stringify({
    42:[{link:'https://player.example.org/event'},{link:'acestream://not-native'}],
    99:[{link:'https://other.example.org/unrelated'}],
  })+';</script>';
 const r=await experimentalMatches('rojadirecta',{fetcher:async()=>response(html)});
 assert.equal(r.matches.length,1);
 assert.equal(r.matches[0].anchors.length,1);
 assert.equal(r.matches[0].anchors[0].page_url,'https://player.example.org/event');
 assert.equal(r.matches[0].match_time,null);
});

test('No private network, credential URL or local host can be a source target',()=>{
 for(const url of ['http://127.0.0.1/live.m3u8','http://[::1]/a.mpd',
  'https://user:password@cdn.example.org/a.m3u8','https://example.local/a.mp4']) {
   assert.equal(publicSourceUrl(url),null,url);
 }
});

test('Public HTML can explicitly publish HLS without executing scripts',async()=>{
 const found=await discoverPublicMedia('https://player.example.org/event',{fetcher:async url=>
   response('<video src="https://cdn.example.org/live.m3u8"></video>')});
 assert.equal(found.lines.length,1);
 assert.equal(found.lines[0].stream_type,'hls');
 assert.equal(found.lines[0].url,'https://cdn.example.org/live.m3u8');
});

test('Sponsor or preroll clips are never emitted as programme links',async()=>{
 const found=await discoverPublicMedia('https://player.example.org/event',{fetcher:async()=>response(
  '<video src="https://cdn.example.org/ads/pre-roll.mp4"></video>'+
  '<script>var actual="https://cdn.example.org/match-highlights.mp4";</script>')});
 assert.deepEqual(found.lines.map(x=>x.url),['https://cdn.example.org/match-highlights.mp4']);
});

test('Public page redirect cannot cross configured publisher host',async()=>{
 await assert.rejects(readPublicSource('https://www.rojadirectavivo.me/live-football',{
  allowedHosts:['rojadirectavivo.me'],
  fetcher:async()=>new Response('Moved',{status:302,
    headers:{location:'http://127.0.0.1/secret'}}),
 }),/Unsupported public source URL/);
});

test('Blocked player script never becomes a verified media stream',async()=>{
 const found=await discoverPublicMedia('https://player.example.org/event',{fetcher:async url=>
  url.endsWith('/embed.js')?
    new Response('Blocked',{status:403}):
    response('<script src="/embed.js" data-play="42"></script>')});
 assert.equal(found.lines.length,0);
});
