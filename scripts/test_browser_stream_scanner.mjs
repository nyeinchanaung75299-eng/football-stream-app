import test from "node:test";
import assert from "node:assert/strict";
import {createMediaCollector,browserMediaType,captureBrowserMedia,handleBrowserStreamScan} from "../cloudflare/public-api/src/browser_stream_scanner.mjs";

const env={
  SUPABASE_URL:"https://auth.example.org",
  SUPABASE_PUBLISHABLE_KEY:"public-test-key",
  ENABLE_FREE_BROWSER_DETECT:"true",
  BROWSER:{},
};
function authFetch(address){
  if(String(address).endsWith("/auth/v1/user"))
    return Response.json({id:"12345678-1234-1234-1234-1234567890ab"});
  if(String(address).includes("/rest/v1/profiles?"))
    return Response.json([{role:"admin"}]);
  throw Error("Unmocked auth request");
}
function request(body={url:"https://video.example.org/watch",authorized:true},auth=true){
  return new Request("https://api.example.org/admin/stream-detect-browser",{
    method:"POST",
    headers:{
      "Content-Type":"application/json",
      "Authorization":auth?"Bearer valid-test-token-for-admin":"",
    },
    body:JSON.stringify(body),
  });
}

test("collector retains HLS/DASH/MP4, dedupes, and rejects internal hosts",()=>{
  const c=createMediaCollector("https://video.example.org/watch");
  c.observe("https://cdn.example.org/live/master.m3u8?exp=soon");
  c.observe("https://cdn.example.org/live/master.m3u8?exp=soon");
  c.observe("https://cdn.example.org/manifest.mpd");
  c.observe("https://cdn.example.org/file.mp4");
  c.observe("https://video.example.org/opaque?id=1","application/vnd.apple.mpegurl");
  c.observe("http://127.0.0.1/test.m3u8");
  c.observe("file:///video.m3u8");
  c.observe("https://user:pw@cdn.example.org/test.m3u8");
  c.observe("https://video.example.org/regular.js");
  assert.deepEqual(c.links.map(x=>x.type),["hls","dash","mp4","hls"]);
  assert.equal(c.links[0].referer,"https://video.example.org/watch");
  assert.equal(c.links[0].origin,"https://video.example.org");
  assert.equal(browserMediaType("https://cdn.example.org/live/stream","application/dash+xml"),"dash");
});

test("authorized browser can observe public HTTPS HLS on port 7059",()=>{
  const c=createMediaCollector("https://player.example.org/watch");
  c.observe("https://edge.example.org:7059/hls/live.m3u8?expires=123");
  c.observe("https://edge.example.org:7059/hls/live.m3u8?expires=123");
  c.observe("https://127.0.0.1:7059/hls/unsafe.m3u8");
  c.observe("https://user:pass@edge.example.org:7059/hls/unsafe.m3u8");
  c.observe("https://edge.example.org:7060/hls/unsafe.m3u8");
  assert.equal(c.links.length,1);
  assert.equal(c.links[0].type,"hls");
  assert.equal(c.links[0].url,"https://edge.example.org:7059/hls/live.m3u8?expires=123");
  assert.equal(c.links[0].referer,"https://player.example.org/watch");
  assert.equal(browserMediaType("https://edge.example.org:7059/hls/live.m3u8"),"hls");
  assert.equal(browserMediaType("https://edge.example.org:7060/hls/live.m3u8"),null);
  assert.throws(()=>createMediaCollector("https://player.example.org:7059/watch"),/Invalid public page URL/);
});

test("iframe media retains its public initiating document without reading headers",()=>{
  const collector=createMediaCollector("https://catalog.example.org/match");
  collector.observe("https://cdn.example.org/master.m3u8");
  collector.observe("https://cdn.example.org/master.m3u8","","https://player.example.org/embed");
  collector.observe("https://cdn.example.org/master.m3u8");
  assert.equal(collector.links.length,1);
  assert.equal(collector.links[0].referer,"https://player.example.org/embed");
  assert.equal(collector.links[0].origin,"https://player.example.org");
});

test("endpoint checks role, free-mode gate and consent before launching browser",async()=>{
  let launches=0;
  const capture=async()=>{ launches++; return {ok:true,mode:"browser",links:[],count:0}; };
  const bad=await handleBrowserStreamScan(request(undefined,false),env,{fetchImpl:authFetch,capture});
  assert.equal(bad.status,403);
  const disabled=await handleBrowserStreamScan(request(),{...env,ENABLE_FREE_BROWSER_DETECT:"false"},{fetchImpl:authFetch,capture});
  assert.equal(disabled.status,503);
  assert.equal((await disabled.json()).code,"browser_disabled");
  const noConsent=await handleBrowserStreamScan(request({url:"https://video.example.org/watch",authorized:false}),env,{fetchImpl:authFetch,capture});
  assert.equal(noConsent.status,400);
  const invalid=await handleBrowserStreamScan(request({url:"http://10.0.0.1/video",authorized:true}),env,{fetchImpl:authFetch,capture});
  assert.equal(invalid.status,400);
  assert.equal(launches,0);
  const result=await handleBrowserStreamScan(request(),env,{fetchImpl:authFetch,capture,allowRequest:async()=>true});
  assert.equal(result.status,200);
  assert.equal(launches,1);
});

