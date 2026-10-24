// Admin-only, bounded website source scanner. This is NOT a headless browser:
// it can discover links in HTML and same-site JS but cannot observe JS runtime
// requests or bypass DRM, paywalls, sign-in, or anti-bot restrictions.
const TYPES = Object.freeze({m3u8:"hls", mpd:"dash", mp4:"mp4", flv:"flv"});
// Bounded reading: scan useful HTML even if the upstream page is larger.
const MAX_PAGE_BYTES = 1024 * 1024;
const MAX_SCRIPT_BYTES = 256 * 1024;
const SCAN_TIMEOUT_MS = 9000;

export function rejectTarget(input) {
  if (typeof input !== "string" || input.length > 2048 || !input.trim()) return null;
  let target;
  try { target = new URL(input.trim()); } catch { return null; }
  if (!["http:", "https:"].includes(target.protocol) ||
      target.username || target.password || target.hash ||
      (target.port && !["80", "443"].includes(target.port))) return null;
  const host = target.hostname.toLowerCase().replace(/\.$/, "");
  // No literal IP hosts, loopback names, pseudo-TLDs or single-label intranet.
  // Cloudflare's public egress additionally denies connections to private IPs.
  if (host.length > 253 || !/^[a-z\d][a-z\d.-]*\.[a-z]{2,}$/i.test(host) ||
      host.split(".").some(p=>!p||p.length>63||p.startsWith("-")||p.endsWith("-")) ||
      /(?:^|\.)(?:localhost|local|internal|test|invalid|example|onion|lan)$/i.test(host) ||
      /(?:^|\.)(?:localhost|metadata|instance-data)(?:\.|$)/i.test(host)) return null;
  return target;
}

export function classifyStream(input) {
  const url=rejectTarget(input);
  if (!url) return null;
  const match=url.pathname.toLowerCase().match(/\.(m3u8|mpd|mp4|flv)$/);
  return match ? TYPES[match[1]] : null;
}

