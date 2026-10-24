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
