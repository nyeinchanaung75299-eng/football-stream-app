
import test from 'node:test';
import assert from 'node:assert/strict';
import {darkbyteFixtureScopeVerified,scopedHubRevision,repositoryFixtureScope} from '../supabase/functions/_shared/repository_snapshot_removals.mjs';
const tree={truncated:false,tree:Array.from({length:6},(_,i)=>({type:'blob',path:'provider_'+(i+1)+'/live_events.json'}))};
const darkbyte='darkbyteprojects/iptv_png',other='Roshavarma/cfy',digest='a'.repeat(64),highlight='provider_6/highlights.json';
test('highlight-only failure does not block a verified fixture snapshot',()=>{
 assert.equal(darkbyteFixtureScopeVerified(tree,[highlight]),true);
 assert.deepEqual(repositoryFixtureScope({status:'partial',revision:scopedHubRevision(digest,true),unavailable_repositories:[darkbyte]}),{complete:true,missingRepositories:[]});
});
test('any failed or absent fixture file prevents fixture-only completion',()=>{
 assert.equal(darkbyteFixtureScopeVerified(tree,[highlight,'provider_1/live_events.json']),false);
 assert.equal(darkbyteFixtureScopeVerified({...tree,tree:tree.tree.slice(1)},[highlight]),false);
 assert.equal(darkbyteFixtureScopeVerified({...tree,truncated:true},[highlight]),false);
 assert.equal(repositoryFixtureScope({status:'partial',revision:digest,unavailable_repositories:[darkbyte]}).complete,false);
});
test('other source failures and unknown states remain partial',()=>{
 assert.deepEqual(repositoryFixtureScope({status:'partial',revision:scopedHubRevision(digest,true),unavailable_repositories:[darkbyte,other]}),{complete:false,missingRepositories:[other]});
 assert.equal(repositoryFixtureScope({status:'unavailable',revision:scopedHubRevision(digest,true),unavailable_repositories:[darkbyte]}).complete,false);
 assert.equal(repositoryFixtureScope({status:'partial',revision:digest,unavailable_repositories:[]}).complete,false);
});
