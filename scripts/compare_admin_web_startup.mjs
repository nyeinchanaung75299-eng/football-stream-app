// Controlled same-runner before/after Flutter Web startup measurements.
// Usage: NCA_WEB_BASE_PATH=/football-stream-app/admin/ node scripts/compare_admin_web_startup.mjs BEFORE_DIR AFTER_DIR
// By default, takes 10 paired cold/warm samples per build. Reports P50/P95.
// No production credentials, backend writes, or native APK builds.
import {createServer} from 'node:http';
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join, resolve, extname} from 'node:path';
import {gzipSync} from 'node:zlib';

const directories = process.argv.slice(2);
if (directories.length !== 2) throw new Error('Expected BEFORE_DIR AFTER_DIR');
const [beforeDir, afterDir] = directories.map(path => resolve(path));
const basePath = process.env.NCA_WEB_BASE_PATH || '/football-stream-app/admin/';
if (!basePath.startsWith('/') || !basePath.endsWith('/')) {
  throw new Error('NCA_WEB_BASE_PATH must be an absolute path ending in /');
}
const samplesPerBuild = Number(process.env.NCA_BENCHMARK_SAMPLES || 10);
if (!Number.isInteger(samplesPerBuild) || samplesPerBuild < 5 || samplesPerBuild > 30) {
  throw new Error('NCA_BENCHMARK_SAMPLES must be an integer from 5 to 30');
}
const mime = {'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm',
  '.json':'application/json','.otf':'font/otf','.ttf':'font/ttf',
  '.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'};
const delay = ms => new Promise(r=>setTimeout(r,ms));
const percentile = (values, fraction) => {
  const sorted = [...values].sort((a,b)=>a-b);
  if (!sorted.length) return null;
  const rank = (sorted.length - 1) * fraction;
  const lower = Math.floor(rank), upper = Math.ceil(rank);
  return Math.round(sorted[lower] + (sorted[upper]-sorted[lower])*(rank-lower));
};
function serve(directory, port) {
  const server=createServer(async(req,res)=>{
    try {
      const u=new URL(req.url,'http://localhost');
      if(!u.pathname.startsWith(basePath)){res.writeHead(404);res.end();return}
      let name=decodeURIComponent(u.pathname.slice(basePath.length)) || 'index.html';
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
  // Do not use flutter-view DOM mutations as first-frame proxies:
  // the element can have children well before Flutter paints its first frame.
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
  if (firstFrameMs === null) {
    throw new Error('flutter-first-frame event not observed: refusing an invalid startup comparison');
  }
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
    basePath, samplesPerBuild, before:[],after:[]};
  for(const [index,key] of ['before','after'].entries()){
    const url='http://127.0.0.1:'+ports[index]+basePath;
    for(let i=0;i<samplesPerBuild;i++){
      // Paired navigations use the same document URL. Only the cold run
      // clears the browser cache; the warm run reuses the downloaded assets.
      const sampleUrl=url+'?sample='+i;
      const cold=await measure(sampleUrl,true);
      const warm=await measure(sampleUrl,false);
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
        result[key][state][metric]={
          count: values.length,
          p50: percentile(values,0.50),
          p95: percentile(values,0.95),
        };
      }
    }
  }
  const comparison={conditions:output.conditions,basePath,samplesPerBuild,...result,
    rawSamples:{before:output.before,after:output.after}};
  if (process.env.NCA_BENCHMARK_OUTPUT) {
    await writeFile(process.env.NCA_BENCHMARK_OUTPUT,
      JSON.stringify(comparison,null,2)+'\n');
  }
  process.stdout.write('STARTUP_COMPARISON='+JSON.stringify(comparison)+'\n');
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
