import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import { probeStreamFirstChunk } from '../supabase/functions/_shared/stream_probe.mjs';

const source = readFileSync(new URL('../cloudflare/public-api/src/index.js', import.meta.url), 'utf8') +
  '\nexport { loadStreamMetadata, protectedClientLinks };';
const { default: worker, loadStreamMetadata, protectedClientLinks } = await import(
  'data:text/javascript;base64,' + Buffer.from(source).toString('base64'),
);
const env = {
  SUPABASE_URL: 'https://db.example', SUPABASE_PUBLISHABLE_KEY: 'test-public',
  PLAYBACK_BACKEND_SECRET: 'test-gateway-secret',
};
const matchId = '00000000-0000-4000-8000-000000000001';
const originalFetch = globalThis.fetch;
const realTimeout = globalThis.setTimeout;
const pause = ms => new Promise(resolve => realTimeout(resolve, ms));

function withShortDeadlines() {
  globalThis.setTimeout = (fn, ms, ...args) => realTimeout(fn, ms >= 5000 ? 25 : ms, ...args);
  return () => { globalThis.setTimeout = realTimeout; };
}
function stalledResponse(signal, type = 'application/json') {
  let cancelled = false;
  return new Response(new ReadableStream({
    start(controller) {
      signal.addEventListener('abort', () => {
        if (!cancelled) controller.error(new DOMException('Aborted', 'AbortError'));
      }, { once: true });
    },
    cancel() { cancelled = true; },
  }), { headers: { 'Content-Type': type } });
}

test('stream metadata is one secret-gated RPC and preserves empty versus missing matches', async () => {
  let valid = true;
  let calls = 0;
  globalThis.fetch = async (url, options) => {
    calls++;
    assert.equal(new URL(url).pathname, '/rest/v1/rpc/get_stream_metadata_for_gateway');
    assert.equal(options.method, 'POST');
    assert.deepEqual(JSON.parse(options.body), { p_match_id: matchId, p_secret: env.PLAYBACK_BACKEND_SECRET });
    return Response.json({ match_valid: valid, streams: [] });
  };
  try {
    const request = () => new Request(`https://api.example/matches/${matchId}/streams`);
    const empty = await worker.fetch(request(), env);
    assert.equal(empty.status, 200);
    assert.deepEqual((await empty.json()).streams, []);
    assert.equal(calls, 1);
    valid = false;
    const missing = await worker.fetch(request(), env);
    assert.equal(missing.status, 404);
    assert.equal(calls, 2);
  } finally { globalThis.fetch = originalFetch; }
});

test('only a missing new RPC uses legacy validation; outage does not duplicate requests', async () => {
  const paths = [];
  globalThis.fetch = async url => {
    const path = new URL(url).pathname; paths.push(path);
    if (path.endsWith('get_stream_metadata_for_gateway')) return new Response('', { status: 404 });
    if (path === '/rest/v1/matches') return Response.json([{ id: matchId }]);
    return Response.json([]);
  };
  try {
    assert.deepEqual(await loadStreamMetadata(env, matchId), { match_valid: true, streams: [] });
    assert.equal(paths.length, 3);
    paths.length = 0;
    globalThis.fetch = async url => { paths.push(new URL(url).pathname); return new Response('', { status: 503 }); };
    await assert.rejects(loadStreamMetadata(env, matchId), error => error.status === 503);
    assert.equal(paths.length, 1);
  } finally { globalThis.fetch = originalFetch; }
});

test('stream configuration stops when a successful metadata body stalls', async () => {
  const restore = withShortDeadlines();
  globalThis.fetch = async (_, { signal }) => stalledResponse(signal);
  try {
    await assert.rejects(loadStreamMetadata(env, matchId), { name: 'AbortError' });
  } finally { restore(); globalThis.fetch = originalFetch; }
});

