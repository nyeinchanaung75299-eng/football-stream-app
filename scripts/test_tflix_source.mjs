import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import {
  decodePublicPlayerWrapper, extractPublicPlayerConfig, safeTflixUrl,
  signedExpiry, tflixMatches, tflixPublicCatalog, tflixPublicMatches, tflixStreams, tflixViewerStreams, verifyTflixMedia,
} from "../supabase/functions/_shared/tflix_source.mjs";

const KID = "0123456789abcdef0123456789abcdef";
const KEY = "abcdef0123456789abcdef0123456789";
const CDN = "https://vix.cdn9859.shop";
const EMBED = "https://xtrahut.xyz/embed/beinsports1-tr";
const expiry = () => Math.floor(Date.now() / 1000) + 3600;
const hlsUrl = () => CDN + "/tflix/secure/public-test/" + expiry() + "/beinsports1-tr.m3u8";
const tsBytes = () => {
  const bytes = new Uint8Array(4096);
  bytes.set(new TextEncoder().encode("RIFF"), 0);
  for (let i = 42; i < bytes.length; i += 188) bytes[i] = 0x47;
  return bytes;
};
function wrapper(text) {
  const values = [...text].map((char) => ((char.charCodeAt(0) + 134 - 256) & 255) ^ 216);
  return "(function(){var _a=[" + values.join(",") + "],_b=216,_c=134,_d=\"\",_i;for(_i=0;_i<_a.length;_i++){_d+=String.fromCharCode(((_a[_i]^_b)-_c+256)%256);}window[\"ev\"+\"al\"](_d);})();";
}
function fakeFetch(routes) {
  const calls = [];
  const fetcher = async (raw, init = {}) => {
    const url = String(raw);
    calls.push({ url, init });
    let value = typeof routes === "function" ? await routes(url, init) : routes[url];
    // Old-schema fixtures remain useful compatibility coverage while catalog()
    // now prefers TFLIX's unified public endpoint.
    if (value === undefined && typeof routes !== "function" && url === "https://tflix.su/api/public") {
      value = routes["https://tflix.su/api/live-scores?scope=board"] ??
        routes["https://tflix.su/api/channels"];
    }
    assert.notEqual(value, undefined, "Unexpected fetch: " + new URL(url).pathname);
    return value instanceof Response ? value : Response.json(value);
  };
  return { calls, fetcher };
}


test("NCA public stream resolver returns two verified keyless lines", async () => {
  const first = hlsUrl();
  const second = CDN + "/tflix/secure/backup/" + expiry() + "/secondary.m3u8";
  const page = "https://tflix.su/match/auto-nca";
  const alt = "https://vixembed.bid/embed/backup-auto-nca";
  const mock = fakeFetch({
    "https://tflix.su/api/live-scores?scope=board": {
      streams: [{ slug: "auto-nca", sport: "football", league: "Premier League",
        homeTeam: { name: "Home" }, awayTeam: { name: "Away" } }],
    },
    [page]: new Response('<script>{"streamUrl":"' + EMBED + '","streamUrl2":"' + alt + '"}</script>'),
    [EMBED]: new Response("var setupOpts={file:'" + first + "',type:'hls'};"),
    [alt]: new Response("var setupOpts={file:'" + second + "',type:'hls'};"),
    [first]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [second]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", first).toString()]: new Response(tsBytes()),
    [new URL("video.ts", second).toString()]: new Response(tsBytes()),
  });
  const result = await tflixViewerStreams({ source_id: "match:auto-nca" }, mock);
  assert.equal(result.line_count, 2);
  assert.deepEqual(result.lines.map(x => x.label), ["NCA Server 1", "NCA Server 2"]);
  assert.deepEqual(result.lines.map(x => x.stream_url), [first, second]);
  assert.ok(result.lines.every(x => x.media_verified && x.key_data === null && x.key_id === null));
  assert.equal(JSON.stringify(result).includes("TFLIX"), false);
});

for (const slot of ["streamUrl", "streamUrl2"]) test("current match channel arrays resolve " + slot + " on the new player host with unique server IDs", async () => {
  const page = "https://tflix.su/match/multi-channel";
  const embeds = ["https://vix.sjncvuaq.xyz/embed/skysportsmainevent-uk",
    "https://vix.sjncvuaq.xyz/embed/skysport8-nz", EMBED];
  const manifests = embeds.map((_, i) => CDN + "/channel-" + i + ".m3u8");
  const chunk = JSON.stringify({ channels: embeds.map((url) => ({ [slot]: url })) });
  const routes = {
    "https://tflix.su/api/live-scores?scope=board": { streams: [{
      slug: "multi-channel", sport: "football", homeTeam: { name: "Home" }, awayTeam: { name: "Away" },
    }] },
    [page]: new Response('<script>self.__next_f.push(' + JSON.stringify([1, chunk]) + ')</script>'),
  };
  for (let i = 0; i < embeds.length; i++) {
    routes[embeds[i]] = new Response(wrapper("var setupOpts={file:'" + manifests[i] + "',type:'hls'};"));
    routes[manifests[i]] = new Response("#EXTM3U\n#EXTINF:6,\nvideo-" + i + ".ts");
    routes[new URL("video-" + i + ".ts", manifests[i]).toString()] = new Response(tsBytes());
  }
  const result = await tflixViewerStreams({ source_id: "match:multi-channel" }, fakeFetch(routes));
  assert.equal(result.line_count, 3);
  assert.equal(new Set(result.lines.map((line) => line.id)).size, 3);
  assert.deepEqual(result.lines.map((line) => line.label), ["NCA Server 1", "NCA Server 2", "NCA Server 3"]);
  assert.deepEqual(result.lines.map((line) => line.stream_url), manifests);
  assert.ok(result.lines.every((line) => line.media_verified && !line.key_id && !line.key_data));
});

