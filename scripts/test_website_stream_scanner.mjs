import test from "node:test";
import assert from "node:assert/strict";
import {
  classifyStream, extractStreamLinks, handleWebsiteStreamScan,
} from "../cloudflare/public-api/src/website_stream_scanner.mjs";

const id="12345678-1234-1234-1234-1234567890ab";
const env={
  SUPABASE_URL:"https://auth.example.org",
  SUPABASE_PUBLISHABLE_KEY:"public-test-key",
};

function mockFetch(url) {
  const address=String(url);
  if(address.endsWith("/auth/v1/user"))
    return Response.json({id});
  if(address.includes("/rest/v1/profiles?"))
    return Response.json([{role:"admin"}]);
  if(address==="https://tv.example.org/watch"){
    return new Response(
      '<video><source src="https://cdn.example.org/hls/main.m3u8?token=abc"></video>'+
      '<script src="/assets/player.js"></script>'+
      '<iframe src="/frame"></iframe>',
      {headers:{"Content-Type":"text/html"}},
    );
  }
  if(address==="https://tv.example.org/assets/player.js")
    return new Response(
      'const dash="https:\\/\\/cdn.example.org\\/dash\\/index.mpd";',
      {headers:{"Content-Type":"application/javascript"}},
    );
  if(address==="https://tv.example.org/frame")
    return new Response(
      '<video src="/assets/movie.mp4"></video>',
      {headers:{"Content-Type":"text/html"}},
    );
  throw Error("Unmocked URL: "+address);
}
function req(url="https://tv.example.org/watch",auth=true,authorized=true) {
  return new Request("https://api.example.com/admin/stream-detect",{
    method:"POST",
    headers:{"Authorization":auth?"Bearer test-admin-token-very-long":"", "Content-Type":"application/json"},
    body:JSON.stringify({url,authorized}),
  });
}

test("classifies HLS, DASH, MP4 and rejects internal hosts",()=>{
  assert.equal(classifyStream("https://cdn.example.org/live/master.m3u8?t=1"),"hls");
  assert.equal(classifyStream("https://cdn.example.org/main.mpd"),"dash");
  assert.equal(classifyStream("https://cdn.example.org/movie.mp4"),"mp4");
  assert.equal(classifyStream("http://localhost/stream.m3u8"),null);
  assert.equal(classifyStream("http://10.0.0.1/stream.m3u8"),null);
  assert.equal(classifyStream("http://169.254.169.254/latest/meta-data.m3u8"),null);
  assert.equal(classifyStream("file:///etc/passwd.m3u8"),null);
});
test("extracts player media URLs from HTML with deduplication",()=>{
  const links=extractStreamLinks(
    '<video src="/movie.mp4"></video><source src="//cdn.example.org/live.m3u8">'+
    '<script>const again="//cdn.example.org/live.m3u8";</script>',
    "https://tv.example.org/watch",
  );
  assert.equal(links.length,2);
  assert.equal(links[0].url,"https://tv.example.org/movie.mp4");
  assert.equal(links[1].url,"https://cdn.example.org/live.m3u8");
});
test("website scanning requires authenticated admin and explicit authorization",async()=>{
  let output=await handleWebsiteStreamScan(req(undefined,false),env,{fetchImpl:mockFetch});
  assert.equal(output.status,403);
  output=await handleWebsiteStreamScan(req(undefined,true,false),env,{fetchImpl:mockFetch});
  assert.equal(output.status,400);
});
test("website scan returns embedded streams and same-site script/iframe media",async()=>{
  const response=await handleWebsiteStreamScan(req(),env,{fetchImpl:mockFetch});
  assert.equal(response.status,200);
  const result=await response.json();
  assert.equal(result.mode,"html-scan");
  assert.equal(result.count,3);
  assert.deepEqual(result.links.map(x=>x.type).sort(),["dash","hls","mp4"]);
  assert.equal(result.links[0].referer,"https://tv.example.org/watch");
  assert.equal(result.links[0].origin,"https://tv.example.org");
});
test("direct stream link is classified without downloading media",async()=>{
  const response=await handleWebsiteStreamScan(req("https://cdn.example.org/live/master.m3u8"),env,{
    fetchImpl:(url)=> {
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      throw Error("Should not fetch media");
    },
  });
  assert.equal(response.status,200);
  assert.equal((await response.json()).links[0].type,"hls");
});
test("HTML scan cannot claim to capture runtime network traffic",async()=>{
  const response=await handleWebsiteStreamScan(req("https://tv.example.org/watch"),env,{
    fetchImpl:async (url)=>{
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      return new Response('<script src="https://external.example.org/player.js"></script>',{
        headers:{"Content-Type":"text/html"},
      });
    },
  });
  assert.equal(response.status,200);
  const payload=await response.json();
  assert.equal(payload.count,0);
  assert.match(payload.notes,/JS-only players/);
});

