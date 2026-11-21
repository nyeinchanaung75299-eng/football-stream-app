import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseMpdData,mpdIdentity,uniqueMpdEntries,fetchRepositoryMpds} from '../supabase/functions/_shared/repository_mpd.mjs';
import {repositoryChannelUpdates} from '../supabase/functions/_shared/repository_updates.mjs';
import {REPOSITORY_TREE_SOURCES} from '../supabase/functions/_shared/repository_trees.mjs';
import {NEW_GITHUB_SOURCES} from '../supabase/functions/_shared/github_source_formats.mjs';

test('only the opt-in scheduled updater accepts explicit missing repositories',async()=>{
 const sha='a'.repeat(40),tree={sha,truncated:false,tree:[{path:'provider_1/sports.json',type:'blob',size:100}]};
 const cfy={sha,truncated:false,tree:[{path:'api/events.json',type:'blob',size:100}]};
 const fetched=[];
 const fetcher=async url=>{
  fetched.push(url);
  if(url.endsWith('repository-trees.json'))return Response.json({fetched_at:new Date().toISOString(),repositories:{
   ...Object.fromEntries(NEW_GITHUB_SOURCES.map(x=>[x.repository,{status:404}])),
   'rohmanabdu/lian':{status:404},'rohmanabdu/deqiaa':{status:404},'darkbyteprojects/iptv_png':tree,'Roshavarma/cfy':cfy}});
  if(url.includes('api.github.com/repos/rohmanabdu/'))return new Response('',{status:404});
  if(url.includes('api.github.com/repos/darkbyteprojects/'))return Response.json(tree);
  if(url.includes('api.github.com/repos/Roshavarma/'))return Response.json(cfy);
  return Response.json([{title:'Sports HD',link:'https://media.example.org/sports.mpd'}]);
 };
 await assert.rejects(fetchRepositoryMpds({fetcher}),/unavailable/i);
 fetched.length=0;
 const snapshot=await repositoryChannelUpdates([],{fetcher});
 assert.equal(snapshot.complete,false);assert.equal(snapshot.entries.length,2);
 assert.deepEqual(snapshot.missingRepositories,['rohmanabdu/lian','rohmanabdu/deqiaa',...NEW_GITHUB_SOURCES.map(x=>x.repository)]);
 assert.equal(fetched.some(url=>url.includes('api.github.com')),false);
 assert.equal(snapshot.probed,0);
 await assert.rejects(repositoryChannelUpdates([],{fetcher:async()=>Response.json({fetched_at:new Date().toISOString(),repositories:
  Object.fromEntries(REPOSITORY_TREE_SOURCES.map(r=>[r,{status:404}]))})}),/No published repository/);
});

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
