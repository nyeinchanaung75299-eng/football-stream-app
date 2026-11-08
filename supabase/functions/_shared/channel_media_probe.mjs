// HTTP, manifest, segment and DRM configuration checks are separate from
// actual decoded video. No probe claims that a browser has played frames.
import {publicSourceUrl} from './darkbyte_catalog.mjs';
const decode=x=>String(x||'').replace(/&amp;/g,'&').replace(/&quot;/g,'"');
export async function probeChannelMedia(line,{fetcher=fetch,timeoutMs=12000,includeKids=false}={}){
 const started=Date.now(),controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeoutMs);
 const result={health_status:'unknown',http_status:0,manifest_status:'not_tested',segment_status:'not_tested',drm_status:'unknown',detail:'Not checked'};
 const headers={Accept:'*/*',Range:'bytes=0-262143','User-Agent':'NCA-Channel-Health/2.0',
  ...(line.referer?{Referer:line.referer}:{}),...(line.origin?{Origin:line.origin}:{})};
 async function prefix(raw,{segment=false}={}){
  let url=publicSourceUrl(raw);if(!url)throw Error('Invalid media address');
  for(let hop=0;hop<4;hop++){
   const response=await fetcher(url.href,{headers:segment?{...headers,Range:'bytes=0-4095'}:headers,redirect:'manual',signal:controller.signal});
   if(response.status>=300&&response.status<400){const next=publicSourceUrl(new URL(response.headers.get('location')||'',url).href);await response.body?.cancel();if(!next)throw Error('Invalid media redirect');url=next;continue;}
   if(!response.ok){await response.body?.cancel();const error=new Error('HTTP '+response.status);error.http=response.status;throw error;}
   const reader=response.body?.getReader();if(!reader)throw Error('Empty media response');
   const chunks=[];let bytes=0;try{while(bytes<(segment?4096:262144)){const item=await reader.read();if(item.done)break;chunks.push(item.value);bytes+=item.value.length;}}finally{await reader.cancel().catch(()=>{});}
   if(!bytes)throw Error('Empty media response');
   const data=new Uint8Array(bytes);let at=0;for(const c of chunks){data.set(c,at);at+=c.length;}
   return {url:url.href,status:response.status,text:segment?'':new TextDecoder().decode(data)};
  }throw Error('Too many media redirects');
 }
 try{
  let body=await prefix(line.stream_url);result.http_status=body.status;
  const isDash=/<(?:\w+:)?MPD\b/i.test(body.text),isHls=body.text.trimStart().startsWith('#EXTM3U');
  if(!isDash&&!isHls){
   if(line.stream_type==='mp4'||line.stream_type==='flv'){
    result.health_status=Date.now()-started>3000?'slow':'healthy';result.manifest_status='not_applicable';result.segment_status='reachable';result.drm_status='unknown';result.detail='Media bytes reachable; video decode not tested';return result;
   }
   result.manifest_status='invalid';throw Error('Response is not a media manifest');
  }
  result.manifest_status='valid';let segment=null;
  if(isHls){
   if(/#EXT-X-STREAM-INF:/.test(body.text)){
    const lines=body.text.split(/\r?\n/);let next=false,child;
    for(const l of lines){if(l.startsWith('#EXT-X-STREAM-INF:'))next=true;else if(next&&l.trim()&&!l.startsWith('#')){child=l.trim();break;}}
    if(!child)throw Error('HLS master has no media playlist');
    body=await prefix(new URL(child,body.url).href);if(!body.text.trimStart().startsWith('#EXTM3U'))throw Error('Invalid HLS media playlist');
   }
   const encrypted=/#EXT-X-KEY:.*METHOD=(?!NONE)/i.test(body.text);
   result.drm_status=encrypted?'source_key_required':'not_required';
   const media=body.text.split(/\r?\n/).map(x=>x.trim()).find(x=>x&&!x.startsWith('#'));
   if(media)segment=new URL(media,body.url).href;
  }else{
   const encrypted=/<(?:\w+:)?ContentProtection\b/i.test(body.text);
   const kids=[...body.text.matchAll(/(?:cenc:)?default_KID\s*=\s*["']([^"']+)/gi)].flatMap(m=>m[1].split(/\s+/)).map(x=>x.replace(/-/g,'').toLowerCase());
   if(includeKids)result.manifest_kids=kids;
   const pair=/^[a-f\d]{32}$/i.test(line.key_id||'')&&/^[a-f\d]{32}$/i.test(line.key_data||'');
   result.drm_status=!encrypted?'not_required':pair&&(!kids.length||kids.includes(line.key_id.replace(/-/g,'').toLowerCase()))?'configured':'missing_configuration';
   const base=body.text.match(/<(?:\w+:)?BaseURL\b[^>]*>([^<]+)</i)?.[1];
   const baseUrl=base?new URL(decode(base.trim()),body.url).href:body.url;
   const rep=body.text.match(/<Representation\b[^>]*\bid=["']([^"']+)/i)?.[1];
   const band=body.text.match(/<Representation\b[^>]*\bbandwidth=["']([^"']+)/i)?.[1];
   const initialization=body.text.match(/<SegmentTemplate\b[^>]*\binitialization=["']([^"']+)/i)?.[1]||body.text.match(/<Initialization\b[^>]*\bsourceURL=["']([^"']+)/i)?.[1];
   const template=initialization||body.text.match(/<SegmentTemplate\b[^>]*\bmedia=["']([^"']+)/i)?.[1];
   if(template){
    const number=body.text.match(/\bstartNumber=["'](\d+)/i)?.[1]||'1';
    const time=body.text.match(/<S\b[^>]*\bt=["'](\d+)/i)?.[1];
    const part=decode(template).replace(/\$RepresentationID\$/g,rep||'').replace(/\$Bandwidth\$/g,band||'').replace(/\$Number(?:%0(\d+)d)?\$/g,(_,digits)=>number.padStart(Number(digits||0),'0')).replace(/\$Time\$/g,time||'');
    if(!part.includes('$'))segment=new URL(part,baseUrl).href;
   }else if(base&&/\.(mp4|m4s)(?:$|\?)/i.test(base))segment=baseUrl;
  }
  if(segment){try{await prefix(segment,{segment:true});result.segment_status='reachable';}catch(error){result.segment_status='failed';throw error;}}
  result.health_status=Date.now()-started>3000?'slow':'healthy';
  result.detail=result.drm_status==='missing_configuration'?'Manifest reachable; DRM configuration needed':segment?'Manifest and media bytes reachable; video decode not tested':'Manifest valid; segment address needs player resolution';
 }catch(error){
  result.http_status=result.http_status||error.http||0;
  result.health_status=[401,403,405,429].includes(error.http)?'unknown':'failed';
  if(result.manifest_status==='not_tested')result.manifest_status='unavailable';
  result.detail=controller.signal.aborted?'Media check timed out':error.http?'Upstream HTTP '+error.http:result.manifest_status==='invalid'?'Response is not a media manifest':'Media or segment unavailable';
 }finally{clearTimeout(timer);controller.abort();result.latency_ms=Date.now()-started;}
 return result;
}
