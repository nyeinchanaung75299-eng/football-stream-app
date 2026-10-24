// Browser Run / Chrome DevTools Protocol (CDP) media request observer.
// No Puppeteer dependency. Never reads network request headers, cookies,
// Authorization values, response bodies, DRM keys or browser credentials.
// It observes only URLs of public media requests while loading authorized pages.
import { classifyStream, rejectTarget, isVerifiedAdmin } from "./website_stream_scanner.mjs";

const MAX_SCAN_MS = 12000;
const MAX_RESULTS = 30;
const MAX_RESPONSE_BYTES = 4096;

function response(payload,status=200) {
  return new Response(JSON.stringify(payload),{status,headers:{
    "Content-Type":"application/json",
    "Access-Control-Allow-Origin":"*",
    "Access-Control-Allow-Headers":"Authorization,Content-Type",
    "Cache-Control":"no-store",
    "Referrer-Policy":"no-referrer",
    "X-Content-Type-Options":"nosniff",
  }});
}

export function browserMediaType(rawUrl,mime="") {
  const direct=classifyStream(rawUrl);
  if(direct)return direct;
  if(!rejectTarget(rawUrl))return null;
  const normalized=String(mime||"").toLowerCase().split(";")[0].trim();
  if(["application/vnd.apple.mpegurl","application/x-mpegurl","audio/mpegurl","audio/x-mpegurl"].includes(normalized))return "hls";
  if(normalized==="application/dash+xml")return "dash";
  if(normalized==="video/mp4")return "mp4";
  return null;
}

export function createMediaCollector(pageUrl){
  const page=rejectTarget(pageUrl);
  if(!page)throw new Error("Invalid public page URL.");
  const found=new Map();
  return {
    observe(url,mime=""){
      if(found.size>=MAX_RESULTS)return;
      const safe=rejectTarget(url);
      const type=browserMediaType(url,mime);
      if(!safe||!type||found.has(safe.href))return;
      // Reference page is a hint, not a captured request header.
      found.set(safe.href,{
        url:safe.href,type,referer:page.href,origin:page.origin,
      });
    },
    get links(){return [...found.values()];},
  };
}

// A minimal CDP client. Single listener for events and command responses;
// bounded command deadlines prevent sessions from getting stuck.
export function cdpClient(socket, timeoutMs=6000){
  const pending=new Map();
  const listeners=new Set();
  let nextId=0;
  const receive=event=>{
    let msg;
    try {msg=JSON.parse(event.data);} catch {return;}
    if(typeof msg.id==="number" && pending.has(msg.id)){
      const row=pending.get(msg.id);pending.delete(msg.id);
      clearTimeout(row.timer);
      if(msg.error)row.reject(new Error(String(msg.error.message||"CDP error")));
      else row.resolve(msg.result||{});
    } else if(msg.method) {
      for(const fn of listeners){
        try{fn(msg);}catch{/* keep observing other requests */}
      }
    }
  };
  socket.addEventListener("message",receive);
  socket.addEventListener("close",()=>{
    for(const row of pending.values()){
      clearTimeout(row.timer);row.reject(new Error("Browser connection closed."));
    }
    pending.clear();
  });
  return {
    onEvent(callback){listeners.add(callback);return ()=>listeners.delete(callback);},
    send(method,params={},sessionId=null){
      return new Promise((resolve,reject)=>{
        const id=++nextId;
        const timer=setTimeout(()=>{pending.delete(id);reject(new Error("Browser command timed out."));},timeoutMs);
        pending.set(id,{resolve,reject,timer});
        try{
          socket.send(JSON.stringify({
            id,method,params,
            ...(sessionId?{sessionId}:{}),
          }));
        }catch(error){clearTimeout(timer);pending.delete(id);reject(error);}
      });
    },
    close(){socket.removeEventListener("message",receive);listeners.clear();},
  };
}