test("CDP observes requests, closes the browser and never reads cookies",async()=>{
  const listeners=new Map();
  const cdpSocket={
    closed:false,
    addEventListener(name,cb){listeners.set(name,cb);},
    removeEventListener(name){listeners.delete(name);},
    accept(){},
    close(){this.closed=true;},
    send(raw){
      const command=JSON.parse(raw);
      if(command.method==="Target.setAutoAttach"){
        listeners.get("message")?.({data:JSON.stringify({
          method:"Target.attachedToTarget",
          params:{sessionId:"iframe-1",targetInfo:{type:"iframe"}},
        })});
      }
      if(command.method==="Network.enable" && command.sessionId==="iframe-1"){
        listeners.get("message")?.({data:JSON.stringify({
          method:"Network.requestWillBeSent",sessionId:"iframe-1",
          params:{requestId:"iframe-1-media",request:{url:"https://cdn.example.org/iframe/child.m3u8"}},
        })});
        listeners.get("message")?.({data:JSON.stringify({
          method:"Network.responseReceived",sessionId:"iframe-1",
          params:{requestId:"iframe-1-media",response:{
            status:200,url:"https://cdn.example.org/iframe/child.m3u8",
            mimeType:"application/vnd.apple.mpegurl",
          }},
        })});
      }
      if(command.method==="Page.navigate"){
        listeners.get("message")?.({data:JSON.stringify({
          method:"Page.frameNavigated",params:{frame:{id:"main",url:"https://video.example.org/watch"}},
        })});
        const events=[
          {method:"Network.requestWillBeSent",params:{requestId:"master",request:{
            url:"https://cdn.example.org/live/master.m3u8",
            headers:{Cookie:"SECRET",Authorization:"Bearer SECRET"},
          }}},
          {method:"Network.responseReceived",params:{requestId:"master",response:{
            status:200,url:"https://cdn.example.org/live/master.m3u8",
            mimeType:"application/vnd.apple.mpegurl",
          }}},
          {method:"Network.responseReceived",params:{requestId:"dash",response:{
            status:206,url:"https://cdn.example.org/live/manifest.mpd",
            mimeType:"application/dash+xml",
          }}},
        ];
        for(const event of events)listeners.get("message")?.({data:JSON.stringify(event)});
      }
      const result=command.method==="Runtime.evaluate"
        ? {result:{value:command.params.expression.includes('frames:')
            ? {videos:1,frames:0} : 1}}
        : {};
      listeners.get("message")?.({data:JSON.stringify({id:command.id,result})});
    },
  };
  let closeCount=0;
  const browser={
    launch:async()=>({sessionId:"abc",targets:[],webSocket:{
      fetch:async()=>({webSocket:cdpSocket}),
    }}),
    closeSession:async()=>{closeCount++;},
  };
  let simulatedWaitMs=0;
  const result=await captureBrowserMedia({...env,BROWSER:browser},
    "https://video.example.org/watch",{
      delay:async(ms)=>{simulatedWaitMs+=ms;},
    });
  assert.equal(simulatedWaitMs,3000,
    "Found media should end the short observation early.");
  assert.equal(result.count,3);
  assert.deepEqual(result.links.map(x=>x.type),["hls","hls","dash"]);
  assert.equal(result.diagnostics.navigationConfirmed,true);
  assert.equal(result.diagnostics.requestsObserved,2);
  assert.equal(result.diagnostics.responsesObserved,3);
  assert.equal(result.diagnostics.confirmedMediaResponses,3);
  assert.equal(result.diagnostics.failedMediaResponses,0);
  assert.equal(result.diagnostics.iframeTargetsObserved,1);
  assert.equal(result.diagnostics.htmlVideoElements,1);
  assert.equal(result.diagnostics.videoPlayAttempts,1);
  assert.equal(closeCount,1);
  assert.equal(cdpSocket.closed,true);
  assert.ok(!JSON.stringify(result).includes("SECRET"));
});

