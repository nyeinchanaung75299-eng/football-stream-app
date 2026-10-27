import assert from "node:assert/strict";
import { test } from "node:test";
import {
  safeStreameUrl, streameMatches, streameStreams,
} from "../supabase/functions/_shared/streame_source.mjs";

const CATALOG = "https://streamcenter.st/game-cards/embed";
const EVENT = "event-espn-league-soccer-eng-1-401879257";
const SOURCE = "645527f1-15e9-4a06-963e-421a87699691";
const LINK = "https://streamcenter.st/api/stream-link/iframe/" + EVENT + "/" + SOURCE;
const EMBED = "https://streame.center/embed/ch1.php";
const PLAYER = "https://streame.center/embed/hls2.php?stream=publicFixture24";
const MEDIA = "https://edgestream7.pro/live/public-fixture.m3u8";

function card() {
  return `<article class="game-card-row">
    <div class="game-card-when"><span class="game-card-status game-card-status-live">LIVE</span>
      <time dateTime="2026-10-19T19:00:00.000Z">Loading</time></div>
    <p class="game-card-league">Premier League</p>
    <h3 aria-label="Tottenham Hotspur vs. Coventry City">
      <span data-team-position="leading" title="Tottenham Hotspur"></span>
      <span data-team-position="trailing" title="Coventry City"></span>
    </h3>
    <a class="game-card-open-link" href="/api/stream-link/iframe/${EVENT}/${SOURCE}">English</a>
    <a href="/watch/${EVENT}">Watch</a>
  </article>`;
}

function mediaBytes() {
  const bytes = new Uint8Array(1024);
  for (let i = 0; i < bytes.length; i += 188) bytes[i] = 0x47;
  return bytes;
}

function fakeFetch(routes) {
  const calls = [];
  const fetcher = async (raw, init = {}) => {
    const url = String(raw);
    calls.push({ url, init });
    const response = routes[url];
    assert.notEqual(response, undefined, "Unexpected fetch: " + new URL(url).pathname);
    return typeof response === "function" ? response(init) : response.clone();
  };
  return { calls, fetcher };
}

test("public StreamCenter cards become English football source rows", async () => {
  const mock = fakeFetch({ [CATALOG]: new Response(card()) });
  const result = await streameMatches({}, mock);
  assert.equal(result.results, 1);
  assert.deepEqual(result.matches[0], {
    source: "streame", source_id: EVENT, schedule_id: EVENT,
    league: "Premier League", home_team: "Tottenham Hotspur",
    away_team: "Coventry City", home_logo: null, away_logo: null,
    match_time: "2026-10-19T19:00:00.000Z", is_live: true,
    status: "LIVE", page_url: "https://streamcenter.st/watch/" + EVENT,
    anchors: [{ uid: SOURCE, room_num: EVENT + ":" + SOURCE,
      nick_name: "English", page_url: LINK }],
  });
  assert.equal(mock.calls.length, 1);
});

test("public iframe chain returns one verified gateway-compatible HLS line", async () => {
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response(`<iframe src="${PLAYER}"></iframe>`),
    [PLAYER]: new Response(`<script>const streamUrl = "${MEDIA}";</script>`),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes(), { status: 206 }),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE, page_url: LINK }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.line_count, 1);
  assert.deepEqual({
    label: result.lines[0].label,
    type: result.lines[0].stream_type,
    url: result.lines[0].url,
    referer: result.lines[0].referer,
    verified: result.lines[0].media_verified,
    gateway: result.lines[0].gateway_compatible,
    keyId: result.lines[0].key_id,
    keyData: result.lines[0].key_data,
  }, {
    label: "English", type: "hls", url: MEDIA, referer: PLAYER,
    verified: true, gateway: true, keyId: null, keyData: null,
  });
  assert.equal(mock.calls.at(-1).init.headers.Range, "bytes=0-4095");
  assert.equal(mock.calls.some(({url}) => url === CATALOG), false);
});

test("a mismatched selected StreamCenter page is rejected before any fetch", async () => {
  const mock = fakeFetch({});
  await assert.rejects(
    streameStreams({room_num: EVENT + ":" + SOURCE,
      page_url: "https://streamcenter.st/api/stream-link/iframe/" + EVENT + "/00000000-0000-0000-0000-000000000000"}, mock),
    /does not match/,
  );
  assert.equal(mock.calls.length, 0);
});

test("StreamCenter adapter rejects forged hosts and source IDs before media fetch", async () => {
  for (const value of [
    "http://streame.center/embed/x", "https://evil.streame.center/x",
    "https://evil.streamec.st/x", "https://streamec.st.evil.example/x",
    "https://evil.embedcenter.st/x", "https://embedcenter.st.evil.example/x",
    "https://streamec.st:444/embed/x", "https://user:password@streamec.st/embed/x",
    "https://edgestream7.pro.evil.example/live.m3u8",
    "https://edgestream100.pro/live.m3u8", "https://example.com/live.m3u8",
  ]) assert.throws(() => safeStreameUrl(value), /Unsupported source host/);

  const mock = fakeFetch({});
  await assert.rejects(streameStreams({ room_num: "../private" }, mock), /Invalid StreamCenter source/);
  assert.equal(mock.calls.length, 0);
});