export async function captureBrowserMedia(env,pageUrl,{
  launch=null,
  delay=(ms)=>new Promise(resolve=>setTimeout(resolve,ms)),
}={}){
  const target=rejectTarget(pageUrl);
  if(!target)throw new Error("Invalid public HTTP(S) page URL.");
  if(!env.BROWSER && !launch)throw new Error("Browser Run is not configured.");
  const collector=createMediaCollector(target.href);
  // Bounded diagnostic counts only. Do not store visited subresource URLs,
  // cookies, Authorization headers or response bodies.
  const diagnostics={
    requestsObserved:0,
    responsesObserved:0,
    pageResponses:0,
    pageHttpStatus:null,
    navigationConfirmed:false,
    htmlVideoElements:null,
    iframeElements:null,
    videoPlayAttempts:0,
  };
  const browser=env.BROWSER;
  let session=null, socket=null, cdp=null;
  try {
    // One short session, no reuse, and always close even after errors.
    session=await (launch ? launch() : browser.launch({targets:true}));
    let connection=session;
    // Use a page-target connection when a page target is available.
    const pageTarget=(session.targets||[]).find(t=>t.type==="page");
    if(pageTarget && browser?.connectSession){
      connection=await browser.connectSession(session.sessionId,{targetId:pageTarget.id});
    }
    const res=await connection.webSocket.fetch("https://browser-binding.invalid",{
      headers:{Upgrade:"websocket"},
    });
    if(!res.webSocket)throw new Error("Browser Run did not open DevTools.");
    socket=res.webSocket;
    socket.accept();
    cdp=cdpClient(socket,5000);
    cdp.onEvent(msg=>{
      // Cross-origin iframe players can run as out-of-process frame targets.
      // Observe their network requests too, without reading request headers.
      if(msg.method==="Target.attachedToTarget"){
        const id=msg.params?.sessionId;
        const type=msg.params?.targetInfo?.type;
        if(id && (type==="iframe" || type==="page")){
          void cdp.send("Network.enable",{maxPostDataSize:0},id)
            .catch(()=>{ /* OOPIF may disappear during navigation. */ });
        }
        return;
      }
      if(msg.method==="Network.requestWillBeSent"){
        diagnostics.requestsObserved=Math.min(10000,diagnostics.requestsObserved+1);
        // Observe URL only; never inspect request.headers or Cookie.
        collector.observe(msg.params?.request?.url||"");
      }else if(msg.method==="Network.responseReceived"){
        diagnostics.responsesObserved=Math.min(10000,diagnostics.responsesObserved+1);
        if(msg.params?.type==="Document"){
          diagnostics.pageResponses++;
          // Only the numeric response status, never response headers/body.
          const status=Number(msg.params?.response?.status);
          if(Number.isInteger(status)&&status>=100&&status<=599)
            diagnostics.pageHttpStatus=status;
        }
        collector.observe(msg.params?.response?.url||"",msg.params?.response?.mimeType||"");
      }else if(msg.method==="Page.frameNavigated" && !msg.params?.frame?.parentId) {
        diagnostics.navigationConfirmed=true;
      }
    });
    // Best-effort inspection of out-of-process iframe requests. The browser
    // may not support auto-attach on all target configurations.
    try {
      await cdp.send("Target.setAutoAttach",{
        autoAttach:true,waitForDebuggerOnStart:false,flatten:true,
      });
    } catch { /* Keep top-level frame monitoring available. */ }
    await cdp.send("Network.enable",{maxPostDataSize:0});
    await cdp.send("Page.enable");
    const navigation=await cdp.send("Page.navigate",{url:target.href});
    if(navigation?.errorText) {
      // Do not return the original error URL or any sensitive page data.
      throw new Error("Browser page navigation failed.");
    }
    await delay(1600);
    // Read only safe page structure counters. This helps distinguish
    // an iframe-only/custom player from an HTML5 video page.
    try {
      const result=await cdp.send("Runtime.evaluate",{
        expression:"(()=>({videos:document.querySelectorAll('video').length,frames:document.querySelectorAll('iframe').length}))()",
        returnByValue:true,
        awaitPromise:false,
      });
      const v=result?.result?.value;
      if(Number.isInteger(v?.videos))diagnostics.htmlVideoElements=Math.min(1000,v.videos);
      if(Number.isInteger(v?.frames))diagnostics.iframeElements=Math.min(1000,v.frames);
    }catch{/* A blocked document may prevent DOM inspection. */}
    // Only trigger native HTML5 video elements, not third-party player
    // buttons, login flows, cookie prompts or arbitrary page clicks.
    try {
      const result=await cdp.send("Runtime.evaluate",{
        expression:"(()=>{let n=0;for(const v of document.querySelectorAll('video')){n++;try{v.muted=true;v.play().catch(()=>{});}catch(_){}}return n;})()",
        returnByValue:true,
        awaitPromise:false,
      });
      const attempts=Number(result?.result?.value);
      if(Number.isInteger(attempts)&&attempts>=0)
        diagnostics.videoPlayAttempts=Math.min(1000,attempts);
    }catch{/* Browser observation still continues if script execution fails. */}
    await delay(MAX_SCAN_MS-1600);
    const note=collector.links.length
      ?"Media URLs observed from browser requests. Playback and expiry are not guaranteed."
      :diagnostics.requestsObserved===0
        ?"No page network requests were observed. Navigation or the browser target may be blocked."
        :diagnostics.htmlVideoElements===0&&diagnostics.iframeElements>0
          ?"The page made network requests but contains iframe players. The stream may load in a separate frame or require a Play click."
          :diagnostics.htmlVideoElements===0
            ?"The page made network requests but no HTML5 video element was found. A custom player or user interaction may be required."
            :"The browser observed requests, but none identified as HLS/DASH/MP4. Playback might need user interaction, authorization or DRM.";
    return {
      ok:true,mode:"browser",count:collector.links.length,links:collector.links,
      partial:false,diagnostics,notes:note,
    };
  } finally {
    try{cdp?.close();}catch{}
    try{socket?.close();}catch{}
    if(session?.sessionId && browser?.closeSession){
      try{await browser.closeSession(session.sessionId);}catch{}
    }
  }
}

