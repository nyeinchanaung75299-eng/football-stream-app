import test from 'node:test';import assert from 'node:assert/strict';
import {sendProjectBackup} from '../supabase/functions/_shared/telegram_project_backup.mjs';
const bytes=new Uint8Array([80,75,3,4,1,2]);
const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
const manifest={filename:'NCA-project-source.zip',source_commit:'a'.repeat(40),scope:'source-and-recovery-instructions',size_bytes:bytes.length,sha256:digest};
test('verified bytes are uploaded only after fixed manifest/hash/size checks',async()=>{
 const urls=[];await sendProjectBackup({chatId:123,token:'fixture-token',fetcher:async(url,options)=>{
  urls.push(url);if(url.endsWith('.json'))return Response.json(manifest);if(url.endsWith('.zip'))return new Response(bytes);
  assert.equal(options.body.get('chat_id'),'123');assert.match(options.body.get('caption'),/NOT included/);return Response.json({ok:true});
 }});assert.equal(urls.length,3);
});
test('wrong hash never reaches Telegram',async()=>{
 let uploads=0;await assert.rejects(sendProjectBackup({chatId:123,token:'fixture-token',fetcher:async url=>{
  if(url.endsWith('.json'))return Response.json({...manifest,sha256:'0'.repeat(64)});if(url.endsWith('.zip'))return new Response(bytes);uploads++;return Response.json({ok:true});
 }}));assert.equal(uploads,0);
});
test('arbitrary filenames cannot turn backup into a URL fetcher',async()=>{
 let calls=0;await assert.rejects(sendProjectBackup({chatId:123,token:'fixture-token',fetcher:async()=>{calls++;return Response.json({...manifest,filename:'https://elsewhere.example/data'});}}));assert.equal(calls,1);
});
