import test from 'node:test';import assert from 'node:assert/strict';
import {confirmedRepositoryRemovals,unobservedRepositoryEntries} from '../supabase/functions/_shared/repository_snapshot_removals.mjs';
test('only absence from completely observed origins proves removal',()=>{
 const previous=[{id:'gone',event_meta:{repositories:['darkbyteprojects/iptv_png','Roshavarma/cfy']}},{id:'keep',event_meta:{repositories:['rohmanabdu/lian']}},{id:'fresh',event_meta:{repositories:['darkbyteprojects/iptv_png']}},{id:'unknown',event_meta:{}}];
 assert.deepEqual(confirmedRepositoryRemovals({entries:[{id:'fresh'}],missingRepositories:['rohmanabdu/lian','rohmanabdu/deqiaa']},previous),['gone']);
});

test('a missing unrelated repository does not preserve obsolete URLs from healthy origins',()=>{
 const rows=[{id:'healthy',event_meta:{repositories:['darkbyteprojects/iptv_png']}},{id:'uncertain',event_meta:{repositories:['rohmanabdu/lian']}}];
 assert.deepEqual(unobservedRepositoryEntries({missingRepositories:['rohmanabdu/lian']},rows).map(x=>x.id),['uncertain']);
});
