import test from 'node:test';
import assert from 'node:assert/strict';
import {websiteMatches,websiteStreams} from '../supabase/functions/_shared/website_sources.mjs';

const media='https://cdn.example.org/live/football.m3u8';
const server={id:'server-1',url:media,enabled:true,type:'majed_player'};
const row={id:'12345',home_team:{name:'ليدز يونايتد'},away_team:{name:'توتنهام'},
  tournament:{name:'الدوري الإنجليزي'},state:'live',start_at:'2030-11-07T12:30:00Z',servers:[server]};
const page='https://www.arena-koora.online/?match=12345&date=2030-11-07';
test('Arena Koora Admin and Viewer share football-only published-server metadata',async()=>{
  const calls=[];
  const fetcher=async target=>{
    calls.push(target);const u=new URL(target);
    assert.equal(u.origin,'https://arenaaliive22.site');assert.equal(u.pathname,'/api/v1/matches');
    return Response.json({matches:[row,{...row,id:'2',servers:[]},
      {...row,id:'3',servers:[{...server,enabled:false}]},
      {...row,id:'4',sportId:2}, {...row,id:'5',hidden:true},
      {...row,id:'6',state:'finished'},
      {...row,id:'7',tournament:{name:'NBA'}},
      {...row,id:'8',servers:[{...server,url:'http://127.0.0.1/private'}]},
    ]});
  };
  const matches=await websiteMatches('arena',{fetcher,date:'2030-11-07'});
  assert.deepEqual(matches.map(m=>m.source_id),['12345','2','3','8']);
  assert(matches.slice(1).every(m=>m.anchors.length===0));
  assert.equal(matches[0].home_team,'Leeds United');
  assert.equal(matches[0].away_team,'Tottenham Hotspur');assert.equal(matches[0].page_url,page);
  assert.equal(matches[0].anchors[0].room_num,'server-1');
  const result=await websiteStreams('arena',{page_url:page,room_num:'server-1'},{fetcher});
  assert.equal(result.lines.length,1);assert.equal(result.lines[0].url,media);
  assert.equal(result.lines[0].referer,page);assert.equal(result.lines[0].stream_type,'hls');
  assert.equal(calls.length,2);
});
test('Arena does not turn disabled, unselected, or iframe servers into native video lines',async()=>{
  const fetcher=async()=>Response.json({matches:[{...row,servers:[server,
    {...server,id:'disabled',enabled:false},
    {...server,id:'website',url:'https://player.example.org/watch/12345'},
  ]}]});
  for(const id of ['disabled','website','unknown']) {
    const result=await websiteStreams('arena',{page_url:page,room_num:id},{fetcher});
    assert.deepEqual(result.lines,[]);
  }
});
test('Arena refuses caller-selected destinations, redirects, and invalid catalogs',async()=>{
  for(const value of ['https://evil.example.org/','http://127.0.0.1/',page+'&url=http://localhost/'])
    await assert.rejects(()=>websiteStreams('arena',{page_url:value},{fetcher:()=>{throw Error('must not fetch');}}),/Invalid Arena/);
  for(const status of [302,403,500])await assert.rejects(()=>websiteMatches('arena',{fetcher:async()=>new Response('',{status})}));
  await assert.rejects(()=>websiteMatches('arena',{fetcher:async()=>Response.json({scores:[]})}),/invalid match payload/);
});
