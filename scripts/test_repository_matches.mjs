import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseRepositoryMatches,mergeRepositoryMatches,repositoryKickoff} from '../supabase/functions/_shared/repository_matches.mjs';
import {publicRepositoryUpdate,orderConfigurationProbes} from '../supabase/functions/_shared/repository_updates.mjs';
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
test('only a verified publisher HTML landing page is an empty export; a network error page is not a deletion',()=>{
 assert.deepEqual(parseRepositoryMatches('<!DOCTYPE HTML PUBLIC "test"><html></html>',{...context,publisher_blob_verified:true}),[]);
 assert.throws(()=>parseRepositoryMatches('<html>gateway error</html>',context),/Invalid published/);
});
test('Admin import activity returns change field names without source URLs or key values',()=>{
 const row=publicRepositoryUpdate({repository:'test',metadata:{license_url:'https://private.example.org/license',changed_fields:['Key','https://private.example.org/source'],last_updated_at:'2026-11-08T00:00:00Z'},channel_lines:{id:'id',label:'HD',stream_url:'https://private.example.org/source',key_data:'private-key',channels:{name:'Sports'}}});
 assert.deepEqual(row.changed_fields,['Key']);assert(!JSON.stringify(row).includes('private.example'));assert(!JSON.stringify(row).includes('private-key'));
});
test('hourly probe limits cannot starve unverified lines behind repeatedly missing DRM keys',()=>{
 const rows=Array.from({length:30},(_,i)=>({id:i,metadata:{},channel_lines:{configuration_status:i<14?'requires_drm':'unverified'}}));
 const checked=new Set();
 for(let run=1;run<=3;run++){
  const batch=orderConfigurationProbes(rows).slice(0,12);
  if(run===1)assert(batch.every(r=>r.channel_lines.configuration_status==='requires_drm'));
  for(const row of batch){checked.add(row.id);row.metadata.last_config_probe=`2026-11-08T0${run}:00:00Z`;}
 }
 assert.equal(checked.size,30);
 assert.equal(orderConfigurationProbes(rows)[0].metadata.last_config_probe,'2026-11-08T01:00:00Z');
});

test('all four repositories merge Man Utd aliases without combining the women fixture',async()=>{
 const repos=['rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy'];
 const base={home_team:'Man Utd',away_team:'Aston Villa',league:'Premier League',football_proven:true,kickoff_at:'2026-11-08T16:30:00.000Z'};
 const rows=repos.map((repository,i)=>({...base,repository,home_team:i%2?'Manchester United':'Man Utd',
  league:i===3?'LIVE EVENT':'Premier League',streams:[{stream_url:`https://cdn.example.org/line${i}.m3u8`,stream_type:'hls',label:'Line '+i}]}));
 rows.push({...rows[2],league:"Women's Super League",kickoff_at:'2026-11-08T12:00:00.000Z'});
 const result=await mergeRepositoryMatches(rows,{now:Date.parse('2026-11-08T16:00:00Z')});
 assert.equal(result.length,2);
 const men=result.find(r=>r.event_meta.league==='Premier League');
 assert(men);assert.equal(men.name,'Manchester United vs Aston Villa');assert.equal(men.streams.length,4);
 assert.deepEqual(new Set(men.event_meta.repositories),new Set(repos));
 assert.equal(result.find(r=>r.event_meta.league==="Women's Super League").streams.length,1);
});

test('MPD lines with identical URL and key pair collapse regardless of provider labels and headers',async()=>{
 const base=parseRepositoryMatches(JSON.stringify([row]),context)[0];
 const duplicate={...base,repository:'darkbyteprojects/iptv_png',streams:base.streams.map(s=>({...s,label:'Different provider name',referer:'https://other.example.org/',origin:'https://other.example.org'}))};
 const result=await mergeRepositoryMatches([base,duplicate],{now:Date.parse('2026-11-08T00:00:00Z')});
 assert.equal(result.length,1);assert.equal(result[0].streams.length,1);
});
