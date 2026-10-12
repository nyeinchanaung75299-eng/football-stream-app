import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import { englishFootballName, firstFootballName, sourceFootballNames, englishSourceDisplayName, englishStreamerName } from '../supabase/functions/_shared/football_names.mjs';

const originalDeno = globalThis.Deno;
const adapters = [];
try {
  for (const name of ['source-match-list', 'soco-links', 'football-fixtures']) {
    let handler;
    globalThis.Deno = { serve(fn) { handler = fn; } };
    let source = readFileSync(new URL(`../supabase/functions/${name}/index.ts`, import.meta.url), 'utf8')
      .replace(/^import .*jsr:.*;\n/gm, '')
      .replace('"../_shared/football_names.mjs"', JSON.stringify(new URL('../supabase/functions/_shared/football_names.mjs', import.meta.url).href))
      .replace('"../_shared/source_match_rows.mjs"', JSON.stringify(new URL('../supabase/functions/_shared/source_match_rows.mjs', import.meta.url).href))
    .replace('"../_shared/tflix_source.mjs"', JSON.stringify(new URL('../supabase/functions/_shared/tflix_source.mjs', import.meta.url).href))
      .replace('"../_shared/stream_probe.mjs"', JSON.stringify(new URL('../supabase/functions/_shared/stream_probe.mjs', import.meta.url).href));
    source += name === 'football-fixtures'
      ? '\nexport { loadSourceFallbackFixtures, sourceFixtureId };'
      : name === 'soco-links'
        ? '\nexport { colaMatchRow, jsonpMatches, roomStreams };'
        : '\nexport { colaMatchRow, jsonpMatches };';
    const api = await import('data:text/javascript;base64,' + Buffer.from(stripTypeScriptTypes(source)).toString('base64'));
    adapters.push({ name, handler, ...api });
  }
} finally { globalThis.Deno = originalDeno; }

test('the reported Big Match labels translate before and after old accent stripping', () => {
  for (const input of ['Giải bóng đá Ngoại hạng Anh', 'Giai bong da Ngoai hang Anh', '  giai BONG DA ngoai hang anh  ']) {
    assert.equal(englishFootballName(input, 'league'), 'English Premier League');
  }
  assert.equal(englishFootballName('Giai bong da vo dich quoc gia Duc', 'league'), 'Bundesliga');
  assert.equal(englishFootballName('Giai Bong da Vo dich Quoc gia Spain', 'league'), 'Spanish La Liga');
  assert.equal(englishFootballName('Giai bong da Serie A Italia', 'league'), 'Italian Serie A');
  for (const input of ['Câu lạc bộ bóng đá Bournemouth', 'Cau lac bo bong da Bournemouth']) {
    assert.equal(englishFootballName(input), 'Bournemouth');
  }
  assert.equal(englishFootballName('Cau lac bo Tottenham Hotspur'), 'Tottenham Hotspur');
});

test('national teams retain women, youth and reserve qualifiers across languages', () => {
  assert.equal(englishFootballName('Đội tuyển quốc gia Tây Ban Nha Nữ U19'), 'Spain Women U19');
  assert.equal(englishFootballName('Doi tuyen QG Bac Macedonia U21'), 'North Macedonia U21');
  assert.equal(englishFootballName('中国女U19'), 'China Women U19');
  assert.equal(englishFootballName('北爱尔兰'), 'Northern Ireland');
  assert.equal(englishFootballName('印度尼西亚'), 'Indonesia');
  assert.equal(englishFootballName('中北美国联', 'league'), 'CONCACAF Nations League');
  assert.equal(englishFootballName('切尔西女足'), 'Chelsea Women');
  assert.equal(englishFootballName('曼联后备队'), 'Manchester United Reserves');
});