test("new player host permission remains exact and validates redirects", async () => {
  assert.equal(safeTflixUrl("https://vix.sjncvuaq.xyz/embed/test").hostname, "vix.sjncvuaq.xyz");
  for (const url of ["https://sjncvuaq.xyz/embed/test", "https://evil.sjncvuaq.xyz/test",
    "https://vix.sjncvuaq.xyz.evil.example/test", "http://vix.sjncvuaq.xyz/test"]) {
    assert.throws(() => safeTflixUrl(url), /Unsupported source host/);
  }
  const page = "https://tflix.su/match/redirect-test";
  const embed = "https://vix.sjncvuaq.xyz/embed/test";
  const mock = fakeFetch({
    "https://tflix.su/api/live-scores?scope=board": { streams: [{
      slug: "redirect-test", sport: "football", homeTeam: { name: "Home" }, awayTeam: { name: "Away" },
    }] },
    [page]: new Response(JSON.stringify({ streamUrl: embed })),
    [embed]: new Response(null, { status: 302, headers: { Location: "https://evil.sjncvuaq.xyz/private" } }),
  });
  const result = await tflixViewerStreams({ source_id: "match:redirect-test" }, mock);
  assert.equal(result.line_count, 0);
  // The single added request attempts the same source's public page for
  // an alternate server; an unapproved redirect is never followed.
  assert.equal(mock.calls.length, 4);
  assert.equal(mock.calls.some(({ url }) => url.includes("evil.sjncvuaq.xyz")), false);
});

test("NCA public resolver rejects forged channel or arbitrary URL IDs before HTTP", async () => {
  const mock = fakeFetch({});
  for (const id of ["channel:sky", "../etc", "match:../bad", "match:abc/stream", ""]) {
    await assert.rejects(tflixViewerStreams({ source_id: id }, mock), /Invalid TFLIX/);
  }
  assert.equal(mock.calls.length, 0);
});

test("NCA public resolver never exports DRM protected MPD or clear keys", async () => {
  const url = CDN + "/protected-nca.mpd";
  const page = "https://tflix.su/match/protected-nca";
  const mock = fakeFetch({
    "https://tflix.su/api/live-scores?scope=board": {
      streams: [{ slug: "protected-nca", sport: "football", league: "Premier League",
        homeTeam: { name: "Home" }, awayTeam: { name: "Away" } }],
    },
    [page]: new Response('<script>{"streamUrl":"' + EMBED + '"}</script>'),
    [EMBED]: new Response("var setupOpts={file:'" + url + "',type:'dash',keyId:'" + KID + "',key:'" + KEY + "'};"),
    [url]: new Response('<MPD><Period><AdaptationSet><ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"/></AdaptationSet></Period></MPD>'),
  });
  const result = await tflixViewerStreams({ source_id: "match:protected-nca" }, mock);
  assert.equal(result.line_count, 0);
  assert.ok(!JSON.stringify(result).includes(KEY));
});

test("NCA public catalog matches Admin fixture count without exposing player URLs", async () => {
  const routes = {
    "https://tflix.su/api/live-scores?scope=board": {
      streams: [
        { slug: "arsenal-leeds", sport: "football", league: "Premier League",
          date: "2026-10-10T11:30:00Z",
          homeTeam: { name: "Arsenal" }, awayTeam: { name: "Leeds United" } },
        { slug: "west-brom-birmingham", sport: "football", league: "Championship",
          date: "2026-10-10T11:30:00Z",
          homeTeam: { name: "West Bromwich" }, awayTeam: { name: "Birmingham" } },
        { slug: "rayo-athletic", sport: "football", league: "La Liga",
          date: "2026-10-10T12:00:00Z",
          homeTeam: { name: "Rayo Vallecano" }, awayTeam: { name: "Athletic Bilbao" } },
      ],
    },
  };
  const admin = await tflixMatches({}, fakeFetch(routes));
  const result = await tflixPublicMatches(fakeFetch(routes));
  assert.equal(result.source, "nca");
  assert.equal(result.results, admin.results);
  assert.equal(result.matches.length, 3);
  assert.deepEqual(result.matches.map((x) => x.home_team),
    ["Arsenal", "West Bromwich", "Rayo Vallecano"]);
  for (const match of result.matches) {
    assert.deepEqual(Object.keys(match).sort(),
      ["source_id","kind","league","home_team","away_team","match_time","is_live"].sort());
    assert.equal(match.page_url, undefined);
    assert.equal(match.anchors, undefined);
    assert.equal(match.stream_url, undefined);
  }
});

test("current public catalog replaces signed-in legacy routes without leaking embeds", async () => {
  const player = "https://mix1.eeeertwfvsgs.xyz/embed/current-football";
  const media = "https://saka.kpores.ru/live/current-football.m3u8";
  const channel = {
    id: "current-channel", slug: "sky-sports-main-event-current",
    name: "Sky Sports Main Event", enabled: 1, embed_url: player, embed_backup: "",
  };
  const payload = {
    events: [{
      id: "current-event", title: "Tottenham vs Coventry", sport: "Football",
      competition: "Angleterre : Premier League", status: "live",
      starts_at: "2026-10-19T19:00:00Z", watch_url: "/watch/tottenham-vs-coventry-current",
      home_name: "Tottenham", away_name: "Coventry", channels: [channel],
    }],
    channels: [channel],
  };
  const routes = {
    "https://tflix.su/api/public": payload,
  };
  const catalog = await tflixMatches({}, fakeFetch(routes));
  assert.equal(catalog.results, 1);
  assert.equal(catalog.matches[0].source_id, "match:tottenham-vs-coventry-current");
  assert.equal(catalog.matches[0].league, "Premier League");
  assert.equal(catalog.matches[0].page_url, "https://tflix.su/watch/tottenham-vs-coventry-current");
  assert.equal(JSON.stringify(catalog).includes(player), false);

  const checked = await tflixStreams({ room_num: catalog.matches[0].source_id }, fakeFetch({
    ...routes,
    [player]: new Response("var setupOpts={file:'" + media + "',type:'hls'};"),
    [media]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", media).toString()]: new Response(tsBytes()),
  }));
  assert.equal(checked.ready, false);
  assert.equal(checked.line_count, 0);
  assert.deepEqual(checked.lines, []);
  assert.match(checked.message, /does not allow playback through this app/);
});

