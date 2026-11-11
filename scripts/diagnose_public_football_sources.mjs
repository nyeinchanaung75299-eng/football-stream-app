// Read-only smoke diagnostic. One public fixture index request per provider.
// Do not fetch match/video pages, authorization tokens or media/DRM URLs.
import { experimentalFootballSites, experimentalMatches } from
  "../supabase/functions/_shared/experimental_football_sources.mjs";

const ids = Object.keys(experimentalFootballSites);
const results = [];
for (let i=0; i<ids.length; i+=3) {
  await Promise.all(ids.slice(i,i+3).map(async source => {
    const site = experimentalFootballSites[source];
    let responseStatus = null;
    let redirectTarget = null;
    const fetcher = async (url, init) => {
      if (String(url) !== site.home) throw Error("Detail page excluded from smoke probe");
      const response = await fetch(url, {...init, redirect:"follow"});
      responseStatus = response.status;
      redirectTarget = response.url;
      if (new URL(response.url).hostname !== site.host &&
          !new URL(response.url).hostname.endsWith("."+site.host)) {
        throw Error("Provider redirected to an unrelated host");
      }
      return response;
    };
    try {
      const info = await experimentalMatches(source,{fetcher});
      const matches = info.matches ?? [];
      results.push({
        source, http:responseStatus,
        matches:matches.length,
        timed:matches.filter(m=>m.match_time).length,
        badges:matches.filter(m=>m.home_logo || m.away_logo).length,
        state:info.diagnostics?.content_state,
        note:matches.length ? "" : "No validated fixture in public HTML",
      });
    } catch(err) {
      results.push({source,http:responseStatus,matches:0,timed:0,badges:0,
        state:"unavailable",note:String(err?.message ?? err).slice(0,150)});
    }
  }));
}
results.sort((a,b)=>ids.indexOf(a.source)-ids.indexOf(b.source));
console.log("PUBLIC_FOOTBALL_SOURCE_SMOKE_JSON="+JSON.stringify(results));
console.table(results);
console.log("Smoke check does not test player URLs or guarantee HLS/DASH playback.");
