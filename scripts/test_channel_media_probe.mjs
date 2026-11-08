import {test} from 'node:test';
import assert from 'node:assert/strict';
import {probeChannelMedia} from '../supabase/functions/_shared/channel_media_probe.mjs';
const line={stream_url:'https://cdn.example.org/one.mpd',stream_type:'dash'};
test('HTTP 200 HTML is not a valid video manifest',async()=>{
 const result=await probeChannelMedia(line,{fetcher:async()=>new Response('<html>error page</html>')});
 assert.equal(result.health_status,'failed');assert.equal(result.manifest_status,'invalid');
});
test('DASH manifest, media bytes and ClearKey configuration are separate from video decode',async()=>{
 const urls=[];const result=await probeChannelMedia({...line,key_id:'a'.repeat(32),key_data:'b'.repeat(32)},{fetcher:async url=>{
  urls.push(url);return new Response(url.endsWith('.mpd')?`<MPD><ContentProtection cenc:default_KID="${'a'.repeat(32)}"/><Representation id="v1"/><SegmentTemplate initialization="init-$RepresentationID$.mp4"/></MPD>`:'binary');}});
 assert.equal(result.manifest_status,'valid');assert.equal(result.segment_status,'reachable');assert.equal(result.drm_status,'configured');
 assert.equal(urls[1],'https://cdn.example.org/init-v1.mp4');assert.equal(result.playback_status,undefined);
 assert(!JSON.stringify(result).includes('b'.repeat(32)));
});
test('missing/mismatched DRM keys do not become configured merely because HTTP works',async()=>{
 const fetcher=async()=>new Response(`<MPD><ContentProtection cenc:default_KID="${'a'.repeat(32)}"/></MPD>`);
 assert.equal((await probeChannelMedia(line,{fetcher})).drm_status,'missing_configuration');
 assert.equal((await probeChannelMedia({...line,key_id:'c'.repeat(32),key_data:'b'.repeat(32)},{fetcher})).drm_status,'missing_configuration');
});
test('HLS master/media/segment are followed with a small bounded read; upstream blocks stay unknown',async()=>{
 const result=await probeChannelMedia({...line,stream_url:'https://cdn.example.org/master.m3u8',stream_type:'hls'},{fetcher:async url=>new Response(
  url.endsWith('master.m3u8')?'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nmedia.m3u8':url.endsWith('media.m3u8')?'#EXTM3U\n#EXTINF:6\nsegment.ts':'binary')});
 assert.equal(result.segment_status,'reachable');assert.equal(result.drm_status,'not_required');
 const blocked=await probeChannelMedia(line,{fetcher:async()=>new Response('',{status:403})});assert.equal(blocked.health_status,'unknown');
});
test('redirects to private hosts are rejected',async()=>{
 const result=await probeChannelMedia(line,{fetcher:async()=>new Response('',{status:302,headers:{Location:'http://127.0.0.1/admin'}})});
 assert.equal(result.health_status,'failed');
});
