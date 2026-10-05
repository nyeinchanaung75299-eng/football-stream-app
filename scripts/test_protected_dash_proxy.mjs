import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const workerPath = fileURLToPath(
  new URL('../cloudflare/public-api/src/index.js', import.meta.url),
);
const source = readFileSync(workerPath, 'utf8') +
  '\nexport { advertisedLinkCount, protectedClientLinks, blockedClientLinks, rewriteDashManifest, rewriteHlsPlaylist, resolveProtectedTarget, workerFetchUrl, isFawaSession };\n';
const mod = await import(
  'data:text/javascript;base64,' + Buffer.from(source).toString('base64')
);

const {
  advertisedLinkCount,
  protectedClientLinks,
  blockedClientLinks,
  rewriteDashManifest,
  rewriteHlsPlaylist,
  resolveProtectedTarget,
  workerFetchUrl,
  isFawaSession,
} = mod;

const kv = new Map();
const env = {
  PLAYBACK_TOKENS: {
    async put(key, value) {
      kv.set(key, value);
    },
    async get(key) {
      return kv.get(key) ?? null;
    },
  },
};

const dashRow = {
  id: 'dash-clear',
  label: 'DASH',
  resolution: '1080p',
  stream_type: 'dash',
  stream_url: 'https://media.example/live/manifest.mpd',
  referer: '',
  origin: '',
  key_id: '',
  key_data: '',
  use_webview: false,
  is_active: true,
  priority: 1,
  available_from: null,
  expires_at: null,
  health_status: 'healthy',
};

assert.equal(
  advertisedLinkCount([dashRow]),
  1,
  'eligible non-DRM DASH must be advertised',
);
const keyedDashRow = {
  ...dashRow,
  id: 'dash-keyed',
  key_id: 'secret-id',
  key_data: 'secret-key',
};
assert.equal(
  advertisedLinkCount([keyedDashRow]),
  1,
  'keyed DASH must remain visible in public line-count metadata',
);
const blockedRows = blockedClientLinks([keyedDashRow]);
assert.equal(blockedRows.length, 1);
assert.equal(blockedRows[0].blocked_reason, 'keyed_dash_not_exposed');
assert.equal(blockedRows[0].stream_url, null);
assert.equal(blockedRows[0].key_id, null);
assert.equal(blockedRows[0].key_data, null);

