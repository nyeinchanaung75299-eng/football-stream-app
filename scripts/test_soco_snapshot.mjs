import test from 'node:test';
import assert from 'node:assert/strict';
import {readSocoSnapshot,refreshSocoSnapshot} from '../cloudflare/public-api/src/soco_snapshot.mjs';
const now=Date.now();
const fixture=JSON.stringify({code:200,data:[{scheduleId:'new',categoryId:1,hostName:'Arsenal',guestName:'Everton',matchTime:now,stream_url:'secret-stream',key_data:'secret-key'}]});
function env(){const values=new Map();return {values,SOURCE_SNAPSHOTS:{get:async(k,type)=>{const v=values.get(k);return type==='json'&&v?JSON.parse(v):v??null;},put:async(k,v)=>values.set(k,v)}};}
test('scheduled transport failure uses a fixed public browser catalog and stores only normalized metadata',async()=>{
 const e=env();let calls=0;
 e.BROWSER={quickAction:async(action,options)=>{calls++;assert.equal(action,'content');assert.equal(options.url,'https://json.vnres.co/matches.json');assert.equal(options.setJavaScriptEnabled,false);return Response.json({success:true,result:'<pre>matches('+fixture+')</pre>'});}};
 const result=await refreshSocoSnapshot(e,{now,fetcher:async()=>new Response('',{status:502})});
 assert.equal(result.ok,true);assert.equal(result.transport,'browser');assert.equal(calls,1);
 const saved=await readSocoSnapshot(e,{now});assert.equal(saved.matches.length,1);assert(!JSON.stringify(saved).includes('secret-'));
});
test('failed refreshes and ordinary reads do not renew a successful snapshot',async()=>{
 const e=env();await refreshSocoSnapshot(e,{now,fetcher:async()=>new Response(fixture)});
 const before=await readSocoSnapshot(e,{now});
 assert.equal((await refreshSocoSnapshot(e,{now:now+60000,fetcher:async()=>new Response('',{status:502})})).ok,false);
 assert.deepEqual(await readSocoSnapshot(e,{now:now+60000}),before);
 assert.equal(await readSocoSnapshot(e,{now:now+16*60000}),null);
});
test('successful empty provider data removes previous matches',async()=>{
 const e=env();await refreshSocoSnapshot(e,{now,fetcher:async()=>new Response(fixture)});
 await refreshSocoSnapshot(e,{now:now+60000,fetcher:async()=>new Response('{"code":200,"data":[]}')});
 assert.deepEqual((await readSocoSnapshot(e,{now:now+60000})).matches,[]);
});
test('browser budget exhaustion never opens a browser or publishes empty success',async()=>{
 const e=env();await e.SOURCE_SNAPSHOTS.put('browser-budget-'+new Date(now).toISOString().slice(0,10),'300000');
 e.BROWSER={quickAction:()=>{assert.fail('budget must block browser launch');}};
 assert.deepEqual(await refreshSocoSnapshot(e,{now,fetcher:async()=>new Response('',{status:403})}),{ok:false,reason:'daily_browser_budget'});
 assert.equal(await readSocoSnapshot(e,{now}),null);
});
