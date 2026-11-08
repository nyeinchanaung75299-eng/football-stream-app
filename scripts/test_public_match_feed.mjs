import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../cloudflare/public-api/src/index.js', import.meta.url), 'utf8') + '\nexport { loadMatchRows, fetchJsonWithTimeout };';
const { default: worker, loadMatchRows, fetchJsonWithTimeout } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const env = { SUPABASE_URL: 'https://database.example', SUPABASE_PUBLISHABLE_KEY: 'test-public-key', GITHUB_MIRROR_URL: 'https://mirror.example/matches.json' };
const match = { id: 'test-match', home_team: 'Team Alpha' };

test('channel catalog pages past the old 250-channel truncation without returning a partial catalog', async()=>{
 const original=globalThis.fetch;
 const rows=Array.from({length:793},(_,i)=>({id:String(i),name:'Channel '+i}));
 const offsets=[];
 globalThis.fetch=async target=>{
  const u=new URL(target);assert.equal(u.pathname,'/rest/v1/channels');
  assert.match(u.searchParams.get('order'),/id.asc/);
  const offset=Number(u.searchParams.get('offset'));offsets.push(offset);
  return Response.json(rows.slice(offset,offset+Number(u.searchParams.get('limit'))));
 };
 try{
  const response=await worker.fetch(new Request('https://api.example/channels'),env,{});
  assert.equal(response.status,200);assert.equal((await response.json()).channels.length,793);
  assert.deepEqual(offsets,[0,500]);
 }finally{globalThis.fetch=original;}
});

test('My Channels guide retains imported channels missing from the older upstream EPG catalog',async()=>{
 const original=globalThis.fetch;
 globalThis.fetch=async target=>{
  const u=new URL(target);
  if(u.pathname==='/rest/v1/channels')return Response.json([
   {id:'nbc',name:'NBC',category:'NBC'},
   {id:'imported',name:'New Sports MPD',category:'Sports'},
  ]);
  if(u.pathname==='/api/schedule')return Response.json({ok:true,channels:[{id:'nbc',name:'NBC',matchedEPG:true,programmes:[
   {title:'Live football',start:1794072600000,end:1794079800000}]}]});
  return Response.json({ok:true,channels:[]});
 };
 try{
  const response=await worker.fetch(new Request('https://api.example/tv-schedule?date=2026-11-08'),env,{});
  const payload=await response.json();assert.equal(response.status,200);
  assert.equal(payload.channels.length,2);assert.equal(payload.channels[0].programmes.length,1);
  assert.equal(payload.channels[1].matchedEPG,false);assert.deepEqual(payload.channels[1].programmes,[]);
 }finally{globalThis.fetch=original;}
});

test('a failed later catalog page returns a retryable error instead of silently hiding channels',async()=>{
 const original=globalThis.fetch;
 globalThis.fetch=async target=>new URL(target).searchParams.get('offset')==='0'
  ?Response.json(Array.from({length:500},(_,i)=>({id:String(i)})))
  :new Response('Unavailable',{status:503});
 try{
  const response=await worker.fetch(new Request('https://api.example/channels'),env,{});
  assert.equal(response.status,502);assert.equal((await response.json()).channels,undefined);
 }finally{globalThis.fetch=original;}
});

test('Totalsportek kickoff-only requests forward the mode and never return stream data', async () => {
  const original = globalThis.fetch;
  let received;
  globalThis.fetch = async (url, init) => {
    assert.equal(new URL(url).pathname, '/functions/v1/soco-links');
    received = JSON.parse(init.body);
    return Response.json({match_time:'2026-11-07T12:30:00Z',
      lines:[{url:'https://private.example/token'}]});
  };
  try {
    const response = await worker.fetch(new Request(
      'https://api.example/sources/totalsportek/streams?metadata_only=1', {
        method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({page_url:'https://totalsportekl.is/Leeds-United-vs-Tottenham-Hotspur/78932'}),
      }),env,{});
    assert.equal(response.status,200);
    assert.equal(received.metadata_only,true);
    const payload = await response.json();
    assert.deepEqual(payload,{ok:true,source:'totalsportek',metadata_only:true,
      match_time:'2026-11-07T12:30:00Z'});
  } finally { globalThis.fetch = original; }
});

