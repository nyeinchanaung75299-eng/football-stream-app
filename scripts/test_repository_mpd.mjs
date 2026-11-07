import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseMpdData,mpdIdentity,uniqueMpdEntries} from '../supabase/functions/_shared/repository_mpd.mjs';

test('M3U in a JSON-named file keeps ClearKey, headers and unconfigured Widevine separately',()=>{
 const data=`#EXTM3U
#EXTINF:-1 tvg-id="NBC.us" group-title="Sports",NBC
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=${'a'.repeat(32)}:${'b'.repeat(32)}
https://cdn.example.org/nbc.mpd|Referer=https%3A%2F%2Fplayer.example.org%2F
#EXTINF:-1,Other
#KODIPROP:inputstream.adaptive.license_type=com.widevine.alpha
#KODIPROP:inputstream.adaptive.license_key=https://license.example.org/key
https://cdn.example.org/other.mpd
#EXTINF:-1,HLS
https://cdn.example.org/live.m3u8`;
 const rows=parseMpdData(data);
 assert.equal(rows.length,2);assert.equal(rows[0].epg_id,'NBC.us');
 assert.equal(rows[0].referer,'https://player.example.org/');assert.equal(rows[0].configuration_status,'configured');
 assert.equal(rows[1].key_data,null);assert.equal(rows[1].configuration_status,'requires_drm');
});
test('nested event feeds include keyless MPD but reject HLS, player pages and private hosts',()=>{
 const rows=parseMpdData(JSON.stringify({events:{events:[{title:'Live football',channels_data:[
  {title:'Sports 1',type:1,link:'https://cdn.example.org/one.mpd'},
  {title:'Player',link:'https://cdn.example.org/player.html'},
  {title:'Private',link:'http://127.0.0.1/one.mpd'},
 ]}]}}));
 assert.equal(rows.length,1);assert.equal(rows[0].name,'Sports 1');assert.equal(rows[0].configuration_status,'unverified');
});
test('cross-repository and rotated-token duplicates collapse without conflating channels',async()=>{
 const rows=await uniqueMpdEntries([
  {name:'A',stream_url:'https://cdn.example.org/live.mpd?id=one&token=old'},
  {name:'B',stream_url:'https://cdn.example.org/live.mpd?token=new&id=one',key_id:'a',key_data:'b'},
  {name:'C',stream_url:'https://cdn.example.org/live.mpd?id=two'},
 ]);
 assert.equal(rows.length,2);assert.equal(rows[0].name,'B');
 assert.equal(mpdIdentity('https://cdn.example.org/live.mpd?id=one&aws_sessionId=x'),'https://cdn.example.org/live.mpd?id=one');
});
