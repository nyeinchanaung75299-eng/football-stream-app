// Read-only smoke diagnostic. One public fixture index request per provider.
// Do not fetch match/video pages, authorization tokens or media/DRM URLs.
import { experimentalFootballSites, experimentalMatches } from
  "../supabase/functions/_shared/experimental_football_sources.mjs";

// Report only static structure around two Soccer links for the table-based
// LiveTV listing. Redact URLs and scripts before printing.
function soccerMarkupSamples(html) {
  const clean = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi," ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi," ");
  const out=[];
  for(const hit of clean.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
    if(out.length>=3) break;
    const title = hit[2].replace(/<[^>]+>/g," ").replace(/\s+/g," ").trim();
    if(!/\s[-–—]\s/.test(title) || title.length<14 || title.length>90) continue;
    const before = clean.slice(Math.max(0,hit.index-750),hit.index);
    if(!/soccer/i.test(before)) continue;
    const sample=(before.slice(-520)+hit[0]).replace(/\s+/g," ").slice(0,850)
      .replace(/(?:src|href|data-url|data-href)\s*=\s*["'][^"']+["']/gi,"")
      .replace(/(?:https?:)?\/\/[^\s"'<>]+/gi,"[URL]")
      .replace(/\bon[a-z]+\s*=\s*["'][^"']+["']/gi,"");
    out.push({title,sample});
  }
  return out;
}

const ids = Object.keys(experimentalFootballSites);
const results = [];

// Diagnostic only. Report public HTML structure, never video/media URL,
// cookies, tokens, full page HTML, or the contents of embedded scripts.
function publicFixtureMarkupShape(html) {
  const safe = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ");
  const count = re => [...safe.matchAll(re)].length;
  const samples = [];
  for (const m of safe.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
    if (samples.length >= 8) break;
    const title = m[2].replace(/<[^>]*>/g, " ").replace(/&[^;]{1,12};/g, " ")
      .replace(/\s+/g, " ").trim();
    if (!/\b(?:vs?\.?|at)\b|\s[–—-]\s/i.test(title) || title.length > 100 || title.length < 8) continue;
    const local = safe.slice(Math.max(0, m.index-400),m.index+Math.min(m[0].length+200,800));
    const href = m[1].match(/\bhref\s*=\s*["']([^"']+)["']/i)?.[1] ?? "";
    let path = "unknown";
    try {
      const url = new URL(href, "https://example.invalid");
      path = url.pathname.slice(0,90); // no search params or fragments
    } catch (_) {}
    const tags = [...local.matchAll(/\bdata-(?:sport|category|discipline)[\w-]*\s*=\s*["']([^"']+)["']/gi)]
      .slice(0,3).map(x=>x[1].slice(0,40));
    samples.push({title:title.slice(0,90),path,tags});
  }
  const jsonTypes=[...html.matchAll(/<script\b([^>]*)>/gi)].slice(0,30)
    .map(x=>x[1].match(/\btype\s*=\s*["']([^"']+)["']/i)?.[1] ?? "(JS)")
    .reduce((acc,t)=>{acc[t]=(acc[t]??0)+1;return acc},{});
  return {bytes:html.length,anchors:count(/<a\b/gi),articles:count(/<article\b/gi),
    listItems:count(/<li\b/gi),timeTags:count(/<time\b/gi),
    sportAttrs:count(/\bdata-(?:sport|category|discipline)[\w-]*\s*=/gi),
    footballMentions:(safe.match(/\b(?:football|soccer)\b/gi)??[]).length,
    jsonTypes,samples};
}
for (let i=0; i<ids.length; i+=3) {
  await Promise.all(ids.slice(i,i+3).map(async source => {
    const site = experimentalFootballSites[source];
    let responseStatus = null;
    let redirectTarget = null;
    let shape = null;
    const fetcher = async (url, init) => {
      if (String(url) !== site.home) throw Error("Detail page excluded from smoke probe");
      const response = await fetch(url, {...init, redirect:"follow"});
      responseStatus = response.status;
      redirectTarget = response.url;
      if (new URL(response.url).hostname !== site.host &&
          !new URL(response.url).hostname.endsWith("."+site.host)) {
        throw Error("Provider redirected to an unrelated host");
      }
      if (["ppv","streamfree","livextv","livetv"].includes(source)) {
        const publicHtml = await response.clone().text();
        shape = publicFixtureMarkupShape(publicHtml);
        if (source === "livetv") shape.soccerSamples = soccerMarkupSamples(publicHtml);
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
        ...(shape ? {shape} : {}),
      });
    } catch(err) {
      results.push({source,http:responseStatus,matches:0,timed:0,badges:0,
        state:"unavailable",note:String(err?.message ?? err).slice(0,150)});
    }
  }));
}
results.sort((a,b)=>ids.indexOf(a.source)-ids.indexOf(b.source));
console.log("PUBLIC_FOOTBALL_SOURCE_SMOKE_JSON="+JSON.stringify(results));
console.log("PUBLIC_FOOTBALL_MARKUP_SHAPES_JSON="+JSON.stringify(results
  .filter(x=>x.shape).map(x=>({source:x.source,shape:x.shape}))));
console.table(results);
console.log("Smoke check does not test player URLs or guarantee HLS/DASH playback.");