async function protectedUrl(type) {
  const rows = await protectedClientLinks([{
    id: 'line', label: 'test', is_active: true, stream_type: type,
    stream_url: `https://media.example/live.${type === 'dash' ? 'mpd' : type}`,
  }], env, 'https://api.example');
  return rows[0].stream_url;
}

test('DASH manifest body and media headers have deadlines', async () => {
  const restore = withShortDeadlines();
  globalThis.fetch = async (_, { signal }) => stalledResponse(signal, 'application/dash+xml');
  try {
    const response = await worker.fetch(new Request(await protectedUrl('dash')), env);
    assert.equal(response.status, 504);
    globalThis.fetch = async (_, { signal }) => new Promise((_, reject) => {
      signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
    });
    const headers = await worker.fetch(new Request(await protectedUrl('flv')), env);
    assert.equal(headers.status, 504);
  } finally { restore(); globalThis.fetch = originalFetch; }
});

test('continuous media survives past header deadline, preserves Range, and cancels with client', async () => {
  const restore = withShortDeadlines();
  let upstreamSignal;
  let streamController;
  globalThis.fetch = async (_, options) => {
    assert.equal(options.headers.get('Range'), 'bytes=0-1023');
    upstreamSignal = options.signal;
    return new Response(new ReadableStream({ start(controller) { streamController = controller; } }), {
      status: 206, headers: { 'Content-Type': 'video/x-flv', 'Content-Range': 'bytes 0-1023/*' },
    });
  };
  try {
    const client = new AbortController();
    const response = await worker.fetch(new Request(await protectedUrl('flv'), {
      headers: { Range: 'bytes=0-1023' }, signal: client.signal,
    }), env);
    await pause(60);
    assert.equal(upstreamSignal.aborted, false, 'healthy media body must have no fixed lifetime timer');
    streamController.enqueue(new Uint8Array([1, 2, 3]));
    const reader = response.body.getReader();
    assert.deepEqual((await reader.read()).value, new Uint8Array([1, 2, 3]));
    assert.equal(response.headers.get('Content-Range'), 'bytes 0-1023/*');
    client.abort();
    assert.equal(upstreamSignal.aborted, true);
    await reader.cancel();
  } finally { restore(); globalThis.fetch = originalFetch; }
});

test('reachability marks first-chunk timeout, empty body, and body failure as failed', async () => {
  try {
    globalThis.fetch = async (_, { signal }) => stalledResponse(signal);
    const stalled = await probeStreamFirstChunk('https://media.example', { timeoutMs: 20 });
    assert.equal(stalled.status, 'failed');
    assert.equal(stalled.httpStatus, 200);
    assert.match(stalled.detail, /timed out/);
    globalThis.fetch = async () => new Response('');
    assert.equal((await probeStreamFirstChunk('https://media.example')).status, 'failed');
    globalThis.fetch = async () => new Response(new ReadableStream({
      start(controller) { controller.error(new Error('broken body')); },
    }));
    assert.equal((await probeStreamFirstChunk('https://media.example')).status, 'failed');
  } finally { globalThis.fetch = originalFetch; }
});

test('slow first media byte is measured; rejected protected upstream stays unknown', async () => {
  try {
    globalThis.fetch = async () => new Response(new ReadableStream({
      start(controller) { realTimeout(() => controller.enqueue(new Uint8Array([1])), 20); },
    }));
    const slow = await probeStreamFirstChunk('https://media.example', { slowMs: 5 });
    assert.equal(slow.status, 'slow');
    assert.ok(slow.latencyMs >= 5);
    globalThis.fetch = async () => new Response('', { status: 403 });
    assert.equal((await probeStreamFirstChunk('https://media.example')).status, 'unknown');
  } finally { globalThis.fetch = originalFetch; }
});

