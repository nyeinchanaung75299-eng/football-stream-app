import {writeFile,rename} from 'node:fs/promises';
import {REPOSITORY_TREE_SOURCES} from '../supabase/functions/_shared/repository_trees.mjs';
const repositories={};
await Promise.all(REPOSITORY_TREE_SOURCES.map(async repo=>{
 try{
 const response=await fetch('https://api.github.com/repos/'+repo+'/git/trees/HEAD?recursive=1',{
  headers:{Accept:'application/vnd.github+json',...(process.env.GH_TOKEN?{Authorization:'Bearer '+process.env.GH_TOKEN}:{})},signal:AbortSignal.timeout(15000)});
 if(response.status===404){await response.body?.cancel();repositories[repo]={status:404};return;}
 if(!response.ok){const status=response.status;await response.body?.cancel();repositories[repo]={status};return;}
 const data=await response.json();
 if(data.truncated||!Array.isArray(data.tree)||!/^[a-f\d]{40}$/.test(data.sha||'')||data.tree.length>5000)throw Error('Incomplete repository metadata');
 repositories[repo]={sha:data.sha,truncated:false,tree:data.tree.filter(row=>row.type==='blob').map(({path,type,sha,size})=>({path,type,sha,size}))};
 }catch{repositories[repo]={status:503};}
}));
if(!Object.values(repositories).some(entry=>entry.sha))throw Error('No GitHub repository returned a valid tree');
const target=process.argv[2];if(!target)throw Error('Output path required');
await writeFile(target+'.tmp',JSON.stringify({fetched_at:new Date().toISOString(),repositories}));await rename(target+'.tmp',target);
console.log('Published complete metadata for '+Object.keys(repositories).length+' repositories; no stream configurations or credentials.');
