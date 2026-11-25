import test from 'node:test';import assert from 'node:assert/strict';
import {confirmedRepositoryRemovals,unobservedRepositoryEntries} from '../supabase/functions/_shared/repository_snapshot_removals.mjs';
const row=(id,...repositories)=>({id,event_meta:{repositories}});
const active='darkbyteprojects/iptv_png',down='dilzyking/allrounderlive',retired='rohmanabdu/lian';
const before=[row('gone',active),row('live',active),row('uncertain',down),row('retired',retired),row('mixed',retired,active),row('mixed-unavailable',retired,down),row('unknown','unknown/repo'),row('missing-origin')];
test('partial: only observed absence and intentional retirement are removed',()=>{
 const snapshot={complete:false,missingRepositories:[down],entries:[{id:'live'}]};
 assert.deepEqual(confirmedRepositoryRemovals(snapshot,before),['gone','retired','mixed']);
 assert.deepEqual(unobservedRepositoryEntries(snapshot,before).map(x=>x.id),['uncertain','mixed-unavailable','unknown','missing-origin']);
});
test('unknown incomplete snapshot retains all entries',()=>{
 const snapshot={complete:false,missingRepositories:[],entries:[]};
 assert.deepEqual(confirmedRepositoryRemovals(snapshot,before),[]);
 assert.deepEqual(unobservedRepositoryEntries(snapshot,before),before);
});
test('present old fixture is retained regardless of kickoff date',()=>{
 const old={...row('old',active),event_meta:{repositories:[active],kickoff_at:'2026-11-22T11:30:00Z'}};
 assert.deepEqual(confirmedRepositoryRemovals({complete:true,entries:[{id:'old'}]},[old]),[]);
});
