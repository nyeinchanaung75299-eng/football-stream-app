// Manifest V3, local tab-scoped observer. No fetches to source/CDN URLs and no
// network uploads. The permission prompt is broad because a source tab's
// playlist may be requested from an otherwise unknown HTTPS CDN origin.
const adminPrefix =
  "https://nyeinchanaung75299-eng.github.io/football-stream-app/admin/";
const sessionKey = (tabId) => "capture:" + tabId;
const sourceHosts = new Set([
  "tflix.su", "www.tflix.su", "tflix1.su", "www.tflix1.su",
  "streamcenter.st", "streame.center", "streamec.st",
]);

function supportedPage(raw) {
  try {
    const url = new URL(raw);
    return url.protocol === "https:" &&
      !url.username && !url.password &&
      sourceHosts.has(url.hostname) &&
      !url.hash && raw.length < 2048;
  } catch { return false; }
}

function mediaLink(raw) {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password ||
        raw.length > 4096) return null;
    if (/\.m3u8$/i.test(url.pathname)) return {url: url.href, format: "hls"};
    if (/\.mpd$/i.test(url.pathname)) return {url: url.href, format: "dash"};
  } catch {}
  return null;
}

function mediaContentType(details) {
  try {
    const type = details.responseHeaders?.find(header =>
      header.name?.toLowerCase() === "content-type")?.value?.toLowerCase() || "";
    const format = /(?:application|audio)\/(?:vnd\.apple\.mpegurl|x-mpegurl)/.test(type)
      ? "hls"
      : /application\/dash\+xml/.test(type) ? "dash" : null;
    if (!format) return null;
    const url = new URL(details.url);
    if (url.protocol !== "https:" || url.username || url.password ||
        details.url.length > 4096) return null;
    return {url: url.href, format};
  } catch { return null; }
}

chrome.runtime.onMessage.addListener((command, sender, respond) => {
  if (!sender.url?.startsWith(adminPrefix) ||
      !Number.isInteger(sender.tab?.id) ||
      !/^[0-9]{8,25}$/.test(command?.requestId || "")) return;
  const adminTabId = sender.tab.id;
  if (command.type === "STOP") {
    chrome.storage.session.get(sessionKey(adminTabId))
      .then((data) => {
        const session = data[sessionKey(adminTabId)];
        if (session?.requestId !== command.requestId) return {error: "Capture already stopped."};
        return chrome.storage.session.remove(sessionKey(adminTabId)).then(() => ({}));
      }).then(respond).catch(() => respond({error: "Could not stop capture."}));
    return true;
  }
  if (command.type !== "START") return;
  if (!supportedPage(command.url)) {
    respond({error: "Unsupported original match page."});
    return;
  }
  // Register the tab before navigation so early manifest requests are not lost.
  chrome.tabs.create({url: "about:blank", active: true}).then(async (sourceTab) => {
    if (!Number.isInteger(sourceTab?.id)) throw Error("Source tab did not open.");
    await chrome.storage.session.set({
      [sessionKey(adminTabId)]: {
        requestId: command.requestId,
        sourceTabId: sourceTab.id,
        expires: Date.now() + 120000,
      },
    });
    await chrome.tabs.update(sourceTab.id, {url: command.url});
    respond({});
  }).catch(() => respond({error: "Could not open original match page."}));
  return true;
});

function reportMedia(details, media) {
  if (!media || details.tabId < 0) return;
  // A source tab can belong to only one actively requested Admin capture.
  chrome.storage.session.get(null).then((items) => {
    const found = Object.entries(items).find(([key, session]) =>
      key.startsWith("capture:") && session?.sourceTabId === details.tabId);
    if (!found) return;
    const [key, session] = found;
    if (Date.now() > session.expires) {
      void chrome.storage.session.remove(key);
      return;
    }
    const adminTabId = Number(key.slice("capture:".length));
    void chrome.tabs.sendMessage(adminTabId, {
      type: "LINK", requestId: session.requestId, ...media,
    }).catch(() => chrome.storage.session.remove(key));
  }).catch(() => {});
}

chrome.webRequest.onBeforeRequest.addListener((details) => {
  reportMedia(details, mediaLink(details.url));
}, {urls: ["https://*/*"]});

// Some players request a manifest through a path without a .m3u8/.mpd
// suffix. Read the MIME type only; never forward response headers or bodies.
chrome.webRequest.onHeadersReceived.addListener((details) => {
  if (mediaLink(details.url)) return;
  reportMedia(details, mediaContentType(details));
}, {urls: ["https://*/*"]}, ["responseHeaders"]);

chrome.tabs.onRemoved.addListener((tabId) => {
  void chrome.storage.session.get(null).then((items) => {
    for (const [key, session] of Object.entries(items)) {
      if (!key.startsWith("capture:") ||
          (key !== sessionKey(tabId) && session?.sourceTabId !== tabId)) continue;
      void chrome.storage.session.remove(key);
      const adminTabId = Number(key.slice("capture:".length));
      if (adminTabId !== tabId) {
        void chrome.tabs.sendMessage(adminTabId, {
          type: "STOPPED", requestId: session.requestId,
        }).catch(() => {});
      }
    }
  }).catch(() => {});
});