test("empty result distinguishes no requests from a loaded iframe player",async()=>{
  const handlers=new Map();
  const socket={
    addEventListener(event,fn){handlers.set(event,fn);},
    removeEventListener(event){handlers.delete(event);},
    accept(){},close(){},
    send(raw){
      const cmd=JSON.parse(raw);
      const emit=(data)=>handlers.get("message")?.({data:JSON.stringify(data)});
      if(cmd.method==="Page.navigate"){
        emit({method:"Network.requestWillBeSent",params:{
          request:{url:"https://video.example.org/watch",headers:{Cookie:"PRIVATE"}},
        }});
        emit({method:"Network.responseReceived",params:{
          type:"Document",response:{status:200,url:"https://video.example.org/watch"},
        }});
      }
      const result=cmd.method==="Runtime.evaluate"
        ? {result:{value:cmd.params.expression.includes("frames:")
            ? {videos:0,frames:1} : 0}}
        : {};
      emit({id:cmd.id,result});
    },
  };
  const browser={
    launch:async()=>({sessionId:"short",targets:[],webSocket:{
      fetch:async()=>({webSocket:socket}),
    }}),
    closeSession:async()=>{},
  };
  let simulatedWaitMs=0;
  const result=await captureBrowserMedia({...env,BROWSER:browser},
    "https://video.example.org/watch",{
      delay:async(ms)=>{simulatedWaitMs+=ms;},
    });
  assert.equal(simulatedWaitMs,9500,
    "An empty scan must stop after the bounded observation window.");
  assert.equal(result.count,0);
  assert.equal(result.diagnostics.requestsObserved,1);
  assert.equal(result.diagnostics.iframeElements,1);
  assert.equal(result.diagnostics.pageHttpStatus,200);
  assert.match(result.notes,/iframe players/);
  assert.ok(!JSON.stringify(result).includes("PRIVATE"));
});

test("browser never reports a failed HLS request as an accessible stream",async()=>{
  const listeners=new Map();
  const socket={
    addEventListener(name,fn){listeners.set(name,fn);},
    removeEventListener(name){listeners.delete(name);},
    accept(){},close(){},
    send(raw){
      const cmd=JSON.parse(raw);
      const emit=value=>listeners.get("message")?.({data:JSON.stringify(value)});
      if(cmd.method==="Page.navigate"){
        emit({method:"Network.requestWillBeSent",params:{
          requestId:"denied-playlist",request:{
            url:"https://edge.example.org:7059/hls/live.m3u8?expires=placeholder",
          },
        }});
        emit({method:"Network.responseReceived",params:{
          requestId:"denied-playlist",type:"Fetch",response:{
            status:403,url:"https://edge.example.org:7059/hls/live.m3u8?expires=placeholder",
            mimeType:"application/vnd.apple.mpegurl",
          },
        }});
        emit({method:"Network.responseReceived",params:{
          requestId:"blocked-document",type:"Document",response:{
            status:403,url:"https://player.example.org/watch",
          },
        }});
      }
      const value=cmd.method==="Runtime.evaluate"
        ? {result:{value:cmd.params.expression.includes("frames:")
            ? {videos:0,frames:0}:0}} : {};
      emit({id:cmd.id,result:value});
    },
  };
  const browser={
    launch:async()=>({sessionId:"denied",targets:[],webSocket:{
      fetch:async()=>({webSocket:socket}),
    }}),
    closeSession:async()=>{},
  };
  const result=await captureBrowserMedia({...env,BROWSER:browser},
    "https://player.example.org/watch",{delay:async()=>{}});
  assert.equal(result.count,0);
  assert.deepEqual(result.links,[]);
  assert.equal(result.diagnostics.requestsObserved,1);
  assert.equal(result.diagnostics.deniedDocumentResponses,1);
  assert.equal(result.diagnostics.failedMediaResponses,1);
  assert.equal(result.diagnostics.confirmedMediaResponses,0);
  assert.match(result.notes,/HTTP 401\/403/);
  assert.equal(JSON.stringify(result).includes("expires=placeholder"),false);
});

test("browser confirms an HTTPS HLS response on public port 7059 after HTTP 206",async()=>{
  const listeners=new Map();
  const socket={
    addEventListener(name,fn){listeners.set(name,fn);},
    removeEventListener(name){listeners.delete(name);},
    accept(){},close(){},
    send(raw){
      const cmd=JSON.parse(raw);
      const emit=value=>listeners.get("message")?.({data:JSON.stringify(value)});
      if(cmd.method==="Page.navigate"){
        emit({method:"Network.requestWillBeSent",params:{
          requestId:"partial",request:{
            url:"https://edge.example.org:7059/hls/live.m3u8?part=1",
          },
        }});
        emit({method:"Network.responseReceived",params:{
          requestId:"partial",response:{
            status:206,url:"https://edge.example.org:7059/hls/live.m3u8?part=1",
            mimeType:"application/vnd.apple.mpegurl",
          },
        }});
      }
      const value=cmd.method==="Runtime.evaluate"
        ? {result:{value:cmd.params.expression.includes("frames:")
            ? {videos:1,frames:0}:1}} : {};
      emit({id:cmd.id,result:value});
    },
  };
  const browser={
    launch:async()=>({sessionId:"partial",targets:[],webSocket:{
      fetch:async()=>({webSocket:socket}),
    }}),
    closeSession:async()=>{},
  };
  const result=await captureBrowserMedia({...env,BROWSER:browser},
    "https://player.example.org/watch",{delay:async()=>{}});
  assert.equal(result.count,1);
  assert.equal(result.links[0].type,"hls");
  assert.equal(result.diagnostics.confirmedMediaResponses,1);
  assert.equal(result.diagnostics.failedMediaResponses,0);
});
