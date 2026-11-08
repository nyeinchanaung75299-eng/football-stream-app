import {test} from 'node:test';
import assert from 'node:assert/strict';
import {loadYyzbFootballCatalogue} from '../supabase/functions/_shared/yyzb_schedule.mjs';
import {sourceMatchRows,isFootballSourceRow} from '../supabase/functions/_shared/source_match_rows.mjs';
const live={scheduleId:1,categoryId:1,hostName:'Napoli',guestName:'Lazio',anchors:[{anchor:{roomNum:'101'}}]};
const future={...live,scheduleId:2,hostName:'Heidenheim'};
test('YYZB matches its original website football catalogue without adding a separate score or NCA schedule',async()=>{
 const calls=[];
 const payload=await loadYyzbFootballCatalogue(async url=>{
  calls.push(url);assert(new URL(url).pathname==='/matches.json');
  return JSON.stringify({code:0,data:{0:[live,future,{...live,scheduleId:3,categoryId:2}],hot:[{...future,anchors:[{anchor:{roomNum:'102'}}]}]}});
 });
 const rows=sourceMatchRows(payload.data,isFootballSourceRow);
 assert.deepEqual(rows.map(r=>r.scheduleId),[1,2]);assert.equal(rows[1].anchors.length,2);assert.equal(calls.length,1);
});
test('YYZB JSONP is accepted and an unavailable original catalogue is an error, not a different source',async()=>{
 const payload=await loadYyzbFootballCatalogue(async()=> 'callback('+JSON.stringify({code:0,data:[live]})+');');
 assert.equal(sourceMatchRows(payload.data,isFootballSourceRow).length,1);
 await assert.rejects(()=>loadYyzbFootballCatalogue(async()=>'<html>error</html>'));
});
