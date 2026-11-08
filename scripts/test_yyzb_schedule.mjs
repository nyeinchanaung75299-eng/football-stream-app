import {test} from 'node:test';
import assert from 'node:assert/strict';
import {loadYyzbSchedules} from '../supabase/functions/_shared/yyzb_schedule.mjs';
import {sourceMatchRows,isFootballSourceRow} from '../supabase/functions/_shared/source_match_rows.mjs';
const live={scheduleId:1,categoryId:1,hostName:'Napoli',guestName:'Lazio',anchors:[{anchor:{roomNum:'101'}}]};
const future={...live,scheduleId:2,hostName:'Heidenheim'};
test('YYZB includes live-only football, future rooms and merged featured rooms without NCA match filtering',async()=>{
 const payload=await loadYyzbSchedules(async url=>JSON.stringify({code:0,data:{0:url.includes('match_all')?[future]:[live,{...future,anchors:[{anchor:{roomNum:'102'}}]},{...live,scheduleId:3,categoryId:2}]}}));
 const rows=sourceMatchRows(payload.data,isFootballSourceRow);
 assert.deepEqual(rows.map(r=>r.scheduleId),[1,2]);assert.equal(rows[1].anchors.length,2);assert.equal(payload.partial,false);
});
test('a failed YYZB export preserves the available independent room catalogue; both failures reject',async()=>{
 const payload=await loadYyzbSchedules(async url=>{if(url.includes('match_all'))throw Error('Unavailable');return 'callback('+JSON.stringify({code:0,data:[live]})+');';});
 assert.equal(payload.partial,true);assert.equal(sourceMatchRows(payload.data,isFootballSourceRow).length,1);
 await assert.rejects(()=>loadYyzbSchedules(async()=>'<html>error</html>'));
});
