// Controlled same-runner before/after Flutter Web startup measurements.
// Usage: node scripts/compare_admin_web_startup.mjs BASE_ADMIN_DIR NEW_ADMIN_DIR
// No production credentials, backend writes, or native APK builds.
import {createServer} from 'node:http';
import {readFile, mkdtemp, rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join, resolve, extname} from 'node:path';
import {gzipSync} from 'node:zlib';

const [beforeDir, afterDir] = process.argv.slice(2).map(path => resolve(path));
if (!beforeDir || !afterDir) throw new Error('Expected BEFORE_DIR AFTER_DIR');
const mime = {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm',
  '.json':'application/json','.otf':'font/otf','.ttf':'font/ttf',
  '.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'};
const delay = ms => new Promise(r=>setTimeout(r,ms));
const median = a => {const x=[...a].sort((v,w)=>v-w);return x[Math.floor(x.length/2)]};
function serve(directory, port) {
  const server=createServer(async(req,res)=>{
    try {
      const u=new URL(req.url,'http://localhost');
      const root='/football-stream-app/admin/';
      if(!u.pathname.startsWith(root)){res.writeHead(404);res.end();return}
      let name=decodeURIComponent(u.pathname.slice(root.length)) || 'index.html';
      if(name.endsWith('/'))name+='index.html';
      if(name.split('/').includes('..'))throw new Error('Invalid path');
      const bytes=await readFile(join(directory,name));
      res.setHeader('Content-Type',mime[extname(name)]||'application/octet-stream');
      res.setHeader('Cache-Control','public,max-age=3600');
      if((req.headers['accept-encoding']||'').includes('gzip') &&
          /\.(js|wasm|html|json|svg|css)$/.test(name)){
        res.setHeader('Content-Encoding','gzip');res.end(gzipSync(bytes,{level:6}));
      }else res.end(bytes);
    }catch(_){res.writeHead(404);res.end()}
  });
  return new Promise(r=>server.listen(port,'127.0.0.1',()=>r(server)));
}