test("the catalog's current streamec.st player alias resolves a verified HLS line", async () => {
  const wrapper = "https://streamec.st/embed/ch6.php";
  const nested = "https://embedcenter.st/embed/ch6.php";
  const player = "https://embedcenter.st/embed/hls_cdn.php?stream=publicFixture24";
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: wrapper } }),
    [wrapper]: new Response('<iframe src="' + nested + '"></iframe>'),
    [nested]: new Response('<iframe src="' + player + '"></iframe>'),
    [player]: new Response('<script>const streamUrl="' + MEDIA + '";</script>'),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes()),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.lines[0].referer, player);
  assert.equal(result.lines[0].origin, "https://embedcenter.st");
  assert.equal(result.lines[0].media_verified, true);
  assert.equal(mock.calls.find(({url}) => url === player).init.headers.Referer, nested);
});

test("cyclic public wrappers stop without arbitrary fetches", async () => {
  const wrapper = "https://streamec.st/embed/ch6.php";
  const nested = "https://embedcenter.st/embed/ch6.php";
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: wrapper } }),
    [wrapper]: new Response('<iframe src="' + nested + '"></iframe>'),
    [nested]: new Response('<iframe src="' + wrapper + '"></iframe>'),
  });
  await assert.rejects(streameStreams({ room_num: EVENT + ":" + SOURCE }, mock), /Unsupported StreamCenter player/);
  assert.equal(mock.calls.length, 3);
});

test("encrypted HLS is excluded", async () => {
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response(`<iframe src="${PLAYER}"></iframe>`),
    [PLAYER]: new Response(`<script>const streamUrl = "${MEDIA}";</script>`),
    [MEDIA]: new Response('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:6,\nsegment.ts'),
  });
  await assert.rejects(
    streameStreams({ room_num: EVENT + ":" + SOURCE, page_url: LINK }, mock),
    /Encrypted HLS/,
  );
});


test("StreamCenter public player tolerates spaced iframe src and object literal streamUrl", async () => {
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response('<iframe class="player" src = "' + PLAYER + '" allowfullscreen></iframe>'),
    [PLAYER]: new Response('<script>window.player = { streamUrl: "' + MEDIA + '" };</script>'),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes(), { status: 206 }),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE, page_url: LINK }, mock);
  assert.equal(result.lines.length, 1);
  assert.equal(result.lines[0].media_verified, true);
  assert.equal(result.lines[0].url, MEDIA);
});

test("an unrelated iframe and URL cannot hide the supported StreamCenter player", async () => {
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response('<iframe src="https://ads.example/ad"></iframe>' +
      '<iframe src="http://127.0.0.1/private"></iframe><iframe src="' + PLAYER + '"></iframe>'),
    [PLAYER]: new Response('<script>var ad={streamUrl:"https://ads.example/ad.m3u8"};' +
      'const streamUrl="' + MEDIA + '";</script>'),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes()),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.lines[0].url, MEDIA);
  assert.equal(mock.calls.some(({url}) => /ads\.example|127\.0\.0\.1/.test(url)), false);
});

test("a failed supported frame does not stop a working backup frame", async () => {
  const failed = "https://streame.center/embed/hls2.php?stream=failedFixture";
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response('<iframe src="' + failed + '"></iframe><iframe src="' + PLAYER + '"></iframe>'),
    [failed]: new Response("Unavailable", { status: 503 }),
    [PLAYER]: new Response('<script>const streamUrl="' + MEDIA + '";</script>'),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes()),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.line_count, 1);
});


test("known StreamCenter wrapper can expose a direct public HLS literal", async () => {
  const wrapper = "https://embedcenter.st/embed/ch6.php";
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: wrapper } }),
    [wrapper]: new Response('<script>window.player={streamUrl:"' + MEDIA + '"};</script>'),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes(), { status: 206 }),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.lines[0].referer, wrapper);
  assert.equal(result.lines[0].url, MEDIA);
  assert.equal(result.lines[0].media_verified, true);
});

test("known wrapper uses literal backup only after a failed iframe", async () => {
  const failed = "https://streame.center/embed/hls2.php?stream=failedFixture";
  const mock = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response('<iframe src="' + failed + '"></iframe>' +
      '<script>const streamUrl="' + MEDIA + '";</script>'),
    [failed]: new Response("Unavailable", { status: 503 }),
    [MEDIA]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    ["https://edgestream7.pro/live/segment.ts"]: new Response(mediaBytes()),
  });
  const result = await streameStreams({ room_num: EVENT + ":" + SOURCE }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.lines[0].referer, EMBED);
});

test("direct wrapper literals remain host and encryption restricted", async () => {
  const blocked = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response('<script>const streamUrl="https://untrusted.example/live.m3u8";</script>'),
  });
  await assert.rejects(
    streameStreams({ room_num: EVENT + ":" + SOURCE }, blocked),
    /StreamCenter player is unavailable/,
  );
  assert.equal(blocked.calls.length, 2);

  const encrypted = fakeFetch({
    [CATALOG]: new Response(card()),
    [LINK]: new Response(null, { status: 302, headers: { Location: EMBED } }),
    [EMBED]: new Response('<script>const streamUrl="' + MEDIA + '";</script>'),
    [MEDIA]: new Response('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXTINF:6,\nsegment.ts'),
  });
  await assert.rejects(
    streameStreams({ room_num: EVENT + ":" + SOURCE }, encrypted),
    /Encrypted HLS/,
  );
  assert.equal(encrypted.calls.some(({url}) => url.endsWith("segment.ts")), false);
});
