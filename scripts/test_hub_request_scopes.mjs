import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {REPOSITORY_TREE_SOURCES} from '../supabase/functions/_shared/repository_trees.mjs';
const path=new URL('../supabase/functions/channel-source-sync/index.ts',import.meta.url);
let code=readFileSync(path,'utf8').replace(/^import .*jsr:.*;\n/gm,'')
 .replace(/(['"])(\.\.\/_shared\/[^'"]+\.mjs)\1/g,(_,q,p)=>JSON.stringify(new URL(p,path).href));
code='const createClient=()=>{throw Error("No external database");};\n'+code;
const before=globalThis.Deno;globalThis.Deno={serve:()=>{},env:{get:()=>''}};
const {channelSourceRequest}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(code)).toString('base64'));
globalThis.Deno=before;
function fixture(role='admin'){
 const sha='a'.repeat(40),rows=REPOSITORY_TREE_SOURCES.map((repository,i)=>({id:i===2?'gh:smsports:'+('c'.repeat(28)):'cached-'+i,kind:i===2?'event':'channel',source_id:'darkbyte',is_present:true,provider:1,name:'Catalog '+i,category:'Sports',source_file:'fixture.json',unsupported_count:0,streams:[],event_meta:{source_repository:repository,source_revision:sha,catalog_schema_version:3,
  ...(i===2?{source_category:'UFC',league:'UFC 323',home_team:'Fighter A',away_team:'Fighter B',kickoff_at:'2026-11-22T17:00:00Z',end_at:'2026-11-22T19:00:00Z'}:{})}}));
 const state={id:'darkbyte',status:'ok',enabled:true,revision:'fixture',last_checked_at:'2026-11-22T00:00:00Z',catalog_schema_version:3,unavailable_repositories:[]};
 const rpcs=[];
 const client={auth:{getUser:async()=>({data:{user:{id:'owner'}}})},from(table){
  const conditions=[];let start=0,end=9999,one=false;
  const query={select(){return query;},eq(k,v){conditions.push([k,v]);return query;},order(){return query;},range(a,b){start=a;end=b;return query;},single(){one=true;return query;},maybeSingle(){return query;},
   then(resolve,reject){const data=table==='profiles'?{role}:table==='channel_source_state'?state:rows.filter(row=>conditions.every(([k,v])=>row[k]===v)).slice(start,end+1);return Promise.resolve({data:one&&Array.isArray(data)?data[0]:data,error:null}).then(resolve,reject);}};
  return query;
 },async rpc(name,args){rpcs.push({name,args});return {data:name==='begin_connected_channel_source_sync'?{lease:'fixture-lease'}:{ok:true,entry_count:args.p_entries.length},error:null};}};
 return {client,rows,rpcs,sha};
}
const req=body=>new Request('https://api.example.org/source-sync',{method:'POST',headers:{authorization:'Bearer fixture','Content-Type':'application/json'},body:JSON.stringify(body)});
test('Hub refresh retains channel rows while combat reads only committed events without running sync',async()=>{
 const f=fixture(),previousFetch=globalThis.fetch;
 globalThis.fetch=async address=>{assert(String(address).endsWith('repository-trees.json'));return Response.json({fetched_at:new Date().toISOString(),repositories:Object.fromEntries(REPOSITORY_TREE_SOURCES.map(repo=>[repo,{sha:f.sha,truncated:false,tree:[]}]))});};
 try{
  const response=await channelSourceRequest(req({action:'sync'}),f.client);assert.equal(response.status,200);
  const committed=f.rpcs.find(r=>r.name==='commit_stream_hub_snapshot').args.p_entries;
  assert.equal(committed.length,f.rows.length);assert(committed.some(row=>row.kind==='channel'));
  f.rpcs.length=0;globalThis.fetch=()=>{throw Error('Combat browsing must not fetch GitHub');};
  const combat=await channelSourceRequest(req({action:'combat_catalog'}),f.client);const data=await combat.json();
  assert.equal(combat.status,200);assert.equal(data.total,1);assert.equal(data.entries[0].category,'ufc');assert.equal(data.entries[0].lines,undefined);
  assert.equal(f.rpcs.length,0);
  const details=await channelSourceRequest(req({action:'details',entry_id:f.rows[2].id}),f.client);assert.equal(details.status,200);assert.equal((await details.json()).entry.id,f.rows[2].id);
  assert.equal((await channelSourceRequest(req({action:'details',entry_id:'gh:foreign:'+('c'.repeat(28))}),f.client)).status,400);
  assert.equal((await channelSourceRequest(req({action:'combat_catalog'}),fixture('viewer').client)).status,403);
 }finally{globalThis.fetch=previousFetch;}
});
