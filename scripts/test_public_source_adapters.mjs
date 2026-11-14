import test from 'node:test';
import assert from 'node:assert/strict';
import {publicSourceUrl,readPublicSource,discoverPublicMedia} from '../supabase/functions/_shared/public_source_media.mjs';
import {experimentalMatches,experimentalFootballSites,configuredRoxiePublicMedia} from '../supabase/functions/_shared/experimental_football_sources.mjs';

const response=(value,type='text/html')=>new Response(value,{headers:{'content-type':type}});

test('Only RoxieStreams remains; Rojadirecta is retired',()=>{
 assert.deepEqual(Object.keys(experimentalFootballSites),['roxie']);
});

test('Roxie literal configuration is read without evaluating player JS',async()=>{
 const html="<button onclick=\"getRandomStream('live.m3u8','admin2')\">Stream 1</button>"+
 "<script>function getRandomStream(streamPath, subdomain = 'admin2'){return `https://${subdomain}.media.example.org/${streamPath}`;}</script>";
 const r=await configuredRoxiePublicMedia('roxie',html,'https://roxiestreams.su/soccer-streams-1');
 assert.equal(r.length,1);assert.equal(r[0].url,'https://admin2.media.example.org/live.m3u8');
 assert.equal((await configuredRoxiePublicMedia('camel',html,'https://www.camel1.tv/')).length,0);
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
 assert.ok(found.lines[0].url.endsWith('.m3u8'));
 assert.equal(found.lines[0].url,'https://cdn.example.org/live.m3u8');
});

test('Sponsor or preroll clips are never emitted as programme links',async()=>{
 const found=await discoverPublicMedia('https://player.example.org/event',{fetcher:async()=>response(
  '<video src="https://cdn.example.org/ads/pre-roll.mp4"></video>'+
  '<script>var actual="https://cdn.example.org/match-highlights.mp4";</script>')});
 assert.deepEqual(found.lines.map(x=>x.url),['https://cdn.example.org/match-highlights.mp4']);
});

test('Public page redirect cannot cross configured publisher host',async()=>{
 await assert.rejects(readPublicSource('https://roxiestreams.su/soccer',{
  allowedHosts:['roxiestreams.su'],
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
