import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const fixtureSource = fs.readFileSync(new URL('../supabase/functions/football-fixtures/index.ts', import.meta.url), 'utf8');
const fixtureHelpers = fixtureSource
  .slice(fixtureSource.indexOf('function sourceFixtureDedupKey'), fixtureSource.indexOf('function fixtureEnglishScore'))
  .replace(/: (?:any|unknown)/g, '');
const fixtures = vm.runInNewContext(`${fixtureHelpers}\n({ sourceFixtureDedupKey, canonicalTeamName })`, { URL, Date });
const kickoff = '2026-10-06T12:00:00Z';
const key = (home, away, extra = {}) => fixtures.sourceFixtureDedupKey({ kickoff_at: kickoff, home_name: home, away_name: away, ...extra });

assert.notEqual(key('海港', '蓉城'), key('申花', '国安'), 'Different untranslated clubs must remain separate.');
assert.notEqual(key('FC 海港', '蓉城'), key('FC 申花', '国安'), 'Latin club prefixes must not erase Han names.');
assert.notEqual(key('ရန်ကုန်', 'မန္တလေး'), key('ပဲခူး', 'မကွေး'), 'Burmese letters and marks must remain significant.');
assert.equal(key('乌兹别克斯坦', '越南'), key('Uzbekistan斯坦', 'Vietnam'), 'Known partial translations must still merge.');
assert.equal(key('South Korea FC', 'Kazakhstan斯坦'), key('韩国', '哈萨克斯坦'), 'Existing translated provider duplicates must still merge.');
assert.notEqual(key('Uzbekistan 青年队', 'Vietnam'), key('Uzbekistan', 'Vietnam'), 'Other Han qualifiers must survive.');
assert.equal(key('one', 'two', { home_logo: 'https://logos.test/1.png?v=1', away_logo: 'https://logos.test/2.png' }), key('three', 'four', { home_logo: 'https://logos.test/1.png?v=2', away_logo: 'https://logos.test/2.png' }), 'Provider logo identity must ignore query tokens.');
assert.notEqual(key('', '', { provider: 'soco', fixture_id: 1 }), key('', '', { provider: 'soco', fixture_id: 2 }), 'Missing names must use fixture identity.');

const maintenanceSource = fs.readFileSync(new URL('../supabase/functions/football-score-sync/index.ts', import.meta.url), 'utf8');
const healthFunction = maintenanceSource
  .slice(maintenanceSource.indexOf('async function syncStreamHealth'), maintenanceSource.indexOf('async function probeStreamLink'))
  .replace(/: (?:any|Date|boolean)/g, '');

class Query {
  constructor(rows) { this.rows = rows.slice(); this.orders = []; }
  select(columns) { assert.ok(columns.includes('matches!inner(id)'), 'Filter parent visibility in the health query.'); return this; }
  eq(field, value) {
    this.rows = this.rows.filter(row => field.startsWith('matches.') ? row.matches[field.slice(8)] === value : row[field] === value);
    return this;
  }
  or(expression) {
    const match = expression.match(/^last_checked_at\.is\.null,last_checked_at\.lte\.(.+)$/);
    assert.ok(match, 'Request never-checked or overdue rows in SQL.');
    this.rows = this.rows.filter(row => row.last_checked_at == null || Date.parse(row.last_checked_at) <= Date.parse(match[1]));
    return this;
  }
  order(field, options) { this.orders.push({ field, ...options }); return this; }
  limit(count) {
    this.rows.sort((a, b) => {
      for (const { field, ascending, nullsFirst } of this.orders) {
        const x = a[field], y = b[field];
        if (x === y) continue;
        if (x == null) return nullsFirst ? -1 : 1;
        if (y == null) return nullsFirst ? 1 : -1;
        const compared = x < y ? -1 : 1;
        return ascending ? compared : -compared;
      }
      return 0;
    });
    this.rows = this.rows.slice(0, count);
    return this;
  }
  then(resolve, reject) { return Promise.resolve({ data: this.rows, error: null }).then(resolve, reject); }
}

const now = new Date('2026-10-06T12:00:00Z');
const row = (id, checked = null, parent = {}) => ({
  id: String(id).padStart(4, '0'), is_active: true, last_checked_at: checked,
  matches: { id, is_active: true, is_featured: true, publish_state: 'published', ...parent },
});
let checked = [];
let probeTime = now;
const sync = vm.runInNewContext(`${healthFunction}\nsyncStreamHealth`, {
  Date,
  console,
  probeStreamLink: async (_client, link) => {
    checked.push(link.id);
    link.last_checked_at = probeTime.toISOString();
    return 'healthy';
  },
});
const client = rows => ({ from(table) { assert.equal(table, 'stream_links'); return new Query(rows); } });

const rows = [
  ...Array.from({ length: 60 }, (_, i) => row(i + 1, '2026-10-06T11:59:00Z')),
  ...Array.from({ length: 20 }, (_, i) => row(i + 61, '2026-10-06T11:40:00Z')),
  row(0, null, { is_active: false }), row(-1, null, { is_featured: false }), row(-2, null, { publish_state: 'draft' }),
];
const summary = await sync(client(rows), now, false);
assert.equal(summary.checked, 16);
assert.deepEqual(checked, Array.from({ length: 16 }, (_, i) => String(i + 61).padStart(4, '0')), 'Overdue links beyond the old first-60 window must be checked.');

checked = [];
const unchecked = Array.from({ length: 80 }, (_, i) => row(i + 1));
for (let run = 0; run < 5; run += 1) {
  probeTime = new Date(now.getTime() + run * 1000);
  await sync(client(unchecked), probeTime, false);
}
assert.equal(new Set(checked).size, 80, 'Oldest-first scheduling must eventually reach every eligible link.');

checked = [];
await sync(client([row(1, '2026-10-06T11:59:00Z')]), now, true);
assert.deepEqual(checked, ['0001'], 'An admin forced check must include recent rows.');

console.log('Backend regressions passed: Unicode fixture identity, translated duplicates, visibility, due filtering, fairness, and forced checks.');
