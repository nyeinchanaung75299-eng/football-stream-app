import {test} from 'node:test';
import assert from 'node:assert/strict';
import {footballHighlights} from '../supabase/functions/_shared/football_highlights.mjs';

test('unavailable uncached match details return metadata only and allow a later retry',async()=>{
  const page='https://dasfootball.com/match/example-home-vs-example-away-2026-11-23-99001999/';
  const entry_id='dasfootball:'+page;
  let available=false, requests=0;
  const fetcher=async address=>{
    assert.equal(address,page);
    requests++;
    if(!available)throw Error('Synthetic source outage');
    return new Response('<title>Example Home vs Example Away | DasFootball</title><button>Highlights</button>',{
      headers:{'Content-Type':'text/html'}
    });
  };
  const failed=await footballHighlights({action:'details',entry_id},{fetcher});
  assert.equal(failed.ok,true);
  assert.equal(failed.entry.details_status,'unavailable');
  assert.equal(failed.entry.source_page_url,page);
  assert.equal(failed.entry.source_page_only,true);
  assert.deepEqual(failed.entry.lines,[]);
  await assert.rejects(footballHighlights({action:'check',entry_id,line_id:'unknown'},{fetcher}),/Normal highlights were not confirmed/);
  available=true;
  const recovered=await footballHighlights({action:'details',entry_id},{fetcher});
  assert.equal(recovered.ok,true);
  assert.equal(recovered.entry.details_status,undefined);
  assert.equal(recovered.entry.title,'Example Home vs Example Away');
  assert.deepEqual(recovered.entry.lines,[]);
  assert.equal(requests,3);
});
