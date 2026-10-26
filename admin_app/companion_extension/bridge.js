// Only the deployed Admin Web origin receives results. The browser extension
// never forwards cookies, response bodies, request headers, or DRM material.
const origin = "https://nyeinchanaung75299-eng.github.io";
const prefix = "NCA_ADMIN_CAPTURE_V1:";

function reply(message) {
  window.postMessage(prefix + JSON.stringify({
    from: "companion", ...message,
  }), origin);
}

window.addEventListener("message", (event) => {
  if (event.source !== window || event.origin !== origin ||
      typeof event.data !== "string" || !event.data.startsWith(prefix)) return;
  let command;
  try { command = JSON.parse(event.data.slice(prefix.length)); }
  catch { return; }
  if (command?.from !== "admin" ||
      !/^[0-9]{8,25}$/.test(command.requestId || "")) return;
  if (command.type === "PING") {
    reply({type: "READY", requestId: command.requestId});
    return;
  }
  if (!["START", "STOP"].includes(command.type)) return;
  chrome.runtime.sendMessage({
    type: command.type,
    requestId: command.requestId,
    ...(command.type === "START" ? {url: command.url} : {}),
  }, (result) => {
    if (chrome.runtime.lastError) {
      reply({type: "ERROR", requestId: command.requestId,
        message: "Browser companion is unavailable. Reload Admin Web."});
    } else if (result?.error) {
      reply({type: "ERROR", requestId: command.requestId,
        message: result.error});
    } else {
      reply({type: command.type === "START" ? "STARTED" : "STOPPED",
        requestId: command.requestId});
    }
  });
});

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "LINK" || message?.type === "STOPPED") reply(message);
});
