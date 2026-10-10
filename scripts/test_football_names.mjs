import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import { englishFootballName, firstFootballName } from '../supabase/functions/_shared/football_names.mjs';

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
      .replace('"../_shared/stream_probe.mjs"', JSON.stringify(new URL('../supabase/functions/_shared/stream_probe.mjs', import.meta.url).href));
    source += name === 'football-fixtures'
      ? '\nexport { loadSourceFallbackFixtures, sourceFixtureId };'
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

const colaRow = {
  sportId: 1, matchId: 'stable-match-id', matchStatus: 1,
  matchTime: '2030-10-10T14:00:00Z',
  homeTeamName: 'Chelsea', awayTeamName: 'Câu lạc bộ bóng đá Bournemouth',
  competitionName: 'Giải bóng đá Ngoại hạng Anh',
  homeTeamLogo: 'https://logos.example/chelsea.png',
  awayTeamLogo: 'https://logos.example/bournemouth.png',
  videoUrl: 'https://media.example/live.m3u8',
};

for (const adapter of adapters.filter(a => a.name !== 'football-fixtures')) {
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
