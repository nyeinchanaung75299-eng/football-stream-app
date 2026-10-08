import assert from 'node:assert/strict';
import test from 'node:test';
import { GET as proxy } from './api/proxy.js';

const origin = 'https://backup.example';
const backend = 'https://supabase-api.nyeinchanaung.us.ci';
const worker = 'https://football-public-api.nyeinchanaung75299-eng.workers.dev';

async function withFetch(stub, action) {
  const previous = globalThis.fetch;
  globalThis.fetch = stub;
  try { return await action(); } finally { globalThis.fetch = previous; }
}

test('Auth credentials, user JWTs, REST writes and count headers pass through unchanged', async () => {
  const seen = [];
  await withFetch(async (url, init) => {
    seen.push({ url: String(url), method: init.method, headers: init.headers,
      body: init.body ? await new Response(init.body).text() : null });
    if (String(url).includes('/auth/')) return Response.json({ access_token: 'test-user-jwt' });
    return new Response('[]', { status: 200, headers: { 'Content-Type': 'application/json', 'Content-Range': '0-0/12' } });
  }, async () => {
    const loginBody = JSON.stringify({ email: 'test@example.invalid', password: 'fixture-password' });
    const login = await proxy(new Request(origin + '/api/proxy?route=auth/v1/token&grant_type=password', {
      method: 'POST', headers: { apikey: 'test-publishable-key', 'Content-Type': 'application/json', Cookie: 'private-cookie' }, body: loginBody,
    }));
    assert.equal((await login.json()).access_token, 'test-user-jwt');
    assert.equal(seen[0].url, backend + '/auth/v1/token?grant_type=password');
    assert.equal(seen[0].body, loginBody);
    assert.equal(seen[0].headers.get('apikey'), 'test-publishable-key');
    assert.equal(seen[0].headers.has('Cookie'), false);

    const write = await proxy(new Request(origin + '/api/proxy?route=rest/v1/matches&ncaPath=matches&id=eq.test&path=eq.fixture', {
      method: 'PATCH', headers: { Authorization: 'Bearer test-user-jwt', apikey: 'test-publishable-key', Prefer: 'return=representation', 'Content-Type': 'application/json' },
      body: '{"is_featured":true}',
    }));
    assert.equal(seen[1].method, 'PATCH');
    assert.equal(seen[1].url, backend + '/rest/v1/matches?id=eq.test&path=eq.fixture');
    assert.equal(seen[1].headers.get('Authorization'), 'Bearer test-user-jwt');
    assert.equal(seen[1].headers.get('Prefer'), 'return=representation');
    assert.equal(write.headers.get('Content-Range'), '0-0/12');
    assert.equal(write.headers.get('Cache-Control'), 'no-store');
    assert.match(write.headers.get('Access-Control-Expose-Headers'), /Content-Range/);
    await write.body.cancel();
  });
});

test('Admin authorization stays with the original Worker and unsupported proxy targets are rejected', async () => {
  let requests = 0;
  await withFetch(async (url, init) => {
    requests += 1;
    assert.equal(String(url), worker + '/admin/functions/football-fixtures');
    assert.equal(init.headers.get('Authorization'), 'Bearer non-admin-fixture');
    return Response.json({ error: 'Admin access required.' }, { status: 403 });
  }, async () => {
    const unauthenticated = await proxy(new Request(origin + '/admin/functions/football-fixtures', { method: 'POST', body: '{}' }));
    assert.equal(unauthenticated.status, 401);
    assert.equal(requests, 0);
    const unauthorized = await proxy(new Request(origin + '/admin/functions/football-fixtures', {
      method: 'POST', headers: { Authorization: 'Bearer non-admin-fixture' }, body: '{}',
    }));
    assert.equal(unauthorized.status, 403);
    await unauthorized.body.cancel();
    for (const path of ['/api/proxy?route=https://evil.invalid/', '/api/proxy?route=p/token/../../auth/v1/token', '/api/proxy?route=rest/v1/matches&route=p/token', '/functions/v1/unlisted-function']) {
      const response = await proxy(new Request(origin + path));
      assert.ok([400, 404].includes(response.status), path);
    }
    assert.equal(requests, 1);
  });
});

