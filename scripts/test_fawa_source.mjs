import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';

const entry = new URL('../supabase/functions/soco-links/index.ts', import.meta.url);
let handler;
const priorDeno = globalThis.Deno;
globalThis.Deno = { serve(fn) { handler = fn; } };
let code = readFileSync(entry, 'utf8').replace(/^import .*jsr:.*;\n/gm, '')
  .replace(/"(\.\.\/_shared\/[^"]+)"/g, (_, path) => JSON.stringify(new URL(path, entry).href));
code += '\nexport { extractFawaMediaUrls };';
const { extractFawaMediaUrls } = await import('data:text/javascript;base64,' +
  Buffer.from(stripTypeScriptTypes(code)).toString('base64'));
globalThis.Deno = priorDeno;

const page = 'http://www.fawanews.sc/Home%20vs%20Away.html';
const rotation = `<script>
  var S1 = ["https://one.example/hls/", "https://two.example/hls/"];
  var S2 = "channel";
  var S3 = ".m3u8";
  var looo = [];
  for (var i = 0; i < S1.length; i++) { looo.push(S1[i] + S2 + S3); }
</script><script>
  var player = new Clappr.Player({source: looo[Math.floor(Math.random() * looo.length)], parentId: '#player'});
</script>`;
const concatenation = `<script>
  var d1 = 'https://cdn.example/live/';
  var d2 = 'channel-id';
  var d3 = '.m3u8';
  var VVVV = [d1 + d2 + d3];
</script><script>
  var player = new Clappr.Player({source: VVVV[Math.floor(Math.random() * VVVV.length)], parentId: '#player'});
</script>`;

test('Fawa rotating origin arrays yield each complete media URL', () => {
  assert.deepEqual([...extractFawaMediaUrls(rotation, page)], [
    'https://one.example/hls/channel.m3u8', 'https://two.example/hls/channel.m3u8',
  ]);
});

test('Fawa CH 2 literal concatenation resolves the actual source array', () => {
  assert.deepEqual([...extractFawaMediaUrls(concatenation, page)], ['https://cdn.example/live/channel-id.m3u8']);
});

test('literal scalar sources, escapes and duplicate URLs are supported', () => {
  const html = `<script>const host="https:\\/\\/cdn.example/";
    const id='cha\\x6enel'; const media=host+id+'.m3u8?one=1&amp;two=2';
    const player = new Clappr.Player({source: media, autoPlay:true});</script>`;
  assert.deepEqual([...extractFawaMediaUrls(html + html, page)], ['https://cdn.example/channel.m3u8?one=1&two=2']);
});

test('existing direct media extraction remains available', () => {
  assert.deepEqual([...extractFawaMediaUrls('<video src="/live.m3u8"></video>', page)],
    ['http://www.fawanews.sc/live.m3u8']);
});

test('page scripts and calls are never executed; unrelated fragments are not sources', () => {
  globalThis.fawaUnexpectedExecution = false;
  const html = `<script>var prefix='https://cdn.example/'; var ext='.m3u8';
    var unused=prefix+'unrelated'+ext;
    var bad=(globalThis.fawaUnexpectedExecution=true, prefix+'bad'+ext);
    var player = new Clappr.Player({source: bad, autoPlay:true});</script>`;
  assert.deepEqual([...extractFawaMediaUrls(html, page)], []);
  assert.equal(globalThis.fawaUnexpectedExecution, false);
  delete globalThis.fawaUnexpectedExecution;
});

test('unknown variables, unsupported URL protocols and large expansions fail closed', () => {
  for (const expression of ['missing+suffix', "'javascript:'+suffix", "'file:///tmp/'+suffix"]) {
    const html = `<script>var suffix='channel.m3u8'; var media=${expression};
      var player=new Clappr.Player({source:media,autoPlay:true});</script>`;
    assert.deepEqual([...extractFawaMediaUrls(html, page)], []);
  }
  const origins = Array.from({ length: 17 }, (_, i) => `'https://cdn${i}.example/'`).join(',');
  const html = rotation.replace('["https://one.example/hls/", "https://two.example/hls/"]', '[' + origins + ']');
  assert.deepEqual([...extractFawaMediaUrls(html, page)], []);
});

test('Viewer and Admin Fawa extraction use the same assembled URLs and probe semantics', async () => {
  const originalFetch = globalThis.fetch;
  let probes = 0;
  globalThis.fetch = async (url) => {
    if (String(url) === page) return new Response(rotation);
    probes++;
    return new Response('#EXTM3U\n#EXTINF:6,\nsegment.ts');
  };
  try {
    for (const skip of [true, false]) {
      const response = await handler(new Request('https://backend.example/soco-links', {
        method: 'POST', body: JSON.stringify({ viewer_public: true, source: 'fawa', action: 'streams', page_url: page, skip_probe: skip }),
      }));
      const body = await response.json();
      assert.equal(response.status, 200);
      assert.equal(body.lines.length, 2);
      assert.equal(body.lines[0].stream_type, 'hls');
      assert.equal(body.lines[0].referer, page);
      assert.equal(body.lines[0].health_status, skip ? 'unknown' : 'healthy');
      assert.equal(probes, skip ? 0 : 2);
    }
  } finally { globalThis.fetch = originalFetch; }
});
