import assert from 'node:assert/strict';
import test from 'node:test';
import {createMonitor, encryptSecret, decryptSecret, lineSummary, redact, endpointName} from '../supabase/functions/system-monitor/core.mjs';

const user = '11111111-1111-4111-8111-111111111111';
const env = {SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_ANON_KEY:'public-fixture',
  SUPABASE_SERVICE_ROLE_KEY:'server-only-fixture'};
const req = (body={},token='valid-session') => new Request('https://monitor.invalid',{
  method:'POST',headers:token ? {Authorization:'Bearer '+token,'Content-Type':'application/json'} : {},
  body:JSON.stringify(body)});
function fixture({role='admin',connections=[],cache=[],providerStatus=200,githubStatus=200,authStatus=200}={}) {
  const calls = []; const writes = [];
  const fetcher = async (input,options={}) => {
    const url = new URL(input); calls.push({url:url.href,options});
    const json = (data,status=200,headers={}) => Response.json(data,{status,headers});
    if (url.pathname === '/auth/v1/user') return json(authStatus === 200 ? {id:user} : {},authStatus);
    if (url.pathname === '/rest/v1/profiles') {
      assert.equal(options.headers.Authorization,'Bearer valid-session');
      assert.equal(options.headers.apikey,'public-fixture'); return json([{role}]);
    }
    if (url.pathname.startsWith('/rest/v1/')) {
      assert.equal(options.headers.apikey,'server-only-fixture');
      if (options.method === 'POST') { writes.push(JSON.parse(options.body)); return new Response(null,{status:204}); }
      if (url.pathname.endsWith('system_monitor_connections')) return json(connections);
      if (url.pathname.endsWith('system_monitor_cache')) return json(cache);
      if (url.pathname.endsWith('matches')) return json([{id:'match'}],200,{'Content-Range':'0-0/4'});
      if (url.pathname.endsWith('stream_links')) return json([{
        label:'Line A',stream_type:'dash',health_status:'failed',health_failure_streak:3,
        health_total_failures:7,last_checked_at:new Date().toISOString(),
        stream_url:'https://upstream.invalid/private?token=playback-secret',
        matches:{home_team:'Team A',away_team:'Team B',source:'fixtures'}}],200,{'Content-Range':'0-0/1'});
    }
    if (url.host === 'api.github.com') return json({workflow_runs:[{status:'in_progress',conclusion:null,
      head_sha:'abcdef123456789',html_url:'https://github.com/'+user,updated_at:new Date().toISOString()}]},githubStatus);
    if (url.host === 'us.posthog.com') {
      assert.equal(options.headers.Authorization,'Bearer read-provider-fixture');
      if (providerStatus !== 200) return json({error:'secret should not be returned'},providerStatus);
      const query = JSON.parse(options.body).query.query;
      return json({results:query.startsWith('SELECT event, count()')
        ? [['$exception',3,2],['playback buffering',5,2]] : []});
    }
    throw new Error('Unexpected request '+url);
  };
  return {handler:createMonitor(env,{fetcher}),calls,writes};
}
test('Missing and rejected sessions cannot start privileged reads',async()=>{
  const f=fixture({authStatus:401});
  assert.equal((await f.handler(req({},null))).status,401);
  assert.equal(f.calls.length,0);
  assert.equal((await f.handler(req({},'forged'))).status,401);
  assert.ok(f.calls.every(c=>c.url.endsWith('/auth/v1/user')));
});
test('Current database role is required, even with a valid session',async()=>{
  const f=fixture({role:'viewer'});
  assert.equal((await f.handler(req({action:'connect',provider:'posthog',secret:'should-not-be-used'}))).status,403);
  assert.equal(f.calls.length,2);assert.equal(f.writes.length,0);
});
test('Live Admin summary distinguishes running builds and missing monitoring connections',async()=>{
  const f=fixture();const response=await f.handler(req());assert.equal(response.status,200);
  const data=await response.json();
  assert.deepEqual(data.services.find(s=>s.id==='supabase').metrics.matches,4);
  assert.equal(data.services.find(s=>s.id==='github').runs[0].state,'in_progress');
  assert.equal(data.services.find(s=>s.id==='github').state,'running');
  assert.ok(data.services.filter(s=>['posthog','cloudflare','vercel','google-drive'].includes(s.id))
    .every(s=>s.state==='not_configured' && !s.metrics));
  assert.equal(data.streams.counts.alerts,1);
  assert.equal(data.streams.lines[0].source,'upstream.invalid');
  const text=JSON.stringify(data);
  for(const secret of ['server-only-fixture','valid-session','playback-secret','encrypted_secret']) assert.ok(!text.includes(secret));
  assert.equal(response.headers.get('Cache-Control'),'private, no-store');
});
test('Read credential is verified, encrypted and never returned',async()=>{
  const f=fixture();
  const response=await f.handler(req({action:'connect',provider:'posthog',
    config:{projectId:'646885',region:'us',host:'https://attacker.invalid'},secret:'read-provider-fixture'}));
  assert.equal(response.status,200);
  const saved=f.writes.find(w=>w.p_encrypted_secret);
  assert.ok(saved);assert.ok(!saved.p_encrypted_secret.includes('read-provider-fixture'));
  assert.deepEqual(saved.p_config,{projectId:'646885',region:'us'});
  assert.equal(await decryptSecret(saved.p_encrypted_secret,env.SUPABASE_SERVICE_ROLE_KEY,'posthog'),'read-provider-fixture');
  assert.ok(!(await response.text()).includes('read-provider-fixture'));
  assert.ok(f.calls.every(c=>!c.url.includes('attacker')));
});
test('Invalid read access or a public SDK token cannot replace a connection',async()=>{
  const f=fixture({providerStatus:403});
  assert.equal((await f.handler(req({action:'connect',provider:'posthog',
    config:{projectId:'646885'},secret:'read-provider-fixture'}))).status,422);
  assert.equal(f.writes.length,0);
  assert.equal((await f.handler(req({action:'connect',provider:'posthog',
    config:{projectId:'646885'},secret:'phc_public-ingest-only'}))).status,400);
});
test('Failed provider refresh preserves unavailable state rather than inventing zero errors',async()=>{
  const encrypted=await encryptSecret('read-provider-fixture',env.SUPABASE_SERVICE_ROLE_KEY,'posthog');
  const f=fixture({providerStatus:403,connections:[{provider:'posthog',config:{projectId:'646885'},encrypted_secret:encrypted}],
    cache:[{provider:'posthog',collected_at:'2020-01-01T00:00:00Z',summary:{events:[{event:'$exception',count:9}]}}]});
  const data=await(await f.handler(req())).json();const p=data.services.find(s=>s.id==='posthog');
  assert.equal(p.state,'needs_access');assert.equal(p.events,undefined);
  assert.equal(p.lastKnown.events[0].count,9);assert.ok(!JSON.stringify(data).includes('read-provider-fixture'));
});
test('Encryption rejects swapped providers, changed ciphertext and wrong server keys',async()=>{
  const encrypted=await encryptSecret('fixture',env.SUPABASE_SERVICE_ROLE_KEY,'posthog');
  await assert.rejects(decryptSecret(encrypted,env.SUPABASE_SERVICE_ROLE_KEY,'cloudflare'));
  await assert.rejects(decryptSecret(encrypted,'wrong','posthog'));
  const parts=encrypted.split('.');parts[2]=(parts[2][0]==='A'?'B':'A')+parts[2].slice(1);
  await assert.rejects(decryptSecret(parts.join('.'),env.SUPABASE_SERVICE_ROLE_KEY,'posthog'));
});
test('Only fresh three-failure streaks alert; stale/missing checks cannot look healthy',()=>{
  const now=Date.now();const rows=[
    {label:'fresh fail',health_status:'failed',health_failure_streak:3,last_checked_at:new Date(now).toISOString()},
    {label:'single fail',health_status:'failed',health_failure_streak:1,last_checked_at:new Date(now).toISOString()},
    {label:'old healthy',health_status:'healthy',last_checked_at:'2020-01-01T00:00:00Z'},
    {label:'unchecked',health_status:'healthy'},
  ];
  const data=lineSummary(rows,rows.length,now);
  assert.equal(data.counts.alerts,1);assert.equal(data.counts.healthy,0);assert.equal(data.counts.stale,2);
  assert.ok(data.lines.every(r=>!Object.hasOwn(r,'is_active')));
});
test('Shareable error text and endpoint names omit protected credentials',()=>{
  const text=redact('https://x.invalid/p/token?key=secret email@example.com Bearer eyJabc.abcdef.signature api_key=secret phx_abc');
  for(const s of ['token?key','email@example.com','eyJabc','api_key=secret','phx_abc']) assert.ok(!text.includes(s));
  assert.equal(endpointName('https://worker.invalid/p/protected-token/file.m4s?secret=x'),'/p/:token/:media');
});
