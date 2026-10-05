import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const htmlPath = fileURLToPath(new URL('../user_app/web/index.html', import.meta.url));
const html = readFileSync(htmlPath, 'utf8');
const playerScript = html.match(/<script>\s*(\(\(\) => \{[\s\S]*?\}\)\(\);)\s*<\/script>/)?.[1];
assert.ok(playerScript, 'The shared browser player must remain extractable from its HTML');

function deferred() {
  let resolve, reject;
  const promise = new Promise((ok, fail) => { resolve = ok; reject = fail; });
  return { promise, resolve, reject };
}

async function flush() {
  for (let i = 0; i < 20; i++) await Promise.resolve();
}

function createHarness({ ios = true, streaming = true, nativeHls = true, plans = {}, attachGate, engineLoads } = {}) {
  let clock = 0, nextTimer = 1;
  const timers = new Map(), elements = new Map();
  const events = [], loads = [], plays = [], players = [], logs = [], scripts = [];

  class Element {
    constructor(id = '') {
      this.id = id; this.children = []; this.style = {}; this.dataset = {};
      this.listeners = new Map(); this.classes = new Set(); this.attributes = {};
      this._text = ''; this._html = ''; this._src = '';
      this.classList = {
        add: (...names) => names.forEach(name => this.classes.add(name)),
        remove: (...names) => names.forEach(name => this.classes.delete(name)),
        contains: name => this.classes.has(name),
        toggle: name => {
          if (this.classes.has(name)) { this.classes.delete(name); return false; }
          this.classes.add(name); return true;
        },
      };
    }
    set className(value) { this.classes = new Set(value.split(/\s+/).filter(Boolean)); }
    get className() { return [...this.classes].join(' '); }
    set textContent(value) { this._text = String(value); this.children = []; }
    get textContent() { return this._text; }
    set innerHTML(value) { this._html = String(value); this.children = []; }
    get innerHTML() { return this._html; }
    set src(value) { this._src = value; this.playUrl = value; }
    get src() { return this._src; }
    appendChild(child) { this.children.push(child); return child; }
    setAttribute(name, value) { this.attributes[name] = value; }
    removeAttribute(name) { delete this.attributes[name]; if (name === 'src') this.src = ''; }
    addEventListener(type, fn, options = {}) {
      const rows = this.listeners.get(type) || [];
      rows.push({ fn, once: !!options.once }); this.listeners.set(type, rows);
    }
    removeEventListener(type, fn) {
      this.listeners.set(type, (this.listeners.get(type) || []).filter(row => row.fn !== fn));
    }
    emit(type, properties = {}) {
      const event = { type, target: this, stopPropagation() {}, ...properties };
      const rows = [...(this.listeners.get(type) || [])];
      for (const row of rows) {
        if (row.once) this.removeEventListener(type, row.fn);
        row.fn(event);
      }
      this[`on${type}`]?.(event);
    }
    click() { this.emit('click'); }
  }

  const ids = [...html.matchAll(/id="(football-[^"]+)"/g)].map(match => match[1]);
  for (const id of ids) elements.set(id, new Element(id));
  const video = elements.get('football-player-video');
  const overlay = elements.get('football-player-overlay');
  const message = elements.get('football-player-message');
  elements.get('football-player-menu').classList.add('hidden');
  video.paused = true;
  video.canPlayType = mime => nativeHls && mime === 'application/vnd.apple.mpegurl' ? 'probably' : '';
  video.pause = () => { video.paused = true; video.emit('pause'); };
  video.load = () => {};
  video.play = () => {
    const url = video.playUrl;
    plays.push(url);
    const plan = plans[url] || {};
    if (plan.playError) return Promise.reject(plan.playError);
    video.paused = false;
    if (!plan.noPlaying) video.emit('playing');
    return Promise.resolve();
  };

  class Player {
    static isBrowserSupported() { return streaming; }
    constructor() { this.listeners = new Map(); this.destroyed = false; players.push(this); }
    async attach(media) {
      this.video = media;
      if (attachGate && players.length === 1) await attachGate.promise;
    }
    configure(config) { this.config = config; }
    addEventListener(name, fn) { this.listeners.set(name, fn); }
    async load(url, start, mime) {
      this.url = url; loads.push({ url, start, mime });
      const plan = plans[url] || {};
      if (plan.loadError) {
        if (plan.emitError) this.listeners.get('error')?.({ detail: plan.loadError });
        throw plan.loadError;
      }
      if (plan.loadGate) await plan.loadGate.promise;
      this.video.playUrl = url;
    }
    getVariantTracks() { return []; }
    async destroy() { this.destroyed = true; }
  }
  const shaka = { Player, polyfill: { installAll() {} } };
  const document = new Element('document');
  document.getElementById = id => elements.get(id);
  document.createElement = () => new Element();
  document.head = new Element('head');
  document.fullscreenElement = null;
  const window = { crypto: { subtle: {} }, posthog: { capture(name, properties) { events.push({ name, properties }); } } };
  if (!engineLoads) window.shaka = shaka;
  if (streaming) window.ManagedMediaSource = class {};
  const context = vm.createContext({
    window, document, shaka,
    navigator: { userAgent: ios ? 'iPhone Safari' : 'Chrome Android', platform: ios ? 'iPhone' : 'Linux', maxTouchPoints: 1 },
    console: { error: (...args) => logs.push(args) },
    setTimeout(fn, delay = 0) { const id = nextTimer++; timers.set(id, { at: clock + delay, fn }); return id; },
    clearTimeout(id) { timers.delete(id); },
  });
  document.head.appendChild = script => {
    scripts.push(script);
    Promise.resolve().then(() => {
      if (engineLoads?.[scripts.length - 1] === 'fail') script.onerror();
      else { window.shaka = shaka; script.onload(); }
    });
    return script;
  };
  vm.runInContext(playerScript, context, { filename: htmlPath });

  return {
    video, overlay, message, elements, events, loads, plays, players, logs, scripts,
    async open(sources, index = 0, match = 'test-match') {
      await window.openFootballPlayer(JSON.stringify(sources), index, 'Test match', match);
      await flush();
    },
    async choose(index) {
      elements.get('football-player-server').click();
      elements.get('football-player-menu-items').children[index].click();
      await flush();
    },
    async close() { elements.get('football-player-close').click(); await flush(); },
    async tick(duration) {
      const end = clock + duration;
      while (true) {
        const next = [...timers].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        const [id, timer] = next;
        timers.delete(id); clock = timer.at; timer.fn(); await flush();
      }
      clock = end; await flush();
    },
  };
}