test('existing proper names and distinct unknown names stay intact; normalization is idempotent', () => {
  for (const name of ['FC Köln', '1. FC Union Berlin', 'Chelsea', 'SV 07 Elversberg', '未知甲', '未知乙', 'CLB']) {
    assert.equal(englishFootballName(name), name);
  }
  assert.notEqual(englishFootballName('未知甲'), englishFootballName('未知乙'));
  for (const name of ['Câu lạc bộ Bournemouth', 'Đội tuyển quốc gia Ấn Độ U23', '中国女U19', 'Hà Nội Nữ', 'Tongliangloong Trùng Khánh']) {
    const normalized = englishFootballName(name);
    assert.equal(englishFootballName(normalized), normalized);
  }
  assert.equal(firstFootballName({ name_en: ' ', name: '' }, '', 'Chelsea'), 'Chelsea');
});

test('reported YYZB clubs and current major European fixtures use their established English names', () => {
  const names = {
    '帕德博恩': 'SC Paderborn 07', '斯图加特': 'VfB Stuttgart',
    '柏林联合': '1. FC Union Berlin', '埃弗斯堡': 'SV 07 Elversberg',
    '奥格斯堡': 'FC Augsburg', '霍芬海姆': 'TSG Hoffenheim',
    '美因茨': 'Mainz 05', '勒沃库森': 'Bayer Leverkusen',
    '巴列卡诺': 'Rayo Vallecano', '毕尔巴鄂竞技': 'Athletic Bilbao',
    '阿拉维斯': 'Deportivo Alaves', '里尔': 'Lille', '勒阿弗尔': 'Le Havre',
    '国际米兰': 'Inter Milan', '帕尔马': 'Parma',
  };
  for (const [original, expected] of Object.entries(names)) assert.equal(englishFootballName(original), expected);
  assert.equal(englishFootballName('帕德博恩U19'), 'SC Paderborn 07 U19');
  assert.equal(englishFootballName('柏林联合U19'), '1. FC Union Berlin U19');
  assert.equal(englishFootballName('英甲', 'league'), 'English League One');
  assert.equal(englishFootballName('欧冠杯', 'league'), 'UEFA Champions League');
});

test('strict source display prefers actual provider English, skips bad fields, and retains unknown identity metadata', () => {
  const row = { scheduleId: 1448174, subCateId: 8, hostName: '帕德博恩', guestName: '斯图加特', subCateName: '德甲',
    hostNameEn: 'Paderborn SC', awayTeam: { name_en: 'Stuttgart FC' } };
  const result = sourceFootballNames(row, true);
  assert.equal(result.home_team, 'Paderborn SC');
  assert.equal(result.away_team, 'Stuttgart FC');
  assert.equal(result.original_home_team, '帕德博恩');
  assert.equal(result.home_team_en, undefined, 'canonical English names must not duplicate large catalog fields');
  const skipped = sourceFootballNames({ ...row, hostNameEn: '未知英文标签', hostName: '切尔西' }, true);
  assert.equal(skipped.home_team, 'Chelsea');
  const unknown = sourceFootballNames({ scheduleId: 'stable-1', subCateId: 999, hostName: '未知甲', guestName: '未知乙', subCateName: '未知联赛' }, true);
  assert.equal(unknown.home_team, 'Home team (stable-1)');
  assert.equal(unknown.away_team, 'Away team (stable-1)');
  assert.equal(unknown.league, 'Football league (999)');
  assert.equal(unknown.original_away_team, '未知乙');
  const another = sourceFootballNames({ scheduleId: 'stable-2', hostName: '未知甲', guestName: '未知乙' }, true);
  assert.notEqual(unknown.home_team, another.home_team);
  assert.notEqual(sourceFootballNames({ hostName: '未知甲' }, true).home_team, sourceFootballNames({ hostName: '未知乙' }, true).home_team);
  for (const name of ['ရန်ကုန်', 'Αθήνα', 'תל אביב']) assert.equal(englishSourceDisplayName(name, 'team', 'Home team (source)'), 'Home team (source)');
  assert.equal(englishFootballName('未知甲'), '未知甲', 'the general identity normalizer must retain unknown Unicode');
});

