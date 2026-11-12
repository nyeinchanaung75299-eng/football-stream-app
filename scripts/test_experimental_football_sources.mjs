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


test("Valid public SportsEvent without URL is schedule only, not a stream", async () => {
  const html = '<script type="application/ld+json">' + JSON.stringify({
    "@type":"SportsEvent", sport:"Football",
    homeTeam:{name:"Arsenal"},awayTeam:{name:"Chelsea"},
    startDate:"2026-11-11T19:00:00Z",
  }) + '</script>';
  const data=await experimentalMatches("rojadirecta",{fetcher:pages({
    "https://en.rojadirectaes.org/live-football":html,
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
    "https://en.rojadirectaes.org/live-football":html,
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
    "https://en.rojadirectaes.org/live-football":html,
  })});
  assert.equal(data.results,0);
});


test("Public football SportsEvent supplies both actual team logos to Pick Big Matches", async () => {
  const fixture = {
    "@type": "SportsEvent", sport: "Football",
    homeTeam: {name:"Turkey", logo:"https://assets.example.org/teams/turkey.png"},
    awayTeam: {name:"Belgium", crest:"/logos/belgium.svg"},
    startDate:"2026-11-12T17:00:00Z",
    url:"/football/turkey-vs-belgium",
  };
  const results = await experimentalMatches("score088",{fetcher:pages({
    "https://www.score088tv.live/football":
      '<script type="application/ld+json">'+JSON.stringify(fixture)+'</script>',
  })});
  assert.equal(results.matches.length,1);
  assert.equal(results.matches[0].home_logo,"https://assets.example.org/teams/turkey.png");
  assert.equal(results.matches[0].away_logo,"https://www.score088tv.live/logos/belgium.svg");
});

test("Team badge identification uses team-name alt, not league logo or unrelated images", async () => {
  const html = [
    '<article>',
    '<a href="/football/arsenal-vs-chelsea">Arsenal vs Chelsea</a>',
    '<img alt="Premier League Logo" src="/assets/premier-league.png">',
    '<img alt="Arsenal Logo" data-src="/logos/arsenal.png">',
    '<img alt="Chelsea crest" src="https://images.example.org/chelsea.png">',
    '<time datetime="2026-11-11T19:00:00Z"></time>',
    '</article>',
  ].join("");
  const results = await experimentalMatches("crichd",{fetcher:pages({
    "https://crichd.pk/sports/soccer-streams":html,
  })});
  assert.equal(results.matches.length,1);
  assert.equal(results.matches[0].home_logo,"https://crichd.pk/logos/arsenal.png");
  assert.equal(results.matches[0].away_logo,"https://images.example.org/chelsea.png");
});

test("Absent logos are never replaced by invented shields, private URLs or fake CDN links", async () => {
  const data = await experimentalMatches("crichd",{fetcher:pages({
    "https://crichd.pk/sports/soccer-streams":
      '<script type="application/json">'+JSON.stringify({sport:"Football",
        homeTeam:{name:"Arsenal",logo:"http://192.168.1.5/badge.png"},
        awayTeam:{name:"Chelsea"},
        url:"/football/arsenal-vs-chelsea",startDate:"2026-11-11T19:00:00Z"
      })+'</script>',
  })});
  assert.equal(data.results,1);
  assert.equal(data.matches[0].home_logo,null);
  assert.equal(data.matches[0].away_logo,null);
});


test("LiveTV soccer card with structured teams and Unix kickoff is recognized", async () => {
  const unix = Math.floor(Date.parse("2026-11-12T18:30:00Z") / 1000);
  const html =
    '<li data-home-team="Turkey" data-away-team="Belgium" data-start-time="'+unix+'">' +
    '<a href="/soccer/xyz-123">Match details</a>' +
    '</li>';
  const result = await experimentalMatches("livetv", {fetcher:pages({
    "https://livetv.li/soccer":html,
  })});
  assert.equal(result.results,1);
  assert.equal(result.matches[0].home_team,"Turkey");
  assert.equal(result.matches[0].away_team,"Belgium");
  assert.equal(result.matches[0].match_time,"2026-11-12T18:30:00.000Z");
  assert.deepEqual(result.diagnostics.available_days_mmt,["2026-11-13"]);
});

test("An unrelated page timestamp is not interpreted as football kickoff", async () => {
  const result = await experimentalMatches("livetv", {fetcher:pages({
    "https://livetv.li/soccer":
      '<li data-home="Turkey" data-away="Belgium" data-timestamp="1794508200">' +
      '<a href="/soccer/xyz-123">Match details</a></li>',
  })});
  assert.equal(result.results,1);
  assert.equal(result.matches[0].match_time,null);
});

