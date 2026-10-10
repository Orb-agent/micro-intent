import { attentionIndices, createConflictPopup } from "./conflict-ui.mjs";
"use strict";
const RATE = 24000; // 24 kHz mono, contracts § Audio
const $ = (id) => document.getElementById(id);
function orbMark() {
  const ticks = Array.from({ length: 48 }, (_, i) =>
    `<rect x="48" y="4" width="4" height="10" rx="2" transform="rotate(${i * 7.5} 50 50)"/>`
  ).join("");
  return `<svg viewBox="0 0 100 100" aria-hidden="true"><g fill="currentColor">${ticks}</g></svg>`;
}
$("orb").innerHTML = orbMark();
$("brandMark").innerHTML = orbMark().replace('<svg viewBox="0 0 100 100" aria-hidden="true">', '<g>').replace('</svg>', '</g>');
const log = (...a) => { const l = $("log"); l.hidden = false; l.textContent += a.join(" ") + "\n"; l.scrollTop = l.scrollHeight; };

let token = "", server = "";
let ws, ctx, micNode, micStream, screenStream, screenVideo;
let mode = "ptt", talking = false, serverState = "idle", dropAudio = false, configRetry;
const widgetMode = new URLSearchParams(location.search).has("widget");
const CONFIG_BOOTSTRAP_URL = "http://localhost:8000";
let playing = [], nextTime = 0, releasedAt = 0, firstAudioLogged = true;

// ---------- WebSocket ----------
function connect() {
  const endpoint = new URL("/ws", server);
  endpoint.protocol = endpoint.protocol === "https:" ? "wss:" : "ws:";
  ws = new WebSocket(endpoint);
  ws.onopen = () => ws.send(JSON.stringify({ type: "hello", token, mode }));
  ws.onclose = (e) => {
    setConn(e.code === 1008 ? "invalid token" : "reconnecting", false);
    if (e.code === 1008) { $("label").textContent = "The backend rejected its configured credentials. Check the backend environment configuration."; return; }
    $("label").textContent = `Waiting for backend at ${new URL(server).host}…`;
    setTimeout(connect, 1000);
  };
  ws.onmessage = (e) => onMessage(JSON.parse(e.data));
}
const send = (m) => ws && ws.readyState === 1 && ws.send(JSON.stringify(m));
function setConn(text, ok) { $("conn").textContent = text; $("conn").classList.toggle("ok", ok); }

function onMessage(m) {
  switch (m.type) {
    case "ready": setConn(mode === "handsfree" ? "connected · hands-free" : "connected", true); $("label").textContent = "Ready when you are"; break;
    case "state":
      serverState = m.state; $("label").textContent = m.label || "";
      if (m.state === "listening" && mode === "handsfree") { stopPlayback(); grabScreen("speech"); }
      renderOrb(); break;
    case "transcript": $("you").textContent = "You: " + m.text; log("transcript", JSON.stringify(m.text)); break;
    case "reply":
      dropAudio = false; firstAudioLogged = false;
      $("say").hidden = false; $("say").textContent = m.say;
      renderCards((m.cards || []).filter((_, index) => !attentionIndices(m.cards || []).includes(index)));
      conflictPopup.setReply(m.cards || []); publishUI(m); break;
    case "a2ui": void conflictPopup.receiveMessages(m.messages); publishUI(m); break;
    case "audio": if (!dropAudio) playChunk(m.data); break;
    case "audio_end": break;
    case "screen_ok":
      $("screenSummary").hidden = false;
      $("screenSummary").textContent = m.summary ? "Sees: " + m.summary : "Screen received (not read)";
      log("screen_ok", m.summary || "(no summary)"); break;
    case "error": log("error", m.message); $("label").textContent = m.message; break;
  }
}

// ---------- Audio in ----------
function ensureCtx() { // needs a user gesture (click, key, submit) before audio can play
  if (!ctx) ctx = new AudioContext({ sampleRate: RATE }); // the browser resamples the mic to 24 kHz
  if (ctx.state === "suspended") ctx.resume();
}

