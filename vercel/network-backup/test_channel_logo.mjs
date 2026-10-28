import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GET, imageSource, imageType } from './api/channel-logo.js';

const png = Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0]);
const endpoint = 'https://backup.example/api/channel-logo';

test('saved public HTTPS PNG source is allowed; private and invalid sources are rejected', () => {
  assert.equal(imageSource('https://cdn.example.org/logo.png')?.href, 'https://cdn.example.org/logo.png');
  for (const url of ['http://cdn.example.org/logo.png', 'https://127.0.0.1/logo.png',
    'https://service.local/logo.png', 'https://user:pass@cdn.example.org/logo.png']) {
    assert.equal(imageSource(url), null);
  }
  assert.equal(imageType(Buffer.from(png)), 'image/png');
});

test('legacy arbitrary URL stays blocked without a network request', async () => {
  const oldFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw new Error('unexpected fetch'); };
  try {
    const result = await GET(new Request(endpoint + '?url=' +
      encodeURIComponent('https://evil.example.org/p.png')));
    assert.equal(result.status, 404);
    assert.equal(calls, 0);
  } finally { globalThis.fetch = oldFetch; }
});

test('channel ID resolves saved logo and returns verified PNG bytes', async () => {
  const oldFetch = globalThis.fetch;
  const id = '56025ef6-a968-426d-a22c-90cc093eeef2';
  const image = 'https://cdn.example.org/custom.png';
  const called = [];
  globalThis.fetch = async (url, options) => {
    called.push(String(url));
    if (called.length === 1) {
      return Response.json({ channels: [{ id, image_url: image }] });
    }
    assert.equal(String(url), image);
    assert.equal(options.redirect, 'error');
    return new Response(png, { headers: { 'Content-Type': 'image/png' } });
  };
  try {
    const response = await GET(new Request(endpoint + '?id=' + id));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Content-Type'), 'image/png');
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), png);
    assert.equal(called.length, 2);
  } finally { globalThis.fetch = oldFetch; }
});