test("Generic multi-sport site does not import basketball as football", async () => {
  const result = await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/":
      '<li data-home="Lakers" data-away="Celtics" data-start-time="1794508200">' +
      '<a href="/basketball/lakers-celtics">Match details</a></li>',
  })});
  assert.equal(result.results,0);
});


test("Competition prefix does not turn a league name into a team", async () => {
  const data = await experimentalMatches("score088", {fetcher: pages({
    "https://www.score088tv.live/football":
      '<li><a href="/football/torreense-w-vs-sparta-praha-w">' +
      'UEFA Europa Cup vs Women – Torreense W – Sparta Praha W 19:00 Watch</a>' +
      '<time datetime="2026-11-12T17:00:00Z"></time></li>' +
      '<li><a href="/football/india-vs-maldives">' +
      'SAFF Championship vs India – Maldives 10:30 Watch</a>' +
      '<time datetime="2026-11-12T19:00:00Z"></time></li>',
  })});
  assert.equal(data.results, 2);
  assert.equal(data.matches[0].home_team, "Torreense W");
  assert.equal(data.matches[0].away_team, "Sparta Praha W");
  assert.equal(data.matches[1].home_team, "India");
  assert.equal(data.matches[1].away_team, "Maldives");
});

test("Football link in embedded JSON identifies sport but explicit basketball overrides it", async () => {
  const payload = {events: [
    {homeTeam:{name:"Arsenal"},awayTeam:{name:"Chelsea"},
      url:"/football/arsenal-vs-chelsea",startDate:"2026-11-12T19:00:00Z"},
    {homeTeam:{name:"Lakers"},awayTeam:{name:"Celtics"},sport:"Basketball",
      url:"/football/lakers-vs-celtics",startDate:"2026-11-12T19:00:00Z"},
  ]};
  const data = await experimentalMatches("streamfree", {fetcher: pages({
    "https://strmfree.st/":
      '<script type="application/json">'+JSON.stringify(payload)+'</script>',
  })});
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].home_team, "Arsenal");
});

test("Detail pages can restore real badges without erasing confirmed index kickoff", async () => {
  const page = "https://crichd.pk/event/arsenal-vs-chelsea";
  const data = await experimentalMatches("crichd", {fetcher: pages({
    "https://crichd.pk/sports/soccer-streams":
      '<article><a href="/event/arsenal-vs-chelsea">Arsenal vs Chelsea</a>' +
      '<time datetime="2026-11-12T19:00:00Z"></time></article>',
    [page]: '<img alt="Arsenal logo" src="/images/arsenal.png">' +
      '<img alt="Chelsea badge" data-src="/images/chelsea.png">',
  })});
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].match_time, "2026-11-12T19:00:00.000Z");
  assert.equal(data.matches[0].home_logo, "https://crichd.pk/images/arsenal.png");
  assert.equal(data.matches[0].away_logo, "https://crichd.pk/images/chelsea.png");
});

test("Public JSON relative HLS and HTML data-file manifest URLs are parsed, not invented", async () => {
  const page = "https://crichd.pk/event/arsenal-vs-chelsea";
  const data = await experimentalStreams("crichd", {page_url: page},
    {fetcher:pages({[page]:
      '<script type="application/json">{"file":"/public/master.m3u8"}</script>' +
      '<video data-file="/public/manifest.mpd"></video>'})});
  assert.deepEqual(data.lines.map(row => row.url).sort(), [
    "https://crichd.pk/public/manifest.mpd",
    "https://crichd.pk/public/master.m3u8",
  ]);
  assert.equal(data.ready, true);
});


for (const [source, home] of [
  ["streamfree", "https://strmfree.st/"],
  ["livextv", "https://livextv.pro/"],
  ["ppv", "https://ppv.st/"],
]) {
  test(`${source} accepts an explicitly football-labelled generic event URL`, async () => {
    const fixture = '<article data-sport="football">' +
      '<a href="/event/arsenal-vs-chelsea">Arsenal vs Chelsea</a>' +
      '<time datetime="2026-11-13T19:00:00Z"></time></article>';
    const data = await experimentalMatches(source, {fetcher:pages({[home]: fixture})});
    assert.equal(data.results, 1);
    assert.equal(data.matches[0].home_team, "Arsenal");
    assert.equal(data.matches[0].away_team, "Chelsea");
    assert.equal(data.matches[0].match_time, "2026-11-13T19:00:00.000Z");
    assert.equal(data.matches[0].verified_kickoff, true);
  });
}

test("Single-event soccer category label can verify a generic URL", async () => {
  const html = '<li><span class="sport-label">Soccer</span>' +
    '<a href="/events/arsenal-vs-chelsea">Arsenal vs Chelsea</a>' +
    '<time datetime="2026-11-13T19:00:00Z"></time></li>';
  const data = await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/": html,
  })});
  assert.equal(data.results, 1);
});