test('Protected metadata stays on the reachable backup and binary range responses stay intact', async () => {
  await withFetch(async (url, init) => {
    assert.equal(init.headers.has('Authorization'), false);
    assert.equal(init.headers.has('apikey'), false);
    if (String(url).includes('/matches/')) return Response.json({ streams: [{ stream_url: worker + '/p/test-token/manifest.mpd' }] });
    assert.equal(init.headers.get('Range'), 'bytes=0-3');
    return new Response(Uint8Array.from([0, 255, 1, 128]), { status: 206, headers: { 'Content-Type': 'video/mp4', 'Content-Range': 'bytes 0-3/100', 'Accept-Ranges': 'bytes' } });
  }, async () => {
    const lines = await proxy(new Request(origin + '/matches/test/streams', { headers: { Authorization: 'Bearer private-fixture', apikey: 'private-fixture' } }));
    assert.equal((await lines.json()).streams[0].stream_url, origin + '/p/test-token/manifest.mpd');
    const data = await proxy(new Request(origin + '/p/test-token/segment.mp4', { headers: { Range: 'bytes=0-3' } }));
    assert.equal(data.status, 206);
    assert.equal(data.headers.get('Content-Range'), 'bytes 0-3/100');
    assert.deepEqual(new Uint8Array(await data.arrayBuffer()), Uint8Array.from([0, 255, 1, 128]));
  });
});

test('Metadata HEAD works with a GET-only upstream and has no response body', async () => {
  await withFetch(async (_, init) => {
    assert.equal(init.method, 'GET');
    return Response.json({ ok: true });
  }, async () => {
    const response = await proxy(new Request(origin + '/health', { method: 'HEAD' }));
    assert.equal(response.status, 200);
    assert.equal(await response.text(), '');
  });
});

test('The header timeout does not cut a healthy continuous media stream after 20 seconds', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let signal;
  let stream;
  await withFetch(async (_, init) => {
    signal = init.signal;
    return new Response(new ReadableStream({ start(controller) { stream = controller; } }), { headers: { 'Content-Type': 'video/x-flv' } });
  }, async () => {
    const response = await proxy(new Request(origin + '/p/test-token/video.flv'));
    t.mock.timers.tick(30000);
    assert.equal(signal.aborted, false);
    stream.enqueue(Uint8Array.from([70, 76, 86]));
    stream.close();
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), Uint8Array.from([70, 76, 86]));
  });
});

test('Metadata body stalls time out and public service probes cannot claim an OAuth connection', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const logged = [];
  t.mock.method(console, 'error', (...args) => logged.push(args));
  await withFetch(async (_, init) => new Response(new ReadableStream({
    start(controller) { init.signal.addEventListener('abort', () => controller.error(new DOMException('fixture-token', 'AbortError'))); },
  }), { headers: { 'Content-Type': 'application/json' } }), async () => {
    const pending = proxy(new Request(origin + '/matches'));
    await Promise.resolve(); await Promise.resolve();
    t.mock.timers.tick(20000);
    const response = await pending;
    assert.equal(response.status, 504);
    assert.equal(JSON.stringify(logged).includes('fixture-token'), false);
  });
  const targets = [];
  await withFetch(async (url) => {
    targets.push(String(url));
    return new Response(null, { status: String(url).includes('googleapis') ? 401 : 200 });
  }, async () => {
    const response = await proxy(new Request(origin + '/service-health'));
    const result = await response.json();
    assert.equal(result.scope, 'service-reachability-via-vercel');
    assert.equal(result.results.find(row => row.service === 'google-drive').http, 401);
    assert.equal(targets.length, 4);
    assert.equal(JSON.stringify(result).includes('connected'), false);
  });
});
