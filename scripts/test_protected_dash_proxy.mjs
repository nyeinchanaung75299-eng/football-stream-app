import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const workerPath = fileURLToPath(
  new URL('../cloudflare/public-api/src/index.js', import.meta.url),
);
const source = readFileSync(workerPath, 'utf8') +
  '\nexport { advertisedLinkCount, protectedClientLinks, rewriteDashManifest, rewriteHlsPlaylist, resolveProtectedTarget, workerFetchUrl, isFawaSession, decryptPlaybackSession };\n';
const mod = await import(
  'data:text/javascript;base64,' + Buffer.from(source).toString('base64')
);

const {
  advertisedLinkCount,
  protectedClientLinks,
  rewriteDashManifest,
  rewriteHlsPlaylist,
  resolveProtectedTarget,
  workerFetchUrl,
  isFawaSession,
  decryptPlaybackSession,
} = mod;

const env = {
  PLAYBACK_BACKEND_SECRET: 'unit-test-playback-secret',
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
const keyedProtectedRows = await protectedClientLinks(
  [keyedDashRow],
  env,
  'https://football-api.example',
);
assert.equal(keyedProtectedRows.length, 1);
assert.match(
  keyedProtectedRows[0].stream_url,
  /^https:\/\/football-api\.example\/p\//,
);
assert.equal(keyedProtectedRows[0].key_id, 'secret-id');
assert.equal(keyedProtectedRows[0].key_data, 'secret-key');

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
const session = await decryptPlaybackSession(
  sessionToken,
  env.PLAYBACK_BACKEND_SECRET,
);
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

const xmlAttribute = (text, name) => {
  const match = text.match(new RegExp('\\b' + name + '="([^"]+)"'));
  assert.ok(match, name + ' attribute must exist');
  return match[1].replace(/&amp;/g, '&').replace(/&quot;/g, '"');
};
const baseValues = (text) => [...text.matchAll(
  /<(?:[\w.-]+:)?BaseURL\b[^>]*>([^<]+)<\/(?:[\w.-]+:)?BaseURL>/g,
)].map((match) => match[1].replace(/&amp;/g, '&'));
async function upstreamTarget(protectedUrl) {
  const parsed = new URL(protectedUrl);
  assert.equal(parsed.origin, 'https://football-api.example');
  const prefix = '/p/' + sessionToken + '/';
  assert.ok(parsed.pathname.startsWith(prefix), 'media must retain its protected session');
  return resolveProtectedTarget(parsed.pathname.slice(prefix.length), session, parsed.href);
}

const hierarchyRewritten = await rewriteDashManifest(
  `<MPD>
    <BaseURL serviceLocation="primary">https://cdn.example/sport/</BaseURL>
    <BaseURL serviceLocation="backup">http://backup.example/mirror/</BaseURL>
    <Period><BaseURL>season/</BaseURL>
      <AdaptationSet><Representation><BaseURL>video/</BaseURL>
        <SegmentTemplate media="chunk-$Number$.m4s" />
      </Representation></AdaptationSet>
    </Period>
  </MPD>`,
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
const hierarchyBases = baseValues(hierarchyRewritten);
assert.equal(hierarchyBases.length, 4, 'CDN alternatives must remain separate BaseURL elements');
assert.ok(hierarchyRewritten.includes('serviceLocation="backup"'));
for (const [rootBase, expected] of [
  [hierarchyBases[0], 'https://cdn.example/sport/season/video/chunk-42.m4s'],
  [hierarchyBases[1], 'http://backup.example/mirror/season/video/chunk-42.m4s'],
]) {
  const periodBase = new URL(hierarchyBases[2], rootBase);
  const representationBase = new URL(hierarchyBases[3], periodBase);
  assert.equal(await upstreamTarget(new URL('chunk-42.m4s', representationBase).href), expected);
}

const rootRelativeRewritten = await rewriteDashManifest(
  `<MPD>
    <BaseURL>https://cdn.example/sport/</BaseURL>
    <BaseURL>http://backup.example/mirror/</BaseURL>
    <Period><AdaptationSet><Representation>
      <SegmentTemplate initialization="/assets/init-$RepresentationID$.m4s"
        media="/assets/chunk-$Number%05d$.m4s?edge=1&amp;token=&#x61;&#98;" />
      <SegmentList><SegmentURL media="/assets/fixed.m4s" index="/assets/index.sidx" />
        <Initialization sourceURL="/assets/fixed-init.m4s" />
      </SegmentList>
    </Representation></AdaptationSet></Period>
  </MPD>`,
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
for (const [rootBase, upstreamOrigin] of baseValues(rootRelativeRewritten).map((base, index) => [
  base, index === 0 ? 'https://cdn.example' : 'http://backup.example',
])) {
  const media = xmlAttribute(rootRelativeRewritten, 'media').replace('$Number%05d$', '00042');
  const initialization = xmlAttribute(rootRelativeRewritten, 'initialization').replace('$RepresentationID$', 'v1');
  assert.equal(await upstreamTarget(new URL(media, rootBase).href),
    upstreamOrigin + '/assets/chunk-00042.m4s?edge=1&token=ab');
  assert.equal(await upstreamTarget(new URL(initialization, rootBase).href),
    upstreamOrigin + '/assets/init-v1.m4s');
  assert.equal(await upstreamTarget(new URL(xmlAttribute(rootRelativeRewritten, 'index'), rootBase).href),
    upstreamOrigin + '/assets/index.sidx');
  assert.equal(await upstreamTarget(new URL(xmlAttribute(rootRelativeRewritten, 'sourceURL'), rootBase).href),
    upstreamOrigin + '/assets/fixed-init.m4s');
}

const prefixedRewritten = await rewriteDashManifest(
  `<?xml version="1.0"?>
  <d:MPD xmlns:d="urn:mpeg:dash:schema:mpd:2011">
    <!-- <BaseURL>https://wrong.example/</BaseURL> -->
    <d:Period><d:BaseURL><![CDATA[../season/]]></d:BaseURL>
      <d:AdaptationSet><d:Representation><d:BaseURL>video-$RepresentationID$/</d:BaseURL>
        <d:SegmentTemplate media="../audio/chunk-$Number$.m4s?token=one&amp;next=/path/$Number$" />
      </d:Representation></d:AdaptationSet>
    </d:Period>
  </d:MPD>`,
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
assert.match(prefixedRewritten, /<d:MPD[^>]*><d:BaseURL>/);
const prefixedBases = baseValues(prefixedRewritten).filter((value) => value !== 'https://wrong.example/');
const prefixedPeriod = new URL(prefixedBases[1], prefixedBases[0]);
const prefixedRepresentation = new URL(prefixedBases[2].replace('$RepresentationID$', 'v1'), prefixedPeriod);
const parentMedia = xmlAttribute(prefixedRewritten, 'media').replaceAll('$Number$', '42');
assert.equal(await upstreamTarget(new URL(parentMedia, prefixedRepresentation).href),
  'https://origin.example/season/audio/chunk-42.m4s?token=one&next=/path/42');

const protocolRelativeRewritten = await rewriteDashManifest(
  '<MPD><BaseURL>http://cdn.example/sport/</BaseURL><Period>' +
    '<SegmentTemplate media="//other.example/segments/$Number$.m4s" />' +
    '</Period></MPD>',
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
assert.equal(await upstreamTarget(new URL(
  xmlAttribute(protocolRelativeRewritten, 'media').replace('$Number$', '42'),
  baseValues(protocolRelativeRewritten)[0],
).href), 'http://other.example/segments/42.m4s');

const singleFileRewritten = await rewriteDashManifest(
  '<MPD><BaseURL>https://cdn.example/sport/video.mp4</BaseURL><Period>' +
    '<SegmentList><SegmentURL media="../audio/chunk-$Number$.m4s" /></SegmentList>' +
    '</Period></MPD>',
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
assert.equal(await upstreamTarget(baseValues(singleFileRewritten)[0]),
  'https://cdn.example/sport/video.mp4');
assert.equal(await upstreamTarget(new URL(
  xmlAttribute(singleFileRewritten, 'media').replace('$Number$', '42'),
  baseValues(singleFileRewritten)[0],
).href), 'https://cdn.example/audio/chunk-42.m4s');

const emptyBaseRewritten = await rewriteDashManifest(
  '<MPD><BaseURL/><Period><SegmentTemplate media="%2e%2e/audio/chunk-$Number$.m4s" /></Period></MPD>',
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
assert.equal(await upstreamTarget(new URL(
  xmlAttribute(emptyBaseRewritten, 'media').replace('$Number$', '42'),
  baseValues(emptyBaseRewritten)[0],
).href), 'https://origin.example/audio/chunk-42.m4s');

const relativeUrl = new URL(
  xmlAttribute(rootRelativeRewritten, 'media').replace('$Number%05d$', '00042'),
  baseValues(rootRelativeRewritten)[0],
);
const protectedRelativePath = relativeUrl.pathname.slice(('/p/' + sessionToken + '/').length);
const tamperedRelativePath = protectedRelativePath.replace(/(~r\/)([A-Za-z0-9_-])/, (_, prefix, first) =>
  prefix + (first === 'A' ? 'B' : 'A'));
await assert.rejects(() => resolveProtectedTarget(tamperedRelativePath, session, relativeUrl.href),
  'relative-reference ciphertext must authenticate before resolving its target');
const relativeParent = protectedRelativePath.slice(0, protectedRelativePath.lastIndexOf('/') + 1);
await assert.rejects(() => resolveProtectedTarget(relativeParent + '../../private.txt', session, relativeUrl.href),
  /escaped its base/, 'unsigned tail traversal must remain blocked after a signed relative reference');

// Exercise the real HTTP route, not only the URL-resolution helper.
const originalFetch = globalThis.fetch;
let fetchedMediaUrl;
try {
  globalThis.fetch = async (input) => {
    fetchedMediaUrl = String(input);
    return new Response('segment', { headers: { 'Content-Type': 'video/mp4' } });
  };
  const mediaUrl = new URL(
    xmlAttribute(rootRelativeRewritten, 'media').replace('$Number%05d$', '00042'),
    baseValues(rootRelativeRewritten)[0],
  );
  const mediaResponse = await mod.default.fetch(new Request(mediaUrl), env, {});
  assert.equal(mediaResponse.status, 200);
  assert.equal(fetchedMediaUrl, 'https://cdn.example/assets/chunk-00042.m4s?edge=1&token=ab');
} finally {
  globalThis.fetch = originalFetch;
}

const linkedManifest = await rewriteDashManifest(
  '<MPD xmlns:xlink="http://www.w3.org/1999/xlink">' +
    '<BaseURL>https://cdn.example/media/</BaseURL>' +
    '<Period xlink:href="periods/one.xml?edge=1&amp;x=2" xlink:actuate="onLoad" />' +
    '<Period xlink:href="../common/two.xml" xlink:actuate="onLoad" />' +
    '<Period xlink:href="/shared/three.xml" xlink:actuate="onLoad" />' +
    '</MPD>',
  'https://origin.example/live/main.mpd',
  sessionToken, session.k, 'https://football-api.example',
);
const linkedReferences = [...linkedManifest.matchAll(/xlink:href="([^"]+)"/g)]
  .map((match) => match[1].replace(/&amp;/g, '&'));
for (const [index, expected] of [
  'https://origin.example/live/periods/one.xml?edge=1&x=2',
  'https://origin.example/common/two.xml',
  'https://origin.example/shared/three.xml',
].entries()) {
  // Shaka resolves XLink against the manifest URI before evaluating BaseURL.
  const linkedUrl = new URL(linkedReferences[index], protectedRows[0].stream_url);
  assert.equal(await upstreamTarget(linkedUrl.href), expected);
}

try {
  globalThis.fetch = async (input) => {
    fetchedMediaUrl = String(input);
    return new Response(
      '<Period xmlns:xlink="http://www.w3.org/1999/xlink">' +
        '<BaseURL>https://fragment-cdn.example/video/</BaseURL>' +
        '<AdaptationSet xlink:href="nested.xml"><Representation>' +
        '<SegmentTemplate media="/segments/chunk-$Number$.m4s" />' +
        '</Representation></AdaptationSet></Period>',
      { headers: { 'Content-Type': 'application/xml' } },
    );
  };
  const linkedResponse = await mod.default.fetch(new Request(linkedReferences[0]), env, {});
  assert.equal(linkedResponse.status, 200);
  assert.equal(fetchedMediaUrl, 'https://origin.example/live/periods/one.xml?edge=1&x=2');
  const fragment = await linkedResponse.text();
  assert.ok(!fragment.includes('fragment-cdn.example'), 'linked XML must not expose raw media hosts');
  assert.ok(!/<MPD|<BaseURL>https:\/\/football-api\.example.*<BaseURL>/.test(fragment),
    'standalone Period fragments must not gain an MPD root or injected base');
  assert.equal(await upstreamTarget(xmlAttribute(fragment, 'xlink:href')),
    'https://origin.example/live/periods/nested.xml');
  assert.equal(await upstreamTarget(new URL(
    xmlAttribute(fragment, 'media').replace('$Number$', '42'), baseValues(fragment)[0],
  ).href), 'https://fragment-cdn.example/segments/chunk-42.m4s');

  globalThis.fetch = async () => new Response(
    '<Unsupported><BaseURL>https://fragment-cdn.example/private/</BaseURL></Unsupported>',
    { headers: { 'Content-Type': 'application/xml' } },
  );
  const unsupportedDocument = await mod.default.fetch(new Request(linkedReferences[0]), env, {});
  assert.equal(unsupportedDocument.status, 502);
  assert.ok(!(await unsupportedDocument.text()).includes('fragment-cdn.example'));
} finally {
  globalThis.fetch = originalFetch;
}

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
console.log('PASS configured ClearKey DASH is returned as a protected playable line');
console.log('PASS relative DASH SegmentTemplate uses protected base routing');
console.log('PASS nested-only BaseURL manifests receive a protected root base');
console.log('PASS absolute DASH templates preserve substitution tokens');
console.log('PASS protected DASH base cannot escape its upstream path');
console.log('PASS nested DASH bases preserve hierarchy and CDN alternatives');
console.log('PASS root-relative DASH media, initialization and index stay protected');
console.log('PASS XML namespaces, comments, CDATA and numeric query entities remain valid');
console.log('PASS parent-relative templates preserve path and query substitutions');
console.log('PASS protocol-relative media preserves the selected upstream scheme');
console.log('PASS single-file and empty BaseURL elements retain their URL semantics');
console.log('PASS encoded parent paths remain protected and relative references authenticate');
console.log('PASS protected relative media traverses the real Worker HTTP route');
console.log('PASS relative, parent-relative and root-relative XLinks use the manifest URI');
console.log('PASS linked XML fragments and recursive document references remain protected');
console.log('PASS unsupported linked documents fail closed without exposing media URLs');
console.log('PASS existing HLS rewrite remains protected');
console.log('PASS Fawa raw IP origins are routed through DNS aliases');
console.log('PASS normal upstream hostnames are not rewritten');
console.log('PASS Fawa sessions use a browser-compatible upstream profile');
console.log('22 protected playback regression checks passed.');
