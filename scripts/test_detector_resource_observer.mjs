import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync(new URL('../admin_app/lib/services/detector_resource_observer.dart',import.meta.url),'utf8')
  .match(/const detectorResourceObserver = r'''([\s\S]*?)''';/)[1];

function document(url,top) {
 const events={},observers=[],resources=[],videos=[],reports=[];
 const win={frames:[],addEventListener:(name,callback)=>events[name]=callback};
 win.top=top ? {postMessage:data=>top.events.message({source:win,data})} : win;
 if(!top)win.flutter_inappwebview={callHandler:(name,data)=>{reports.push({name,data});return Promise.resolve();}};
 const context={window:win,document:{baseURI:url,querySelectorAll:()=>videos,addEventListener:()=>{}},location:{href:url},
  performance:{getEntriesByType:()=>resources},URL,Date,Math,Set,
  setInterval:()=>1,clearInterval:()=>{},
  PerformanceObserver:class{constructor(callback){observers.push(callback);}observe(){}}};
 vm.runInNewContext(source,context);
 return {win,events,observers,resources,videos,reports};
}

test('late HLS inside active iframe reaches the current top document without native interception',()=>{
 const top=document('https://player.example/watch');
 const child=document('https://iframe.example/player',top);
 top.win.frames.push(child.win);
 child.resources.push({name:'https://cdn.example/live.m3u8'});
 child.observers[0]({getEntries:()=>child.resources});
 assert.ok(top.reports.length);
 assert.equal(top.reports[0].data.frameUrl,'https://iframe.example/player');
 assert.equal(top.reports[0].data.pageUrl,'https://player.example/watch');
 assert.deepEqual(Array.from(top.reports[0].data.urls),['https://cdn.example/live.m3u8']);
 assert.equal(top.reports[0].data.documentId,top.win.__ncaDetectorDocumentId);
 assert.equal(top.reports[0].data.mediaUrls.length,0);
});

test('detached iframe events, blob URLs, segments and private page data never export',()=>{
 const top=document('https://player.example/watch');
 const child=document('https://iframe.example/player',top);
 top.win.frames.push(child.win);
 child.resources.push({name:'https://cdn.example/seg.ts'});
 child.videos.push({currentSrc:'blob:https://iframe.example/video',src:''});
 child.win.__ncaDetectorScan();
 assert.equal(top.reports.length,0);
 top.win.frames=[];
 child.resources.push({name:'https://cdn.example/late.m3u8'});
 child.observers[0]({getEntries:()=>child.resources});
 assert.equal(top.reports.length,0);
});

test('explicit video source association is retained but script cannot trigger a network fetch',()=>{
 const top=document('https://player.example/watch');
 top.videos.push({currentSrc:'https://cdn.example/current.m3u8',src:''});
 top.win.__ncaDetectorScan();
 assert.deepEqual(Array.from(top.reports[0].data.mediaUrls),['https://cdn.example/current.m3u8']);
 assert.deepEqual(Object.keys(top.reports[0].data).sort(),['documentId','frameUrl','mediaUrls','pageUrl','urls']);
});
