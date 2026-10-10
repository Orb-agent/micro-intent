"use strict";

const modeInput = document.getElementById("mode");
const status = document.getElementById("status");
const openButton = document.getElementById("open");

chrome.storage.local.get({ voiceMode: "ptt" }, (saved) => {
  modeInput.value = saved.voiceMode;
});

modeInput.addEventListener("change", () => {
  chrome.storage.local.set({ voiceMode: modeInput.value });
});

openButton.addEventListener("click", async () => {
  try {
    await chrome.storage.local.set({ voiceMode: modeInput.value });
    await chrome.tabs.create({ url: chrome.runtime.getURL("client.html") });
    window.close();
  } catch (error) {
    status.textContent = error.message || "Could not open the assistant.";
  }
});
