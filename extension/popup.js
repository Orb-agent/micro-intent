"use strict";

const DEFAULT_SERVER = "http://localhost:8000";
const serverInput = document.getElementById("server");
const tokenInput = document.getElementById("token");
const modeInput = document.getElementById("mode");
const status = document.getElementById("status");
const saveButton = document.getElementById("save");
const openButton = document.getElementById("open");
const enableSiteButton = document.getElementById("enableSite");

function parseServer(value) {
  let url;
  try {
    url = new URL(value.trim());
  } catch {
    throw new Error("Enter a valid backend URL.");
  }
  const local = ["localhost", "127.0.0.1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && local)) {
    throw new Error("Use HTTPS for remote servers; HTTP is allowed for localhost.");
  }
  if (url.username || url.password || url.search || url.hash || !["", "/"].includes(url.pathname)) {
    throw new Error("Enter the backend origin only, without a path or credentials.");
  }
  return url.origin;
}

function hostPattern(origin) {
  return `${origin}/*`;
}

function loadSettings() {
  chrome.storage.local.get({ beaverServer: DEFAULT_SERVER, beaverToken: "", voiceMode: "ptt" }, (saved) => {
    serverInput.value = saved.beaverServer;
    tokenInput.value = saved.beaverToken;
    modeInput.value = saved.voiceMode;
  });
}

saveButton.addEventListener("click", async () => {
  saveButton.disabled = true;
  status.textContent = "Requesting access to the selected server…";
  try {
    const server = parseServer(serverInput.value);
    const token = tokenInput.value.trim();
    const voiceMode = modeInput.value;
    const granted = await chrome.permissions.request({ origins: [hostPattern(server)] });
    if (!granted) throw new Error("Server access was not granted; settings were not changed.");
    await chrome.storage.local.set({ beaverServer: server, beaverToken: token, voiceMode });
    status.textContent = "Saved. Orbs will use this server and voice mode.";
  } catch (error) {
    status.textContent = error.message || "Could not save settings.";
  } finally {
    saveButton.disabled = false;
  }
});

openButton.addEventListener("click", async () => {
  try {
    const server = parseServer(serverInput.value);
    const saved = await chrome.storage.local.get({ beaverToken: "", voiceMode: "ptt" });
    const token = tokenInput.value.trim() || saved.beaverToken;
    if (!token) throw new Error("Enter and save your APP_TOKEN first.");
    const permitted = await chrome.permissions.contains({ origins: [hostPattern(server)] });
    if (!permitted) throw new Error("Save the server and allow access before opening the assistant.");
    await chrome.storage.local.set({ beaverServer: server, beaverToken: token, voiceMode: modeInput.value || saved.voiceMode });
    await chrome.tabs.create({ url: chrome.runtime.getURL("client.html") });
    window.close();
  } catch (error) {
    status.textContent = error.message || "Could not open the assistant.";
  }
});

enableSiteButton.addEventListener("click", async () => {
  enableSiteButton.disabled = true;
  status.textContent = "Requesting access to this site…";
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !tab.url) throw new Error("Open a regular website tab first.");
    const page = new URL(tab.url);
    if (!['http:', 'https:'].includes(page.protocol)) throw new Error("The floating orb works on regular HTTP or HTTPS websites.");
    const origin = page.origin;
    const pattern = `${origin}/*`;
    const granted = await chrome.permissions.request({ origins: [pattern] });
    if (!granted) throw new Error("Site access was not granted.");
    const id = `orbs-floating-${btoa(origin).replaceAll("=", "").replaceAll("+", "-").replaceAll("/", "_")}`;
    const registered = await chrome.scripting.getRegisteredContentScripts({ ids: [id] });
    if (!registered.length) {
      await chrome.scripting.registerContentScripts([{
        id,
        matches: [pattern],
        js: ["floating-orb.js"],
        runAt: "document_idle",
        persistAcrossSessions: true,
      }]);
    }
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["floating-orb.js"] });
    status.textContent = `Floating orb enabled on ${page.host}.`;
  } catch (error) {
    status.textContent = error.message || "Could not enable the floating orb.";
  } finally {
    enableSiteButton.disabled = false;
  }
});

modeInput.addEventListener("change", () => {
  chrome.storage.local.set({ voiceMode: modeInput.value });
});

loadSettings();