test('count query failure cannot produce an authoritative zero-line match', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async url => {
    const path = new URL(url).pathname;
    if (path === '/rest/v1/matches') return Response.json([match]);
    if (path === '/rest/v1/match_stream_counts') return new Response('Unavailable', { status: 503 });
    return Response.json([{ ...match, stream_count: 2 }]);
  };
  try {
    const result = await loadMatchRows(env);
    assert.equal(result.source, 'github');
    assert.equal(result.rows[0].stream_count, 2);
  } finally { globalThis.fetch = original; }
});

test('match list and count query start together without a serial round trip', async () => {
  const original = globalThis.fetch;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let countsStarted = false;
  globalThis.fetch = async url => {
    if (new URL(url).pathname === '/rest/v1/matches') {
      await gate; return Response.json([match]);
    }
    countsStarted = true;
    return Response.json([{ match_id: match.id, stream_count: 3 }]);
  };
  try {
    const pending = loadMatchRows(env);
    await new Promise(resolve => setImmediate(resolve));
    const startedInParallel = countsStarted;
    release();
    const result = await pending;
    assert.equal(startedInParallel, true);
    assert.equal(result.rows[0].stream_count, 3);
  } finally { release(); globalThis.fetch = original; }
});

test('an authoritative empty match list stays empty rather than reviving a mirror', async () => {
  const original = globalThis.fetch;
  let mirrorRequests = 0;
  globalThis.fetch = async url => {
    if (new URL(url).host === 'mirror.example') { mirrorRequests++; return Response.json([match]); }
    return Response.json([]);
  };
  try {
    const result = await loadMatchRows(env);
    assert.equal(result.source, 'supabase');
    assert.deepEqual(result.rows, []);
    assert.equal(mirrorRequests, 0);
  } finally { globalThis.fetch = original; }
});

test('empty matches remain authoritative even while the count service is down', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async url => new URL(url).pathname === '/rest/v1/matches'
    ? Response.json([]) : new Response('Unavailable', { status: 503 });
  try {
    const result = await loadMatchRows(env);
    assert.equal(result.source, 'supabase');
    assert.deepEqual(result.rows, []);
  } finally { globalThis.fetch = original; }
});

test('metadata deadline also cancels a body stalled after successful headers', async () => {
  const original = globalThis.fetch;
  let aborted = false;
  globalThis.fetch = async (_, { signal }) => new Response(new ReadableStream({
    start(controller) {
      signal.addEventListener('abort', () => {
        aborted = true;
        controller.error(new DOMException('Aborted', 'AbortError'));
      });
    },
  }));
  try {
    await assert.rejects(fetchJsonWithTimeout('https://database.example', {}, 20), { name: 'AbortError' });
    assert.equal(aborted, true);
  } finally { globalThis.fetch = original; }
});

test('TV schedule relay returns programme metadata only', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async url => {
    const request = new URL(url);
    assert.equal(request.origin, 'https://my-channels-match-guide.vercel.app');
    assert.equal(request.pathname, '/api/schedule');
    assert.equal(request.searchParams.get('date'), '2026-10-29');
    assert.equal(request.searchParams.get('days'), '8');
    return Response.json({
      timezone: 'Asia/Yangon',
      updated_at: '2026-10-29T12:00:00.000Z',
      sources: [{ name: 'au', ok: true, secret: 'not-public' }],
      channels: [{
        id: 'channel-1',
        name: 'TNT Sports 1',
        image_url: 'https://images.example/tnt.png',
        category: 'Sport',
        matchedEPG: true,
        region: 'uk',
        stream_url: 'https://private.example/stream.m3u8?token=secret',
        programmes: [{
          start: 1793275200000,
          end: 1793278800000,
          title: 'Everton vs Newcastle United',
          description: 'Live football',
          drm_key: 'private-key',
        }],
      }],
    });
  };
  try {
    const response = await worker.fetch(
      new Request('https://worker.example/tv-schedule?date=2026-10-29&days=99'),
      env,
      {},
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), '*');
    const body = await response.json();
    assert.equal(body.days, 8);
    assert.equal(body.channels.length, 1);
    assert.equal(body.channels[0].name, 'TNT Sports 1');
    assert.equal(body.channels[0].stream_url, undefined);
    assert.equal(body.channels[0].programmes[0].drm_key, undefined);
    assert.equal(body.sources[0].secret, undefined);
  } finally { globalThis.fetch = original; }
});

