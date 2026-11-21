const base='https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/project-backup/';
const max=45*1024*1024;
async function read(response,limit){
 if(!response.ok)throw Error('Backup unavailable');const reader=response.body?.getReader();if(!reader)throw Error('Empty backup');
 const chunks=[];let size=0;try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit)throw Error('Backup too large');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const data=new Uint8Array(size);let at=0;for(const chunk of chunks){data.set(chunk,at);at+=chunk.length;}return data;
}
export async function sendProjectBackup({chatId,token,fetcher=fetch}){
 if(!Number.isSafeInteger(chatId)||!token)throw Error('Invalid backup request');
 const data=await read(await fetcher(base+'source-latest.json',{redirect:'error',signal:AbortSignal.timeout(15000)}),8192);
 const manifest=JSON.parse(new TextDecoder().decode(data));
 if(manifest.filename!=='NCA-project-source.zip'||manifest.scope!=='source-and-recovery-instructions'||!Number.isSafeInteger(manifest.size_bytes)||manifest.size_bytes<=0||manifest.size_bytes>max||!/^[a-f0-9]{40}$/.test(manifest.source_commit)||!/^[a-f0-9]{64}$/.test(manifest.sha256))throw Error('Invalid backup manifest');
 const bytes=await read(await fetcher(base+manifest.filename,{redirect:'error',signal:AbortSignal.timeout(60000)}),manifest.size_bytes);
 const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join('');
 if(bytes.length!==manifest.size_bytes||digest!==manifest.sha256||bytes[0]!==80||bytes[1]!==75)throw Error('Backup integrity check failed');
 const body=new FormData();body.set('chat_id',String(chatId));body.set('document',new Blob([bytes],{type:'application/zip'}),manifest.filename);
 body.set('caption','NCA project source backup\nCommit: '+manifest.source_commit+'\nSHA-256 verified. Includes source, migrations, build scripts and recovery instructions.\nDatabase data, secrets and signing keys are NOT included. Use /apk for signed app files.');
 const sent=await fetcher('https://api.telegram.org/bot'+token+'/sendDocument',{method:'POST',body,signal:AbortSignal.timeout(75000)});
 if(!sent.ok||(await sent.json())?.ok!==true)throw Error('Backup upload failed');return manifest;
}
