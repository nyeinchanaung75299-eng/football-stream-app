import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readRepositoryTrees,REPOSITORY_TREE_SOURCES} from '../supabase/functions/_shared/repository_trees.mjs';
const now=Date.parse('2026-11-08T11:00:00Z'),sha='a'.repeat(40),tree={sha,truncated:false,tree:[{type:'blob',path:'api/events.json',sha:'b'.repeat(40),size:100}]};
test('complete fresh metadata avoids anonymous GitHub API calls and preserves original blob hashes',async()=>{
 const calls=[];const rows=await readRepositoryTrees(REPOSITORY_TREE_SOURCES,{now,fetcher:async url=>{
  calls.push(url);assert(url.startsWith('https://raw.githubusercontent.com/'));
  return Response.json({fetched_at:new Date(now-300000).toISOString(),repositories:Object.fromEntries(REPOSITORY_TREE_SOURCES.map(repo=>[repo,tree]))});
 }});
 assert.equal(calls.length,1);assert.equal(rows.length,REPOSITORY_TREE_SOURCES.length);assert.equal(rows[0].tree[0].sha,'b'.repeat(40));
});
test('stale or incomplete metadata never causes a false removal; API failures reject the refresh',async()=>{
 for(const mirror of [{fetched_at:new Date(now-3600000).toISOString(),repositories:Object.fromEntries(REPOSITORY_TREE_SOURCES.map(repo=>[repo,tree]))},{fetched_at:new Date(now).toISOString(),repositories:{}}]){
  let calls=0;
  await assert.rejects(()=>readRepositoryTrees(['Roshavarma/cfy'],{now,fetcher:async url=>{
   calls++;return url.includes('raw.githubusercontent.com')?Response.json(mirror):new Response('',{status:403});
  }}),error=>error.code==='repository_http_403');assert.equal(calls,2);
 }
 await assert.rejects(()=>readRepositoryTrees(['other/repo']),/Unsupported/);
});


test('opt-in partial tree sync skips only 404 repositories, never 403 or untrusted trees',async()=>{
 const calls=[];
 const rows=await readRepositoryTrees(REPOSITORY_TREE_SOURCES,{now,allowMissing:true,fetcher:async url=>{
  calls.push(url);
  if(url.startsWith('https://raw.githubusercontent.com/'))
   return Response.json({fetched_at:new Date(now-3600000).toISOString(),repositories:{}});
  if(REPOSITORY_TREE_SOURCES.slice(0,2).some(repo=>url.includes('/'+repo+'/')))return new Response('',{status:404});
  return Response.json(tree);
 }});
 assert.equal(rows.length,REPOSITORY_TREE_SOURCES.length);
 assert.equal(rows.filter(x=>x===null).length,2);
 assert.equal(rows[2].sha,sha);
 assert.equal(rows[3].sha,sha);
 assert.equal(calls.length,REPOSITORY_TREE_SOURCES.length+1);
 await assert.rejects(()=>readRepositoryTrees(['Roshavarma/cfy'],{
  now,allowMissing:true,fetcher:async url=>url.includes('raw.githubusercontent.com')
   ?Response.json({fetched_at:new Date(now-3600000).toISOString(),repositories:{}})
   :new Response('',{status:403}),
 }),error=>error.code==='repository_http_403');
});

test('fresh explicit missing records permit partial sync without anonymous API calls',async()=>{
 let calls=0;const repositories=Object.fromEntries(REPOSITORY_TREE_SOURCES.map((r,i)=>[r,i<2?{status:404}:tree]));
 const rows=await readRepositoryTrees(REPOSITORY_TREE_SOURCES,{now,allowMissing:true,fetcher:async()=>{calls++;return Response.json({fetched_at:new Date(now).toISOString(),repositories});}});
 assert.equal(calls,1);assert.equal(rows[0],null);assert.equal(rows[2].sha,sha);
});

test('only the six retained repository sources are scheduled; retired sources are rejected without fetching',async()=>{
 assert.equal(REPOSITORY_TREE_SOURCES.length,6);
 for(const repo of ['rohmanabdu/lian','rohmanabdu/deqiaa']){
  let calls=0;
  await assert.rejects(()=>readRepositoryTrees([repo],{fetcher:async()=>{calls++;throw Error('Unexpected fetch');}}),/Unsupported repository/);
  assert.equal(calls,0);
 }
});

test('shared rate limits defer further anonymous requests until the reset; fresh metadata still wins',async()=>{
 let current=now, fresh=false, blocked=true, apiCalls=0;
 const fetcher=async url=>{
  if(url.includes('raw.githubusercontent.com'))return Response.json({fetched_at:new Date(current-(fresh?0:3600000)).toISOString(),repositories:Object.fromEntries(REPOSITORY_TREE_SOURCES.map(repo=>[repo,tree]))});
  apiCalls++;
  return blocked?new Response('',{status:403,headers:{'x-ratelimit-remaining':'0','x-ratelimit-reset':String((now+1800000)/1000)}}):Response.json(tree);
 };
 const read=()=>readRepositoryTrees(REPOSITORY_TREE_SOURCES,{now:current,fetcher,allowMissing:true,isolateFailures:true});
 assert((await read()).every(x=>x===null));assert.equal(apiCalls,1);
 current+=60000;assert((await read()).every(x=>x===null));assert.equal(apiCalls,1);
 fresh=true;assert((await read()).every(x=>x.sha===sha));assert.equal(apiCalls,1);
 fresh=false;blocked=false;current=now+1800001;
 assert((await read()).every(x=>x.sha===sha));assert.equal(apiCalls,7);
});

test('source-specific access denial does not block unrelated metadata or pretend it was removed',async()=>{
 const first=REPOSITORY_TREE_SOURCES[0],second=REPOSITORY_TREE_SOURCES[1];let apiCalls=0;
 const fetcher=async url=>{
  if(url.includes('raw.githubusercontent.com'))return Response.json({fetched_at:new Date(now).toISOString(),repositories:{}});
  apiCalls++;return url.includes('/'+first+'/')?new Response('',{status:403}):Response.json(tree);
 };
 const read=()=>readRepositoryTrees([first,second],{now,fetcher,allowMissing:true,isolateFailures:true});
 assert.deepEqual(await read(),[null,tree]);assert.equal(apiCalls,2);
 assert.deepEqual(await read(),[null,tree]);assert.equal(apiCalls,3);
 await assert.rejects(()=>readRepositoryTrees([first],{now,fetcher,allowMissing:true}),e=>e.code==='repository_http_403'&&e.deferred===true);
 assert.equal(apiCalls,3);
});
