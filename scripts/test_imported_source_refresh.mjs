import test from 'node:test';import assert from 'node:assert/strict';
import {refreshImportedSources,selectRenewedLine} from '../cloudflare/public-api/src/imported_source_refresh.mjs';
const row={link_id:'saved',source:'soco',config_hash:'hash',last_resolved_at:'2020-01-01',selector:{label:'HD',stream_type:'hls',resolution:'1080p'}};
test('renewal claims once, chooses same quality and only updates the stored row',async()=>{
 const calls=[];const result=await refreshImportedSources({imported_sources:[row]},
 {rpc:async(name,fields)=>{calls.push([name,fields]);return name.startsWith('claim')?{refresh_lease:'lease'}:true;},
 resolve:async()=>({lines:[{label:'HD',resolution:'1080p',stream_type:'hls',url:'https://cdn.example/new.m3u8'}]})});
 assert.equal(result,true);assert.deepEqual(calls.map(c=>c[0]),['claim_imported_source_refresh','apply_imported_source_refresh']);
 assert.equal(calls[1][1].p_link_id,'saved');
});
test('ambiguous qualities and verification failures never switch to an arbitrary line',async()=>{
 assert.equal(selectRenewedLine([{stream_type:'hls',label:'Other',url:'https://cdn.example/1'},{stream_type:'hls',label:'Different',url:'https://cdn.example/2'}],row.selector),null);
 let writes=0;await refreshImportedSources({imported_sources:[row]},{rpc:async(name)=>{writes++;return {refresh_lease:'lease'};},resolve:async()=>{throw Error('verification required');}});assert.equal(writes,1);
});
test('fresh and recently attempted lines do not consume resolver requests',async()=>{
 let calls=0;await refreshImportedSources({imported_sources:[{...row,last_resolved_at:new Date().toISOString()},{...row,last_attempt_at:new Date().toISOString()}]},
 {rpc:async()=>{calls++;},resolve:async()=>{calls++;}});assert.equal(calls,0);
});

test('a changed single source identity cannot silently replace the imported quality',()=>{
 assert.equal(selectRenewedLine([{label:'Unrelated',stream_type:'hls',resolution:'1080p',url:'https://cdn.example/other.m3u8'}],row.selector),null);
});
test('renewal budget resolves at most two stale imports per explicit stream-list request',async()=>{
 let claims=0;
 await refreshImportedSources({imported_sources:Array.from({length:50},(_,i)=>({...row,link_id:'line-'+i}))},
 {rpc:async(name)=>{claims++;return null;},resolve:async()=>{throw Error('not leased');}});
 assert.equal(claims,2);
});
