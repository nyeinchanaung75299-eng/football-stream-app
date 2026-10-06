import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const workerPath = fileURLToPath(
  new URL('../cloudflare/public-api/src/index.js', import.meta.url),
);
const source = readFileSync(workerPath, 'utf8') +
  '\nexport { handleSupabaseRelay };\n';
const mod = await import(
  'data:text/javascript;base64,' + Buffer.from(source).toString('base64')
);
const { handleSupabaseRelay } = mod;

const env = {
  SUPABASE_URL: 'https://project.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'publishable-test-key',
};

const originalFetch = globalThis.fetch;
const OriginalRequest = globalThis.Request;

// Node 24 requires duplex:'half' when a Request is constructed with a
// ReadableStream body. Cloudflare Workers does not require callers to set it,
// so normalize the test runtime without changing production relay behavior.
globalThis.Request = class CompatibleRequest extends OriginalRequest {
  constructor(input, init = undefined) {
    if (init?.body && init.duplex == null) {
      init = {...init, duplex: 'half'};
    }
    super(input, init);
  }
};

const calls = [];

globalThis.fetch = async (input, init) => {
  const request = input instanceof Request
    ? input
    : new Request(input, init);
  const body = request.method === 'GET' || request.method === 'HEAD'
    ? ''
    : await request.clone().text();
  calls.push({
    url: request.url,
    method: request.method,
    headers: Object.fromEntries(request.headers.entries()),
    body,
  });

  if (request.url.endsWith('/rest/v1/')) {
    return new Response('[]', {
      status: 200,
      headers: {'content-type':'application/json'},
    });
  }

  return new Response(
    JSON.stringify({ok:true, path:new URL(request.url).pathname}),
    {
      status: 200,
      headers: {'content-type':'application/json'},
    },
  );
};

try {
  const health = await handleSupabaseRelay(
    new Request('https://supabase-api.example/health'),
    env,
  );
  assert.equal(health.status, 200);
  const healthJson = await health.json();
  assert.equal(healthJson.ok, true);
  assert.equal(healthJson.service, 'supabase-relay');
  assert.equal(calls.at(-1).url, 'https://project.supabase.co/rest/v1/');
  assert.equal(calls.at(-1).headers.apikey, 'publishable-test-key');

  const rest = await handleSupabaseRelay(
    new Request(
      'https://supabase-api.example/rest/v1/matches?select=id&limit=1',
      {
        headers: {
          apikey: 'client-key',
          Authorization: 'Bearer user-token',
          Origin: 'https://viewer.example',
        },
      },
    ),
    env,
  );
  assert.equal(rest.status, 200);
  assert.equal(
    calls.at(-1).url,
    'https://project.supabase.co/rest/v1/matches?select=id&limit=1',
  );
  assert.equal(calls.at(-1).headers.apikey, 'client-key');
  assert.equal(calls.at(-1).headers.authorization, 'Bearer user-token');
  assert.equal(
    rest.headers.get('access-control-allow-origin'),
    'https://viewer.example',
  );

  const auth = await handleSupabaseRelay(
    new Request(
      'https://supabase-api.example/auth/v1/token?grant_type=password',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: 'client-key',
        },
        body: JSON.stringify({email:'test@example.com',password:'secret'}),
      },
    ),
    env,
  );
  assert.equal(auth.status, 200);
  assert.equal(
    calls.at(-1).url,
    'https://project.supabase.co/auth/v1/token?grant_type=password',
  );
  assert.equal(calls.at(-1).method, 'POST');
  assert.match(calls.at(-1).body, /test@example\.com/);

  const preflight = await handleSupabaseRelay(
    new Request('https://supabase-api.example/rest/v1/matches', {
      method: 'OPTIONS',
      headers: {
        Origin: 'https://viewer.example',
        'Access-Control-Request-Headers':
          'authorization,apikey,content-type,x-client-info',
      },
    }),
    env,
  );
  assert.equal(preflight.status, 204);
  assert.match(
    preflight.headers.get('access-control-allow-methods') || '',
    /PATCH/,
  );

  const denied = await handleSupabaseRelay(
    new Request('https://supabase-api.example/not-allowed'),
    env,
  );
  assert.equal(denied.status, 404);

  console.log('PASS Supabase relay health uses upstream REST endpoint');
  console.log('PASS REST path/query and auth headers are preserved');
  console.log('PASS Auth POST bodies are proxied');
  console.log('PASS Browser CORS preflight supports Supabase methods');
  console.log('PASS Unknown relay routes are rejected');
  console.log('5 Supabase relay regression checks passed.');
} finally {
  globalThis.fetch = originalFetch;
  globalThis.Request = OriginalRequest;
}
