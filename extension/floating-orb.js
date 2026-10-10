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
})();
