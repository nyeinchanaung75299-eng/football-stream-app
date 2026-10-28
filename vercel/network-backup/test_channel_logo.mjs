import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GET } from './api/channel-logo.js';

const endpoint = 'https://backup.example/api/channel-logo?url=';
const logo = 'https://images.fotmob.com/image_resources/logo/leaguelogo/dark/133.png';

test('only the intended image host and path can be fetched', async () => {
  const oldFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw new Error('should not fetch'); };
  try {
    for (const url of [
      'https://127.0.0.1/image_resources/logo/a.png',
      'https://images.fotmob.com.evil.test/image_resources/logo/a.png',
      'https://images.fotmob.com/private/a.png',
      'https://thumb.wikimedia.org/wikipedia/commons/thumb/a.png?redirect=evil',
    ]) {
      const response = await GET(new Request(endpoint + encodeURIComponent(url)));
      assert.equal(response.status, 400);
    }
    assert.equal(calls, 0);
  } finally { globalThis.fetch = oldFetch; }
});

test('valid small image is relayed with an image content type', async () => {
  const oldFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url.href, logo);
    assert.equal(options.redirect, 'error');
    return new Response(new Uint8Array([137, 80, 78, 71]), {
      headers: { 'Content-Type': 'image/png' },
    });
  };
  try {
    const response = await GET(new Request(endpoint + encodeURIComponent(logo)));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Content-Type'), 'image/png');
    assert.equal((await response.arrayBuffer()).byteLength, 4);
  } finally { globalThis.fetch = oldFetch; }
});