async function startAudio() {
  ensureCtx();
  if (ctx.state === "suspended") await ctx.resume();
  await ctx.audioWorklet.addModule(chrome.runtime.getURL("pcm-worklet.js"));
  micStream = await navigator.mediaDevices.getUserMedia({
    audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
  });
  micNode = new AudioWorkletNode(ctx, "pcm");
  micNode.port.onmessage = (e) => { if (talking || mode === "handsfree") send({ type: "audio", data: b64(e.data) }); };
  ctx.createMediaStreamSource(micStream).connect(micNode);
  $("hint").textContent = mode === "handsfree"
    ? "Hands-free: just talk. Talking over the beaver interrupts it."
    : "Hold the orb or Space while you talk. Click the orb while it speaks to stop it.";
  log("mic on at", ctx.sampleRate, "Hz");
}

function stopAudio() {
  talking = false;
  serverState = "idle";
  if (micNode) { micNode.port.onmessage = null; try { micNode.disconnect(); } catch {} micNode = null; }
  if (micStream) { micStream.getTracks().forEach((track) => track.stop()); micStream = null; }
  renderOrb();
}

function b64(buf) {
  const bytes = new Uint8Array(buf); let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

// ---------- Audio out ----------
function playChunk(data) {
  if (!ctx) return;
  const raw = atob(data), n = raw.length >> 1, f = new Float32Array(n);
  for (let i = 0; i < n; i++) { const v = raw.charCodeAt(2 * i) | (raw.charCodeAt(2 * i + 1) << 8); f[i] = (v > 32767 ? v - 65536 : v) / 32768; }
  const buf = ctx.createBuffer(1, n, RATE); buf.copyToChannel(f, 0);
  const src = ctx.createBufferSource(); src.buffer = buf; src.connect(ctx.destination);
  nextTime = Math.max(nextTime, ctx.currentTime + 0.03);
  src.start(nextTime); nextTime += buf.duration;
  playing.push(src); src.onended = () => { playing = playing.filter((s) => s !== src); renderOrb(); };
  if (!firstAudioLogged && releasedAt) { firstAudioLogged = true; log(`first audio ${((performance.now() - releasedAt) / 1000).toFixed(2)} s after release`); }
  renderOrb();
}

function stopPlayback() {
  dropAudio = true; // contracts § WebSocket: drop audio until the next reply
  for (const s of playing) { try { s.stop(); } catch {} }
  playing = []; nextTime = 0; renderOrb();
}

function renderOrb() {
  const state = playing.length ? "speaking" : talking ? "listening" : serverState;
  $("orb").dataset.state = state;
}

// ---------- Push to talk ----------
async function press() {
  if (!micNode) { await startAudio(); return; }      // first click only turns the mic on
  if (mode === "handsfree") { if (playing.length) { stopPlayback(); send({ type: "interrupt" }); } return; }
  if (talking) return;
  if (playing.length || serverState !== "idle") stopPlayback(); // the first audio frame interrupts server-side
  talking = true; renderOrb(); grabScreen("press");
}
function release() {
  if (!talking) return;
  talking = false; releasedAt = performance.now(); send({ type: "audio_end" }); renderOrb();
}
$("orb").addEventListener("pointerdown", (e) => {
  e.preventDefault();
  if (!widgetMode) press();
});
if (widgetMode) {
  document.body.classList.add("orbs-widget");
  $("orb").addEventListener("click", async () => {
    $("orb").disabled = true;
    try {
      if (mode === "handsfree") {
        if (micNode) { stopAudio(); $("label").textContent = "Tap to listen"; }
        else { await startAudio(); $("label").textContent = "Listening · tap to pause"; }
      } else if (talking) {
        release(); $("label").textContent = "Tap to talk";
      } else {
        if (!micNode) await startAudio();
        if (playing.length || serverState !== "idle") stopPlayback();
        talking = true; renderOrb(); grabScreen("orb"); $("label").textContent = "Listening · tap to send";
      }
    } catch (error) {
      $("label").textContent = "Microphone access needed";
      log("mic error:", error.message);
    } finally { $("orb").disabled = false; }
  });
} else {
  for (const ev of ["pointerup", "pointerleave", "pointercancel"]) $("orb").addEventListener(ev, release);
}
const editing = () => document.activeElement?.matches("input,textarea,select,button,a,[contenteditable=true]");
addEventListener("keydown", (e) => { if (!widgetMode && e.code === "Space" && !e.repeat && !editing()) { e.preventDefault(); press(); } });
addEventListener("keyup", (e) => { if (!widgetMode && e.code === "Space" && !editing()) { e.preventDefault(); release(); } });

$("mode").addEventListener("change", () => {
  mode = $("mode").value; stopPlayback(); talking = false;
  if (ws) { ws.onclose = null; ws.close(); } connect();
  if (micNode) $("hint").textContent = mode === "handsfree" ? "Hands-free: just talk." : "Hold the orb or Space while you talk.";
});

// ---------- Screen ----------
$("share").addEventListener("click", async () => {
  try {
    screenStream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 2 }, audio: false });
    screenVideo = Object.assign(document.createElement("video"), { srcObject: screenStream, muted: true });
    await screenVideo.play();
    screenStream.getVideoTracks()[0].onended = () => { screenStream = null; $("share").textContent = "Share screen"; $("sendScreen").disabled = true; };
    $("share").textContent = "Sharing ✓"; $("sendScreen").disabled = false;
    log("screen sharing on: a frame goes with each question");
  } catch (e) { log("screen share cancelled:", e.message); }
});
$("sendScreen").addEventListener("click", () => grabScreen("button"));

