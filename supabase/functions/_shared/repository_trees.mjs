export const REPOSITORY_TREE_SOURCES=['darkbyteprojects/iptv_png','Roshavarma/cfy',
 'nehalmahamuddev/SM-IPTV-Category-Playlists-Auto-Sync','dilzyking/allrounderlive',
 'sm-monirulislam/Upcoming-and-Live-Sports-Data','mdjamsad9/dudetvapi'];
const mirror='https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/repository-trees.json';
const cooldowns=new WeakMap();
const DEFAULT_COOLDOWN=15*60000;
function validTree(tree){return tree&&!tree.truncated&&/^[a-f\d]{40}$/.test(tree.sha||'')&&Array.isArray(tree.tree)&&tree.tree.length<=5000;}
function httpFailure(response){
 const retryAfter=response.headers.get('retry-after'),remaining=response.headers.get('x-ratelimit-remaining');
 return Object.assign(Error('Repository metadata unavailable'),{code:'repository_http_'+response.status,
  status:response.status,retryAfter,reset:response.headers.get('x-ratelimit-reset'),
  sharedLimit:response.status===429||(response.status===403&&(remaining==='0'||retryAfter!==null))});
}
function retryUntil(error,now){
 const retry=error.retryAfter;
 const retryAt=retry===null||retry===undefined?0:/^\d+$/.test(retry.trim())?now+Number(retry)*1000:Date.parse(retry);
 const resetAt=error.sharedLimit&&error.reset?Number(error.reset)*1000:0;
 return Math.max(now+DEFAULT_COOLDOWN,Number.isFinite(retryAt)?retryAt:0,Number.isFinite(resetAt)?resetAt:0);
}
function activeCooldown(state,repo,now){
 for(const value of [state.shared,state.repositories.get(repo)])if(value&&value.until>now)
  return Object.assign(Error('Repository metadata retry deferred'),{code:value.code,deferred:true});
 return null;
}
async function read(url,fetcher,signal){
 const response=await fetcher(url,{redirect:'error',signal,headers:{Accept:'application/json','User-Agent':'NCA-Published-Repository/1.0'}});
 if(!response.ok){const error=httpFailure(response);await response.body?.cancel();throw error;}
 const reader=response.body.getReader(),chunks=[];let size=0;
 try{while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>1024*1024)throw Error('Repository metadata exceeds budget');chunks.push(value);}}
 finally{await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(size);let i=0;for(const chunk of chunks){bytes.set(chunk,i);i+=chunk.length;}return JSON.parse(new TextDecoder().decode(bytes));
}
// Scheduled Actions publish metadata using the repository-scoped token.
// A stale mirror is never deletion evidence. The anonymous fallback observes
// rate-limit headers and backs off within the lifetime of the current isolate.
export async function readRepositoryTrees(repositories,{fetcher=fetch,signal,now=Date.now(),allowMissing=false,isolateFailures=false}={}){
 if(repositories.some(repo=>!REPOSITORY_TREE_SOURCES.includes(repo)))throw Error('Unsupported repository');
 let state=cooldowns.get(fetcher);
 if(!state){state={shared:null,repositories:new Map()};cooldowns.set(fetcher,state);}
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);
 const combined=signal?AbortSignal.any([signal,controller.signal]):controller.signal;
 try{
  let mirrorRepositories;
  try{
   const data=await read(mirror,fetcher,combined),age=now-Date.parse(data.fetched_at);
   if(Number.isFinite(age)&&age>=-60000&&age<=30*60000)
    mirrorRepositories=data.repositories;
  }catch{/* Fall back to GitHub per source. */}
  const results=[];
  // Probe missing entries sequentially so an explicit shared rate limit does
  // not cause another five anonymous requests in the same refresh.
  for(const repo of repositories){
   const mirrored=mirrorRepositories?.[repo];
   if(validTree(mirrored)){results.push(mirrored);continue;}
   if(allowMissing&&mirrored?.status===404){results.push(null);continue;}
   try{
    const deferred=activeCooldown(state,repo,now);if(deferred)throw deferred;
    const tree=await read('https://api.github.com/repos/'+repo+'/git/trees/HEAD?recursive=1',fetcher,combined);
    if(!validTree(tree))throw Error('Incomplete repository tree');
    results.push(tree);
   }catch(error){
    if(!error?.deferred&&(error?.status===403||error?.status===429)){
     const value={until:retryUntil(error,now),code:error.code};
     if(error.sharedLimit)state.shared=value;else state.repositories.set(repo,value);
    }
    // A failure is never reported as a confirmed deletion. Only opt-in
    // callers may retain a partial snapshot while other sources succeed.
    if(allowMissing&&(error?.code==='repository_http_404'||isolateFailures)){
     console.warn('Repository metadata fetch failed',{repository:repo,code:error?.code||error?.name||'invalid_metadata'});
     results.push(null);continue;
    }
    throw error;
   }
  }
  return results;
 }finally{clearTimeout(timer);controller.abort();}
}
