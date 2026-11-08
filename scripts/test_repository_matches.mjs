import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseRepositoryMatches,mergeRepositoryMatches,repositoryKickoff} from '../supabase/functions/_shared/repository_matches.mjs';
const context={repository:'Roshavarma/cfy',source_file:'api/events.json'};
const row={cat:'Football',eventInfo:{teamA:'Napoli',teamB:'Inter Milan',eventName:'Serie A',startTime:'2026/11/08 14:00:00 +0000',teamAFlag:'https://logos.example.org/napoli.png',teamBFlag:'https://logos.example.org/inter.png'},
 channels_data:[{title:'HD',link:'https://cdn.example.org/sport.mpd?token=a',api:'a'.repeat(32)+':'+ 'b'.repeat(32),type:1}]};
test('nested CFY fixtures keep team logos and exact offset time; static channels and other sports are excluded',()=>{
 const data=parseRepositoryMatches(JSON.stringify({events:{events:[row,{...row,cat:'Cricket',eventInfo:{...row.eventInfo,eventCat:'Cricket'}},{title:'TNT Sports',channels_data:row.channels_data}]}}),context);
 assert.equal(data.length,1);assert.equal(data[0].home_logo_url,row.eventInfo.teamAFlag);assert.equal(data[0].kickoff_at,'2026-11-08T14:00:00.000Z');
 assert.equal(data[0].streams[0].key_data,'b'.repeat(32));assert.equal(repositoryKickoff('08/11/2026 14:00:00'),null);
});
test('repeated fixtures and rotated tokens collapse across repositories; different DRM configurations remain separate',async()=>{
 const one=parseRepositoryMatches(JSON.stringify([row]),context)[0];
 const two={...one,repository:'darkbyteprojects/iptv_png',streams:one.streams.map(s=>({...s,stream_url:s.stream_url.replace('token=a','token=b')}))};
 const three={...one,repository:'rohmanabdu/lian',streams:one.streams.map(s=>({...s,key_data:'c'.repeat(32)}))};
 const later={...one,kickoff_at:'2026-11-09T14:00:00.000Z'};
 const data=await mergeRepositoryMatches([one,two,three,later],{now:Date.parse('2026-11-08T00:00:00Z')});
 assert.equal(data.length,2);assert.equal(data[0].streams.length,2);assert.equal(data[0].event_meta.repositories.length,3);
});
test('M3U match data ignores tokenApi/code and reads an explicit WIB date without inventing a timezone',()=>{
 const data=parseRepositoryMatches(`#EXTM3U\n#EXTINF:-1 group-title="Football",Napoli vs Inter Milan - Serie A (20:00 WIB * 08-11-2026)\nhttps://cdn.example.org/one.m3u8`,{repository:'rohmanabdu/lian'});
 assert.equal(data.length,1);assert.equal(data[0].away_team,'Inter Milan');assert.equal(data[0].kickoff_at,'2026-11-08T13:00:00.000Z');
});
