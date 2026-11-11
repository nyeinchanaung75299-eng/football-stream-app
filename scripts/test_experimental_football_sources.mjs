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

test("No kickoff is inferred from an article publication timestamp alone", async () => {
  const data = await experimentalMatches("crichd", {fetcher: pages({
    "https://crichd.pk/sports/soccer-streams": '<a href="/event/arsenal-vs-liverpool">Arsenal Liverpool</a>',
    "https://crichd.pk/event/arsenal-vs-liverpool": '<meta name="datePublished" content="2026-11-10T15:00:00Z">No published kickoff',
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


test("Pick Big Matches reads explicit football times from a JSON-LD SportsEvent", async () => {
  const html = '<html><script type="application/ld+json">' +
    JSON.stringify({"@type":"SportsEvent",sport:"Football",name:"Arsenal vs Liverpool",
      homeTeam:{name:"Arsenal"},awayTeam:{name:"Liverpool"},
      startDate:"2026-11-11T19:00:00Z",url:"/event/arsenal-vs-liverpool"}) +
    '</script></html>';
  const data = await experimentalMatches("crichd", {fetcher:pages({
    "https://crichd.pk/sports/soccer-streams":html,
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].home_team,"Arsenal");
  assert.equal(data.matches[0].away_team,"Liverpool");
  assert.equal(data.matches[0].match_time,"2026-11-11T19:00:00.000Z");
  assert.equal(data.matches[0].verified_kickoff,true);
  assert.equal(data.diagnostics.embedded_json_documents,1);
});

test("Sources and Pick Big Matches read public Next.js event JSON without running scripts", async () => {
  const next = {props:{pageProps:{events:[{
    id:123,homeTeam:{name:"Liverpool"},awayTeam:{name:"Man City"},
    sport:{name:"Football"},tournament:{name:"Premier League"},
    url:"/football/liverpool-vs-man-city",startTimestamp:1794420000,
  }]}}};
  const data=await experimentalMatches("sports808", {fetcher:pages({
    "https://www.livesports808.cc/football?lang=2":
      '<script id="__NEXT_DATA__" type="application/json">'+JSON.stringify(next)+'</script>',
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].league,"Premier League");
  assert.equal(data.matches[0].source,"sports808");
  assert.equal(data.matches[0].verified_kickoff,true);
  assert.equal(data.matches[0].match_time,new Date(1794420000*1000).toISOString());
});

test("Generic multisport JSON requires football evidence and rejects foreign event hosts", async () => {
  const page={events:[
    {homeTeam:{name:"Boston"},awayTeam:{name:"Lakers"},sport:"Basketball",
      url:"/event/boston-vs-lakers",startDate:"2026-11-11T19:00:00Z"},
    {homeTeam:{name:"Arsenal"},awayTeam:{name:"Liverpool"},sport:"Football",
      url:"https://another-site.example/event/arsenal-vs-liverpool",startDate:"2026-11-11T19:00:00Z"},
    {homeTeam:{name:"Arsenal"},awayTeam:{name:"Liverpool"},sport:"Football",
      url:"/football/arsenal-vs-liverpool",startDate:"2026-11-11T19:00:00Z"},
  ]};
  const data=await experimentalMatches("streamfree",{fetcher:pages({
    "https://strmfree.st/":'<script type="application/json">'+JSON.stringify(page)+'</script>',
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].home_team,"Arsenal");
  assert.equal(data.matches[0].away_team,"Liverpool");
});

test("Invalid JavaScript state and unrelated strings cannot create matches", async () => {
  const data=await experimentalMatches("crichd",{fetcher:pages({
    "https://crichd.pk/sports/soccer-streams":
      '<script>window.__INITIAL_STATE__={homeTeam:"Arsenal",evil:function(){}};</script>'+
      '<script type="application/json">{"homeTeam":"Arsenal","awayTeam":"Liverpool","url":"https://outside.example/football/arsenal-vs-liverpool"}</script>',
  })});
  assert.equal(data.results,0);
  assert.equal(data.diagnostics.content_state,"no_recognized_football_fixtures");
});


test("CricHD countowns in each single-event li card map to the correct fixture", async () => {
  const observed = Date.parse("2026-11-10T22:00:00Z");
  const html = [
    '<ul>',
    '<li class="match"><a href="/event/arsenal-vs-chelsea">Arsenal vs Chelsea</a><span>Starts in: 01:30:00</span></li>',
    '<li class="match"><a href="/event/liverpool-vs-everton">Liverpool vs Everton</a><span>Starts in: 04:00:00</span></li>',
    '</ul>',
  ].join("");
  const result = await experimentalMatches("crichd",{
    now: () => observed,
    fetcher: pages({"https://crichd.pk/sports/soccer-streams":html}),
  });
  assert.equal(result.matches.length,2);
  assert.equal(result.matches[0].home_team,"Arsenal");
  assert.equal(result.matches[0].match_time,"2026-11-10T23:30:00.000Z");
  assert.equal(result.matches[0].kickoff_estimated,true);
  assert.equal(result.matches[1].home_team,"Liverpool");
  assert.equal(result.matches[1].match_time,"2026-11-11T02:00:00.000Z");
  assert.equal(result.diagnostics.estimated_countdown_count,2);
});

test("Countdown in another match card never leaks to this match", async () => {
  const catalog = '<li><a href="/event/arsenal-vs-chelsea">Arsenal vs Chelsea</a><span>Starts in: 01:30:00</span></li>'+
    '<li><a href="/event/liverpool-vs-everton">Liverpool vs Everton</a></li>';
  const data = await experimentalMatches("crichd", {fetcher:pages({
    "https://crichd.pk/sports/soccer-streams": catalog,
  })});
  assert.equal(data.results,2);
  const noTime=data.matches.find(m=>m.home_team==="Liverpool");
  assert.equal(noTime.match_time,null);
});

test("JSON countdown in seconds is supported only for a fresh response", async () => {
  const observed=Date.parse("2026-11-10T22:00:00Z");
  const embedded = '<script type="application/ld+json">'+
    JSON.stringify({"@type":"SportsEvent", sport:"Football",
      homeTeam:{name:"Arsenal"},awayTeam:{name:"Chelsea"},
      url:"/event/arsenal-vs-chelsea",countdown:5400})+
    '</script>';
  const data=await experimentalMatches("crichd",{
    now:()=>observed,fetcher:pages({"https://crichd.pk/sports/soccer-streams":embedded}),
  });
  assert.equal(data.results,1);
  assert.equal(data.matches[0].match_time,"2026-11-10T23:30:00.000Z");
  assert.equal(data.matches[0].kickoff_estimated,true);
});

test("MMT date remains correct across a Myanmar day boundary", () => {
  const actualUtc = Date.parse("2026-11-10T21:30:00Z");
  const mmt = new Date(actualUtc + (6*60+30)*60*1000);
  assert.equal(mmt.toISOString().slice(0,10),"2026-11-11");
  assert.equal(mmt.toISOString().slice(11,16),"04:00");
});


test("Provider exposes actual Myanmar dates when valid UTC kickoff falls on next MMT day", async () => {
  const page = '<script type="application/ld+json">'+JSON.stringify({
    "@type":"SportsEvent",sport:"Football",homeTeam:{name:"Arsenal"},
    awayTeam:{name:"Chelsea"},url:"/event/arsenal-vs-chelsea",
    startDate:"2026-11-11T21:30:00Z"
  })+'</script>';
  const data=await experimentalMatches("crichd",{fetcher:pages({
    "https://crichd.pk/sports/soccer-streams":page,
  })});
  assert.equal(data.results,1);
  assert.equal(data.diagnostics.confirmed_kickoff_count,1);
  assert.deepEqual(data.diagnostics.available_days_mmt,["2026-11-12"]);
});

test("Public football SportsEvent with title and same-site URL is recognized", async () => {
  const page = '<script type="application/ld+json">'+JSON.stringify({
    "@type":"SportsEvent",sport:"Soccer",
    name:"Arsenal vs Chelsea",url:"/football/arsenal-chelsea",
    startDate:"2026-11-11T19:00:00Z"
  })+'</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://en.rojadirectaes.org/live-football":page,
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].home_team,"Arsenal");
  assert.equal(data.matches[0].away_team,"Chelsea");
  assert.equal(data.diagnostics.available_days_mmt[0],"2026-11-12");
});

test("Public JSON site metadata alone does not create fake football matches", async () => {
  const page = '<script type="application/ld+json">'+JSON.stringify({
    "@type":"WebSite",name:"Sports Portal",url:"https://en.rojadirectaes.org/"
  })+'</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://en.rojadirectaes.org/live-football":page,
  })});
  assert.equal(data.results,0);
  assert.equal(data.diagnostics.embedded_json_documents,1);
  assert.deepEqual(data.diagnostics.available_days_mmt,[]);
});