test('TV schedule joins the public MX and UK extended feeds by existing channel id', async () => {
  const original = globalThis.fetch;
  const kickoff = Date.parse('2026-11-01T13:00:00Z');
  const start = kickoff - 5 * 60 * 1000;
  const ids = { mx: 'canal-5', uk: 'premier-2' };
  let firstFetch = null;
  globalThis.fetch = async url => {
    const request = new URL(url);
    if (firstFetch == null) firstFetch = request.pathname;
    if (request.pathname === '/api/schedule') {
      return Response.json({
        sources: [{ name: 'uk', ok: true }],
        channels: [
          { id: ids.mx, name: 'Canal 5', matchedEPG: false, programmes: [] },
          { id: ids.uk, name: 'Premier Sports 2 UK', matchedEPG: false, programmes: [] },
        ],
      });
    }
    if (request.pathname === '/api/epg-mx') {
      return Response.json({
        sources: [{ name: 'mx', ok: true }],
        channels: [{
          id: ids.mx, matchedEPG: true, region: 'mx',
          programmes: [{
            start, title: 'Getafe vs Sevilla En Vivo',
            stream_url: 'https://private.example/secret.m3u8',
          }],
        }],
      });
    }
    if (request.pathname === '/api/uk-extended') {
      return Response.json({
        channels: [{
          id: ids.uk, matchedEPG: true, region: 'uk',
          programmes: [{
            start, title: 'Live: LaLiga',
            subtitle: 'Getafe CF v Sevilla FC',
            description: 'Live football',
            drm_key: 'private-secret',
          }],
        }],
      });
    }
    return Response.json({ channels: [], sources: [{ name: 'feed', ok: true }] });
  };
  try {
    const response = await worker.fetch(
      new Request('https://worker.example/tv-schedule?date=2026-11-01&days=8'),
      env, {},
    );
    assert.equal(response.status, 200);
    assert.equal(firstFetch, '/api/schedule', 'baseline EPG must be fetched before optional feeds');
    const body = await response.json();
    assert.equal(body.channels.length, 2);
    assert.equal(body.matched_channels, 2);
    const mx = body.channels.find(c => c.id === ids.mx);
    const uk = body.channels.find(c => c.id === ids.uk);
    assert.equal(mx.programmes[0].title, 'Getafe vs Sevilla En Vivo');
    assert.equal(uk.programmes[0].subtitle, 'Getafe CF v Sevilla FC');
    assert.equal(mx.programmes[0].stream_url, undefined);
    assert.equal(uk.programmes[0].drm_key, undefined);
    assert.equal(mx.programmes[0].start, start);
    assert.equal(uk.programmes[0].start, start);
  } finally { globalThis.fetch = original; }
});

test('cold NBC guide does not wait for unrelated feeds and survives a later isolate through public metadata cache',async()=>{
 const original=globalThis.fetch,originalCaches=globalThis.caches;
 const stored=new Map(),background=[];let release;
 const gate=new Promise(resolve=>release=resolve);
 globalThis.caches={default:{async match(req){return stored.get(req.url)?.clone();},async put(req,response){stored.set(req.url,response.clone());}}};
 const baseline={channels:[{id:'nbc-test',name:'NBC',matchedEPG:false,programmes:[]}]};
 globalThis.fetch=async target=>{
  const u=new URL(target);
  if(u.pathname==='/rest/v1/channels')return Response.json([{id:'nbc-test',name:'NBC'}]);
  if(u.hostname==='raw.githubusercontent.com')return Response.json({ok:true,updated_at:new Date().toISOString(),channels:[]});
  if(u.pathname==='/api/schedule')return Response.json(baseline);
  if(u.searchParams.get('source')==='US2')return Response.json({channels:[{
   id:'nbc-test',matchedEPG:true,region:'us',programmes:[{start:Date.parse('2026-11-07T17:30:00Z'),
    title:'Live: Premier League Soccer',description:'Nottingham Forest host Manchester City.',drm_key:'never-cache-this'}],
  }]});
  await gate;return Response.json({channels:[]});
 };
 try{
  const request=new Request('https://worker.example/tv-schedule?date=2026-11-08&days=3');
  const response=await worker.fetch(request,env,{waitUntil:p=>background.push(p)});
  const first=await response.json();assert.equal(first.channels[0].matchedEPG,true);
  assert.equal(first.channels[0].programmes[0].description,'Nottingham Forest host Manchester City.');
  release();await Promise.all(background);
  assert.equal(stored.size,1);assert(!(await [...stored.values()][0].clone().text()).includes('never-cache-this'));
  globalThis.fetch=async target=>new URL(target).pathname==='/api/schedule'?Response.json(baseline):Promise.reject(Error('Regional feed down'));
  const second=await worker.fetch(request,env,{waitUntil:p=>background.push(p)});
  assert.equal((await second.json()).channels[0].matchedEPG,true);
  await Promise.all(background);
 }finally{release();globalThis.fetch=original;globalThis.caches=originalCaches;}
});

