import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
let handler,role='admin';const writes=[];const id='11111111-1111-4111-8111-111111111111';
const db={auth:{async getUser(){return {data:{user:{id,user_metadata:{role:'admin'}}}};}},
 from(table){const q={select(){return q;},eq(){return q;},in(){return q;},update(row){writes.push(row);return q;},
  async single(){return {data:table==='profiles'?{role}:{id,stream_url:'https://cdn.example.org/private.mpd',stream_type:'dash'}};},
  async maybeSingle(){return {data:null};},then(resolve){resolve({data:null});}};return q;},
 async rpc(name){return {data:name==='channel_line_config_hash'?'current-version':name==='channel_health_job_status'?{status:'completed',checked:10}:[]};}};
globalThis.__healthTestClient=db;
const oldDeno=globalThis.Deno;
globalThis.Deno={serve(fn){handler=fn;},env:{get(name){return {SUPABASE_URL:'https://backend.example.org',SUPABASE_ANON_KEY:'fixture-public',SUPABASE_SERVICE_ROLE_KEY:'fixture-private'}[name];}}};
let code=readFileSync(new URL('../supabase/functions/stream-health/index.ts',import.meta.url),'utf8')
 .replace(/^import .*jsr:.*;\n/gm,'')
 .replace(/(['"])(\.\.\/_shared\/[^'"]+\.mjs)\1/g,(_,q,path)=>JSON.stringify(new URL('../supabase/functions/'+path.replace(/^\.\.\//,''),import.meta.url).href));
code='const createClient=()=>globalThis.__healthTestClient;\n'+code;
await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(code)).toString('base64'));
const request=(body,auth=true)=>new Request('https://backend.example.org/stream-health',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer fixture'}:{})},body:JSON.stringify(body)});
test('anonymous and Viewer sessions cannot preview private lines, start jobs or record playback',async()=>{
 for(const action of ['preview','start_job','record_playback']){
  assert.equal((await handler(request({action,channel_line_id:id},false))).status,401);
  role='viewer';assert.equal((await handler(request({action,channel_line_id:id}))).status,401);
 }
 role='admin';assert.equal(writes.length,0);
});
test('Admin playback verification needs the current version and decoded frames',async()=>{
 role='admin';
 const base={action:'record_playback',channel_line_id:id,status:'verified',version:'current-version',frames:0,width:640,height:360,advanced:1};
 assert.equal((await handler(request(base))).status,400);
 assert.equal((await handler(request({...base,frames:4,version:'old-version'}))).status,409);
 assert.equal((await handler(request({...base,frames:4}))).status,200);
 assert.equal(writes.at(-1).playback_status,'verified');
 const preview=await handler(request({action:'preview',channel_line_id:id}));assert.equal(preview.status,200);
 assert.equal((await preview.json()).version,'current-version');
});
test.after(()=>{globalThis.Deno=oldDeno;delete globalThis.__healthTestClient;});
