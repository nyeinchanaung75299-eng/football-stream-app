import test from "node:test";
import assert from "node:assert/strict";
import { experimentalMatches, explicitKickoff, experimentalStreams } from "../supabase/functions/_shared/experimental_football_sources.mjs";

function pages(map) {
  return async (url) => {
    const body = map[String(url)] ?? "<html></html>";
    return { ok: true, status: 200,
      headers: { get: (key) => key === "content-type" ? "text/html" : null },
      text: async () => body,
    };
  };
}

test("CricHD event slug can resolve a confirmed UTC kickoff", async () => {
  const data = await experimentalMatches("crichd", {fetcher: pages({
    "https://crichd.pk/sports/soccer-streams": '<a href="/event/arsenal-vs-liverpool">Arsenal Liverpool</a>',
    "https://crichd.pk/event/arsenal-vs-liverpool": '<time datetime="2026-11-11T19:00:00Z">19:00 UTC</time>',
  })});
  assert.equal(data.matches.length, 1);
  assert.equal(data.matches[0].home_team, "Arsenal");
  assert.equal(data.matches[0].away_team, "Liverpool");
  assert.equal(data.matches[0].match_time, "2026-11-11T19:00:00.000Z");
  assert.equal(data.diagnostics.confirmed_kickoff_count, 1);
});

test("No kickoff is inferred from a blog publish timestamp or countdown", async () => {
  const data = await experimentalMatches("crichd", {fetcher: pages({
    "https://crichd.pk/sports/soccer-streams": '<a href="/event/arsenal-vs-liverpool">Arsenal Liverpool</a>',
    "https://crichd.pk/event/arsenal-vs-liverpool": '<meta name="datePublished" content="2026-11-10T15:00:00Z">Starts in 03:20:00',
  })});
  assert.equal(data.matches.length, 1);
  assert.equal(data.matches[0].match_time, null);
  assert.equal(data.matches[0].verified_kickoff, false);
  assert.equal(data.diagnostics.confirmed_kickoff_count, 0);
  assert.equal(explicitKickoff("Starts in 03:02:50"), null);
});

test("External-domain event URLs are ignored", async () => {
  const data = await experimentalMatches("crichd", {fetcher: pages({
    "https://crichd.pk/sports/soccer-streams": '<a href="https://outsider.invalid/event/arsenal-vs-liverpool">Arsenal vs Liverpool</a>',
  })});
  assert.equal(data.results, 0);
});

test("No HLS/DASH lines are invented when a page contains no media URL", async () => {
  const data = await experimentalStreams("crichd", {
    page_url: "https://crichd.pk/event/arsenal-vs-liverpool",
  }, {fetcher: pages({
    "https://crichd.pk/event/arsenal-vs-liverpool": "<html>Stream available soon</html>",
  })});
  assert.deepEqual(data.lines, []);
  assert.equal(data.ready, false);
});

test("Fresh 03:02:50 countdown converts to an estimated UTC kickoff and Myanmar local time", async () => {
  // Nov 11 05:17 MMT = Nov 10 22:47 UTC.
  const observedAt = Date.parse("2026-11-10T22:47:00Z");
  const data = await experimentalMatches("crichd", {
    now: () => observedAt,
    fetcher: pages({
      "https://crichd.pk/sports/soccer-streams":
        '<a href="/event/arsenal-vs-liverpool"><span>Starts in: 03:02:50</span> Arsenal Liverpool</a>',
    }),
  });
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].match_time, "2026-11-11T01:49:50.000Z");
  assert.equal(data.matches[0].kickoff_estimated, true);
  assert.equal(data.matches[0].verified_kickoff, false);
  assert.equal(data.matches[0].kickoff_source, "countdown");
  // 01:49:50 UTC + 06:30 = 08:19:50 Myanmar time.
  assert.equal(data.diagnostics.estimated_countdown_count, 1);
});

test("Stale HTTP countdown cannot invent a football kickoff", async () => {
  const observedAt = Date.parse("2026-11-10T22:47:00Z");
  const data = await experimentalMatches("crichd", {
    now: () => observedAt,
    fetcher: async (url) => ({
      ok: true, status: 200,
      headers: {get: (key) => key === "content-type" ? "text/html"
        : key === "age" ? "200" : null},
      text: async () => String(url).includes("/event/")
        ? "<html></html>"
        : '<a href="/event/arsenal-vs-liverpool"><span>Starts in: 03:02:50</span> Arsenal Liverpool</a>',
    }),
  });
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].match_time, null);
  assert.equal(data.diagnostics.estimated_countdown_count, 0);
});
