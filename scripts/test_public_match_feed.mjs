import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../cloudflare/public-api/src/index.js', import.meta.url), 'utf8') + '\nexport { loadMatchRows, fetchJsonWithTimeout };';
const { default: worker, loadMatchRows, fetchJsonWithTimeout } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const env = { SUPABASE_URL: 'https://database.example', SUPABASE_PUBLISHABLE_KEY: 'test-public-key', GITHUB_MIRROR_URL: 'https://mirror.example/matches.json' };
const match = { id: 'test-match', home_team: 'Team Alpha' };

test('count query failure cannot produce an authoritative zero-line match', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async url => {
    const path = new URL(url).pathname;
    if (path === '/rest/v1/matches') return Response.json([match]);
    if (path === '/rest/v1/match_stream_counts') return new Response('Unavailable', { status: 503 });
    return Response.json([{ ...match, stream_count: 2 }]);
  };
  try {
    const result = await loadMatchRows(env);
    assert.equal(result.source, 'github');
    assert.equal(result.rows[0].stream_count, 2);
  } finally { globalThis.fetch = original; }
});

test('match list and count query start together without a serial round trip', async () => {
  const original = globalThis.fetch;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let countsStarted = false;
  globalThis.fetch = async url => {
    if (new URL(url).pathname === '/rest/v1/matches') {
      await gate; return Response.json([match]);
    }
    countsStarted = true;
    return Response.json([{ match_id: match.id, stream_count: 3 }]);
  };
  try {
    const pending = loadMatchRows(env);
    await new Promise(resolve => setImmediate(resolve));
    const startedInParallel = countsStarted;
    release();
    const result = await pending;
    assert.equal(startedInParallel, true);
    assert.equal(result.rows[0].stream_count, 3);
  } finally { release(); globalThis.fetch = original; }
});

test('an authoritative empty match list stays empty rather than reviving a mirror', async () => {
  const original = globalThis.fetch;
  let mirrorRequests = 0;
  globalThis.fetch = async url => {
    if (new URL(url).host === 'mirror.example') { mirrorRequests++; return Response.json([match]); }
    return Response.json([]);
  };
  try {
    const result = await loadMatchRows(env);
    assert.equal(result.source, 'supabase');
    assert.deepEqual(result.rows, []);
    assert.equal(mirrorRequests, 0);
  } finally { globalThis.fetch = original; }
});

test('empty matches remain authoritative even while the count service is down', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async url => new URL(url).pathname === '/rest/v1/matches'
    ? Response.json([]) : new Response('Unavailable', { status: 503 });
  try {
    const result = await loadMatchRows(env);
    assert.equal(result.source, 'supabase');
    assert.deepEqual(result.rows, []);
  } finally { globalThis.fetch = original; }
});

test('metadata deadline also cancels a body stalled after successful headers', async () => {
  const original = globalThis.fetch;
  let aborted = false;
  globalThis.fetch = async (_, { signal }) => new Response(new ReadableStream({
    start(controller) {
      signal.addEventListener('abort', () => {
        aborted = true;
        controller.error(new DOMException('Aborted', 'AbortError'));
      });
    },
  }));
  try {
    await assert.rejects(fetchJsonWithTimeout('https://database.example', {}, 20), { name: 'AbortError' });
    assert.equal(aborted, true);
  } finally { globalThis.fetch = original; }
});

test('TV schedule relay returns programme metadata only', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async url => {
    const request = new URL(url);
    assert.equal(request.origin, 'https://my-channels-match-guide.vercel.app');
    assert.equal(request.pathname, '/api/schedule');
    assert.equal(request.searchParams.get('date'), '2026-10-29');
    assert.equal(request.searchParams.get('days'), '8');
    return Response.json({
      timezone: 'Asia/Yangon',
      updated_at: '2026-10-29T12:00:00.000Z',
      sources: [{ name: 'au', ok: true, secret: 'not-public' }],
      channels: [{
        id: 'channel-1',
        name: 'TNT Sports 1',
        image_url: 'https://images.example/tnt.png',
        category: 'Sport',
        matchedEPG: true,
        region: 'uk',
        stream_url: 'https://private.example/stream.m3u8?token=secret',
        programmes: [{
          start: 1793275200000,
          end: 1793278800000,
          title: 'Everton vs Newcastle United',
          description: 'Live football',
          drm_key: 'private-key',
        }],
      }],
    });
  };
  try {
    const response = await worker.fetch(
      new Request('https://worker.example/tv-schedule?date=2026-10-29&days=99'),
      env,
      {},
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), '*');
    const body = await response.json();
    assert.equal(body.days, 8);
    assert.equal(body.channels.length, 1);
    assert.equal(body.channels[0].name, 'TNT Sports 1');
    assert.equal(body.channels[0].stream_url, undefined);
    assert.equal(body.channels[0].programmes[0].drm_key, undefined);
    assert.equal(body.sources[0].secret, undefined);
  } finally { globalThis.fetch = original; }
});