test("a gateway-incompatible candidate does not hide a working backup in the same player", async () => {
  const player = "https://mix1.eeeertwfvsgs.xyz/embed/current-football";
  const blocked = "https://saka.kpores.ru/live/fixture.m3u8";
  const working = hlsUrl();
  const channel = { id: "backup-fixture", name: "Fixture server", enabled: 1, embed_url: player };
  const result = await tflixStreams({ room_num: "match:backup-fixture" }, fakeFetch({
    "https://tflix.su/api/public": {
      events: [{ sport: "Football", status: "live", competition: "Fixture league",
        watch_url: "/watch/backup-fixture", home_name: "Home", away_name: "Away",
        starts_at: "2026-10-25T12:00:00Z", channels: [channel] }],
      channels: [channel],
    },
    [player]: new Response("var player={sources:[{file:'" + blocked + "'},{file:'" + working + "'}]};"),
    [blocked]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", blocked).toString()]: new Response(tsBytes()),
    [working]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", working).toString()]: new Response(tsBytes()),
  }));
  assert.equal(result.ready, true);
  assert.equal(result.line_count, 1);
  assert.equal(result.lines[0].url, working);
  assert.equal(result.lines[0].gateway_compatible, true);
  assert.equal(result.message, "Verified manifest and media sample.");
});

test("Viewer NCA, TFLIX, and StreamCenter streams are protected and verified", () => {
  const file = readFileSync(new URL("../supabase/functions/soco-links/index.ts", import.meta.url), "utf8");
  assert.match(file, /if \(source === "nca"\)/);
  assert.match(file, /if \(!viewerPublic\)/);
  assert.match(file, /verifyPlaybackBackendSecret\(body\.playback_secret\)/);
  assert.match(file, /tflixViewerStreams\(\{ \.\.\.body, label_prefix: "NCA" \}\)/);
  assert.match(file, /tflixPublicCatalog\(body\.catalog\)/);
  assert.match(file, /if \(\(source === "tflix" \|\| source === "streame"\) && viewerPublic\)/);
  assert.match(file, /if \(source === "streame"\) return json\(await streameStreams\(body\)\)/);
});

test("TFLIX score-only football fixtures never gain fabricated broadcast anchors", async () => {
  const mock = fakeFetch({
    "https://tflix.su/api/live-scores?scope=board": {
      streams: [{ slug: "australia-cricket", league: "Cricket", homeTeam: { name: "A" }, awayTeam: { name: "B" } }],
      matches: [{ slug: "arsenal-leeds", league: "Premier League" }],
      boardLeagues: [{ label: "Premier League", sport: "football" }, { label: "Cricket", sport: "cricket" }],
    },
  });
  const result = await tflixMatches({}, mock);
  assert.equal(result.matches.length, 0);
  assert.match(result.message, /No football streams/);
});

test("TFLIX Matches retain genuine assigned IDs and UTC kickoff without using score-only rows", async () => {
  const mock = fakeFetch({
    "https://tflix.su/api/live-scores?scope=board": {
      streams: [{ slug: "arsenal-leeds-assigned", league: "Premier League", date: "2026-10-10T11:30:00Z",
        homeTeam: { name: "Arsenal" }, awayTeam: { name: "Leeds" }, isLive: true }],
      boardLeagues: [{ label: "Premier League", sport: "football" }],
    },
  });
  const result = await tflixMatches({ catalog: "matches" }, mock);
  assert.equal(result.matches[0].source_id, "match:arsenal-leeds-assigned");
  assert.equal(result.matches[0].match_time, "2026-10-10T11:30:00.000Z");
  assert.equal(result.matches[0].anchors[0].page_url, "https://tflix.su/match/arsenal-leeds-assigned");
  assert.equal(result.matches[0].media_verified, undefined);
});