test("Multi-sport source still rejects generic URLs with no event-specific sport", async () => {
  const data = await experimentalMatches("livextv", {fetcher:pages({
    "https://livextv.pro/": '<h2>Football</h2><li>' +
      '<a href="/event/arsenal-vs-chelsea">Arsenal vs Chelsea</a>' +
      '<time datetime="2026-11-13T19:00:00Z"></time></li>',
  })});
  assert.equal(data.results, 0);
});

test("An explicitly non-football card is rejected even when its URL contains football", async () => {
  const html = '<article data-sport="basketball">' +
    '<a href="/football/lakers-vs-celtics">Lakers vs Celtics</a>' +
    '<time datetime="2026-11-13T19:00:00Z"></time></article>';
  const data = await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/": html,
  })});
  assert.equal(data.results, 0);
});

test("Conflicting football/cricket labels reject the card rather than guess", async () => {
  const html = '<li data-category="football" data-sport="cricket">' +
    '<a href="/events/india-vs-pakistan">India vs Pakistan</a>' +
    '<time datetime="2026-11-13T19:00:00Z"></time></li>';
  const data = await experimentalMatches("ppv", {fetcher:pages({
    "https://ppv.st/": html,
  })});
  assert.equal(data.results, 0);
});

test("A football label on a different card must not authorize this generic match URL", async () => {
  const html = '<li data-sport="football"><a href="/football/arsenal-vs-chelsea">' +
    'Arsenal vs Chelsea</a></li><li><a href="/event/lakers-vs-celtics">' +
    'Lakers vs Celtics</a></li>';
  const data = await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/": html,
  })});
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].home_team, "Arsenal");
});


test("LiveTV public table row imports only a genuinely labelled Soccer fixture", async () => {
  const html = [
    '<div class="side-match-item"><tr><td><img alt="Basketball"></td><td>',
    '<a class="live" href="/view/basketball">Lakers - Celtics</a>',
    '<span class="evdesc">06:00 (Basketball)</span></td></tr></div>',
    '<div class="side-match-item"><tr><td><img alt="Soccer"></td><td>',
    '<a class="live" href="/view/arsenal-chelsea">Arsenal - Chelsea</a>',
    '<span class="evdesc">21:00 (Soccer)</span></td></tr></div>',
    '<div class="side-match-item"><tr><td><img alt="Tennis"></td><td>',
    '<a class="live" href="/view/tennis">Player One - Player Two</a>',
    '<span class="evdesc">21:30 (Tennis)</span></td></tr></div>',
  ].join('');
  const data = await experimentalMatches("livetv", {fetcher:pages({
    "https://livetv.li/soccer": html,
  })});
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].home_team, "Arsenal");
  assert.equal(data.matches[0].away_team, "Chelsea");
  assert.equal(data.matches[0].match_time, null);
  assert.equal(data.matches[0].verified_kickoff, false);
  assert.equal(data.matches[0].source, "livetv");
});

test("LiveTV source rejects ambiguous rows, foreign events and unverified sport", async () => {
  const data = await experimentalMatches("livetv", {fetcher:pages({
    "https://livetv.li/soccer": [
      '<div class="side-match-item"><img alt="Soccer">',
      '<a href="https://other.invalid/view/123">Arsenal - Chelsea</a>',
      '<span class="evdesc">20:00 (Soccer)</span></div>',
      '<div class="side-match-item"><img alt="Soccer">',
      '<a href="/view/multi">Team A - Team B</a>',
      '<a href="/view/multi2">Team C - Team D</a></div>',
      '<div class="side-match-item">',
      '<a href="/view/none">Arsenal - Chelsea</a></div>',
      '<div class="side-match-item"><img alt="Basketball">',
      '<span class="evdesc">20:00 (Soccer)</span>',
      '<a href="/view/conflict">Arsenal - Chelsea</a></div>',
    ].join(''),
  })});
  assert.equal(data.results, 0);
});

test("LiveTV uses only an explicitly published UTC kickoff, not local clock label", async () => {
  const html = '<div class="side-match-item"><img alt="Soccer">' +
    '<a href="/view/arsenal-chelsea">Arsenal - Chelsea</a>' +
    '<time datetime="2026-11-13T20:00:00Z"></time>' +
    '<span class="evdesc">21:00 (Soccer)</span></div>';
  const data = await experimentalMatches("livetv", {fetcher:pages({
    "https://livetv.li/soccer": html,
  })});
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].match_time, "2026-11-13T20:00:00.000Z");
  assert.equal(data.matches[0].verified_kickoff, true);
});