test("blocked upstream website is reported as a scan error, not a scanner outage",async()=>{
  const response=await handleWebsiteStreamScan(req("https://blocked.example.org/watch"),env,{
    fetchImpl:async (url)=>{
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      return new Response("Blocked",{status:403});
    },
  });
  assert.equal(response.status,422);
  const result=await response.json();
  assert.equal(result.code,"website_fetch_failed");
  assert.match(result.error,/HTTP 403/);
  assert.doesNotMatch(result.error,/token|cookie/i);
});

test("website request timeout/HTTP failures do not masquerade as connectivity problems",async()=>{
  const response=await handleWebsiteStreamScan(req("https://error.example.org/watch"),env,{
    fetchImpl:async (url)=>{
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      return new Response("Unavailable",{status:503});
    },
  });
  assert.equal(response.status,422);
  const result=await response.json();
  assert.match(result.error,/HTTP 503/);
});

test("large advertised HTML still returns embedded HLS instead of HTTP 422",async()=>{
  const response=await handleWebsiteStreamScan(req("https://large.example.org/watch"),env,{
    fetchImpl:async (url)=>{
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      return new Response(
        '<video src="https://cdn.example.org/live/main.m3u8"></video>',
        {headers:{"Content-Type":"text/html","Content-Length":"20000000"}},
      );
    },
  });
  assert.equal(response.status,200);
  const data=await response.json();
  assert.equal(data.count,1);
  assert.equal(data.links[0].type,"hls");
  assert.equal(data.partial,true);
  assert.match(data.notes,/results may be incomplete/);
});

test("oversized chunked HTML is truncated and scan still succeeds",async()=>{
  const huge= '<video src="/live/main.mpd"></video>' + "x".repeat(1100000);
  const response=await handleWebsiteStreamScan(req("https://large.example.org/watch"),env,{
    fetchImpl:async (url)=>{
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      return new Response(huge,{headers:{"Content-Type":"text/html"}});
    },
  });
  assert.equal(response.status,200);
  const data=await response.json();
  assert.equal(data.count,1);
  assert.equal(data.links[0].url,"https://large.example.org/live/main.mpd");
  assert.equal(data.partial,true);
  assert.match(data.notes,/only the first part was scanned/);
});

test("oversized linked JavaScript yields partial results without losing HTML media",async()=>{
  const response=await handleWebsiteStreamScan(req("https://large.example.org/watch"),env,{
    fetchImpl:async (url)=>{
      if(String(url).startsWith(env.SUPABASE_URL))return mockFetch(url);
      if(String(url).endsWith("/player.js"))
        return new Response('const src="/second.m3u8";'+"x".repeat(270000),{
          headers:{"Content-Type":"application/javascript"},
        });
      return new Response(
        '<video src="/first.mp4"></video><script src="/player.js"></script>',
        {headers:{"Content-Type":"text/html"}},
      );
    },
  });
  assert.equal(response.status,200);
  const data=await response.json();
  assert.equal(data.count,2);
  assert.deepEqual(data.links.map(x=>x.type).sort(),["hls","mp4"]);
  assert.equal(data.partial,true);
});

test("small normal HTML is reported as fully scanned",async()=>{
  const response=await handleWebsiteStreamScan(req(),env,{fetchImpl:mockFetch});
  assert.equal(response.status,200);
  const data=await response.json();
  assert.equal(data.partial,false);
});