const source = (type, name = type) => ({
  streamType: type, label: name, url: `https://api.example.invalid/p/test-${name}`,
});
const tests = [];
function test(name, run) { tests.push({ name, run }); }
const failures = h => h.events.filter(event => event.name === 'playback line failed');

test('HLS aliases select native HLS on an extensionless protected URL', async () => {
  for (const type of ['hls', 'm3u8']) {
    const line = source(type), h = createHarness();
    await h.open([line]);
    assert.equal(h.video.src, line.url);
    assert.equal(h.players.length, 0);
    assert.equal(h.events.filter(event => event.name === 'playback started').length, 1);
  }
});

test('modern iOS preserves the chosen DASH line and supplies MPD MIME to Shaka', async () => {
  for (const type of ['dash', 'mpd']) {
    const line = source(type), backup = source('hls'), h = createHarness();
    await h.open([backup, line], 1);
    assert.equal(h.loads.length, 1);
    assert.equal(h.loads[0].url, line.url);
    assert.equal(h.loads[0].mime, 'application/dash+xml');
    assert.deepEqual(h.plays, [line.url]);
  }
});

test('non-native HLS uses the same engine with explicit HLS MIME', async () => {
  const line = source('m3u8'), h = createHarness({ nativeHls: false, ios: false });
  await h.open([line]);
  assert.equal(h.loads[0].mime, 'application/vnd.apple.mpegurl');
  assert.equal(h.loads[0].url, line.url);
});

