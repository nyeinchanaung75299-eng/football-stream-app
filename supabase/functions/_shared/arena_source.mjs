import { englishFootballName } from './football_names.mjs';
import { isFootballSourceRow } from './source_match_rows.mjs';

const HOME = 'https://www.arena-koora.online/';
const API = 'https://arenaaliive22.site/api/v1/matches';
const kinds = {m3u8:'hls',mpd:'dash',flv:'flv',mp4:'mp4'};

function publicUrl(value) {
  try {
    const u = new URL(value);
    return u.protocol === 'https:' && !u.username && !u.password && !u.port &&
      !/^[\d.]+$|:|(^|\.)(localhost|local|internal|test|invalid)$/.test(u.hostname) ? u : null;
  } catch { return null; }
}
function football(row) {
  if (isFootballSourceRow(row)) return true;
  if (row?.sportId != null || row?.sport_id != null || row?.sport != null ||
      row?.categoryId != null || row?.category_id != null) return false;
  const league = String(row?.tournament?.name_en || row?.tournament?.name || '');
  return /premier league|la liga|bundesliga|serie a|ligue [12]|champions league|europa league|الدوري (?:الإنجليزي|الإسباني|الإيطالي|الألماني|الفرنسي)|دوري أبطال أوروبا|الدوري الأوروبي/i.test(league) &&
    isFootballSourceRow({...row, sportId:1});
}
function servers(row) {
  return (Array.isArray(row?.servers) ? row.servers : []).filter(server =>
    server?.enabled !== false && server?.enabled !== 0 && server?.enabled !== '0' &&
    server?.id && publicUrl(server?.url));
}
function name(value, kind = 'team') {
  const known = {'ليدز يونايتد':'Leeds United','توتنهام':'Tottenham Hotspur',
    'نابولي':'Napoli','لاتسيو':'Lazio','كريستال بالاس':'Crystal Palace','ليفربول':'Liverpool',
    'سندرلاند':'Sunderland','تشيلسي':'Chelsea','مان يونايتد':'Manchester United','أستون فيلا':'Aston Villa',
    'إنتر ميلان':'Inter Milan','كومو':'Como','أتلتيكو مدريد':'Atletico Madrid','برشلونة':'Barcelona',
    'أرسنال':'Arsenal','هال سيتي':'Hull City','إيفرتون':'Everton','فولهام':'Fulham',
    'ميلان':'AC Milan','فيرينتسفاروشي':'Ferencvaros','ألكمار':'AZ Alkmaar','يوفنتوس':'Juventus',
    'الدوري الإنجليزي':'Premier League','الدوري الإنجليزي الممتاز':'Premier League',
    'الدوري الإسباني':'La Liga','الدوري الإيطالي':'Serie A','الدوري الألماني':'Bundesliga',
    'الدوري الفرنسي':'Ligue 1','دوري أبطال أوروبا':'UEFA Champions League','الدوري الأوروبي':'UEFA Europa League'};
  const raw = String(value || '').trim();
  return known[raw] || englishFootballName(raw, kind);
}
async function catalog({date, fetcher, now}) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(String(date || '')) ? date : new Date(now).toISOString().slice(0,10);
  const target = new URL(API);target.search = new URLSearchParams({date:day,scope:'all',lang:'en'}).toString();
  const controller = new AbortController();const timer = setTimeout(()=>controller.abort(),6500);
  try {
    const response = await fetcher(target.href,{redirect:'manual',signal:controller.signal,
      headers:{Accept:'application/json','User-Agent':'NCA-Source/1.0'}});
    if (!response.ok) {await response.body?.cancel().catch(()=>{});throw new Error('Arena Koora returned HTTP '+response.status+'.');}
    const reader = response.body?.getReader();if (!reader) throw new Error('Arena Koora returned an empty response.');
    const chunks=[];let size=0;
    try {while(true) {const {done,value}=await reader.read();if(done)break;
      size+=value.length;if(size>2*1024*1024)throw new Error('Arena Koora response exceeds size limit.');chunks.push(value);
    }} finally {await reader.cancel().catch(()=>{});}
    const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
    const payload=JSON.parse(new TextDecoder().decode(bytes));
    if (!Array.isArray(payload?.matches)) throw new Error('Arena Koora returned an invalid match payload.');
    return {day,rows:payload.matches};
  } finally {clearTimeout(timer);controller.abort();}
}
function selectable(row, now) {
  const kickoff=Date.parse(row?.start_at || '');
  return football(row) && !row?.hidden && !row?.tournament_hidden &&
    !['finished','ended','cancelled'].includes(String(row?.state || '').toLowerCase()) &&
    (!Number.isFinite(kickoff) || now-kickoff<=4*3600000);
}
export async function arenaMatches({date,fetcher=fetch,now=Date.now()}={}) {
  const {day,rows}=await catalog({date,fetcher,now});
  return rows.filter(row=>selectable(row,now)).map(row=>{
    const id=String(row.id || '');const page=HOME+'?'+new URLSearchParams({match:id,date:day});
    const live=['live','inprogress'].includes(String(row.state).toLowerCase());
    const time=Date.parse(row.start_at || '');
    return {source:'arena',source_id:id,schedule_id:id,sport_id:1,
      league:name(row.tournament?.name_en || row.tournament?.name,'league'),
      home_team:name(row.home_team?.name_en || row.home_team?.name),
      away_team:name(row.away_team?.name_en || row.away_team?.name),
      home_logo:row.home_team?.logo || null,away_logo:row.away_team?.logo || null,
      match_time:Number.isFinite(time)?new Date(time).toISOString():null,
      status:live?'LIVE':'SCHEDULED',hot:live,page_url:page,
      anchors:servers(row).map((server,index)=>({room_num:String(server.id),
        nick_name:'Arena Koora '+(index+1),page_url:page})),
    };
  }).filter(row=>row.source_id && row.home_team && row.away_team);
}
export async function arenaStreams(body,{fetcher=fetch,now=Date.now()}={}) {
  const page=publicUrl(body?.page_url);
  if (!page || page.origin!==new URL(HOME).origin || page.pathname!=='/' ||
      [...page.searchParams.keys()].some(key=>!['match','date'].includes(key)) ||
      !/^\d{1,16}$/.test(page.searchParams.get('match') || '')) throw new Error('Invalid Arena Koora match page.');
  const {rows}=await catalog({date:page.searchParams.get('date'),fetcher,now});
  const row=rows.find(item=>String(item.id)===page.searchParams.get('match'));
  if (!row || !selectable(row,now)) return {ok:true,source:'arena',lines:[],live_status:false};
  const requested=String(body.room_num || '');const found=new Map();
  for (const [index,server] of servers(row).entries()) {
    if (requested && requested!==String(row.id) && requested!==String(server.id)) continue;
    const media=publicUrl(server.url);const ext=media.pathname.match(/\.(m3u8|mpd|flv|mp4)$/i)?.[1]?.toLowerCase();
    if (!ext || found.has(media.href)) continue;
    found.set(media.href,{id:'arena:'+row.id+':'+server.id,label:'Arena Koora '+(index+1),
      url:media.href,stream_type:kinds[ext],referer:page.href,origin:page.origin,health_status:'unknown'});
  }
  return {ok:true,source:'arena',lines:[...found.values()],live_status:String(row.state).toLowerCase()==='live'};
}
