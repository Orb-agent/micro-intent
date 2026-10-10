"use strict";

(() => {
  if (window.top !== window.self || document.querySelector("iframe[data-orbs-floating]")) return;
  const orb = document.createElement("iframe");
  orb.dataset.orbsFloating = "true";
  orb.title = "Orbs voice assistant";
  orb.allow = "microphone; autoplay";
  orb.src = chrome.runtime.getURL("client.html?widget=1");
  Object.assign(orb.style, {
    position: "fixed",
    right: "18px",
    bottom: "18px",
    width: "128px",
    height: "112px",
    border: "0",
    background: "transparent",
    zIndex: "2147483647",
    overflow: "hidden",
    colorScheme: "dark",
  });
  (document.documentElement || document.body).appendChild(orb);
  const extensionURL = new URL(orb.src);
  const extensionOrigin = `${extensionURL.protocol}//${extensionURL.host}`;
  addEventListener("message", (event) => {
    if (event.source === orb.contentWindow && event.origin === extensionOrigin &&
        event.data?.type === "orbs-layout") {
      const expanded = event.data.expanded === true;
      orb.style.width = expanded ? "min(380px, calc(100vw - 36px))" : "128px";
      const height = Number.isFinite(event.data.height) ? Math.max(200, Math.min(460, event.data.height)) : 460;
      orb.style.height = expanded ? `min(${height}px, calc(100dvh - 36px))` : "112px";
    }
    // Only the backend root page is accepted by the service worker as a source.
    if (event.source === window && event.origin === location.origin &&
        event.data?.channel === "orbs-a2ui" && ["reply", "a2ui", "dismiss"].includes(event.data.message?.type)) {
      void chrome.runtime.sendMessage({ type: "orbs-ui", message: event.data.message }).catch(() => {});
    }
  });
})();