export async function handleBrowserStreamScan(request,env,{fetchImpl=fetch,allowRequest=null,capture=captureBrowserMedia}={}){
  if(request.method!=="POST")return response({error:"POST required."},405);
  let authorized=false;
  try { authorized=await isVerifiedAdmin(request,env,fetchImpl); }
  catch{return response({error:"Admin session verification unavailable."},503);}
  if(!authorized)return response({error:"Verified Admin session required."},403);
  // Free-only mode. This value must be provisioned after confirming the
  // Cloudflare Workers plan is Free. A binding alone does NOT enable scanning.
  if(env.ENABLE_FREE_BROWSER_DETECT!=="true"){
    return response({
      error:"Browser Run is not enabled. Confirm the Workers Free plan and enable free usage first.",
      code:"browser_disabled",
    },503);
  }
  if(!env.BROWSER)return response({error:"Browser Run binding is not configured.",code:"browser_unavailable"},503);
  if(allowRequest && !await allowRequest(request,env,"browser-media-detect",2)){
    return response({error:"Too many browser scans. Please try later."},429);
  }
  let raw;
  try{
    const body=await request.text();
    if(body.length>MAX_RESPONSE_BYTES)return response({error:"Request too large."},413);
    raw=JSON.parse(body);
  }catch{return response({error:"Invalid JSON body."},400);}
  if(raw?.authorized!==true)return response({error:"Page inspection permission required."},400);
  const target=rejectTarget(raw?.url);
  if(!target)return response({error:"A public HTTP(S) page URL is required."},400);
  try{
    return response(await capture(env,target.href));
  }catch(e){
    const message=String(e?.message||"Browser scan failed.");
    // Do not return raw exceptions, URLs or bearer tokens.
    const safe=message.includes("Browser Run")?"Browser Run is unavailable. Check the binding and Free quota."
      :"Browser could not load or inspect that page. It may block automation.";
    return response({error:safe,code:"browser_scan_failed"},422);
  }
}