test('older iOS reports unsupported DASH and falls back to supplied HLS', async () => {
  const dash = source('dash'), mp4 = source('mp4'), hls = source('hls');
  const h = createHarness({ streaming: false });
  await h.open([dash, mp4, hls]);
  assert.equal(h.loads.length, 0);
  assert.equal(failures(h)[0].properties.reason, 'unsupported_browser');
  await h.tick(1000);
  assert.deepEqual(h.plays, [hls.url]);
});

test('DASH DRM errors fall back once without leaking error messages or keys', async () => {
  const dash = source('dash'), hls = source('hls');
  const error = { category: 6, code: 6001, message: 'https://upstream.invalid/private?key=SECRET' };
  const h = createHarness({ plans: { [dash.url]: { loadError: error, emitError: true } } });
  await h.open([dash, hls]);
  assert.equal(failures(h).length, 1, 'Error event and rejected load must not schedule two fallbacks');
  assert.equal(failures(h)[0].properties.reason, 'drm_error');
  assert.equal(failures(h)[0].properties.error_code, 6001);
  await h.tick(1000);
  assert.deepEqual(h.plays, [hls.url]);
  assert.equal(h.events.filter(event => event.name === 'playback auto fallback').length, 1);
  assert.ok(!JSON.stringify(h.events).includes('SECRET'));
  assert.ok(!JSON.stringify(h.events).includes('upstream.invalid'));
  assert.equal(h.logs.length, 0);
});

test('startup stalls fall back to HLS and ignore a late old load completion', async () => {
  const dash = source('dash'), hls = source('hls'), gate = deferred();
  const h = createHarness({ plans: { [dash.url]: { loadGate: gate } } });
  const opening = h.open([dash, hls]);
  await flush();
  assert.equal(h.loads.length, 1);
  await h.tick(30000);
  assert.equal(failures(h)[0].properties.reason, 'startup_timeout');
  assert.deepEqual(h.plays, [hls.url]);
  gate.resolve(); await opening;
  assert.deepEqual(h.plays, [hls.url], 'Stale load must not play the old source');
});

test('started playback can recover from a later stall, while user pause does not fail a line', async () => {
  const primary = source('hls', 'primary'), backup = source('hls', 'backup');
  const h = createHarness();
  await h.open([primary, backup]);
  h.video.emit('waiting'); h.video.emit('stalled');
  await h.tick(17000);
  assert.equal(failures(h)[0].properties.reason, 'stall_timeout');
  assert.deepEqual(h.plays, [primary.url, backup.url]);
  const paused = createHarness();
  await paused.open([primary, backup]);
  paused.video.emit('waiting'); paused.video.pause();
  await paused.tick(30000);
  assert.equal(failures(paused).length, 0);
  assert.deepEqual(paused.plays, [primary.url]);
});

test('autoplay denial offers an explicit Play action and never marks the source broken', async () => {
  const primary = source('hls'), backup = source('hls', 'backup');
  const plan = { playError: { name: 'NotAllowedError', message: 'Browser requires a gesture' } };
  const h = createHarness({ plans: { [primary.url]: plan } });
  await h.open([primary, backup]);
  assert.match(h.message.textContent, /Tap Play/);
  assert.equal(h.message.children[0].textContent, 'Play');
  await h.tick(60000);
  assert.equal(failures(h).length, 0);
  assert.deepEqual(h.plays, [primary.url]);
  delete plan.playError;
  h.message.children[0].click(); await flush();
  assert.deepEqual(h.plays, [primary.url, primary.url]);
  assert.equal(h.events.filter(event => event.name === 'playback started').length, 1);
});

test('native format errors do fall back instead of being swallowed like autoplay denial', async () => {
  const primary = source('hls'), backup = source('hls', 'backup');
  const h = createHarness({ plans: { [primary.url]: { playError: { name: 'NotSupportedError' } } } });
  await h.open([primary, backup]); await h.tick(1000);
  assert.equal(failures(h).length, 1);
  assert.deepEqual(h.plays, [primary.url, backup.url]);
});