export function extractStreamLinks(raw, pageUrl, cap=35) {
  const base=rejectTarget(pageUrl);
  if (!base) return [];
  const text=String(raw||"")
    .replace(/\\u002f/gi, "/")
    .replace(/\\u003a/gi, ":")
    .replace(/\\\//g, "/")
    .replace(/&amp;/gi, "&")
    .replace(/&#38;/gi, "&")
    .replace(/&quot;/gi, '"');
  // Detect quoted and embedded absolute/protocol-relative/relative media URLs.
  const re=/((?:https?:\/\/|\/\/|\/(?!\/)|\.{1,2}\/)[^\s"'<>(){}\\\[\],;]{1,650}?\.(?:m3u8|mpd|mp4|flv)(?:\?[^\s"'<>()[\]{}\\]{0,500})?)/gi;
  const seen=new Set();
  const out=[];
  let match;
  while ((match=re.exec(text)) && out.length<cap) {
    let candidate=match[1].replace(/&(?:amp|#38);/gi,"&");
    // Trailing quotes and script punctuation are not part of a URL.
    candidate=candidate.replace(/[.?!:;,&]+$/, "");
    try {
      const resolved=new URL(candidate,base);
      const type=classifyStream(resolved.href);
      if (!type || seen.has(resolved.href)) continue;
      seen.add(resolved.href);
      out.push({
        url:resolved.href,
        type,
        // These are suggested browser page context values, NOT intercepted
        // request headers. No cookies, authorization or DRM keys are read.
        referer:base.href,
        origin:base.origin,
      });
    } catch {}
  }
  return out;
}

function json(data,status=200) {
  return new Response(JSON.stringify(data),{
    status,
    headers:{
      "Content-Type":"application/json",
      "Access-Control-Allow-Origin":"*",
      "Access-Control-Allow-Headers":"Authorization,Content-Type",
      "Cache-Control":"no-store",
      "X-Content-Type-Options":"nosniff",
      "Referrer-Policy":"no-referrer",
    },
  });
}

async function boundedResponseBody(response, maxBytes) {
  if (!response.body) return {text:"",truncated:false};
  const reader=response.body.getReader();
  let total=0;
  let truncated=false;
  const buffers=[];
  try {
    while (true) {
      const part=await reader.read();
      if (part.done) break;
      const remaining=maxBytes-total;
      if (remaining<=0) {
        truncated=true;
        break;
      }
      // Do not retain bytes beyond the cap even if the server sends a
      // huge stream chunk or does not provide Content-Length.
      const take=Math.min(remaining,part.value.byteLength);
      if (take>0) {
        buffers.push(part.value.subarray(0,take));
        total+=take;
      }
      if (take<part.value.byteLength) {
        truncated=true;
        break;
      }
    }
  } finally { await reader.cancel().catch(()=>{}); }
  const result=new Uint8Array(total);
  let offset=0;
  for(const chunk of buffers){ result.set(chunk,offset);offset+=chunk.length; }
  return {text:new TextDecoder().decode(result),truncated};
}

async function loadPage(address,kind,fetchImpl) {
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),SCAN_TIMEOUT_MS);
  try {
    let uri=address;
    for(let i=0;i<3;i++){
      if(!rejectTarget(uri)) throw new Error("Unsafe website URL or redirect.");
      const response=await fetchImpl(uri,{
        method:"GET",
        redirect:"manual",
        headers:{
          "Accept":kind==="script"?"text/javascript,application/javascript,text/plain;q=0.9":"text/html,application/xhtml+xml,*/*;q=0.8",
          "User-Agent":"NCA-Admin-Media-Discovery/1.0",
        },
        signal:controller.signal,
      });
      if ([301,302,303,307,308].includes(response.status)){
        const location=response.headers.get("Location");
        await response.body?.cancel().catch(()=>{});
        if(!location) throw new Error("Website redirect had no destination.");
        uri=new URL(location,uri).href;
        continue;
      }
      if(!response.ok) {
        await response.body?.cancel().catch(()=>{});
        if(response.status===403) {
          throw new Error("Website denied the scanner request (HTTP 403). The website owner may restrict automated access.");
        }
        if(response.status===429) {
          throw new Error("Website rate limited the scanner (HTTP 429). Try later.");
        }
        throw new Error("Website returned HTTP "+response.status+".");
      }
      const ct=(response.headers.get("Content-Type")||"").toLowerCase();
      if(kind==="script" && !/javascript|text\/plain|octet-stream/.test(ct)){
        await response.body?.cancel().catch(()=>{});
        return {url:uri,text:"",partial:false};
      }
      if(kind==="page" && ct && !/html|text\/plain/.test(ct)){
        await response.body?.cancel().catch(()=>{});
        throw new Error("The URL does not return an HTML website.");
      }
      const limit=kind==="script"?MAX_SCRIPT_BYTES:MAX_PAGE_BYTES;
      const length=Number(response.headers.get("Content-Length")||"0");
      // Content-Length is advisory: NEVER reject a large page outright.
      // Scan a limited prefix and cancel the rest of the response.
      const body=await boundedResponseBody(response,limit);
      return {
        url:uri,
        text:body.text,
        partial:body.truncated || (Number.isFinite(length) && length>limit),
      };
    }
    throw new Error("Too many website redirects.");
  } finally {clearTimeout(timer);controller.abort();}
}

export async function isVerifiedAdmin(request,env,fetchImpl) {
  const header=request.headers.get("Authorization")||"";
  if (!/^Bearer [^ ]{12,}$/.test(header)) return false;
  const base=env.SUPABASE_URL?.trim();
  const key=env.SUPABASE_PUBLISHABLE_KEY?.trim();
  if(!base||!key) return false;
  const tokenHeaders={Authorization:header,apikey:key,Accept:"application/json"};
  const userResponse=await fetchImpl(base.replace(/\/+$/,"")+"/auth/v1/user",{
    headers:tokenHeaders,signal:AbortSignal.timeout(6000),
  });
  if(!userResponse.ok)return false;
  const user=await userResponse.json().catch(()=>null);
  const userId=String(user?.id||"");
  if(!/^[a-f0-9-]{36}$/i.test(userId))return false;
  const profileUrl=base.replace(/\/+$/,"")+"/rest/v1/profiles?select=role&id=eq."+encodeURIComponent(userId)+"&limit=1";
  const profileResponse=await fetchImpl(profileUrl,{
    headers:tokenHeaders,signal:AbortSignal.timeout(6000),
  });
  if(!profileResponse.ok)return false;
  const rows=await profileResponse.json().catch(()=>[]);
  return Array.isArray(rows)&&rows.length===1&&rows[0]?.role==="admin";
}

export async function handleWebsiteStreamScan(request,env,{fetchImpl=fetch,allowRequest=null}={}) {
  if(request.method!=="POST")return json({error:"POST required."},405);
  let admin=false;
  try {admin=await isVerifiedAdmin(request,env,fetchImpl);}
  catch {return json({error:"Could not verify Admin session."},503);}
  if(!admin)return json({error:"A verified Admin session is required."},403);
  if(allowRequest && !(await allowRequest(request,env,"admin-website-scan",8))) {
    return json({error:"Scan limit reached. Try again later."},429);
  }
  let input;
  try {
    const body=await request.text();
    if(body.length>4096)return json({error:"Request too large."},413);
    input=JSON.parse(body);
  }catch{return json({error:"Invalid JSON request."},400);}
  if(input?.authorized!==true)return json({error:"Confirm that you may inspect this website."},400);
  const target=rejectTarget(input?.url);
  if(!target)return json({error:"Enter a valid public HTTP(S) website URL."},400);
  const direct=classifyStream(target.href);
  if(direct) {
    return json({ok:true,mode:"direct",page_url:target.href,links:[{
      url:target.href,type:direct,referer:"",origin:"",
    }],count:1,notes:"Direct media URL; playback not verified."});
  }
  try {
    const page=await loadPage(target.href,"page",fetchImpl);
    let found=extractStreamLinks(page.text,page.url);
    let partial=page.partial;
    const visited=new Set([page.url]);
    // Only inspect a few same-host JavaScript files or iframe documents.
    // Running scripts requires a browser engine and is not performed here.
    const resourceRe=/<(?:script|iframe)\b[^>]*?\bsrc\s*=\s*["']([^"']{1,1000})["']/gi;
    const resources=[];
    let item;
    while((item=resourceRe.exec(page.text))&&resources.length<3){
      try {
        const address=new URL(item[1].replace(/&amp;/g,"&"),page.url);
        if(address.host!==new URL(page.url).host || !rejectTarget(address.href) || visited.has(address.href))continue;
        const kind=item[0].startsWith("<iframe")?"page":"script";
        visited.add(address.href);
        resources.push({url:address.href,kind});
      } catch{}
    }
    for(const res of resources) {
      try{
        const result=await loadPage(res.url,res.kind,fetchImpl);
        if(result.partial) partial=true;
        for(const link of extractStreamLinks(result.text,page.url))
          if(!found.some(x=>x.url===link.url))found.push(link);
      }catch{
        // Optional scripts/iframes may fail independently.
      }
      if(found.length>=35)break;
    }
    found=found.slice(0,35);
    return json({
      ok:true,mode:"html-scan",page_url:page.url,links:found,count:found.length,
      partial,
      notes:(found.length
        ?"Found media URLs embedded in website source. Playback and expiry are not verified."
        :"No direct media URLs in the accessible HTML/scripts. JS-only players require a real browser network observer; this scanner cannot intercept playback requests.")
        +(partial?" Some pages were large: only the first part was scanned, so results may be incomplete.":""),
    });
  }catch(error){
    // Never include credentials, URL query strings, or upstream HTML in error messages.
    const raw=String(error?.message||"").replace(/https?:\/\/\S+/gi,"[website]");
    const detail=error?.name==="AbortError"
      ? "Website request timed out before the page could be read."
      : raw==="fetch failed" || raw==="Failed to fetch" || !raw
        ? "Website could not be fetched by the scanner. It may be offline or blocking server requests."
        : raw;
    // A site lookup failure is an input/target problem, not an API outage.
    // 422 lets the Admin Web display the real cause instead of silently
    // trying other healthy API gateways and reporting 'cannot connect'.
    return json({error:detail,code:"website_fetch_failed"},422);
  }
}
