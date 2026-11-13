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

// The retired experimental sources are not supported by the app or backend.
// Keep regression coverage for the remaining allowed Rojadirecta provider.

test("Public football SportsEvent with title and same-site URL is recognized", async () => {
  const page = '<script type="application/ld+json">'+JSON.stringify({
    "@type":"SportsEvent",sport:"Soccer",
    name:"Arsenal vs Chelsea",url:"/football/arsenal-chelsea",
    startDate:"2026-11-11T19:00:00Z"
  })+'</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://www.rojadirectavivo.me/live-football":page,
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].home_team,"Arsenal");
  assert.equal(data.matches[0].away_team,"Chelsea");
  assert.equal(data.diagnostics.available_days_mmt[0],"2026-11-12");
});

test("Public JSON site metadata alone does not create fake football matches", async () => {
  const page = '<script type="application/ld+json">'+JSON.stringify({
    "@type":"WebSite",name:"Sports Portal",url:"https://www.rojadirectavivo.me/"
  })+'</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://www.rojadirectavivo.me/live-football":page,
  })});
  assert.equal(data.results,0);
  assert.equal(data.diagnostics.embedded_json_documents,1);
  assert.deepEqual(data.diagnostics.available_days_mmt,[]);
});


test("Valid public SportsEvent without URL is schedule only, not a stream", async () => {
  const html = '<script type="application/ld+json">' + JSON.stringify({
    "@type":"SportsEvent", sport:"Football",
    homeTeam:{name:"Arsenal"},awayTeam:{name:"Chelsea"},
    startDate:"2026-11-11T19:00:00Z",
  }) + '</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://www.rojadirectavivo.me/live-football":html,
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].match_time,"2026-11-11T19:00:00.000Z");
  assert.equal(data.matches[0].page_url,null);
  assert.equal(data.matches[0].schedule_only,true);
  assert.deepEqual(data.matches[0].anchors,[]);
  assert.equal(data.diagnostics.schedule_only_count,1);
  assert.deepEqual(data.diagnostics.available_days_mmt,["2026-11-12"]);
});

test("Generic JSON without SportsEvent type and URL does not invent fixtures", async () => {
  const html='<script type="application/json">'+JSON.stringify({
    sport:"Football",homeTeam:{name:"Arsenal"},awayTeam:{name:"Chelsea"},
    startDate:"2026-11-11T19:00:00Z",
  })+'</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://www.rojadirectavivo.me/live-football":html,
  })});
  assert.equal(data.results,0);
});

test("External links never turn into trusted schedule-only video sources", async () => {
  const html='<script type="application/ld+json">'+JSON.stringify({
    "@type":"SportsEvent",sport:"Football",
    homeTeam:{name:"Arsenal"},awayTeam:{name:"Chelsea"},
    startDate:"2026-11-11T19:00:00Z",
    url:"https://foreign.invalid/event/arsenal-vs-chelsea",
  })+'</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://www.rojadirectavivo.me/live-football":html,
  })});
  assert.equal(data.results,0);
});



test("Only Rojadirecta remains an available experimental provider", async () => {
  const {isExperimentalFootballSource,experimentalFootballSites} =
    await import("../supabase/functions/_shared/experimental_football_sources.mjs");
  assert.deepEqual(Object.keys(experimentalFootballSites),["rojadirecta"]);
  for (const retired of ["camel","xoilac","livetv","crichd","roxie","vipbox",
      "viprow","score088","sports808","livextv","streamfree","ppv"]) {
    assert.equal(isExperimentalFootballSource(retired),false,retired);
  }
});

test("Rojadirecta without a public media URL never invents HLS", async () => {
  const page="https://www.rojadirectavivo.me/live-football";
  const output=await experimentalStreams("rojadirecta",{page_url:page},{fetcher:pages({
    [page]:"<html><body>No public media URL</body></html>",
  })});
  assert.deepEqual(output.lines,[]);
});

test("Rojadirecta cannot use a foreign host as an event page", async () => {
  const result = await experimentalStreams("rojadirecta",
    {page_url:"https://foreign.invalid/event/one"},
    {fetcher:pages({})});
  assert.equal(result.ready, false);
  assert.deepEqual(result.lines, []);
});