const protectedRows = await protectedClientLinks(
  [dashRow],
  env,
  'https://football-api.example',
);
assert.equal(protectedRows.length, 1);
assert.equal(protectedRows[0].stream_type, 'dash');
assert.match(protectedRows[0].stream_url, /^https:\/\/football-api\.example\/p\//);
assert.equal(protectedRows[0].key_id, null);
assert.equal(protectedRows[0].key_data, null);

const sessionToken = protectedRows[0].stream_url.split('/').pop();
const session = JSON.parse(await env.PLAYBACK_TOKENS.get('s:' + sessionToken));
assert.equal(session.t, 'dash');

const simpleMpd = `<?xml version="1.0"?>
<MPD type="dynamic">
  <Period>
    <AdaptationSet>
      <Representation id="v1">
        <SegmentTemplate
          initialization="init-$RepresentationID$.m4s"
          media="chunk-$RepresentationID$-$Number%05d$.m4s" />
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>`;

const simpleRewritten = await rewriteDashManifest(
  simpleMpd,
  'https://media.example/live/manifest.mpd?token=hidden',
  sessionToken,
  session.k,
  'https://football-api.example',
);
assert.ok(!simpleRewritten.includes('media.example'));
const injectedBase = simpleRewritten.match(
  /<BaseURL>https:\/\/football-api\.example\/p\/[^/]+\/b\/([^/]+)\/<\/BaseURL>/,
);
assert.ok(injectedBase, 'manifest without BaseURL must get a protected base');
const segmentTarget = await resolveProtectedTarget(
  'b/' + injectedBase[1] + '/chunk-v1-00001.m4s',
  session,
  'https://football-api.example/p/' + sessionToken +
    '/b/' + injectedBase[1] + '/chunk-v1-00001.m4s',
);
assert.equal(segmentTarget, 'https://media.example/live/chunk-v1-00001.m4s');

const nestedOnlyMpd = `<MPD>
  <Period>
    <AdaptationSet>
      <BaseURL>video/</BaseURL>
      <Representation>
        <SegmentTemplate media="v-$Number$.m4s" />
      </Representation>
    </AdaptationSet>
    <AdaptationSet>
      <Representation>
        <SegmentTemplate media="a-$Number$.m4s" />
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>`;

const nestedRewritten = await rewriteDashManifest(
  nestedOnlyMpd,
  'https://media.example/live/manifest.mpd',
  sessionToken,
  session.k,
  'https://football-api.example',
);
const rootBases = [...nestedRewritten.matchAll(
  /<MPD[^>]*><BaseURL>https:\/\/football-api\.example\/p\/[^/]+\/b\/([^/]+)\/<\/BaseURL>/g,
)];
assert.equal(
  rootBases.length,
  1,
  'nested-only BaseURL manifests must still receive one protected MPD-level base',
);
assert.ok(
  !nestedRewritten.includes('media.example') &&
    !nestedRewritten.includes('https://cdn.example'),
  'nested-only BaseURL rewrite must not expose upstream hosts',
);

const absoluteMpd = `<MPD>
  <BaseURL>https://cdn.example/sports/game/</BaseURL>
  <Period>
    <AdaptationSet>
      <Representation>
        <SegmentTemplate
          initialization="https://cdn.example/sports/game/init-$RepresentationID$.m4s"
          media="https://cdn.example/sports/game/seg-$Number$.m4s?edge=1&amp;x=2" />
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>`;

const absoluteRewritten = await rewriteDashManifest(
  absoluteMpd,
  'https://origin.example/path/manifest.mpd',
  sessionToken,
  session.k,
  'https://football-api.example',
);
assert.ok(!absoluteRewritten.includes('cdn.example'));
assert.ok(absoluteRewritten.includes('$RepresentationID$'));
assert.ok(absoluteRewritten.includes('$Number$'));

const mediaMatch = absoluteRewritten.match(
  /media="https:\/\/football-api\.example\/p\/[^/]+\/b\/([^/]+)\/seg-\$Number\$\.m4s\?edge=1&amp;x=2"/,
);
assert.ok(mediaMatch, 'absolute DASH template must keep its substitution token');
const requestedPath =
  'b/' + mediaMatch[1] + '/seg-42.m4s';
const absoluteTarget = await resolveProtectedTarget(
  requestedPath,
  session,
  'https://football-api.example/p/' + sessionToken +
    '/' + requestedPath + '?edge=1&x=2',
);
assert.equal(
  absoluteTarget,
  'https://cdn.example/sports/game/seg-42.m4s?edge=1&x=2',
);

await assert.rejects(
  () => resolveProtectedTarget(
    'b/' + mediaMatch[1] + '/../../private.txt',
    session,
    'https://football-api.example/p/' + sessionToken +
      '/b/' + mediaMatch[1] + '/../../private.txt',
  ),
  /escaped its base/,
  'protected DASH base routes must not allow path escape',
);

const hls = await rewriteHlsPlaylist(
  '#EXTM3U\nsegment-1.ts\n',
  'https://media.example/live/master.m3u8',
  sessionToken,
  session.k,
  'https://football-api.example',
);
assert.ok(!hls.includes('media.example'));
assert.match(hls, /https:\/\/football-api\.example\/p\//);

const fawaAlias = workerFetchUrl(
  'http://193.47.62.41/hls/SZSZSZQQ.m3u8?token=abc',
);
assert.equal(
  fawaAlias.toString(),
  'http://fawa41-origin.nyeinchanaung.us.ci/hls/SZSZSZQQ.m3u8?token=abc',
  'Fawa IP literal must be routed through the DNS-only origin alias',
);
assert.equal(
  workerFetchUrl('https://media.example/live/master.m3u8').toString(),
  'https://media.example/live/master.m3u8',
  'normal upstream hostnames must stay unchanged',
);
assert.equal(
  isFawaSession({
    r: 'http://www.fawanews.sc/France%20vs%20Belgium.html',
    o: 'http://www.fawanews.sc',
  }),
  true,
  'Fawa referer/origin must select the browser-compatible request profile',
);

console.log('PASS protected non-DRM DASH is advertised');
console.log('PASS keyed DASH is counted and shown as safe blocked metadata');
console.log('PASS relative DASH SegmentTemplate uses protected base routing');
console.log('PASS nested-only BaseURL manifests receive a protected root base');
console.log('PASS absolute DASH templates preserve substitution tokens');
console.log('PASS protected DASH base cannot escape its upstream path');
console.log('PASS existing HLS rewrite remains protected');
console.log('PASS Fawa raw IP origins are routed through DNS aliases');
console.log('PASS normal upstream hostnames are not rewritten');
console.log('PASS Fawa sessions use a browser-compatible upstream profile');
console.log('11 protected playback regression checks passed.');
