import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../cloudflare/public-api/src/index.js', import.meta.url), 'utf8');
const { default: worker } = await import(
  'data:text/javascript;base64,' + Buffer.from(source).toString('base64'),
);
const env = {
  SUPABASE_URL: 'https://backend.example',
  SUPABASE_PUBLISHABLE_KEY: 'test-publishable-key',
  PLAYBACK_BACKEND_SECRET: 'test-playback-secret',
  GITHUB_MIRROR_URL: 'https://mirror.example/matches.json',
};
const matchId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const match = { id: matchId, home_team: 'Home', away_team: 'Away' };
const originalFetch = globalThis.fetch;
let countsStatus = 200;
let countsBody = [];
let mirrorRequests = 0;
globalThis.fetch = async (input) => {
  const url = new URL(input);
  if (url.hostname === 'mirror.example') {
    mirrorRequests += 1;
    return Response.json([{ ...match, stream_count: 4 }]);
  }
  if (url.pathname === '/rest/v1/matches') return Response.json([match]);
  if (url.pathname === '/rest/v1/match_stream_counts') {
    return Response.json(countsBody, { status: countsStatus });
  }
  if (url.pathname === '/rest/v1/rpc/get_stream_links_for_gateway') return Response.json([]);
  throw new Error('Unexpected mock upstream route');
};

try {
  const loadMatches = async () => {
    const response = await worker.fetch(new Request('https://gateway.example/matches'), env, {});
    assert.equal(response.status, 200);
    return response.json();
  };
  countsStatus = 503;
  const unavailableCounts = await loadMatches();
  assert.equal(unavailableCounts.source, 'github');
  assert.equal(unavailableCounts.matches[0].stream_count, 4);
  assert.equal(mirrorRequests, 1);

  countsStatus = 200;
  countsBody = { error: 'invalid count payload' };
  const malformedCounts = await loadMatches();
  assert.equal(malformedCounts.source, 'github');
  assert.equal(malformedCounts.matches[0].stream_count, 4);
  assert.equal(mirrorRequests, 2);

  countsBody = [];
  const authoritativeZero = await loadMatches();
  assert.equal(authoritativeZero.source, 'supabase');
  assert.equal(authoritativeZero.matches[0].stream_count, 0);
  assert.equal(mirrorRequests, 2, 'successful empty counts must not enrich from a stale mirror');

  const streamsResponse = await worker.fetch(new Request(
    'https://gateway.example/matches/' + matchId + '/streams',
  ), env, {});
  assert.equal(streamsResponse.status, 200);
  const streams = await streamsResponse.json();
  assert.equal(streams.ok, true);
  assert.deepEqual(streams.streams, []);
  assert.equal(streams.stream_count, 0);
  assert.equal(streams.playable_stream_count, 0);

  console.log('PASS unavailable stream counts use the mirror fallback');
  console.log('PASS malformed stream counts use the mirror fallback');
  console.log('PASS successful zero counts remain authoritative');
  console.log('PASS published matches with no streams return authoritative empty results');
  console.log('4 public gateway regression checks passed.');
} finally {
  globalThis.fetch = originalFetch;
}
