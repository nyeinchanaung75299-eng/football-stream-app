import test from 'node:test';import assert from 'node:assert/strict';
import {confirmedRepositoryRemovals} from '../supabase/functions/_shared/repository_snapshot_removals.mjs';
test('only absence from completely observed origins proves removal',()=>{
 const previous=[{id:'gone',event_meta:{repositories:['darkbyteprojects/iptv_png','Roshavarma/cfy']}},{id:'keep',event_meta:{repositories:['rohmanabdu/lian']}},{id:'fresh',event_meta:{repositories:['darkbyteprojects/iptv_png']}},{id:'unknown',event_meta:{}}];
 assert.deepEqual(confirmedRepositoryRemovals({entries:[{id:'fresh'}],missingRepositories:['rohmanabdu/lian','rohmanabdu/deqiaa']},previous),['gone']);
});