test('YYZB streamer names remain English while raw import identity and explicit audio-language tags survive', () => {
  const raw = { uid: 578718, nickName: '达达（粤语）', anchor: { roomNum: '578718' } };
  const result = englishStreamerName(raw, 4);
  assert.equal(result.nick_name, 'Streamer 5 (Cantonese)');
  assert.equal(result.commentary_language, 'Cantonese');
  assert.equal(result.original_nick_name, raw.nickName);
  assert.equal(result.import_name, raw.nickName);
  assert.equal(englishStreamerName({ nickName: '老白聊球', nickNameEn: 'Alex' }, 0).nick_name, 'Alex');
  assert.equal(englishStreamerName({ nickName: '斯姐開啵(粤語)' }, 1).nick_name, 'Streamer 2 (Cantonese)');
  assert.equal(englishStreamerName({ nickName: '主播（普通话）' }, 2).nick_name, 'Streamer 3 (Mandarin)');
  assert.equal(englishStreamerName({ nickName: '必胜客' }, 0).commentary_language, null, 'do not guess a spoken language from Chinese spelling');
  assert.deepEqual(raw, { uid: 578718, nickName: '达达（粤语）', anchor: { roomNum: '578718' } });
});

const colaRow = {
  sportId: 1, matchId: 'stable-match-id', matchStatus: 1,
  matchTime: '2030-10-10T14:00:00Z',
  homeTeamName: 'Chelsea', awayTeamName: 'Câu lạc bộ bóng đá Bournemouth',
  competitionName: 'Giải bóng đá Ngoại hạng Anh',
  homeTeamLogo: 'https://logos.example/chelsea.png',
  awayTeamLogo: 'https://logos.example/bournemouth.png',
  videoUrl: 'https://media.example/live.m3u8',
};

test('authenticated room nicknames use the same decoded import identity as catalogs', async () => {
  const adapter = adapters.find(a => a.name === 'soco-links');
  const originalFetch = globalThis.fetch;
  try {
    for (const [raw, expected] of [[' <b>达达</b> &amp;   Alex（粤语） ', '达达 & Alex（粤语）'], [null, null]]) {
      globalThis.fetch = async () => Response.json({ data: { room: { anchor: { nickName: raw } } } });
      const payload = await (await adapter.roomStreams({
        source: 'yyzb', roomBase: 'https://source.example', roomNum: 'stable-room',
        scheduleId: 'source-123', refererOrigin: 'https://source.example', statusOnly: true,
      })).json();
      assert.equal(payload.anchor_name, expected);
      assert.equal(payload.room_num, 'stable-room');
    }
  } finally { globalThis.fetch = originalFetch; }
});