let lastGrab = 0;
function grabScreen(why) {
  if (!screenVideo || !screenVideo.videoWidth || performance.now() - lastGrab < 1500) return;
  lastGrab = performance.now();
  const scale = Math.min(1, 1280 / screenVideo.videoWidth);
  const c = Object.assign(document.createElement("canvas"), {
    width: Math.round(screenVideo.videoWidth * scale), height: Math.round(screenVideo.videoHeight * scale) });
  c.getContext("2d").drawImage(screenVideo, 0, 0, c.width, c.height);
  const url = c.toDataURL("image/jpeg", 0.8);
  $("screenThumb").src = url; $("screenThumb").style.display = "block";
  send({ type: "screen", mime: "image/jpeg", data: url.split(",")[1] });
  log(`screen frame sent (${why}, ${c.width}x${c.height}, ${Math.round(url.length * 0.75 / 1024)} KB)`);
}

// ---------- Text ----------
$("textForm").addEventListener("submit", (e) => {
  e.preventDefault(); const t = $("text").value.trim(); if (!t) return;
  if (!ws || ws.readyState !== WebSocket.OPEN) { $("label").textContent = "Waiting for the backend. Keep it running, then try again."; return; }
  ensureCtx(); stopPlayback(); grabScreen("text"); releasedAt = performance.now();
  send({ type: "text", text: t }); $("you").textContent = "You: " + t; $("text").value = "";
});

