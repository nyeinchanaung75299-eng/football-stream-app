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
          params:{request:{url:"https://cdn.example.org/iframe/child.m3u8"}},
        })});
      }
      if(command.method==="Page.navigate"){
        listeners.get("message")?.({data:JSON.stringify({
          method:"Page.frameNavigated",params:{frame:{id:"main",url:"https://video.example.org/watch"}},
        })});
        const events=[
          {method:"Network.requestWillBeSent",params:{request:{
            url:"https://cdn.example.org/live/master.m3u8",
            headers:{Cookie:"SECRET",Authorization:"Bearer SECRET"},
          }}},
          {method:"Network.responseReceived",params:{response:{
            url:"https://cdn.example.org/live/manifest.mpd",mimeType:"application/dash+xml",
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
  const result=await captureBrowserMedia({...env,BROWSER:browser},"https://video.example.org/watch",{delay:async()=>{}});
  assert.equal(result.count,3);
  assert.deepEqual(result.links.map(x=>x.type),["hls","hls","dash"]);
  assert.equal(result.diagnostics.navigationConfirmed,true);
  assert.equal(result.diagnostics.requestsObserved,2);
  assert.equal(result.diagnostics.responsesObserved,1);
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
  const result=await captureBrowserMedia({...env,BROWSER:browser},
    "https://video.example.org/watch",{delay:async()=>{}});
  assert.equal(result.count,0);
  assert.equal(result.diagnostics.requestsObserved,1);
  assert.equal(result.diagnostics.iframeElements,1);
  assert.equal(result.diagnostics.pageHttpStatus,200);
  assert.match(result.notes,/iframe players/);
  assert.ok(!JSON.stringify(result).includes("PRIVATE"));
});