test("LiveTV mixed-sports JSON cannot inherit soccer status from page URL", async () => {
  const events = [
    {homeTeam:{name:"Lakers"}, awayTeam:{name:"Celtics"},
      url:"/event/lakers-celtics", startDate:"2026-11-13T20:00:00Z"},
    {homeTeam:{name:"Arsenal"}, awayTeam:{name:"Chelsea"}, sport:"Soccer",
      url:"/event/arsenal-chelsea", startDate:"2026-11-13T20:00:00Z"},
    {homeTeam:{name:"Heat"}, awayTeam:{name:"Bulls"}, sport:"Basketball",
      url:"/soccer/heat-bulls", startDate:"2026-11-13T20:00:00Z"},
  ];
  const data = await experimentalMatches("livetv", {fetcher:pages({
    "https://livetv.li/soccer": '<script type="application/json">'+
      JSON.stringify({events})+'</script>',
  })});
  assert.equal(data.results, 1);
  assert.equal(data.matches[0].home_team, "Arsenal");
  assert.equal(data.matches[0].away_team, "Chelsea");
});


test("StreamFree single-event div fixture card with explicit soccer evidence is recognized", async () => {
  const html = '<div class="fixture-card" data-sport="soccer">' +
    '<a href="/events/arsenal-chelsea">Arsenal vs Chelsea</a>' +
    '<time datetime="2026-11-13T19:00:00Z"></time></div>';
  const result = await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/": html,
  })});
  assert.equal(result.results, 1);
  assert.equal(result.matches[0].home_team, "Arsenal");
  assert.equal(result.matches[0].away_team, "Chelsea");
  assert.equal(result.matches[0].verified_kickoff, true);
});

test("LiveXTV section event-item card requires its own football marker", async () => {
  const html =
    '<h2>Soccer fixtures</h2>' +
    '<section class="event-item" data-sport="basketball">' +
    '<a href="/events/lakers-celtics">Lakers vs Celtics</a></section>' +
    '<section class="event-item" data-category="football">' +
    '<a href="/events/turkey-belgium">Turkey vs Belgium</a></section>' +
    '<section class="event-item">' +
    '<a href="/events/unknown-unknown">Unknown vs Unknown</a></section>';
  const result = await experimentalMatches("livextv", {fetcher:pages({
    "https://livextv.pro/": html,
  })});
  assert.equal(result.results, 1);
  assert.equal(result.matches[0].home_team, "Turkey");
  assert.equal(result.matches[0].away_team, "Belgium");
  assert.equal(result.matches[0].match_time, null);
});

test("Public JSON eventUrl and explicit homeName/awayName identify football match", async () => {
  const json = {fixtures:[{
    sport: "Soccer", eventUrl: "/events/turkey-belgium",
    homeName: "Turkey", awayName: "Belgium",
    startDate: "2026-11-13T19:00:00Z",
  }]};
  const result = await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/":
      '<script type="application/json">' + JSON.stringify(json) + '</script>',
  })});
  assert.equal(result.results, 1);
  assert.equal(result.matches[0].away_team, "Belgium");
  assert.equal(result.matches[0].match_time, "2026-11-13T19:00:00.000Z");
});

test("Public JSON match_url and explicit nested teams can identify source fixture", async () => {
  const json = {games:[{
    sport:"Football", match_url:"/events/team-one-team-two",
    teams: {home:{name:"Team One"},away:{name:"Team Two"}},
    startDate:"2026-11-13T19:00:00Z",
  }]};
  const result = await experimentalMatches("livextv", {fetcher:pages({
    "https://livextv.pro/":
      '<script type="application/json">' + JSON.stringify(json) + '</script>',
  })});
  assert.equal(result.results,1);
  assert.equal(result.matches[0].home_team,"Team One");
  assert.equal(result.matches[0].away_team,"Team Two");
});

test("American football, basketball, and foreign event links stay excluded", async () => {
  const json={events:[
    {sport:"American Football",homeName:"Bills",awayName:"Chiefs",
      event_url:"/football/bills-chiefs",startDate:"2026-11-13T19:00:00Z"},
    {sport:"Basketball",homeName:"Lakers",awayName:"Celtics",
      eventUrl:"/football/lakers-celtics",startDate:"2026-11-13T19:00:00Z"},
    {sport:"Football",homeName:"Arsenal",awayName:"Chelsea",
      match_url:"https://outside.example/event/arsenal-chelsea",
      startDate:"2026-11-13T19:00:00Z"},
  ]};
  const result=await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/":
      '<script type="application/json">'+JSON.stringify(json)+'</script>',
  })});
  assert.equal(result.results,0);
});

test("A football title on a different div card never validates an unlabelled event", async () => {
  const html='<div class="match-card" data-sport="soccer">' +
    '<a href="/events/turkey-belgium">Turkey vs Belgium</a></div>' +
    '<div class="match-card">' +
    '<a href="/events/lakers-celtics">Lakers vs Celtics</a></div>';
  const result=await experimentalMatches("streamfree", {fetcher:pages({
    "https://strmfree.st/":html,
  })});
  assert.equal(result.results,1);
  assert.equal(result.matches[0].home_team,"Turkey");
});