test('manual selection cancels an already scheduled automatic fallback', async () => {
  const bad = source('dash'), backup = source('hls', 'backup'), manual = source('hls', 'manual');
  const h = createHarness({ plans: { [bad.url]: { loadError: { code: 3016 } } } });
  await h.open([bad, backup, manual]);
  await h.choose(2); await h.tick(30000);
  assert.deepEqual(h.plays, [manual.url]);
});

test('new match cancels prior fallback and keeps telemetry attached to the new match', async () => {
  const bad = source('dash'), oldBackup = source('hls', 'old'), fresh = source('hls', 'new');
  const h = createHarness({ plans: { [bad.url]: { loadError: { code: 3016 } } } });
  await h.open([bad, oldBackup], 0, 'old-match');
  await h.open([fresh], 0, 'new-match'); await h.tick(30000);
  assert.deepEqual(h.plays, [fresh.url]);
  const started = h.events.filter(event => event.name === 'playback started');
  assert.equal(started.length, 1);
  assert.equal(started[0].properties.match_id, 'new-match');
});

test('closing cancels fallback and prevents a late pending load from playing or reopening', async () => {
  const dash = source('dash'), backup = source('hls'), gate = deferred();
  const h = createHarness({ plans: { [dash.url]: { loadGate: gate } } });
  const opening = h.open([dash, backup]); await flush();
  await h.close(); gate.resolve(); await opening; await h.tick(60000);
  assert.equal(h.overlay.classList.contains('open'), false);
  assert.deepEqual(h.plays, []);
  assert.equal(failures(h).length, 0);
  const bad = source('dash', 'bad');
  const queued = createHarness({ plans: { [bad.url]: { loadError: { code: 3016 } } } });
  await queued.open([bad, backup]); await queued.close(); await queued.tick(60000);
  assert.deepEqual(queued.plays, []);
  assert.equal(queued.overlay.classList.contains('open'), false);
});

test('a source change while attachment is pending never starts the stale DASH load', async () => {
  const dash = source('dash'), hls = source('hls'), gate = deferred();
  const h = createHarness({ attachGate: gate });
  const opening = h.open([dash, hls]); await flush();
  await h.choose(1);
  gate.resolve(); await opening; await h.tick(30000);
  assert.deepEqual(h.plays, [hls.url]);
  assert.equal(h.loads.length, 0, 'Stale attach continuation must not load DASH');
});

test('Android browsers still attempt the explicitly chosen DASH source', async () => {
  const hls = source('hls'), dash = source('dash'), h = createHarness({ ios: false });
  await h.open([hls, dash], 1);
  assert.equal(h.loads[0].url, dash.url);
  assert.deepEqual(h.plays, [dash.url]);
});

test('a failed engine download can be retried and DASH-only failures explain the HLS alternative', async () => {
  const dash = source('dash'), h = createHarness({ engineLoads: ['fail', 'success'] });
  await h.open([dash]);
  assert.match(h.message.textContent, /compatible HLS line/);
  assert.equal(h.scripts.length, 1);
  await h.choose(0);
  assert.equal(h.scripts.length, 2, 'Retry must download again after a failed engine request');
  assert.deepEqual(h.plays, [dash.url]);
});

test('untrusted metadata cannot become URL or credential telemetry', async () => {
  const line = source('https://upstream.invalid/?key=SECRET', 'opaque');
  line.resolution = 'https://upstream.invalid/?key=SECRET';
  line.healthStatus = 'SECRET';
  const h = createHarness();
  await h.open([line]);
  const started = h.events.find(event => event.name === 'playback started');
  assert.equal(started.properties.stream_type, 'auto');
  assert.equal(started.properties.resolution, 'unknown');
  assert.equal(started.properties.health_status, 'unknown');
  assert.ok(!JSON.stringify(h.events).includes('SECRET'));
  assert.ok(!JSON.stringify(h.events).includes('upstream.invalid'));
});

for (const { name, run } of tests) {
  await run();
  process.stdout.write(`PASS ${name}\n`);
}
process.stdout.write(`${tests.length} web player regression checks passed.\n`);
