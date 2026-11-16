import { englishFootballName } from './football_names.mjs';
import { isFootballSourceRow } from './source_match_rows.mjs';

const HOME = 'https://www.arena-koora.online/';
const API = 'https://arenaaliive22.site/api/v1/matches';
const kinds = {m3u8:'hls',mpd:'dash',flv:'flv',mp4:'mp4'};
// Arena's published schedule uses Arabia Standard Time (UTC+03:00).
const arenaDay = now => new Date(now + 3*3600000).toISOString().slice(0,10);

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
  return /premier league|la liga|bundesliga|serie a|ligue [12]|champions league|europa league|(?:uefa |european )?nations league|conference league|eredivisie|primeira liga|championship|fa cup|efl cup|copa del rey|coppa italia|dfb[- ]pokal|coupe de france|international friendl(?:y|ies)|fifa world cup|world cup qualif(?:ier|ication)|africa cup(?: of nations)?|afcon|كأس (?:الأمم|أمم) (?:الإفريقية|الأفريقية|إفريقيا|أفريقيا)|دوري أبطال آسيا|دوري المؤتمر الأوروبي|الدوري (?:الإنجليزي|الإسباني|الإيطالي|الألماني|الفرنسي|الهولندي|البرتغالي|التركي|السعودي)|دوري أبطال أوروبا|الدوري الأوروبي|دوري الأمم الأوروبية|كأس (?:الاتحاد الإنجليزي|الرابطة الإنجليزية|ملك إسبانيا|إيطاليا|ألمانيا|فرنسا)|(?:مباريات?|لقاء) ودية|تصفيات كأس العالم/i.test(league) &&
    isFootballSourceRow({...row, sportId:1});
}
function servers(row) {
  return (Array.isArray(row?.servers) ? row.servers : []).filter(server =>
    server?.enabled !== false && server?.enabled !== 0 && server?.enabled !== '0' &&
    server?.id && publicUrl(server?.url));
}
// Provider English labels are preferred above. These Arabic football labels
// cover the current African/European schedule; unseen proper names use a
// readable Latin transliteration rather than silently staying in Arabic.
const arenaArabicNames = Object.freeze({
  'تصفيات كأس أمم أفريقيا':'Africa Cup of Nations Qualifiers',
  'تصفيات كأس أمم إفريقيا':'Africa Cup of Nations Qualifiers',
  'تصفيات كأس الأمم الأفريقية':'Africa Cup of Nations Qualifiers',
  'تصفيات كأس الأمم الإفريقية':'Africa Cup of Nations Qualifiers',
  'تصفيات كأس أفريقيا':'Africa Cup of Nations Qualifiers',
  'كأس الأمم الأفريقية - تصفيات':'Africa Cup of Nations Qualifiers',
  'موزمبيق':'Mozambique','إثيوبيا':'Ethiopia','اثيوبيا':'Ethiopia',
  'زامبيا':'Zambia','بوروندي':'Burundi','نيجيريا':'Nigeria',
  'الهلال':'Al Hilal','النصر':'Al Nassr',
  'تنزانيا':'Tanzania','مصر':'Egypt','المغرب':'Morocco',
  'المغرب العربي':'Morocco','الجزائر':'Algeria','تونس':'Tunisia',
  'السنغال':'Senegal','غانا':'Ghana','الكاميرون':'Cameroon',
  'ساحل العاج':'Ivory Coast','كوت ديفوار':'Ivory Coast',
  'الكونغو':'Congo','الكونغو الديمقراطية':'DR Congo',
  'جمهورية الكونغو الديمقراطية':'DR Congo','أنغولا':'Angola',
  'أنجولا':'Angola','جنوب السودان':'South Sudan',
  'السودان':'Sudan','أوغندا':'Uganda','اوغندا':'Uganda',
  'كينيا':'Kenya','رواندا':'Rwanda','بنين':'Benin',
  'توغو':'Togo','مالي':'Mali','غينيا':'Guinea',
  'غينيا بيساو':'Guinea-Bissau','غينيا الاستوائية':'Equatorial Guinea',
  'الغابون':'Gabon','الجابون':'Gabon','بوركينا فاسو':'Burkina Faso',
  'النيجر':'Niger','تشاد':'Chad','موريتانيا':'Mauritania',
  'ليبيا':'Libya','إريتريا':'Eritrea','اريتريا':'Eritrea',
  'الصومال':'Somalia','جيبوتي':'Djibouti','جزر القمر':'Comoros',
  'مدغشقر':'Madagascar','ملاوي':'Malawi','زيمبابوي':'Zimbabwe',
  'بوتسوانا':'Botswana','ناميبيا':'Namibia',
  'جنوب أفريقيا':'South Africa','جنوب إفريقيا':'South Africa',
  'ليسوتو':'Lesotho','إسواتيني':'Eswatini','سوازيلاند':'Eswatini',
  'الرأس الأخضر':'Cape Verde','كاب فيردي':'Cape Verde',
  'سيشل':'Seychelles','موريشيوس':'Mauritius',
  'ليبيريا':'Liberia','سيراليون':'Sierra Leone',
  'غامبيا':'Gambia','الغامبيا':'Gambia',
  'أفريقيا الوسطى':'Central African Republic',
  'جمهورية أفريقيا الوسطى':'Central African Republic',
  'ساو تومي وبرينسيب':'São Tomé and Príncipe',
});
const arabicLetters = Object.freeze({
  'ا':'a','أ':'a','إ':'i','آ':'aa','ب':'b','ت':'t','ث':'th',
  'ج':'j','ح':'h','خ':'kh','د':'d','ذ':'dh','ر':'r','ز':'z',
  'س':'s','ش':'sh','ص':'s','ض':'d','ط':'t','ظ':'z','ع':'a',
  'غ':'gh','ف':'f','ق':'q','ك':'k','ل':'l','م':'m','ن':'n',
  'ه':'h','ة':'a','و':'w','ؤ':'u','ي':'y','ى':'a','ئ':'i',
  'ء':'','پ':'p','ڤ':'v','چ':'ch','گ':'g'
});
function latinArenaFallback(raw) {
  const normalized=String(raw).normalize('NFKC')
    .replace(/[\u064b-\u065f\u0670\u06d6-\u06ed\u0640]/g,'').trim();
  return normalized.replace(/[\u0621-\u064a\u0671\u067e\u0686\u06a4\u06af]/g,
      letter=>arabicLetters[letter]??letter)
    .replace(/\s+/g,' ').trim()
    .replace(/\b[a-z]/g,letter=>letter.toUpperCase());
}

