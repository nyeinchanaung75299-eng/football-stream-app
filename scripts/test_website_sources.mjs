import {test} from 'node:test';
import assert from 'node:assert/strict';
import {websiteMatches,websiteStreams} from '../supabase/functions/_shared/website_sources.mjs';
test('unsupported website providers cannot fetch metadata or player pages',async()=>{
 const fetcher=()=>{throw Error('Unexpected provider request');};
 await assert.rejects(()=>websiteMatches('unsupported',{fetcher}),/Unsupported/);
 await assert.rejects(()=>websiteStreams('unsupported',{}, {fetcher}),/Unsupported/);
 await assert.rejects(()=>websiteMatches('totalsportek',{fetcher}),/Unsupported/);
 await assert.rejects(()=>websiteStreams('totalsportek',{}, {fetcher}),/Unsupported/);
});