for (const adapter of adapters.filter(a => a.name !== 'football-fixtures')) {
  test(adapter.name + ': YYZB display preserves IDs, legacy Admin imports, and Viewer masking', async () => {
    const originalFetch = globalThis.fetch;
    const row = { scheduleId: 1448174, categoryId: 1, subCateId: 8, subCateName: '德甲',
      hostName: '帕德博恩', guestName: '斯图加特', matchTime: '2030-10-10T14:00:00Z',
      anchors: [{ uid: 578718, nickName: '达达（粤语）', anchor: { roomNum: '578718' } }] };
    globalThis.fetch = async () => Response.json({ data: [row] });
    try {
      const admin = await (await adapter.jsonpMatches({ source: 'yyzb', url: 'https://source.example/matches' })).json();
      const result = admin.matches[0];
      assert.equal(result.home_team, 'SC Paderborn 07');
      assert.equal(result.original_home_team, '帕德博恩');
      assert.equal(result.home_team_en, undefined);
      assert.equal(result.match_time, row.matchTime.replace('Z', '.000Z'));
      assert.equal(result.anchors[0].nick_name, row.anchors[0].nickName, 'legacy nickname import identity stays intact');
      assert.equal(result.anchors[0].nick_name_en, 'Streamer 1 (Cantonese)');
      assert.equal(result.anchors[0].room_num, '578718');
      assert.equal(result.anchors[0].uid, 578718);
      if (adapter.name === 'soco-links') {
        const viewer = await (await adapter.jsonpMatches({ source: 'yyzb', url: 'https://source.example/matches', viewerPublic: true })).json();
        const anchor = viewer.matches[0].anchors[0];
        assert.equal(anchor.nick_name, 'YYZB Server 1 (Cantonese)');
        assert.equal(anchor.nick_name_en, undefined);
        assert.equal(anchor.original_nick_name, undefined);
        assert.equal(anchor.import_name, undefined);
        assert.equal(/\p{Script=Han}/u.test(JSON.stringify(anchor)), false);
      }
      const soco = await (await adapter.jsonpMatches({ source: 'soco', url: 'https://source.example/matches' })).json();
      assert.equal(soco.matches[0].anchors[0].nick_name, row.anchors[0].nickName);
      assert.equal(soco.matches[0].anchors[0].nick_name_en, undefined);
    } finally { globalThis.fetch = originalFetch; }
  });

  test(adapter.name + ': representative 4030-match catalogs fit the existing 2MiB relay limit', async () => {
    const originalFetch = globalThis.fetch;
    const rows = Array.from({ length: 4030 }, (_, index) => ({
      scheduleId: 1440000 + index, categoryId: 1, subCateId: 8, subCateName: '德甲',
      hostName: '未知甲', guestName: '未知乙', matchTime: '2030-10-10T14:00:00Z', status: 1, matchStatus: 0,
      hostIcon: 'https://sta.ncctrials.com/file/imgs/team/football/164871161365.png',
      guestIcon: 'https://sta.ncctrials.com/file/imgs/team/football/164871149852.png',
      anchors: index % 20 === 0 ? [{ uid: 578718, nickName: '达达（粤语）',
        icon: 'https://sta.ncctrials.com/file/head/20260903/example.jpg', anchor: { roomNum: '578718' } }] : [],
    }));
    globalThis.fetch = async () => Response.json({ data: rows });
    try {
      for (const viewerPublic of adapter.name === 'soco-links' ? [false, true] : [false]) {
        const response = await adapter.jsonpMatches({ source: 'yyzb', url: 'https://source.example/matches', viewerPublic });
        const text = await response.text();
        const result = JSON.parse(text);
        assert.equal(result.matches.length, rows.length, 'never discard fixtures to meet a body cap');
        assert.ok(Buffer.byteLength(text) < 2 * 1024 * 1024, 'compact names must fit the current body budget');
        assert.equal(result.matches[0].schedule_id, rows[0].scheduleId);
        assert.equal(result.matches.at(-1).schedule_id, rows.at(-1).scheduleId);
      }
    } finally { globalThis.fetch = originalFetch; }
  });
  test(`${adapter.name}: a Cola row without English nodes produces English names and keeps identity/media metadata`, () => {
    const before = structuredClone(colaRow);
    const result = adapter.colaMatchRow('chelsea-bournemouth', colaRow);
    assert.equal(result.league, 'English Premier League');
    assert.equal(result.home_team, 'Chelsea');
    assert.equal(result.away_team, 'Bournemouth');
    assert.equal(result.source_id, colaRow.matchId);
    assert.equal(result.schedule_id, colaRow.matchId);
    assert.equal(result.home_logo, colaRow.homeTeamLogo);
    assert.equal(result.away_logo, colaRow.awayTeamLogo);
    assert.equal(result.match_time, '2030-10-10T14:00:00.000Z');
    assert.equal(result.anchors[0].room_num, colaRow.matchId);
    assert.ok(result.page_url.endsWith('/chelsea-bournemouth'));
    assert.deepEqual(colaRow, before);
  });

  test(`${adapter.name}: explicit English fields beat localized names; empty node names fall back`, () => {
    const result = adapter.colaMatchRow('game', { ...colaRow,
      homeTeamNameEn: 'Chelsea',
      node_api_data: {
        home_team: { name: '切尔西' },
        away_team: { name_en: 'Bournemouth', name: '伯恩茅斯' },
        competition: { name_en: '', name: '' },
      },
    });
    assert.equal(result.home_team, 'Chelsea');
    assert.equal(result.away_team, 'Bournemouth');
    assert.equal(result.league, 'English Premier League');
  });

  test(`${adapter.name}: Soco/YYZB rows use English fields and translate common Chinese display labels`, async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => Response.json({ data: [{
      scheduleId: 'source-123', categoryId: 1, categoryName: '足球',
      subCateName: '英超', hostName: '切尔西', guestName: '伯恩茅斯',
      hostNameEn: 'Chelsea FC', matchTime: '2030-10-10T14:00:00Z',
    }] });
    try {
      const payload = await (await adapter.jsonpMatches({ source: 'yyzb', url: 'https://source.example/matches' })).json();
      const match = payload.matches[0];
      assert.equal(match.league, 'English Premier League');
      assert.equal(match.home_team, 'Chelsea FC');
      assert.equal(match.away_team, 'Bournemouth');
      assert.equal(match.source_id, 'source-123');
    } finally { globalThis.fetch = originalFetch; }
  });

  test(`${adapter.name}: grouped featured schedules survive deduplication in either traversal order`, async () => {
    const originalFetch = globalThis.fetch;
    const row = {
      scheduleId: 123, categoryId: 1, subCateName: '英超',
      hostName: '切尔西', guestName: '伯恩茅斯',
      matchTime: 1917863400000, status: 1, matchStatus: 0,
      hot: false, anchors: [{ uid: 456, nickName: 'Original nickname', anchor: { roomNum: 'stable-room' } }],
    };
    // Numeric object keys always precede named keys: this is the live YYZB
    // shape that used to discard the duplicate from `data.hot`.
    const fixtures = [
      { 0: [row], hot: [{ ...row, hot: undefined }] },
      { hot: [{ ...row, hot: undefined }], list: [row] },
    ];
    try {
      for (const data of fixtures) {
        const before = structuredClone(data);
        globalThis.fetch = async () => Response.json({ data });
        const payload = await (await adapter.jsonpMatches({ source: 'yyzb', url: 'https://source.example/matches' })).json();
        assert.equal(payload.matches.length, 1);
        const match = payload.matches[0];
        assert.equal(match.hot, true);
        assert.equal(match.source_id, '123');
        assert.equal(match.schedule_id, 123);
        assert.equal(match.match_time, new Date(row.matchTime).toISOString());
        assert.equal(match.home_team, 'Chelsea');
        assert.equal(match.league, 'English Premier League');
        assert.equal(match.anchors[0].room_num, 'stable-room');
        assert.equal(match.anchors[0].nick_name, 'Original nickname');
        if (adapter.name === 'soco-links') {
          assert.equal(match.status, 1, 'featured is independent of schedule status');
          assert.equal(match.match_status, 0, 'featured must not make an upcoming match live');
        }
        assert.deepEqual(data, before, 'provider data must not be mutated');
      }
    } finally { globalThis.fetch = originalFetch; }
  });

  test(`${adapter.name}: explicit featured flags merge, while ordinary and non-football schedules stay distinct`, async () => {
    const originalFetch = globalThis.fetch;
    const base = { categoryId: 1, hostName: 'Chelsea', guestName: 'Bournemouth', matchTime: '2030-10-10T14:00:00Z' };
    globalThis.fetch = async () => Response.json({ data: {
      list: [
        { ...base, scheduleId: 'explicit', hot: false },
        { ...base, scheduleId: 'ordinary', hot: 0 },
        { ...base, scheduleId: 'flagged', hot: true },
        { ...base, scheduleId: 'alternate', isHot: 1 },
        { ...base, scheduleId: 'missing', hot: 2 },
        { ...base, scheduleId: 'explicit', hot: true },
      ],
      hot: [{ ...base, scheduleId: 'basketball', categoryId: 2, categoryName: '篮球' }],
    } });
    try {
      const payload = await (await adapter.jsonpMatches({ source: 'soco', url: 'https://source.example/matches' })).json();
      assert.equal(payload.matches.length, 5);
      const flags = Object.fromEntries(payload.matches.map(match => [match.source_id, match.hot]));
      assert.deepEqual(flags, { explicit: true, ordinary: false, flagged: true, alternate: true, missing: false });
    } finally { globalThis.fetch = originalFetch; }
  });
}