test('GitHub EPG requires a fresh saved station binding and strips private source fields',async()=>{
 const original=globalThis.fetch;let binding='Station1.in',old=false,baselineHasStation=true;
 const channel={id:'imported-station',name:'Sports 1',epg_source:'GH:share_IN1'};
 globalThis.fetch=async target=>{
  const u=new URL(target);
  if(u.pathname==='/rest/v1/channels')return Response.json([{...channel,epg_id:binding}]);
  if(u.pathname==='/api/schedule')return Response.json({channels:baselineHasStation?[{...channel,matchedEPG:false,programmes:[]}]:[]});
  if(u.hostname==='raw.githubusercontent.com')return Response.json({ok:true,
   updated_at:new Date(Date.now()-(old?36*3600000:0)).toISOString(),channels:[{
    ...channel,epg_id:'Station1.in',matchedEPG:true,programmes:[{
     start:Date.now()+60000,title:'Napoli vs Inter Milan',key_data:'never-publish-this',
    }],
   }]});
  return Response.json({channels:[]});
 };
 const run=()=>worker.fetch(new Request('https://api.example/tv-schedule?date=2026-11-08'),env,{}).then(r=>r.json());
 try{
  const first=await run();assert.equal(first.channels[0].matchedEPG,true);
  assert.equal(first.channels[0].programmes[0].title,'Napoli vs Inter Milan');
  assert(!JSON.stringify(first).includes('never-publish-this'));
  baselineHasStation=false;
  assert.equal((await run()).channels[0].matchedEPG,true,'new saved station must not wait for the upstream catalog snapshot');
  binding='AnotherStation.in';assert.equal((await run()).channels[0].matchedEPG,false);
  binding='Station1.in';old=true;assert.equal((await run()).channels[0].matchedEPG,false);
 }finally{globalThis.fetch=original;}
});

test('saved US2 NBC metadata is available even when the regional guide is cold',async()=>{
 const original=globalThis.fetch;
 let savedSource='US2',verifiedAt=new Date().toISOString();
 const row={id:'verified-nbc',name:'NBC',epg_id:'NBC.East.Stream.us2',epg_source:'US2'};
 globalThis.fetch=async target=>{
  const u=new URL(target);
  if(u.pathname==='/rest/v1/channels')return Response.json([{...row,epg_source:savedSource}]);
  if(u.pathname==='/api/schedule')return Response.json({channels:[{...row,matchedEPG:false,programmes:[]}]});
  if(u.hostname==='raw.githubusercontent.com')return Response.json({ok:true,updated_at:new Date().toISOString(),channels:[{
   ...row,verified_at:verifiedAt,matchedEPG:true,programmes:[{start:Date.now(),title:'Live: Premier League Soccer'}],
  }]});
  throw Error('Regional feed cold');
 };
 const run=()=>worker.fetch(new Request('https://api.example/tv-schedule?date=2026-11-08'),env,{}).then(r=>r.json());
 try{
  assert.equal((await run()).channels[0].matchedEPG,true);
  savedSource='UK1';assert.equal((await run()).channels[0].matchedEPG,false);
  savedSource='US2';verifiedAt=new Date(Date.now()-36*3600000).toISOString();
  assert.equal((await run()).channels[0].matchedEPG,false);
 }finally{globalThis.fetch=original;}
});
