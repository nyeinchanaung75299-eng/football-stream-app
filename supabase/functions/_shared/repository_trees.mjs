export const REPOSITORY_TREE_SOURCES=['rohmanabdu/lian','rohmanabdu/deqiaa','darkbyteprojects/iptv_png','Roshavarma/cfy'];
const mirror='https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/repository-trees.json';
function validTree(tree){return tree&&!tree.truncated&&/^[a-f\d]{40}$/.test(tree.sha||'')&&Array.isArray(tree.tree)&&tree.tree.length<=5000;}
async function read(url,fetcher,signal){
 const response=await fetcher(url,{redirect:'error',signal,headers:{Accept:'application/json','User-Agent':'NCA-Published-Repository/1.0'}});
 if(!response.ok){await response.body?.cancel();throw Object.assign(Error('Repository metadata unavailable'),{code:'repository_http_'+response.status});}
 const reader=response.body.getReader(),chunks=[];let size=0;
 try{while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>1024*1024)throw Error('Repository metadata exceeds budget');chunks.push(value);}}
 finally{await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(size);let i=0;for(const chunk of chunks){bytes.set(chunk,i);i+=chunk.length;}return JSON.parse(new TextDecoder().decode(bytes));
}
// Scheduled Actions use the repository-scoped token to publish metadata only.
// Edge servers avoid shared anonymous GitHub API quotas. Raw files remain
// pinned to the original tree revision and fixture blobs are SHA-verified.
export async function readRepositoryTrees(repositories,{fetcher=fetch,signal,now=Date.now()}={}){
 if(repositories.some(repo=>!REPOSITORY_TREE_SOURCES.includes(repo)))throw Error('Unsupported repository');
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);
 const combined=signal?AbortSignal.any([signal,controller.signal]):controller.signal;
 try{
  try{
   const data=await read(mirror,fetcher,combined),age=now-Date.parse(data.fetched_at);
   if(Number.isFinite(age)&&age>=-60000&&age<=30*60000&&repositories.every(repo=>validTree(data.repositories?.[repo])))
    return repositories.map(repo=>data.repositories[repo]);
  }catch{/* Fall back to GitHub without trusting a partial/stale mirror. */}
  return await Promise.all(repositories.map(async repo=>{
   const tree=await read('https://api.github.com/repos/'+repo+'/git/trees/HEAD?recursive=1',fetcher,combined);
   if(!validTree(tree))throw Error('Incomplete repository tree');return tree;
  }));
 }finally{clearTimeout(timer);controller.abort();}
}