function name(value, kind = 'team') {
  const known = {
    // Exact Arabic identities from Arena's published Nations League schedule.
    'بلجيكا':'Belgium','إيطاليا':'Italy','فرنسا':'France','تركيا':'Türkiye',
    'كرواتيا':'Croatia','التشيك':'Czechia','إسبانيا':'Spain','إنجلترا':'England',
    'دوري الأمم الأوروبية':'UEFA Nations League',
    // Nations League / international names from the same Arena schedule.
    'ليختنشتاين':'Liechtenstein','ليتوانيا':'Lithuania',
    'هولندا':'Netherlands','ألمانيا':'Germany','صربيا':'Serbia',
    'اليونان':'Greece','مالطا':'Malta','جبل طارق':'Gibraltar',
    'البرتغال':'Portugal','الدنمارك':'Denmark','النرويج':'Norway',
    'السويد':'Sweden','رومانيا':'Romania','بولندا':'Poland',
    'سويسرا':'Switzerland','النمسا':'Austria','ويلز':'Wales',
    'اسكتلندا':'Scotland','إيرلندا':'Ireland','أيرلندا':'Ireland',
    'أيرلندا الشمالية':'Northern Ireland','ألبانيا':'Albania',
    'فنلندا':'Finland','سان مارينو':'San Marino','قبرص':'Cyprus',
    'الجبل الأسود':'Montenegro','مونتينيغرو':'Montenegro',
    'البوسنة والهرسك':'Bosnia and Herzegovina','جورجيا':'Georgia',
    'كازاخستان':'Kazakhstan','أرمينيا':'Armenia',
    'أذربيجان':'Azerbaijan','آيسلندا':'Iceland',
    'لوكسمبورغ':'Luxembourg','لاتفيا':'Latvia','إستونيا':'Estonia',
    'بلغاريا':'Bulgaria','أوكرانيا':'Ukraine','مولدوفا':'Moldova',
    'سلوفاكيا':'Slovakia','سلوفينيا':'Slovenia','المجر':'Hungary',
    'كوسوفو':'Kosovo','مقدونيا الشمالية':'North Macedonia',
    'التشيك':'Czechia','التشيكية':'Czechia',
    'إسرائيل':'Israel','روسيا':'Russia',
    // Common top-five European football club labels. Exact names only;
    // unknown provider identities are preserved rather than guessed.
    'ريال مدريد':'Real Madrid','ريال بيتيس':'Real Betis',
    'ريال سوسيداد':'Real Sociedad','إشبيلية':'Sevilla',
    'فالنسيا':'Valencia','فياريال':'Villarreal',
    'جيرونا':'Girona','خيتافي':'Getafe','أوساسونا':'Osasuna',
    'بايرن ميونخ':'Bayern Munich','بايرن ميونيخ':'Bayern Munich',
    'بوروسيا دورتموند':'Borussia Dortmund',
    'بوروسيا مونشنغلادباخ':'Borussia Monchengladbach',
    'باير ليفركوزن':'Bayer Leverkusen','لايبزيغ':'RB Leipzig',
    'شتوتغارت':'VfB Stuttgart','فرانكفورت':'Eintracht Frankfurt',
    'مانشستر سيتي':'Manchester City','مانشستر يونايتد':'Manchester United',
    'آرسنال':'Arsenal','نيوكاسل يونايتد':'Newcastle United',
    'وست هام يونايتد':'West Ham United','برينتفورد':'Brentford',
    'برايتون':'Brighton & Hove Albion','نوتنغهام فورست':'Nottingham Forest',
    'بورنموث':'Bournemouth','وولفرهامبتون':'Wolverhampton Wanderers',
    'باريس سان جيرمان':'Paris Saint-Germain',
    'مارسيليا':'Marseille','ليون':'Lyon','ليل':'Lille',
    'موناكو':'Monaco','رين':'Rennes','نيس':'Nice','لانس':'Lens',
    'روما':'AS Roma','أتالانتا':'Atalanta','فيورنتينا':'Fiorentina',
    'بولونيا':'Bologna','تورينو':'Torino','أودينيزي':'Udinese',
    // Competition labels for verified football fixture classes.
    'دوري المؤتمر الأوروبي':'UEFA Conference League',
    'الدوري الهولندي':'Eredivisie',
    'الدوري البرتغالي':'Portuguese Primeira Liga',
    'الدوري التركي':'Turkish Super Lig',
    'الدوري السعودي':'Saudi Pro League',
    'كأس الاتحاد الإنجليزي':'FA Cup',
    'كأس الرابطة الإنجليزية':'EFL Cup',
    'كأس ملك إسبانيا':'Copa del Rey',
    'كأس إيطاليا':'Coppa Italia',
    'كأس ألمانيا':'DFB-Pokal',
    'كأس فرنسا':'Coupe de France',
    'تصفيات كأس العالم':'FIFA World Cup Qualifiers',
    'دوري أبطال آسيا':'AFC Champions League',
    'مباراة ودية':'International Friendly',
    'مباريات ودية':'International Friendlies',
    'ليدز يونايتد':'Leeds United','توتنهام':'Tottenham Hotspur',
    'نابولي':'Napoli','لاتسيو':'Lazio','كريستال بالاس':'Crystal Palace','ليفربول':'Liverpool',
    'سندرلاند':'Sunderland','تشيلسي':'Chelsea','مان يونايتد':'Manchester United','أستون فيلا':'Aston Villa',
    'إنتر ميلان':'Inter Milan','كومو':'Como','أتلتيكو مدريد':'Atletico Madrid','برشلونة':'Barcelona',
    'أرسنال':'Arsenal','هال سيتي':'Hull City','إيفرتون':'Everton','فولهام':'Fulham',
    'ميلان':'AC Milan','فيرينتسفاروشي':'Ferencvaros','ألكمار':'AZ Alkmaar','يوفنتوس':'Juventus',
    'الدوري الإنجليزي':'Premier League','الدوري الإنجليزي الممتاز':'Premier League',
    'الدوري الإسباني':'La Liga','الدوري الإيطالي':'Serie A','الدوري الألماني':'Bundesliga',
    'الدوري الفرنسي':'Ligue 1','دوري أبطال أوروبا':'UEFA Champions League','الدوري الأوروبي':'UEFA Europa League',
    'كأس الأمم الأفريقية':'Africa Cup of Nations','كأس الأمم الإفريقية':'Africa Cup of Nations',
    'كأس أمم إفريقيا':'Africa Cup of Nations','كأس أمم أفريقيا':'Africa Cup of Nations'};
  const raw = String(value || '').trim();
  const normalized=raw.normalize('NFKC')
    .replace(/[\u064b-\u065f\u0670\u06d6-\u06ed\u0640]/g,'').trim();
  const supplied=known[raw] || known[normalized] || arenaArabicNames[normalized];
  if(supplied)return supplied;
  const english=englishFootballName(raw, kind);
  // Never invent a different opponent. For unrecognized Arabic identities,
  // transliterate the provider's own name and preserve its stable fixture ID.
  return /[\u0600-\u06ff]/.test(english) ? latinArenaFallback(english) : english;
}
async function catalog({date, fetcher, now}) {
  const day = /^\d{4}-\d{2}-\d{2}$/.test(String(date || '')) ? date : arenaDay(now);
  const target = new URL(API);target.search = new URLSearchParams({date:day,scope:'all'}).toString();
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
  // The Admin "All" view needs a small, bounded span of publisher days.
  // Respect explicit date requests and keep Arena's own UTC+03 calendar.
  const exact=/^\d{4}-\d{2}-\d{2}$/.test(String(date||''));
  const today=arenaDay(now);
  const dates=exact?[date]:[0,1,2].map(i=>
    new Date(Date.parse(today+'T00:00:00Z')+i*86400000).toISOString().slice(0,10));
  const fetched=await Promise.allSettled(dates.map(day=>catalog({date:day,fetcher,now})));
  const catalogues=fetched.filter(x=>x.status==='fulfilled').map(x=>x.value);
  if(!catalogues.length)throw fetched.find(x=>x.status==='rejected')?.reason ||
    Error('Arena Koora schedule unavailable');
  const seen=new Set();
  return catalogues.flatMap(({day,rows})=>rows.filter(row=>selectable(row,now)).map(row=>{
    const id=String(row.id || '');
    const page=HOME+'?'+new URLSearchParams({m:'1',arena_match:id,arena_date:day});
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
  }).filter(row=>{
    if(!row.source_id || !row.home_team || !row.away_team ||
       seen.has(row.source_id))return false;
    seen.add(row.source_id);return true;
  }));
}
export async function arenaStreams(body,{fetcher=fetch,now=Date.now()}={}) {
  const page=publicUrl(body?.page_url);
  const params=page?.searchParams;
  const keys=params?[...params.keys()]:[];
  const modern=params?.has('arena_match') ?? false;
  const permitted=modern?['m','arena_match','arena_date']:['match','date'];
  const matchId=params?.get(modern?'arena_match':'match') || '';
  const day=params?.get(modern?'arena_date':'date');
  if (!page || page.origin!==new URL(HOME).origin || page.pathname!=='/' ||
      keys.some(key=>!permitted.includes(key)) || new Set(keys).size!==keys.length ||
      (modern && params.get('m')!==null && params.get('m')!=='1') ||
      !/^\d{1,16}$/.test(matchId) ||
      (day != null && !/^\d{4}-\d{2}-\d{2}$/.test(day))) {
    throw new Error('Invalid Arena Koora match page.');
  }
  const {rows}=await catalog({date:day,fetcher,now});
  const row=rows.find(item=>String(item.id)===matchId);
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
