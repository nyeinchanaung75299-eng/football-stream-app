import test from 'node:test';
import assert from 'node:assert/strict';
import {websiteMatches,websiteStreams} from '../supabase/functions/_shared/website_sources.mjs';

const media='https://cdn.example.org/live/football.m3u8';
const server={id:'server-1',url:media,enabled:true,type:'majed_player'};
const row={id:'12345',home_team:{name:'ليدز يونايتد'},away_team:{name:'توتنهام'},
  tournament:{name:'الدوري الإنجليزي'},state:'live',start_at:'2030-11-07T12:30:00Z',servers:[server]};
const page='https://www.arena-koora.online/?m=1&arena_match=12345&arena_date=2030-11-07';
test('Arena Koora Admin and Viewer share football-only published-server metadata',async()=>{
  const calls=[];
  const fetcher=async target=>{
    calls.push(target);const u=new URL(target);
    assert.equal(u.origin,'https://arenaaliive22.site');assert.equal(u.pathname,'/api/v1/matches');
    assert.equal(u.searchParams.get('scope'),'all');assert.equal(u.searchParams.has('lang'),false);
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


test('Arena 2026-11-15 published Arabic Nations League fixture JSON yields four English matches',async()=>{
  const now=Date.parse('2026-11-15T20:02:30Z');
  const teams=[
    ['5181798','بلجيكا','إيطاليا','Belgium','Italy'],
    ['5181799','فرنسا','تركيا','France','Türkiye'],
    ['5181859','كرواتيا','التشيك','Croatia','Czechia'],
    ['5181860','إسبانيا','إنجلترا','Spain','England'],
  ];
  const data={success:true,date:'2026-11-15',matches:teams.map(([id,home,away])=>({
    id,date:'2026-11-15',start_at:'2026-11-15T22:45:00+03:00',
    state:'live',hidden:false,tournament_hidden:false,
    home_team:{name:home,logo:'https://imgs.example.org/teams/'+id+'.png'},
    away_team:{name:away,logo:'https://imgs.example.org/teams/'+id+'-away.png'},
    tournament:{name:'دوري الأمم الأوروبية'},
    servers:[{id:'fixture-'+id,url:media,enabled:true,type:'majed_player'}],
  }))};
  const fetcher=async url=>{
    const u=new URL(url);
    assert.equal(u.hostname,'arenaaliive22.site');
    assert.equal(u.searchParams.get('date'),'2026-11-15');
    assert.equal(u.searchParams.get('scope'),'all');
    assert.equal(u.searchParams.has('lang'),false);
    return Response.json(data);
  };
  const matches=await websiteMatches('arena',{fetcher,date:'2026-11-15',now});
  assert.equal(matches.length,4);
  for(let i=0;i<matches.length;i++){
    const [id,_arabicHome,_arabicAway,englishHome,englishAway]=teams[i];
    assert.equal(matches[i].source_id,id);
    assert.equal(matches[i].home_team,englishHome);
    assert.equal(matches[i].away_team,englishAway);
    assert.equal(matches[i].league,'UEFA Nations League');
    assert.equal(matches[i].match_time,'2026-11-15T19:45:00.000Z');
    assert.equal(matches[i].page_url,
      'https://www.arena-koora.online/?m=1&arena_match='+id+'&arena_date=2026-11-15');
    assert.equal(matches[i].anchors.length,1);
  }
  // Use an injected clock, not a stale historical broadcast when CI runs.
  const {arenaStreams}=await import('../supabase/functions/_shared/arena_source.mjs');
  const result=await arenaStreams({
    page_url:matches[0].page_url,room_num:'fixture-5181798',
  },{fetcher,now});
  assert.equal(result.lines.length,1);
  assert.equal(result.lines[0].url,media);
  assert.equal(result.lines[0].health_status,'unknown');
});

test('Arena default Admin list spans three publisher UTC+03 days',async()=>{
  const now=Date.parse('2026-11-15T22:50:00Z');
  const dates=[];
  const fetcher=async url=>{dates.push(new URL(url).searchParams.get('date'));return Response.json({matches:[]});};
  const result=await websiteMatches('arena',{fetcher,now});
  assert.deepEqual(result,[]);
  assert.deepEqual(dates,['2026-11-16','2026-11-17','2026-11-18']);
});

test('Arena accepts the legacy generated match URL and rejects unsafe modern parameters',async()=>{
  const legacy='https://www.arena-koora.online/?match=12345&date=2030-11-07';
  const fetcher=async()=>Response.json({matches:[row]});
  const oldResult=await websiteStreams('arena',{page_url:legacy,room_num:'server-1'},{fetcher});
  assert.equal(oldResult.lines.length,1);
  for(const url of [
    'https://www.arena-koora.online/?m=2&arena_match=12345&arena_date=2030-11-07',
    'https://www.arena-koora.online/?m=1&arena_match=12345&arena_date=2030-11-07&url=http://localhost',
    'https://www.arena-koora.online/?m=1&arena_match=12345&arena_match=6789',
    'https://www.arena-koora.online/?m=1&arena_match=wrong',
  ]) {
    await assert.rejects(()=>websiteStreams('arena',{page_url:url},{fetcher}),/Invalid Arena/);
  }
});


test('Arena translates national teams from the current mobile Arabic schedule even before servers appear',async()=>{
  const cases=[
    ['ليختنشتاين','ليتوانيا','Liechtenstein','Lithuania'],
    ['هولندا','ألمانيا','Netherlands','Germany'],
    ['صربيا','اليونان','Serbia','Greece'],
    ['مالطا','جبل طارق','Malta','Gibraltar'],
  ];
  const now=Date.parse('2030-11-16T19:00:00Z');
  const fetcher=async()=>Response.json({matches:cases.map(([home,away],i)=>({
    id:String(i+200),home_team:{name:home},away_team:{name:away},
    tournament:{name:'دوري الأمم الأوروبية'},
    start_at:'2030-11-17T02:15:00+03:00',state:'scheduled',servers:[],
  }))});
  const matches=await websiteMatches('arena',{date:'2030-11-16',fetcher,now});
  assert.equal(matches.length,4);
  for(let i=0;i<cases.length;i++){
    assert.equal(matches[i].home_team,cases[i][2]);
    assert.equal(matches[i].away_team,cases[i][3]);
    assert.equal(matches[i].league,'UEFA Nations League');
    assert.deepEqual(matches[i].anchors,[]);
  }
});

test('Arena includes major European leagues, cups and other verified football categories',async()=>{
  const fixtures=[
    ['الدوري الإنجليزي','مانشستر سيتي','آرسنال','Premier League','Manchester City','Arsenal'],
    ['الدوري الإسباني','ريال مدريد','فياريال','La Liga','Real Madrid','Villarreal'],
    ['الدوري الألماني','بايرن ميونخ','بوروسيا دورتموند','Bundesliga','Bayern Munich','Borussia Dortmund'],
    ['الدوري الإيطالي','روما','أتالانتا','Serie A','AS Roma','Atalanta'],
    ['الدوري الفرنسي','باريس سان جيرمان','مارسيليا','Ligue 1','Paris Saint-Germain','Marseille'],
    ['دوري المؤتمر الأوروبي','باريس سان جيرمان','ليون','UEFA Conference League','Paris Saint-Germain','Lyon'],
    ['كأس ملك إسبانيا','ريال مدريد','برشلونة','Copa del Rey','Real Madrid','Barcelona'],
    ['دوري أبطال آسيا','الهلال','النصر','AFC Champions League','Al Hilal','Al Nassr'],
  ];
  const now=Date.parse('2030-11-16T19:00:00Z');
  const fetcher=async()=>Response.json({matches:[
    ...fixtures.map(([league,home,away],i)=>({
      id:String(400+i),home_team:{name:home},away_team:{name:away},
      tournament:{name:league},
      start_at:'2030-11-17T02:15:00+03:00',state:'scheduled',servers:[],
    })),
    {id:'500',sportId:2,tournament:{name:'La Liga'},home_team:{name:'ريال مدريد'},
      away_team:{name:'برشلونة'},start_at:'2030-11-17T02:15:00+03:00',servers:[]},
    {id:'501',tournament:{name:'NBA'},home_team:{name:'Team A'},
      away_team:{name:'Team B'},start_at:'2030-11-17T02:15:00+03:00',servers:[]},
  ]});
  const matches=await websiteMatches('arena',{date:'2030-11-16',fetcher,now});
  assert.equal(matches.length,fixtures.length);
  fixtures.forEach((item,i)=>{
    assert.equal(matches[i].league,item[3]);
    assert.equal(matches[i].home_team,item[4]);
    assert.equal(matches[i].away_team,item[5]);
  });
});

test('Arena includes Africa Cup football fixtures without mixing in NFL and NBA',async()=>{
  const now=Date.parse('2030-11-16T17:00:00Z');
  const fixture=league=>({
    id:'51',start_at:'2030-11-17T23:00:00+03:00',
    state:'scheduled',hidden:false,
    tournament:{name:league},
    home_team:{name:'Egypt'},away_team:{name:'Morocco'},servers:[]
  });
  for(const league of ['Africa Cup of Nations','AFCON','كأس الأمم الأفريقية','كأس أمم إفريقيا']){
    const matches=await websiteMatches('arena',{date:'2030-11-17',now,
      fetcher:async()=>Response.json({matches:[
        fixture(league),{...fixture(league),id:'52',sportId:2},
        {...fixture('NFL'),id:'53'}, {...fixture('NBA'),id:'54'},
      ]})});
    assert.equal(matches.length,1,league);
    assert.equal(matches[0].source_id,'51');
    assert.equal(matches[0].home_team,'Egypt');
    assert.equal(matches[0].away_team,'Morocco');
    if(/كأس/.test(league))assert.equal(matches[0].league,'Africa Cup of Nations');
  }
});

test('Arena multi-day catalogue keeps each match id once and uses its published date',async()=>{
  const now=Date.parse('2030-11-16T13:00:00Z');
  const fetcher=async url=>{
    const date=new URL(url).searchParams.get('date');
    const fixture={id:'520',start_at:'2030-11-17T20:00:00+03:00',
      state:'scheduled',tournament:{name:'Africa Cup of Nations'},
      home_team:{name:'Egypt'},away_team:{name:'Morocco'},servers:[]};
    return Response.json({matches:date==='2030-11-16'?[fixture]:
      date==='2030-11-17'?[fixture,{...fixture,id:'521'}]:[]});
  };
  const matches=await websiteMatches('arena',{now,fetcher});
  assert.deepEqual(matches.map(m=>m.source_id),['520','521']);
  assert.equal(matches[0].page_url,
    'https://www.arena-koora.online/?m=1&arena_match=520&arena_date=2030-11-16');
});


test('Arena translates AFCON qualifiers and unknown Arabic names without changing fixture identity',async()=>{
  const now=Date.parse('2030-11-16T17:00:00Z');
  const fixtures=[
    ['601','موزمبيق','إثيوبيا','Mozambique','Ethiopia'],
    ['602','زامبيا','بوروندي','Zambia','Burundi'],
    ['603','نيجيريا','تنزانيا','Nigeria','Tanzania'],
    ['604','فريق تجريبي','خصم جديد',null,null],
  ];
  const matches=await websiteMatches('arena',{date:'2030-11-17',now,
    fetcher:async()=>Response.json({matches:fixtures.map(([id,home,away])=>({
      id,tournament:{name:'تصفيات كأس أمم أفريقيا'},
      home_team:{name:home},away_team:{name:away},state:'scheduled',
      start_at:'2030-11-17T20:00:00+03:00',servers:[],
    }))})});
  assert.equal(matches.length,4);
  for(let i=0;i<4;i++){
    assert.equal(matches[i].source_id,fixtures[i][0]);
    assert.equal(matches[i].league,'Africa Cup of Nations Qualifiers');
    assert(!/[\u0600-\u06ff]/.test(matches[i].home_team+' '+matches[i].away_team));
    if(i<3){
      assert.equal(matches[i].home_team,fixtures[i][3]);
      assert.equal(matches[i].away_team,fixtures[i][4]);
    }
  }
});