let nextId=0,activeCount=new Map(),pending=new Map(),ws;
async function connectChrome(port) {
  let list;
  for(let n=0;n<80;n++){
    try{
      const resp=await fetch('http://127.0.0.1:'+port+'/json');
      list=await resp.json();
      if(list.some(x=>x.webSocketDebuggerUrl))break;
    }catch(_){}
    await delay(250);
  }
  const tab=list?.find(x=>x.type==='page' && x.webSocketDebuggerUrl);
  if(!tab)throw new Error('Headless Chrome DevTools did not start');
  ws=new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
  ws.onmessage=event=>{
    const m=JSON.parse(event.data);
    if(m.id){const p=pending.get(m.id);if(p){pending.delete(m.id);
      if(m.error)p.reject(new Error(m.error.message));else p.resolve(m.result||{})}}
    else if(m.method==='Network.responseReceived'){
      activeCount.set(m.params.requestId,m.params.response.url);
    }else if(m.method==='Network.loadingFinished' && measuring){
      const url=activeCount.get(m.params.requestId)||'';
      if(url.startsWith('http://127.0.0.1:')) {
        received.push({url,bytes:Math.round(m.params.encodedDataLength||0)});
      }
    }
  };
}
function call(method,params={}) {
  const id=++nextId;
  return new Promise((resolve,reject)=>{
    pending.set(id,{resolve,reject});
    ws.send(JSON.stringify({id,method,params}));
  });
}
let measuring=false,received=[];
const install=`(() => {
  window.__ncaFirstFrameAt = 0;
  const mark=()=>{if(!window.__ncaFirstFrameAt)window.__ncaFirstFrameAt=performance.now()};
  window.addEventListener('flutter-first-frame',mark,{once:true});
  document.addEventListener('flutter-first-frame',mark,{once:true});
  document.addEventListener('DOMContentLoaded',()=>{
    const observer=new MutationObserver(()=>{
      const v=document.querySelector('flutter-view');
      if(v && v.children.length){mark();observer.disconnect()}
    });
    observer.observe(document.body,{subtree:true,childList:true});
  },{once:true});
})();`;
async function evaluate(expression) {
  const r=await call('Runtime.evaluate',{expression,returnByValue:true});
  return r.result?.value;
}
async function measure(url,clearCache) {
  if(clearCache)await call('Network.clearBrowserCache');
  await call('Page.navigate',{url:'about:blank'});
  await delay(120);
  received=[];activeCount.clear();measuring=true;
  await call('Page.navigate',{url});
  let firstFrameMs=null;
  for(let i=0;i<350;i++){
    const v=await evaluate('Number(window.__ncaFirstFrameAt || 0)').catch(()=>0);
    if(v>0){firstFrameMs=Math.round(v);break}
    await delay(100);
  }
  await delay(300);
  measuring=false;
  const assets=received.filter(x=>!x.url.includes('/api/'));
  const sum=matcher=>assets.filter(x=>matcher.test(new URL(x.url).pathname))
    .reduce((p,x)=>p+x.bytes,0);
  return {
    firstFrameMs,
    mainJsBytes:sum(/main\.dart\.js$/),
    canvasWasmBytes:sum(/\.wasm$/),
    bootstrapBytes:sum(/flutter_bootstrap\.js$/),
    totalAssetBytes:assets.reduce((p,x)=>p+x.bytes,0),
    assetRequests:assets.length,
  };
}
const ports=[8127,8128],chromePort=9322;
const servers=[];
const userData=await mkdtemp(join(tmpdir(),'nca-web-benchmark-'));
let chrome;
try{
  servers.push(await serve(beforeDir,ports[0]),await serve(afterDir,ports[1]));
  const bin=process.env.CHROME_BIN||'google-chrome';
  chrome=spawn(bin,['--headless=new','--disable-gpu','--no-sandbox',
    '--disable-dev-shm-usage','--remote-debugging-port='+chromePort,
    '--user-data-dir='+userData,'about:blank'],{stdio:'ignore'});
  await connectChrome(chromePort);
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Network.enable');
  await call('Page.addScriptToEvaluateOnNewDocument',{source:install});
  // Identical, reproducible 8 Mbps/40ms profile, not a user's phone network.
  await call('Network.emulateNetworkConditions',{
    offline:false,latency:40,
    downloadThroughput:1024*1024,uploadThroughput:1024*1024,
  });
  const output={conditions:'Chromium headless, local gzip static host, 8 Mbps, 40ms simulated latency',
    before:[],after:[]};
  for(const [index,key] of ['before','after'].entries()){
    const url='http://127.0.0.1:'+ports[index]+'/football-stream-app/admin/';
    for(let i=0;i<3;i++){
      const cold=await measure(url+'?cold='+i,true);
      const warm=await measure(url+'?warm='+i,false);
      output[key].push({cold,warm});
      process.stdout.write(key+' sample '+(i+1)+': '+JSON.stringify({cold,warm})+'\n');
    }
  }
  const result={};
  for(const key of ['before','after']){
    const samples=output[key];
    result[key]={};
    for(const state of ['cold','warm']){
      result[key][state]={};
      for(const metric of ['firstFrameMs','mainJsBytes','canvasWasmBytes',
          'bootstrapBytes','totalAssetBytes','assetRequests']){
        const values=samples.map(x=>x[state][metric]).filter(x=>x!==null);
        result[key][state][metric]=values.length?median(values):null;
      }
    }
  }
  process.stdout.write('STARTUP_COMPARISON='+JSON.stringify({
    conditions:output.conditions,...result,
  })+'\n');
}finally{
  try{ws?.close()}catch(_){}
  if (chrome) {
    if (chrome.exitCode === null) chrome.kill('SIGTERM');
    await new Promise(r => {
      if (chrome.exitCode !== null) return r();
      const deadline = setTimeout(r, 2500);
      chrome.once('exit', () => { clearTimeout(deadline); r(); });
    });
  }
  for(const server of servers)await new Promise(r=>server.close(r));
  // Chrome child processes can still touch a profile briefly after SIGTERM.
  // Cleanup must not change the validity of completed measurements.
  await rm(userData,{recursive:true,force:true}).catch(() => {});
}
