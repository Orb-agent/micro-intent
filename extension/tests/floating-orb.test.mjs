import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
test("only the extension frame may expand the orb, and website replies cannot set its content", () => {
  const frame = { style: {}, dataset: {}, contentWindow: {} }, sent = [];
  let listener;
  const win = {}; win.top = win.self = win;
  runInNewContext(readFileSync(new URL("../floating-orb.js", import.meta.url), "utf8"), {
    window: win, URL, location: { origin: "https://lu.ma" },
    document: { querySelector: () => null, createElement: () => frame, documentElement: { appendChild() {} } },
    chrome: { runtime: { getURL: (path) => "chrome-extension://orbs/" + path, sendMessage: async (message) => sent.push(message) } },
    addEventListener: (_, callback) => { listener = callback; },
  });
  assert.equal(frame.style.width, "128px");
  listener({ source: frame.contentWindow, origin: "https://lu.ma", data: { type: "orbs-layout", expanded: true } });
  assert.equal(frame.style.width, "128px");
  listener({ source: frame.contentWindow, origin: "chrome-extension://orbs", data: { type: "orbs-layout", expanded: true } });
  assert.match(frame.style.width, /380px/);
  listener({ source: frame.contentWindow, origin: "chrome-extension://orbs", data: { type: "orbs-layout", expanded: true, height: 360 } });
  assert.match(frame.style.height, /360px/);
  listener({ source: frame.contentWindow, origin: "chrome-extension://orbs", data: { type: "orbs-layout", expanded: true, height: 9999 } });
  assert.match(frame.style.height, /460px/);
  listener({ source: frame.contentWindow, origin: "chrome-extension://orbs", data: { type: "orbs-layout", expanded: false } });
  assert.equal(frame.style.height, "112px");
  listener({ source: win, origin: "https://lu.ma", data: { channel: "orbs-a2ui", message: { type: "audio", data: "not forwarded" } } });
  assert.equal(sent.length, 0);
});
