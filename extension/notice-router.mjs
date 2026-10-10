import { attentionIndices, conflictKey, selectCardMessages } from "../backend/static/conflict-core.mjs";

// Keep generated UI inside extension frames. Website scripts never receive card data.
export class NoticeRouter {
  constructor() { this.views = new Map(); this.latest = null; this.activeTab = null; this.dismissed = new Set(); }
  connect(tabId, send) {
    this.views.set(tabId, send);
    if (tabId === this.activeTab) this.deliver(tabId);
    return () => { if (this.views.get(tabId) === send) this.views.delete(tabId); };
  }
  activate(tabId) { this.activeTab = tabId; this.deliver(tabId); }
  publish(message, source) {
    if (message?.type === "reply" && Array.isArray(message.cards) && message.cards.length <= 3) {
      this.latest = { source, cards: message.cards, messages: [] };
      // A new answer clears old warnings in other tabs without copying the answer.
      for (const send of this.views.values()) send({ type: "clear" });
    } else if (message?.type === "a2ui" && this.latest?.source === source) {
      const indices = attentionIndices(this.latest.cards);
      if (!indices.length) return;
      try { this.latest.messages = selectCardMessages(message.messages, indices); }
      catch { return; }
    } else return;
    this.deliver(this.activeTab);
  }
  deliver(tabId) {
    if (!this.latest || !this.views.has(tabId)) return;
    const keys = attentionIndices(this.latest.cards).map((index) => conflictKey(this.latest.cards[index]));
    if (!keys.some((key) => !this.dismissed.has(key))) return;
    this.views.get(tabId)({ type: "notice", cards: this.latest.cards, messages: this.latest.messages,
      dismissed: [...this.dismissed] });
  }
  dismiss(keys) {
    if (!Array.isArray(keys) || keys.length > 3 || keys.some((key) => typeof key !== "string" || key.length > 10000)) return;
    for (const key of keys) this.dismissed.add(key);
    // Limit memory to the latest acknowledged conflicts in this browser session.
    while (this.dismissed.size > 256) this.dismissed.delete(this.dismissed.values().next().value);
    for (const send of this.views.values()) send({ type: "acknowledge", keys });
  }
}

export function trustedSource(sender, extensionOrigin, backendOrigin) {
  try {
    const url = new URL(sender.url);
    if (`${url.protocol}//${url.host}` === extensionOrigin && url.pathname === "/client.html") return true;
    const backend = new URL(backendOrigin);
    const loopback = (host) => ["localhost", "127.0.0.1"].includes(host);
    const sameBackend = url.origin === backend.origin ||
      (loopback(url.hostname) && loopback(backend.hostname) && url.protocol === backend.protocol && url.port === backend.port);
    return sameBackend && url.pathname === "/" && sender.frameId === 0;
  } catch { return false; }
}
