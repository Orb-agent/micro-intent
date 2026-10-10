import { NoticeRouter, trustedSource } from "./notice-router.mjs";
const router = new NoticeRouter();
const extensionOrigin = chrome.runtime.getURL("").replace(/\/$/, "");
let backendOrigin = "http://localhost:8000", configPromise;
async function configure() {
  configPromise ??= fetch("http://localhost:8000/extension-config", {
    cache: "no-store", headers: { "X-Orbs-Client": "orbs-ui" },
  }).then(async (response) => {
    if (!response.ok) throw new Error("Backend unavailable");
    const config = await response.json();
    backendOrigin = new URL(config.backend_url).origin;
  }).catch(() => { configPromise = undefined; });
  await configPromise;
}
const sourceId = (sender) => `${sender.tab?.id ?? "assistant"}:${sender.frameId ?? 0}`;
chrome.runtime.onConnect.addListener(async (port) => {
  if (port.name !== "orbs-notices" || port.sender?.id !== chrome.runtime.id ||
      !port.sender.tab || !trustedSource(port.sender, extensionOrigin, "")) return;
  let closed = false;
  port.onDisconnect.addListener(() => { closed = true; });
  await configure();
  if (closed) return;
  const tabURL = new URL(port.sender.tab.url || "about:blank");
  if (tabURL.origin === backendOrigin || (["localhost", "127.0.0.1"].includes(tabURL.hostname) && tabURL.port === "8000")) return;
  const tabId = port.sender.tab.id;
  const disconnect = router.connect(tabId, (message) => { try { port.postMessage(message); } catch {} });
  if (port.sender.tab.active) router.activate(tabId);
  port.onDisconnect.addListener(disconnect);
  port.onMessage.addListener((message) => {
    if (message.type === "dismiss") router.dismiss(message.keys);
  });
});
chrome.tabs.onActivated.addListener(({ tabId }) => {
  // Remember the last website when the full assistant tab becomes active.
  if (router.views.has(tabId)) router.activate(tabId);
});
chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  const [tab] = await chrome.tabs.query({ active: true, windowId });
  if (tab && router.views.has(tab.id)) router.activate(tab.id);
});
chrome.runtime.onMessage.addListener((request, sender, respond) => {
  if (sender.id !== chrome.runtime.id || request?.type !== "orbs-ui") return;
  void (async () => {
    await configure();
    if (!trustedSource(sender, extensionOrigin, backendOrigin)) return;
    const message = request.message;
    if (JSON.stringify(message).length > 100000) return;
    // Forward only generated UI, never tokens, audio, or page screenshots.
    if (message?.type === "reply") router.publish({ type: "reply", cards: message.cards }, sourceId(sender));
    else if (message?.type === "a2ui") router.publish({ type: "a2ui", messages: message.messages }, sourceId(sender));
    else if (message?.type === "dismiss") router.dismiss(message.keys);
  })().then(() => respond({ ok: true })).catch(() => respond({ ok: false }));
  return true;
});