// ---------- Cards (from reply.cards; the iPhone app renders the a2ui messages instead) ----------
const hm = (iso) => iso ? new Date(iso).toLocaleTimeString("de-CH", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Zurich" }) : "";
const day = (iso) => iso ? new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", timeZone: "Europe/Zurich" }) : "";
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

function renderCards(cards) {
  $("cards").innerHTML = cards.map(cardMarkup).join("");
}
function cardMarkup(c) {
    if (c.kind === "train") return `<div class="card"><div class="kind">Train</div>
      <div class="big">${hm(c.departure)} → ${hm(c.arrival)}</div>
      <div>${esc(c.line)} · ${esc(c.from)} → ${esc(c.to)}</div>
      <div class="meta">${c.platform ? `Platform <span class="badge">${esc(c.platform)}</span> · ` : ""}${c.transfers ? c.transfers + " change(s)" : "direct"}${c.delay_min ? ` · <span class="verdict-clash">+${c.delay_min} min</span>` : ""}</div></div>`;
    if (c.kind === "conflict") return `<div class="card"><div class="kind">Plan check · <span class="verdict-${esc(c.verdict)}">${esc(c.verdict)}</span></div>
      <div><b>${esc(c.event?.title)}</b> ${day(c.event?.start)} ${hm(c.event?.start)}–${hm(c.event?.end)}</div>
      <div><b>${esc(c.proposal?.title)}</b> ${day(c.proposal?.start)} ${hm(c.proposal?.start)}${c.proposal?.place ? " · " + esc(c.proposal.place) : ""}</div>
      ${c.note ? `<div class="meta">${esc(c.note)}</div>` : ""}</div>`;
    if (c.kind === "event") return `<div class="card"><div class="kind">${c.source === "luma" ? "Luma event" : "Calendar"}</div>
      <div><b>${esc(c.title)}</b></div><div class="meta">${day(c.start)} ${hm(c.start)}–${hm(c.end)}${c.location ? " · " + esc(c.location) : ""}</div></div>`;
    if (c.kind === "flight") return `<div class="card"><div class="kind">Flight</div>
      <div class="big">${esc(c.from)} → ${esc(c.to)}</div>
      <div>${esc(c.flight_number)} · ${day(c.departure)} ${hm(c.departure)} → ${hm(c.arrival)}</div>
      ${c.booking_ref ? `<div class="meta">Booking ${esc(c.booking_ref)}</div>` : ""}</div>`;
    return `<div class="card"><pre>${esc(JSON.stringify(c, null, 2))}</pre></div>`;
}

let noticePort;
const conflictPopup = createConflictPopup({
  popup: $("conflictPopup"), content: $("conflictContent"), dismissButton: $("dismissConflict"),
  renderFallback: (cards) => { $("conflictContent").innerHTML = cards.map(cardMarkup).join(""); }, log,
  onVisibilityChange: (visible) => {
    document.body.classList.toggle("has-notice", visible);
    if (widgetMode) parent.postMessage({ type: "orbs-layout", expanded: visible }, "*");
  },
  onDismiss: (keys) => {
    if (noticePort) { try { noticePort.postMessage({ type: "dismiss", keys }); } catch {} }
    else void chrome.runtime.sendMessage({ type: "orbs-ui", message: { type: "dismiss", keys } }).catch(() => {});
  },
});
function publishUI(message) {
  const payload = message.type === "reply" ? { type: "reply", cards: message.cards || [] }
    : { type: "a2ui", messages: message.messages };
  void chrome.runtime.sendMessage({ type: "orbs-ui", message: payload }).catch(() => {});
}
function connectNotices() {
  if (!widgetMode) return;
  noticePort = chrome.runtime.connect({ name: "orbs-notices" });
  noticePort.onMessage.addListener((message) => {
    if (message.type === "clear") conflictPopup.setReply([]);
    if (message.type === "acknowledge") conflictPopup.acknowledge(message.keys);
    if (message.type === "notice") {
      conflictPopup.acknowledge(message.dismissed || []);
      conflictPopup.setReply(message.cards);
      if (message.messages?.length) void conflictPopup.receiveMessages(message.messages);
    }
  });
  noticePort.onDisconnect.addListener(() => { noticePort = undefined; setTimeout(connectNotices, 1000); });
}
connectNotices();

async function initialize() {
  const settings = await chrome.storage.local.get({ voiceMode: "ptt" });
  chrome.storage.local.remove(["beaverServer", "beaverToken"]);
  mode = settings.voiceMode === "handsfree" ? "handsfree" : "ptt";
  $("mode").value = mode;
  if (widgetMode) $("label").textContent = mode === "handsfree" ? "Tap to listen" : "Tap to talk";

  try {
    const response = await fetch(new URL("/extension-config", CONFIG_BOOTSTRAP_URL), {
      cache: "no-store", headers: { "X-Orbs-Client": "orbs-ui" },
    });
    if (!response.ok) throw new Error(`Backend config unavailable (${response.status})`);
    const config = await response.json();
    if (typeof config.app_token !== "string" || !config.app_token || typeof config.backend_url !== "string") {
      throw new Error("Backend configuration is incomplete");
    }
    token = config.app_token;
    server = config.backend_url;
    clearTimeout(configRetry);
  } catch {
    setConn("configuration unavailable", false);
    $("label").textContent = "Start the Orbs backend to load assistant configuration.";
    configRetry = setTimeout(initialize, 2500);
    return;
  }
  connect();
}

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== "local" || !changes.voiceMode) return;
  if (changes.voiceMode) { mode = changes.voiceMode.newValue === "handsfree" ? "handsfree" : "ptt"; stopAudio(); }
  if (ws) { ws.onclose = null; ws.close(); }
  stopPlayback();
  initialize();
});

initialize();