test('football-fixtures normalizes fallback names without changing source fixture IDs', async () => {
  const adapter = adapters.find(a => a.name === 'football-fixtures');
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_, options) => {
    assert.equal(options.headers.Authorization, 'Bearer admin-session');
    const source = JSON.parse(options.body).source;
    return Response.json({ matches: [{ source_id: source + '-123',
      league: 'Giai bong da Ngoai hang Anh', home_team: 'Chelsea',
      away_team: 'Cau lac bo bong da Bournemouth', match_time: '2030-10-10T14:00:00Z',
      home_logo: 'https://logos.example/chelsea.png', away_logo: 'https://logos.example/bournemouth.png',
    }] });
  };
  try {
    const result = await adapter.loadSourceFallbackFixtures({
      supabaseUrl: 'https://backend.example', anonKey: 'public-key', authHeader: 'Bearer admin-session',
      mode: 'date', date: '2030-10-10', deletedFixtureIds: new Set(),
    });
    assert.equal(result.fixtures.length, 1, 'equivalent source fixtures deduplicate');
    const match = result.fixtures[0];
    assert.equal(match.league_name, 'English Premier League');
    assert.equal(match.away_name, 'Bournemouth');
    assert.equal(match.fixture_id, adapter.sourceFixtureId(match.provider, match.provider_fixture_id));
    assert.equal(match.away_logo, 'https://logos.example/bournemouth.png');
  } finally { globalThis.fetch = originalFetch; }
});