test("TFLIX Channels remain channels, exclude unrelated sports, and never invent a kickoff/opponent", async () => {
  const mock = fakeFetch({
    "https://tflix.su/api/channels": [
      { slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR", isLive: true },
      { slug: "sky-sports-cricket", name: "Sky Sports Cricket" },
      { slug: "movie", name: "Movie" },
      { slug: "../invalid", name: "Sky Sports" },
    ],
  });
  const result = await tflixMatches({ catalog: "channels" }, mock);
  assert.equal(result.matches.length, 1);
  assert.equal(result.matches[0].kind, "channel");
  assert.equal(result.matches[0].source_id, "channel:bein-sports-1-tr");
  assert.equal(result.matches[0].away_team, "");
  assert.equal(result.matches[0].match_time, null);
  assert.equal(result.matches[0].anchors[0].media_verified, undefined);
});

test("public TFLIX catalog exposes both match and channel metadata without player URLs", async () => {
  const mock = fakeFetch({
    "https://tflix.su/api/public": {
      events: [{ slug: "public-match", sport: "Football", status: "live",
        competition: "England: Premier League", starts_at: "2026-10-22T18:00:00Z",
        watch_url: "/watch/public-match", home_name: "Home", away_name: "Away",
        channels: [{ streamUrl: "https://media.example/live.m3u8", key: "private" }] }],
      channels: [{ slug: "sky-sports", name: "Sky Sports Main Event", isLive: true,
        page_url: "https://tflix.su/channel/sky-sports",
        stream_url: "https://media.example/live.m3u8", key_data: "private" }],
    },
  });
  for (const kind of ["matches", "channels"]) {
    const result = await tflixPublicCatalog(kind, mock);
    assert.equal(result.source, "tflix");
    assert.equal(result.catalog, kind);
    assert.equal(result.matches.length, 1);
    assert.equal(result.matches[0].kind, kind === "matches" ? "match" : "channel");
    const serialized = JSON.stringify(result);
    assert.equal(serialized.includes("page_url"), false);
    assert.equal(serialized.includes("stream_url"), false);
    assert.equal(serialized.includes("key_data"), false);
    assert.equal(serialized.includes("anchors"), false);
  }
});

test("observed public literal array decoder returns text without executing player scripts", () => {
  globalThis.tflixTestExecuted = false;
  const plain = "globalThis.tflixTestExecuted=true;var media=" + JSON.stringify(hlsUrl()) + ";var setupOpts={file:media,type:'hls'};";
  const html = wrapper(plain);
  assert.equal(decodePublicPlayerWrapper(html), plain);
  const config = extractPublicPlayerConfig(html, EMBED);
  assert.equal(config.length, 1);
  assert.equal(config[0].stream_type, "hls");
  assert.equal(globalThis.tflixTestExecuted, false);
  assert.equal(decodePublicPlayerWrapper(html.replace("String.fromCharCode", "executeArbitrary")), "");
  delete globalThis.tflixTestExecuted;
});

test("only a complete singular public ClearKey pair is preserved", () => {
  const mpd = CDN + "/public-test.mpd";
  const config = extractPublicPlayerConfig("var setupOpts={file:'" + mpd + "',clearKeys:{'" + KID.toUpperCase() + "':'" + KEY + "'}}", EMBED);
  assert.equal(config[0].key_id, KID);
  assert.equal(config[0].key_data, KEY);
  assert.throws(() => extractPublicPlayerConfig("file:'" + mpd + "',key_id:'" + KID + "'", EMBED), /incomplete/);
  assert.throws(() => extractPublicPlayerConfig("file:'" + mpd + "',clearKeys:{'" + KID + "':'" + KEY + "','11111111111111111111111111111111':'" + KEY + "'}", EMBED), /Multiple/);
});

test("HLS master and child media segment are verified, with actual source headers and signed expiry", async () => {
  const url = hlsUrl();
  const child = new URL("variant.m3u8", url).toString();
  const segment = new URL("video.ts", url).toString();
  const mock = fakeFetch({
    [url]: new Response("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000\nvariant.m3u8"),
    [child]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [segment]: new Response(tsBytes(), { status: 206, headers: { "Content-Type": "image/webp" } }),
  });
  const line = await verifyTflixMedia({ url }, EMBED, mock);
  assert.equal(line.media_verified, true);
  assert.equal(line.health_status, "healthy");
  assert.equal(line.key_id, null);
  assert.equal(line.key_data, null);
  assert.equal(line.origin, "https://xtrahut.xyz");
  assert.equal(Date.parse(line.expires_at), Number(url.split("/").at(-2)) * 1000);
  assert.equal(mock.calls.length, 3);
  assert.equal(mock.calls[2].init.headers.Range, "bytes=0-4095");
  assert.equal(mock.calls[2].init.headers.Referer, EMBED);
  assert.equal(line.referer, EMBED);
});

test("images, HTML, and denied media cannot be marked verified", async () => {
  const url = hlsUrl(), media = new URL("video.ts", url).toString();
  for (const response of [
    new Response("<html>denied</html>"), new Response(new Uint8Array(4096)),
    new Response("Denied", { status: 403 }), new Response("Bad gateway", { status: 502 }),
  ]) {
    const mock = fakeFetch({
      [url]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"), [media]: response,
    });
    await assert.rejects(verifyTflixMedia({ url }, EMBED, mock));
  }
});

test("three coincidental TS sync bytes are rejected; native-compatible five packet boundaries are required", async () => {
  const url = hlsUrl(), media = new URL("video.ts", url).toString();
  const broken = tsBytes();
  broken[42 + 564] = 0;
  const mock = fakeFetch({
    [url]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"), [media]: new Response(broken),
  });
  await assert.rejects(verifyTflixMedia({ url }, EMBED, mock), /not verified media/);
});

test("HLS external audio and session-key masters fail closed", async () => {
  const url = hlsUrl();
  for (const extra of [
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio.m3u8"',
    '#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="license"',
  ]) {
    const mock = fakeFetch({ [url]: new Response("#EXTM3U\n" + extra + '\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="audio"\nvariant.m3u8') });
    await assert.rejects(verifyTflixMedia({ url }, EMBED, mock), /unsupported/);
    assert.equal(mock.calls.length, 1);
  }
});

test("encrypted HLS, including AES-128, fails closed without a verified decrypted media sample", async () => {
  const url = hlsUrl(), media = new URL("video.ts", url).toString(), key = new URL("key", url).toString();
  for (const size of [15, 16, 17]) {
    const mock = fakeFetch({
      [url]: new Response('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:6,\nvideo.ts'),
      [key]: new Response(new Uint8Array(size)),
      [media]: new Response(tsBytes()),
    });
    await assert.rejects(verifyTflixMedia({ url }, EMBED, mock), /unsupported/);
    assert.equal(mock.calls.length, 1);
  }
  const mock = fakeFetch({ [url]: new Response('#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key"\n#EXTINF:6,\nvideo.ts') });
  await assert.rejects(verifyTflixMedia({ url }, EMBED, mock), /unsupported/);
  assert.equal(mock.calls.length, 1);
});

function fmp4(type = "moof") {
  const bytes = new Uint8Array(128);
  bytes.set(new TextEncoder().encode(type), 4);
  return bytes;
}
function dashXml(protection = "", base = "video/") {
  return '<MPD type="static"><BaseURL>' + CDN + '/</BaseURL><Period><BaseURL>' + base +
    '</BaseURL><AdaptationSet mimeType="video/mp4">' + protection +
    '<Representation id="v" bandwidth="1000"><BaseURL>nested/</BaseURL><SegmentList><Initialization sourceURL="/init.mp4"/><SegmentURL media="segment.m4s"/></SegmentList></Representation></AdaptationSet></Period></MPD>';
}

test("DASH resolves nested/root-relative URLs and verifies initialization plus media", async () => {
  const url = CDN + "/manifest.mpd";
  const protection = '<ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc" cenc:default_KID="' + KID + '"/>';
  const mock = fakeFetch({
    [url]: new Response(dashXml(protection)),
    [CDN + "/init.mp4"]: new Response(fmp4("ftyp")),
    [CDN + "/video/nested/segment.m4s"]: new Response(fmp4()),
  });
  const line = await verifyTflixMedia({ url, key_id: KID, key_data: KEY }, EMBED, mock);
  assert.equal(line.media_verified, true);
  assert.equal(line.key_id, KID);
  assert.equal(mock.calls.length, 3);
});

test("encrypted DASH with missing keys, multiple KIDs, or unsupported DRM fails before media requests", async () => {
  const url = CDN + "/manifest.mpd";
  for (const [protection, candidate] of [
    ['<ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc" cenc:default_KID="' + KID + '"/>', {}],
    ['<ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc" cenc:default_KID="' + KID + ' 11111111111111111111111111111111"/>', { key_id: KID, key_data: KEY }],
    ['<ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"/>', { key_id: KID, key_data: KEY }],
    ['<ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc"/>', { key_id: KID, key_data: KEY }],
  ]) {
    const mock = fakeFetch({ [url]: new Response(dashXml(protection)) });
    await assert.rejects(verifyTflixMedia({ url, ...candidate }, EMBED, mock));
    assert.equal(mock.calls.length, 1);
  }
});

test("malformed or deeply nested DASH cannot pass media verification", async () => {
  const url = CDN + "/manifest.mpd";
  for (const xml of [
    "<MPD><Period></MPD>", "<MPD><Period></Period>", "<MPD></Period></MPD>",
    "<MPD>" + "<Period>".repeat(65) + "</Period>".repeat(65) + "</MPD>",
  ]) {
    const mock = fakeFetch({ [url]: new Response(xml) });
    await assert.rejects(verifyTflixMedia({ url }, EMBED, mock), /XML|deeply/);
    assert.equal(mock.calls.length, 1);
  }
});

test("unsafe destinations and redirect targets are rejected before network access", async () => {
  for (const host of [
    "mix.eeeertwfvsgs.xyz",
    "mix1.eeeertwfvsgs.xyz",
    "sha.dsfigosdhgfvsshed.xyz",
    "xu.sjncvuaq.xyz",
    "saka.kpores.ru",
  ]) {
    assert.equal(safeTflixUrl(`https://${host}/player`).hostname, host);
    assert.throws(() => safeTflixUrl(`https://${host}.attacker.test/player`));
    assert.throws(() => safeTflixUrl(`https://evil-${host}/player`));
  }
  for (const url of ["http://tflix.su/", "https://127.0.0.1/", "https://169.254.169.254/", "https://xtrahut.xyz.attacker.test/", "https://user:pass@tflix.su/", "https://tflix.su:8443/"]) {
    assert.throws(() => safeTflixUrl(url));
  }
  const url = hlsUrl();
  const mock = fakeFetch({ [url]: new Response(null, { status: 302, headers: { Location: "https://127.0.0.1/internal" } }) });
  await assert.rejects(verifyTflixMedia({ url }, EMBED, mock), /Unsupported source host/);
  assert.equal(mock.calls.length, 1);
});

test("mandatory extraction ignores skip_probe and never returns an embed as a playable line", async () => {
  const url = hlsUrl();
  const page = "https://tflix.su/channel/bein-sports-1-tr";
  const rsc = '7:["$","Player",null,{"streamUrl":"' + EMBED + '","streamUrl2":""}]';
  const mock = fakeFetch({
    "https://tflix.su/api/channels": [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR", isLive: true }],
    [page]: new Response("<script>self.__next_f.push(" + JSON.stringify([1, rsc]) + ")</script>"),
    [EMBED]: new Response(wrapper("var media=" + JSON.stringify(url) + ";var setupOpts={file:media,type:'hls'};")),
    [url]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", url).toString()]: new Response(tsBytes()),
  });
  const result = await tflixStreams({ catalog: "channels", room_num: "channel:bein-sports-1-tr", page_url: page, skip_probe: true }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.lines.length, 1);
  assert.equal(result.lines[0].url, url);
  assert.equal(result.lines[0].media_verified, true);
  assert.equal(mock.calls.length, 5);
});

test("a working primary remains usable if the backup embed is broken", async () => {
  const url = hlsUrl(), page = "https://tflix.su/channel/bein-sports-1-tr";
  const backup = "https://tmaxapp.site/welive/player.php?id=public-test";
  const mock = fakeFetch({
    "https://tflix.su/api/channels": [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR" }],
    [page]: new Response('<script>{"streamUrl":"' + EMBED + '","streamUrl2":"' + backup + '"}</script>'),
    [EMBED]: new Response(wrapper("var setupOpts={file:'" + url + "',type:'hls'};")),
    [backup]: new Response("Player unavailable", { status: 502 }),
    [url]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", url).toString()]: new Response(tsBytes()),
  });
  const result = await tflixStreams({ room_num: "channel:bein-sports-1-tr" }, mock);
  assert.equal(result.lines.length, 1);
  assert.equal(result.lines[0].server_name, "Server 1");
  assert.equal(result.lines[0].label, "Server 1 • HLS");
  assert.equal(mock.calls.some(({ url }) => url === backup), true);
});

test("both verified TFLIX server slots appear as separate, correctly ordered source lines", async () => {
  const first = hlsUrl(), second = CDN + "/tflix/secure/sky-sport-1/" + expiry() + "/sky-sport-1.m3u8";
  const secondEmbed = "https://vixembed.bid/embed/sky-sport-1-nz";
  const page = "https://tflix.su/match/arsenal-leeds-assigned";
  const mock = fakeFetch({
    "https://tflix.su/api/live-scores?scope=board": {
      streams: [{ slug: "arsenal-leeds-assigned", sport: "football", league: "Premier League",
        homeTeam: { name: "Arsenal" }, awayTeam: { name: "Leeds United" } }],
    },
    // Even when streamUrl2 occurs first, UI order should be server 1 then 2.
    [page]: new Response('<script>{"streamUrl2":"' + secondEmbed + '","streamUrl":"' + EMBED + '"}</script>'),
    [EMBED]: new Response(wrapper("var setupOpts={file:'" + first + "',type:'hls'};")),
    [secondEmbed]: new Response("var setupOpts={file:'" + second + "',type:'hls'};"),
    [first]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [second]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", first).toString()]: new Response(tsBytes()),
    [new URL("video.ts", second).toString()]: new Response(tsBytes()),
  });
  const result = await tflixStreams({ room_num: "match:arsenal-leeds-assigned" }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.line_count, 2);
  assert.deepEqual(result.lines.map((line) => line.server_name), ["Server 1", "Server 2"]);
  assert.deepEqual(result.lines.map((line) => line.url), [first, second]);
  assert.ok(result.lines.every((line) => line.media_verified && line.health_status === "healthy"));
});

test("broken first server does not hide a verified second server", async () => {
  const first = hlsUrl(), second = CDN + "/tflix/secure/public-test/" + expiry() + "/backup.m3u8";
  const secondEmbed = "https://vixembed.bid/embed/backup";
  const page = "https://tflix.su/channel/bein-sports-1-tr";
  const mock = fakeFetch({
    "https://tflix.su/api/channels": [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR" }],
    [page]: new Response('<script>{"streamUrl":"' + EMBED + '","streamUrl2":"' + secondEmbed + '"}</script>'),
    [EMBED]: new Response("var setupOpts={file:'" + first + "',type:'hls'};"),
    [secondEmbed]: new Response("var setupOpts={file:'" + second + "',type:'hls'};"),
    [first]: new Response("Access denied", { status: 403 }),
    [second]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", second).toString()]: new Response(tsBytes()),
  });
  const result = await tflixStreams({ room_num: "channel:bein-sports-1-tr" }, mock);
  assert.equal(result.line_count, 1);
  assert.equal(result.lines[0].server_name, "Server 2");
  assert.equal(result.lines[0].url, second);
});

test("two server slots sharing one direct manifest are deduplicated", async () => {
  const url = hlsUrl(), secondEmbed = "https://vixembed.bid/embed/duplicate";
  const page = "https://tflix.su/channel/bein-sports-1-tr";
  const segment = new URL("video.ts", url).toString();
  const routes = {
    "https://tflix.su/api/channels": [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR" }],
    [page]: () => new Response('<script>{"streamUrl":"' + EMBED + '","streamUrl2":"' + secondEmbed + '"}</script>'),
    [EMBED]: () => new Response("var setupOpts={file:'" + url + "',type:'hls'};"),
    [secondEmbed]: () => new Response("var setupOpts={file:'" + url + "',type:'hls'};"),
    [url]: () => new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [segment]: () => new Response(tsBytes()),
  };
  const mock = fakeFetch((u, init) => {
    const value = routes[u] ?? (u === "https://tflix.su/api/public"
      ? routes["https://tflix.su/api/channels"] : undefined);
    return typeof value === "function" ? value(u, init) : value;
  });
  const result = await tflixStreams({ room_num: "channel:bein-sports-1-tr" }, mock);
  assert.equal(result.line_count, 1);
  assert.equal(result.lines[0].server_name, "Server 1");
});

test("403/502 and unsupported player configurations yield zero importable lines without leaking signed URLs", async () => {
  const url = hlsUrl(), page = "https://tflix.su/channel/bein-sports-1-tr";
  const mock = fakeFetch({
    "https://tflix.su/api/channels": [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR" }],
    [page]: new Response('<script>{"streamUrl":"' + EMBED + '"}</script>'),
    [EMBED]: new Response(wrapper("var setupOpts={file:'" + url + "',type:'hls'};")),
    [url]: new Response("Denied", { status: 403 }),
  });
  const result = await tflixStreams({ room_num: "channel:bein-sports-1-tr", skip_probe: true }, mock);
  assert.equal(result.ready, false);
  assert.equal(result.lines.length, 0);
  assert.match(result.message, /HTTP 403/);
  assert.equal(result.message.includes("public-test"), false);
});

test("forged catalog page and expired signature are rejected without requesting attacker media", async () => {
  const mock = fakeFetch({ "https://tflix.su/api/channels": [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR" }] });
  await assert.rejects(tflixStreams({ room_num: "channel:bein-sports-1-tr", page_url: "https://tflix.su/channel/other" }, mock));
  assert.equal(mock.calls.length, 1);
  const url = CDN + "/tflix/secure/public-test/" + (Math.floor(Date.now() / 1000) - 1) + "/video.m3u8";
  await assert.rejects(verifyTflixMedia({ url }, EMBED, { fetcher: () => { throw new Error("Must not fetch"); } }), /expired/);
  assert.ok(signedExpiry(url));
});

test("one shared deadline covers stalled body reads and cancels upstream downloads", async () => {
  let cancelled = false;
  const fetcher = async (_, init) => new Response(new ReadableStream({
    start(controller) { init.signal.addEventListener("abort", () => { cancelled = true; controller.error(new Error("aborted")); }); },
  }));
  const started = Date.now();
  await assert.rejects(verifyTflixMedia({ url: hlsUrl() }, EMBED, { fetcher, timeoutMs: 20 }), /timed out/);
  assert.equal(cancelled, true);
  assert.ok(Date.now() - started < 500);
});

test("stalled cancellation callbacks cannot hold a completed manifest verification open", async () => {
  const url = hlsUrl();
  const started = Date.now();
  const fetcher = async () => new Response(new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode("<html>not media</html>")); controller.close(); },
    cancel() { return new Promise(() => {}); },
  }));
  await assert.rejects(verifyTflixMedia({ url }, EMBED, { fetcher, timeoutMs: 20 }), /invalid HLS/);
  assert.ok(Date.now() - started < 500);
});

test("both Edge adapters require a verified user and freshly checked Admin role before dispatching TFLIX", async () => {
  const original = { Deno: globalThis.Deno, fetch: globalThis.fetch, createClient: globalThis.createClient };
  let role = "admin", valid = true, userChecks = 0, roleChecks = 0, networkCalls = 0, gatewayChecks = 0;
  globalThis.createClient = () => ({
    auth: { getUser: async () => { userChecks++; return { data: { user: valid ? { id: "admin-test" } : null }, error: valid ? null : new Error("invalid") }; } },
    rpc: async (name, args) => {
      assert.equal(name, "get_stream_metadata_for_gateway");
      gatewayChecks++;
      return args.p_secret === "gateway-secret" ? { data: { match_valid: false }, error: null }
        : { data: null, error: new Error("unauthorized") };
    },
    from: () => ({
      select: () => ({ eq: () => ({ single: async () => { roleChecks++; return { data: { role } }; } }) }),
    }),
  });
  globalThis.fetch = async (raw) => {
    networkCalls++;
    if (String(raw) === "https://tflix.su/api/public") return Response.json({
      events: [{ slug: "public-match", sport: "Football", status: "live",
        competition: "Premier League", watch_url: "/watch/public-match",
        home_name: "Home", away_name: "Away", channels: [{
          embed_url: "https://xtrahut.xyz/embed/public-match",
        }] }],
      channels: [{ slug: "bein-sports-1-tr", name: "BeIN Sports 1 TR" }],
    });
    assert.equal(String(raw), "https://xtrahut.xyz/embed/public-match", "TFLIX must not silently fall back to Soco.");
    return new Response("<html>No direct media</html>");
  };
  try {
    for (const name of ["source-match-list", "soco-links"]) {
      let handler;
      globalThis.Deno = { serve(fn) { handler = fn; }, env: { get: () => "public-test" } };
      const source = readFileSync(new URL("../supabase/functions/" + name + "/index.ts", import.meta.url), "utf8")
        .replace(/^import .*jsr:.*;\n/gm, "")
        .replace(/"(\.\.\/_shared\/[^"]+)"/g, (_, path) => JSON.stringify(new URL("../supabase/functions/" + name + "/" + path, import.meta.url).href));
      await import("data:text/javascript;base64," + Buffer.from(stripTypeScriptTypes(source)).toString("base64"));
      const invoke = (headers = {}, body = {}) => handler(new Request("https://backend.example/" + name, {
        method: "POST", headers, body: JSON.stringify({ source: "tflix", catalog: "channels", ...body }),
      }));
      userChecks = roleChecks = networkCalls = 0;
      assert.equal((await invoke()).status, 401);
      assert.equal(userChecks, 0);
      valid = false;
      assert.equal((await invoke({ Authorization: "Bearer invalid" })).status, 401);
      assert.equal(roleChecks, 0);
      valid = true; role = "user";
      assert.equal((await invoke({ Authorization: "Bearer user" })).status, 403);
      assert.equal(networkCalls, 0);
      role = "admin";
      const response = await invoke({ Authorization: "Bearer admin" });
      const payload = await response.json();
      assert.equal(response.status, 200);
      assert.equal(payload.source, "tflix");
      assert.equal(payload.catalog, "channels");
      assert.equal(payload.matches[0].kind, "channel");
      assert.equal(networkCalls, 1);
      const unknownSource = await invoke(
        { Authorization: "Bearer admin" },
        { source: "unknown-provider" },
      );
      assert.equal(unknownSource.status, 400);
      assert.deepEqual(await unknownSource.json(), { error: "Unsupported source." });
      assert.equal(networkCalls, 1, "Unknown providers must not silently fetch the Soco catalog.");
      // A restored JWT must not keep using an Admin role that was revoked.
      role = "user";
      assert.equal((await invoke({ Authorization: "Bearer formerly-admin" })).status, 403);
      assert.equal(networkCalls, 1);
      role = "admin";
      const publicResult = await invoke({ Authorization: "Bearer admin" }, { viewer_public: true });
      assert.equal(publicResult.status, name === "soco-links" ? 200 : 403);
      if (name === "soco-links") assert.equal((await publicResult.json()).source, "tflix");
      assert.equal(networkCalls, name === "soco-links" ? 2 : 1);
      if (name === "soco-links") {
        const checks = userChecks;
        const publicWithoutSession = await invoke({}, { viewer_public: true });
        assert.equal(publicWithoutSession.status, 200);
        assert.equal(userChecks, checks);
        assert.equal(networkCalls, 3);
        assert.equal(gatewayChecks, 0);

        const noSecret = await invoke({}, { viewer_public: true, action: "streams", source_id: "match:public-match" });
        assert.equal(noSecret.status, 403);
        assert.equal(gatewayChecks, 0);
        const protectedLookup = await invoke({}, { viewer_public: true, action: "streams",
          source_id: "match:public-match", playback_secret: "gateway-secret" });
        assert.equal(protectedLookup.status, 200);
        assert.equal((await protectedLookup.json()).line_count, 0);
        assert.equal(gatewayChecks, 1);
      }
    }
  } finally {
    globalThis.Deno = original.Deno; globalThis.fetch = original.fetch; globalThis.createClient = original.createClient;
  }
});


test("TFLIX matches resolve public events payload even when channels array is omitted", async () => {
  const slug = "public-events-only";
  const page = "https://tflix.su/watch/" + slug;
  const media = hlsUrl();
  const mock = fakeFetch({
    "https://tflix.su/api/public": {
      events: [{
        sport: "Football", status: "live", watch_url: "/watch/" + slug,
        competition: "England: Premier League", home_name: "Home", away_name: "Away",
        channels: [{ name: "Sports", embed_url: EMBED }],
      }],
    },
    [EMBED]: new Response("var config={file:'" + media + "',type:'hls'}"),
    [media]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    [new URL("segment.ts",media).toString()]: new Response(tsBytes()),
  });
  const result = await tflixStreams({ room_num: "match:" + slug, page_url: page }, mock);
  assert.equal(result.ready,true);
  assert.equal(result.lines.length,1);
  assert.equal(result.lines[0].media_verified,true);
});

test("TFLIX channels resolve a public channels-only payload", async () => {
  const media = hlsUrl();
  const id = "bein-sports-demo";
  const mock = fakeFetch({
    "https://tflix.su/api/public": {
      channels: [{ slug: id, name: "BeIN Sports Demo", enabled: true, embed_url: EMBED }],
    },
    [EMBED]: new Response("var source={file:'" + media + "'}"),
    [media]: new Response("#EXTM3U\n#EXTINF:6,\nsegment.ts"),
    [new URL("segment.ts",media).toString()]: new Response(tsBytes()),
  });
  const result = await tflixStreams({ room_num: "channel:" + id }, mock);
  assert.equal(result.ready,true);
  assert.equal(result.lines.length,1);
});

test("TFLIX malformed unified public response retries legacy public catalog", async () => {
  const mock = fakeFetch({
    "https://tflix.su/api/public": { status: "ok" },
    "https://tflix.su/api/channels": [{
      slug: "bein-sports-demo", name: "BeIN Sports Demo", enabled: true,
    }],
  });
  const result = await tflixMatches({catalog:"channels"},mock);
  assert.equal(result.results,1);
  assert.equal(mock.calls.length,2);
});


test("TFLIX public player streamUrl literal is verified as media, not assumed playable", async () => {
  const match = "direct-public-player";
  const url = hlsUrl();
  const embed = "https://vixembed.bid/embed/direct-public-player";
  const mock = fakeFetch({
    "https://tflix.su/api/public": {
      events: [{
        sport: "Football", status: "live", watch_url: "/watch/" + match,
        competition: "Fixture", home_name: "Team A", away_name: "Team B",
        channels: [{ name: "Public player", embed_url: embed }],
      }],
    },
    [embed]: new Response('<script>const config={streamUrl:"' + url + '"}</script>'),
    [url]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", url).toString()]: new Response(tsBytes()),
  });
  const result = await tflixViewerStreams({ source_id: "match:" + match, label_prefix: "TFLIX" }, mock);
  assert.equal(result.line_count, 1);
  assert.equal(result.lines[0].media_verified, true);
  assert.equal(result.lines[0].key_id, null);
  assert.equal(result.lines[0].key_data, null);
});

test("TFLIX can recover a different public page player after broken catalog embed", async () => {
  const match = "fallback-public-player";
  const page = "https://tflix.su/watch/" + match;
  const first = "https://xtrahut.xyz/embed/failed-public-fixture";
  const backup = "https://vixembed.bid/embed/public-page-backup";
  const url = hlsUrl();
  const mock = fakeFetch({
    "https://tflix.su/api/public": {
      events: [{
        sport: "Football", status: "live", watch_url: "/watch/" + match,
        competition: "Fixture", home_name: "Team A", away_name: "Team B",
        channels: [{ name: "Main", embed_url: first }],
      }],
    },
    [first]: new Response("Unavailable", { status: 503 }),
    [page]: new Response('<script>const player={streamUrl:"' + backup + '"};</script>'),
    [backup]: new Response('<script>const opts={streamUrl:"' + url + '"};</script>'),
    [url]: new Response("#EXTM3U\n#EXTINF:6,\nvideo.ts"),
    [new URL("video.ts", url).toString()]: new Response(tsBytes()),
  });
  const result = await tflixViewerStreams({ source_id: "match:" + match, label_prefix: "TFLIX" }, mock);
  assert.equal(result.ready, true);
  assert.equal(result.line_count, 1);
  assert.equal(result.lines[0].stream_url, url);
  assert.equal(mock.calls.some(x => x.url === first), true);
  assert.equal(mock.calls.some(x => x.url === page), true);
  assert.equal(mock.calls.some(x => x.url === backup), true);
});

test("TFLIX rejects a direct literal on an unauthorized host without media access", async () => {
  const match = "blocked-public-player";
  const embed = "https://vixembed.bid/embed/blocked-public-player";
  const mock = fakeFetch({
    "https://tflix.su/api/public": {
      events: [{
        sport: "Football", status: "live", watch_url: "/watch/" + match,
        competition: "Fixture", home_name: "A", away_name: "B",
        channels: [{ name: "Public player", embed_url: embed }],
      }],
    },
    [embed]: new Response(
      '<script>const config={streamUrl:"https://private.example/live.m3u8"}</script>',
    ),
  });
  const result = await tflixViewerStreams({ source_id: "match:" + match, label_prefix: "TFLIX" }, mock);
  assert.equal(result.line_count, 0);
  assert.equal(mock.calls.some(x => x.url.includes("private.example")), false);
});


test("TFLIX verifies a slow four-hop public stream within the Viewer request budget", async () => {
  const slug = "slow-four-hop-fixture";
  const media = hlsUrl();
  const segment = new URL("part.ts", media).toString();
  const responses = {
    "https://tflix.su/api/public": {
      events: [{ sport: "Football", status: "live",
        watch_url: "/watch/" + slug, home_name: "Home", away_name: "Away",
        channels: [{ name: "Public server", embed_url: EMBED }] }],
    },
    [EMBED]: new Response('<script>const player={streamUrl:"' + media + '"};</script>'),
    [media]: new Response("#EXTM3U\n#EXTINF:6,\npart.ts"),
    [segment]: new Response(tsBytes()),
  };
  const slow = fakeFetch(async (url, init) => {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(resolve, 1800);
      init.signal?.addEventListener("abort", () => {
        clearTimeout(timer);
        reject(new Error("Request aborted"));
      }, { once: true });
    });
    return responses[url];
  });
  const result = await tflixViewerStreams({
    source_id: "match:" + slug, label_prefix: "TFLIX",
  }, slow);
  assert.equal(result.line_count, 1);
  assert.equal(result.ready, true);
  assert.equal(result.lines[0].media_verified, true);
  assert.equal(result.lines[0].stream_url, media);
  assert.deepEqual(slow.calls.map(x => x.url),
    ["https://tflix.su/api/public", EMBED, media, segment]);
});
