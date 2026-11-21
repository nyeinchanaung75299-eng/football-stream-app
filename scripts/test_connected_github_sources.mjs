import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {NEW_GITHUB_SOURCES,HUB_GITHUB_SOURCES,normalizeGithubDocument,readGithubDocuments} from '../supabase/functions/_shared/github_source_formats.mjs';
import {githubCatalogEntries,fetchConnectedGithubCatalog} from '../supabase/functions/_shared/connected_github_catalog.mjs';
import {parseRepositoryMatches,mergeRepositoryMatches} from '../supabase/functions/_shared/repository_matches.mjs';
const sha='a'.repeat(40),url='https://cdn.example.org/sports.m3u8';
const eventInfo={teamA:'Newcastle',teamB:'Arsenal',eventName:'Premier League',eventCat:'Football',startTime:'2026/11/21 17:30:00 +0000'};
test('all four committed formats expose native lines through the existing catalog and fixture flow',async()=>{
 const payloads=[{channels:[{id:'live',name:'[Live] Newcastle vs Arsenal - HD',category:'live_sports',servers:[{name:'HD',stream_url:url},{name:'Hidden',publish:'0',stream_url:'https://cdn.example.org/hidden.m3u8'}]}]},
  [{id:1,title:'Newcastle vs Arsenal',cat:'Football',event:{...eventInfo,name:'Premier League',category:'Football',startTimeUTC:eventInfo.startTime},dashStreams:[{title:'HD',url}]}],
  {matches:[{event_name:'Newcastle vs Arsenal',Category:'Football',eventInfo,streams:[{channel_name:'HD',stream_url:url}]}]},
  [{id:1,title:'Newcastle vs Arsenal',cat:'Football',eventInfo,decoded_channels:[{title:'HD',link:url}]}]];
 const fixtures=[];
 for(const [i,source] of NEW_GITHUB_SOURCES.entries()){
  const rows=normalizeGithubDocument(source.repository,'fixture.json',payloads[i]);
  const entries=await githubCatalogEntries(source,[{path:'fixture.json',rows}],sha);
  assert.equal(entries.length,1);assert.equal(entries[0].provider,source.provider);assert.equal(entries[0].streams.length,1);
  assert.equal(entries[0].event_meta.source_repository,source.repository);
  fixtures.push(...parseRepositoryMatches(JSON.stringify(rows),{repository:source.repository,source_file:'fixture.json'}));
 }
 const merged=await mergeRepositoryMatches(fixtures,{now:Date.parse('2026-11-21T17:00:00Z')});
 assert.equal(merged.length,1);assert.equal(merged[0].streams.length,1);assert.equal(merged[0].event_meta.repositories.length,4);
 const row=normalizeGithubDocument(NEW_GITHUB_SOURCES[2].repository,'Sports_data.json',{matches:[{Category:'American football',eventInfo,streams:[{stream_url:url}]}]});
 assert.equal(parseRepositoryMatches(JSON.stringify(row),{repository:NEW_GITHUB_SOURCES[2].repository}).length,0);
});
test('unknown source clocks remain undated and token/API references are not executed',async()=>{
 const source=NEW_GITHUB_SOURCES[2];
 const rows=normalizeGithubDocument(source.repository,'Sports_data.json',{matches:[{Category:'Football',eventInfo:{...eventInfo,startTime:'21/11/2026 11:00:00 PM'},streams:[{channel_name:'Token',tokenApi:'https://tokens.example.org/private'}]}]});
 const parsed=parseRepositoryMatches(JSON.stringify(rows),{repository:source.repository});
 assert.equal(parsed[0].kickoff_at,null);assert.equal(parsed[0].streams.length,0);
 const old=normalizeGithubDocument(source.repository,'Sports_data.json',{matches:[{Category:'Football',eventInfo:{...eventInfo,startTime:'01/10/2026 11:00:00 PM'},streams:[{stream_url:url}]}]});
 const dated=parseRepositoryMatches(JSON.stringify([{eventInfo,cat:'Football',streams:[{link:'https://cdn.example.org/current.m3u8'}]}]),{repository:'Roshavarma/cfy'});
 const merged=await mergeRepositoryMatches([...dated,...parseRepositoryMatches(JSON.stringify(old),{repository:source.repository})],{now:Date.parse('2026-11-21T17:00:00Z')});
 assert.equal(merged.length,2);assert.equal(merged.find(r=>r.event_meta.kickoff_at)?.streams.length,1);
});
test('DudeTV reads reviewed referenced channel JSONs and verifies each Git blob before use',async()=>{
 const source=NEW_GITHUB_SOURCES[3],payloads={
  'public_decrypted/events_with_channels.json':[],
  'public_decrypted/cats/sports.json':[{id:'1',title:'Sports HD',cat:'Sports',formats:['HD']}],
  'public_decrypted/channels/1.json':[{title:'HD',link:url}],
 };
 const texts=Object.fromEntries(Object.entries(payloads).map(([k,v])=>[k,JSON.stringify(v)]));
 const tree={sha,truncated:false,tree:Object.entries(texts).map(([path,text])=>({path,type:'blob',size:Buffer.byteLength(text),sha:createHash('sha1').update('blob '+Buffer.byteLength(text)+'\0').update(text).digest('hex')}))};
 let calls=0;const fetcher=async address=>{calls++;const path=address.split('/'+sha+'/')[1];assert(path in texts);return new Response(texts[path]);};
 const docs=await readGithubDocuments(source.repository,tree,{fetcher});
 const entries=await githubCatalogEntries(source,docs,sha);
 assert.equal(calls,3);assert.equal(entries[0].streams.length,1);
 await assert.rejects(readGithubDocuments(source.repository,tree,{fetcher:async()=>new Response('[]')}),/blob verification/);
});
test('unchanged source rows are reused and unavailable source rows are retained without re-downloading channels',async()=>{
 const repositories=['darkbyteprojects/iptv_png',...HUB_GITHUB_SOURCES.map(x=>x.repository)];
 const previous=repositories.map((repository,i)=>({id:'cached-'+i,streams:[],event_meta:{source_repository:repository,source_revision:sha,catalog_schema_version:3}}));
 for(const missing of [false,true]){
  let calls=0;
  const result=await fetchConnectedGithubCatalog({previous,fetcher:async address=>{
   calls++;assert(address.endsWith('/repository-trees.json'));
   return Response.json({fetched_at:new Date().toISOString(),repositories:Object.fromEntries(repositories.map((r,i)=>[r,missing&&i===4?{status:404}:{sha,truncated:false,tree:[]}]))});
  }});
  assert.equal(calls,1);assert.equal(result.entries.length,repositories.length);assert.equal(result.complete,!missing);
  assert.equal(result.entries[4],previous[4]);
 }
});
test('one failed file leaves its last catalog while a healthy changed repository still updates',async()=>{
 const repos=['darkbyteprojects/iptv_png',...HUB_GITHUB_SOURCES.map(x=>x.repository)];
 const previous=repos.map((repository,i)=>({id:'saved-'+i,streams:[],event_meta:{source_repository:repository,source_revision:sha,catalog_schema_version:3}}));
 const payload=JSON.stringify({matches:[{event_name:'Newcastle vs Arsenal',Category:'Football',eventInfo,streams:[{stream_url:url}]}]});
 const blob={type:'blob',path:'Sports_data.json',size:Buffer.byteLength(payload),sha:createHash('sha1').update('blob '+Buffer.byteLength(payload)+'\0').update(payload).digest('hex')};
 const trees=Object.fromEntries(repos.map((r,i)=>[r,{sha:i===1?'b'.repeat(40):i===3?'c'.repeat(40):sha,truncated:false,
  tree:i===3?[blob]:i===1?[{...blob,path:'output/channels.json'}]:[]}]));
 const result=await fetchConnectedGithubCatalog({previous,fetcher:async address=>{
  if(address.endsWith('repository-trees.json'))return Response.json({fetched_at:new Date().toISOString(),repositories:trees});
  if(address.endsWith('Sports_data.json'))return new Response(payload);
  return new Response('',{status:503});
 }});
 assert.equal(result.complete,false);assert(result.entries.some(x=>x.id===previous[1].id));
 assert(result.entries.some(x=>x.id.startsWith('gh:smsports:')));assert(!result.entries.some(x=>x.id===previous[3].id));
});