test('manual and scheduled checks persist a stalled first byte as failed without disabling a line', async () => {
  const originalDeno = globalThis.Deno;
  const restore = withShortDeadlines();
  globalThis.Deno = { serve() {} };
  const sharedUrl = new URL('../supabase/functions/_shared/stream_probe.mjs', import.meta.url);
  globalThis.fetch = async (_, { signal }) => stalledResponse(signal);
  const updates = [];
  const client = {
    from(table) {
      assert.equal(table, 'stream_links');
      return { update(row) { updates.push(row); return { async eq() { return {}; } }; } };
    },
  };
  const line = { id: 'test-line', match_id: matchId, stream_url: 'https://media.example/live.mpd' };
  try {
    for (const [file, exportName] of [
      ['stream-health', 'checkLink'], ['football-score-sync', 'probeStreamLink'],
    ]) {
      let ts = readFileSync(new URL(`../supabase/functions/${file}/index.ts`, import.meta.url), 'utf8')
        .replace(/^import .*jsr:.*;\n/gm, '')
        .replace('"../_shared/stream_probe.mjs"', JSON.stringify(sharedUrl.href));
      ts += `\nexport { ${exportName} };`;
      const mod = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(ts)).toString('base64'));
      await mod[exportName](client, line);
    }
    assert.equal(updates.length, 2);
    for (const row of updates) {
      assert.equal(row.health_status, 'failed');
      assert.ok(row.health_latency_ms >= 20);
      assert.equal('is_active' in row, false, 'reachability failure must remain alert-only');
    }
  } finally { restore(); globalThis.fetch = originalFetch; globalThis.Deno = originalDeno; }
});

test('all four source providers skip Viewer probes without claiming healthy; default extraction probes', async () => {
  const originalDeno = globalThis.Deno;
  let handler;
  globalThis.Deno = { serve(fn) { handler = fn; } };
  const sourceUrl = new URL('../supabase/functions/soco-links/index.ts', import.meta.url);
  const sharedUrl = new URL('../supabase/functions/_shared/stream_probe.mjs', import.meta.url);
  let ts = readFileSync(sourceUrl, 'utf8').replace(/^import .*jsr:.*;\n/gm, '');
  ts = ts.replace('"../_shared/stream_probe.mjs"', JSON.stringify(sharedUrl.href));
  try {
    await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(ts)).toString('base64'));
    let probeCalls = 0;
    globalThis.fetch = async url => {
      const host = new URL(url).host;
      if (host === 'media.example') { probeCalls++; return new Response('#EXTM3U\nsegment.ts\n'); }
      if (host.includes('fawanews.')) return new Response('<video src="https://media.example/live.m3u8"></video>');
      if (host === 'api.cltvlv.com') return Response.json({ code: '0000', data: {
        game: { matchId: 'room1', sportId: 1, videoUrl: 'https://media.example/live.m3u8' },
      } });
      return Response.json({ data: { stream: { m3u8: 'https://media.example/live.m3u8' } } });
    };
    for (const provider of ['soco', 'yyzb', 'fawa', 'cola']) {
      const body = { source: provider, action: 'streams', viewer_public: true,
        room_num: 'room1', page_url: 'http://www.fawanews.sc/game.html', skip_probe: true };
      const response = await handler(new Request('https://backend.example/soco-links', {
        method: 'POST', body: JSON.stringify(body),
      }));
      assert.equal(response.status, 200, provider);
      const payload = await response.json();
      assert.ok(payload.lines.length, provider);
      assert.equal(probeCalls, 0, provider + ' must not wait for media probes');
      assert.equal(payload.lines[0].health_status, 'unknown');
      assert.equal(payload.lines[0].checked_at, null);
      delete body.skip_probe;
      const checked = await handler(new Request('https://backend.example/soco-links', {
        method: 'POST', body: JSON.stringify(body),
      }));
      assert.equal((await checked.json()).lines[0].health_status, 'healthy', provider);
      assert.ok(probeCalls > 0);
      probeCalls = 0;
    }
  } finally { globalThis.fetch = originalFetch; globalThis.Deno = originalDeno; }
});
