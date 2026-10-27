import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const folder = new URL("../admin_app/companion_extension/", import.meta.url);
const manifest = JSON.parse(fs.readFileSync(new URL("manifest.json", folder)));
const workerCode = fs.readFileSync(new URL("worker.js", folder), "utf8");
const bridgeCode = fs.readFileSync(new URL("bridge.js", folder), "utf8");
const adminUrl =
  "https://nyeinchanaung75299-eng.github.io/football-stream-app/admin/";
const requestId = "1793060006123456";

test("Admin Web companion watches only the user-opened source tab", async () => {
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.host_permissions, ["https://*/*"]);
  assert.deepEqual(manifest.content_scripts[0].matches, [adminUrl + "*"]);
  const listeners = {};
  const session = {};
  const sent = [];
  let nextId = 37;
  const chrome = {
    runtime: {onMessage: {addListener: fn => {listeners.command = fn;}}},
    tabs: {
      create: async opts => {
        assert.equal(opts.url, "about:blank", "register before navigating");
        return {id: ++nextId};
      },
      update: async (id, opts) => {
        assert.equal(id, 38);
        assert.equal(opts.url, "https://tflix.su/watch/fixture");
        // A media request can happen immediately on page navigation.
        listeners.media({tabId: id, url: "https://cdn.example.org/live.m3u8"});
      },
      sendMessage: async (tabId, message) => {sent.push({tabId, message});},
      onRemoved: {addListener: fn => {listeners.removed = fn;}},
    },
    storage: {session: {
      set: async rows => Object.assign(session, rows),
      get: async key => key === null ? {...session} : {[key]: session[key]},
      remove: async key => {delete session[key];},
    }},
    webRequest: {
      onBeforeRequest: {addListener: fn => {listeners.media = fn;}},
      onHeadersReceived: {addListener: fn => {listeners.response = fn;}},
    },
  };
  vm.runInNewContext(workerCode, {chrome, URL, Date, Set, Object, Number}, {
    filename: "worker.js",
  });
  const start = await new Promise(resolve => listeners.command({
    type: "START", requestId, url: "https://tflix.su/watch/fixture",
  }, {url: adminUrl, tab: {id: 9}}, resolve));
  assert.equal(start.error, undefined);
  // Let the async session read from the first navigation finish.
  await new Promise(resolve => setImmediate(resolve));
  listeners.media({tabId: 99, url: "https://cdn.example.org/wrong.m3u8"});
  listeners.media({tabId: 38, url: "https://cdn.example.org/live/second.mpd?x=1"});
  listeners.media({tabId: 38, url: "https://cdn.example.org/license"});
  listeners.media({tabId: 38, url: "http://cdn.example.org/insecure.m3u8"});
  listeners.response({tabId: 38, url: "https://cdn.example.org/tokenized/playlist?key=abc",
    responseHeaders: [{name: "Content-Type", value: "application/vnd.apple.mpegurl"}]});
  listeners.response({tabId: 38, url: "https://cdn.example.org/license",
    responseHeaders: [{name: "Content-Type", value: "application/octet-stream"}]});
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(sent.map(x => x.message.format), ["hls", "dash", "hls"]);
  assert.ok(sent.every(x => x.tabId === 9 && x.message.requestId === requestId));
  assert.ok(!JSON.stringify(sent).includes("license"));
  assert.ok(!JSON.stringify(session).includes("cdn.example.org"));
  const stopped = await new Promise(resolve => listeners.command({
    type: "STOP", requestId,
  }, {url: adminUrl, tab: {id: 9}}, resolve));
  assert.equal(stopped.error, undefined);
  assert.deepEqual(session, {});
});

test("untrusted page and unsupported source cannot start capture", async () => {
  const listeners = {};
  const chrome = {
    runtime: {onMessage: {addListener: fn => {listeners.command = fn;}}},
    tabs: {onRemoved: {addListener() {}}, create: async () => {
      throw Error("unexpected tab");
    }},
    storage: {session: {get: async () => ({})}},
    webRequest: {
      onBeforeRequest: {addListener() {}},
      onHeadersReceived: {addListener() {}},
    },
  };
  vm.runInNewContext(workerCode, {chrome, URL, Date, Set, Object, Number});
  assert.equal(listeners.command({
    type: "START", requestId, url: "https://tflix.su/watch/fixture",
  }, {url: "https://other.example.org/", tab: {id: 9}}, () => {}), undefined);
  const result = await new Promise(resolve => listeners.command({
    type: "START", requestId, url: "https://other.example.org/watch",
  }, {url: adminUrl, tab: {id: 9}}, resolve));
  assert.match(result.error, /Unsupported/);
});

test("content bridge passes only requested commands and observed URLs", () => {
  const posted = [];
  const handlers = {};
  const origin = "https://nyeinchanaung75299-eng.github.io";
  const window = {
    addEventListener: (name, fn) => {handlers[name] = fn;},
    postMessage: (data, target) => posted.push({data, target}),
  };
  const chrome = {
    runtime: {
      lastError: null,
      sendMessage: (command, callback) => callback({}),
      onMessage: {addListener: fn => {handlers.result = fn;}},
    },
  };
  vm.runInNewContext(bridgeCode, {window, chrome, JSON});
  const payload = "NCA_ADMIN_CAPTURE_V1:" + JSON.stringify({
    from: "admin", type: "PING", requestId,
  });
  handlers.message({source: window, origin: "https://evil.example.org", data: payload});
  assert.equal(posted.length, 0);
  handlers.message({source: window, origin, data: payload});
  assert.equal(posted.length, 1);
  assert.equal(posted[0].target, origin);
  assert.equal(JSON.parse(posted[0].data.split(":").slice(1).join(":")).type, "READY");
  handlers.result({type: "LINK", requestId,
    url: "https://cdn.example.org/master.m3u8", format: "hls"});
  assert.equal(posted.length, 2);
  assert.ok(posted[1].data.includes("master.m3u8"));
});