test('Big Match list still requires an Admin session after the naming change', async () => {
  const adapter = adapters.find(a => a.name === 'source-match-list');
  const result = await adapter.handler(new Request('https://backend.example/source-match-list', {
    method: 'POST', body: JSON.stringify({ source: 'cola' }),
  }));
  assert.equal(result.status, 401);
});

test('fallback deduplication retains original identities and distinguishes mixed Unicode team names', async () => {
  const adapter = adapters.find(a => a.name === 'football-fixtures');
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_, options) => {
    const source = JSON.parse(options.body).source;
    return Response.json({ matches: [
      { source_id: source + '-first', league: 'Football', match_time: '2030-10-10T14:00:00Z',
        home_team: source === 'yyzb' ? 'Home team (first)' : 'A未知甲',
        away_team: source === 'yyzb' ? 'Away team (first)' : 'B未知乙',
        ...(source === 'yyzb' ? { original_home_team: 'A未知甲', original_away_team: 'B未知乙' } : {}) },
      { source_id: source + '-second', league: 'Football', match_time: '2030-10-10T14:00:00Z',
        home_team: source === 'yyzb' ? 'Home team (second)' : 'A未知丙',
        away_team: source === 'yyzb' ? 'Away team (second)' : 'B未知丁',
        ...(source === 'yyzb' ? { original_home_team: 'A未知丙', original_away_team: 'B未知丁' } : {}) },
    ] });
  };
  try {
    const result = await adapter.loadSourceFallbackFixtures({
      supabaseUrl: 'https://backend.example', anonKey: 'public-key', authHeader: 'Bearer admin-session',
      mode: 'date', date: '2030-10-10', deletedFixtureIds: new Set(),
    });
    assert.equal(result.fixtures.length, 2, 'merge equivalent sources without merging different unknown teams');
    assert.equal(new Set(result.fixtures.map(row => row.fixture_id)).size, 2);
  } finally { globalThis.fetch = originalFetch; }
});
