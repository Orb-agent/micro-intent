import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { NoticeRouter, trustedSource } from "../notice-router.mjs";
import { conflictKey } from "../../backend/static/conflict-core.mjs";
const reply = JSON.parse(readFileSync(new URL("../../backend/fixtures/demo_reply.json", import.meta.url)));
const messages = JSON.parse(readFileSync(new URL("../../backend/fixtures/demo_a2ui.json", import.meta.url)));
const cards = [{ ...reply.cards[0], verdict: "clash" }, reply.cards[1]];
function setup() {
  const router = new NoticeRouter(), luma = [], other = [];
  router.connect(1, (m) => luma.push(m)); router.connect(2, (m) => other.push(m));
  router.activate(1);
  return { router, luma, other };
}
test("assistant replies show the selected A2UI conflict on the active website", () => {
  const { router, luma, other } = setup();
  router.publish({ type: "reply", cards }, "assistant");
  router.publish({ type: "a2ui", messages }, "assistant");
  assert.equal(luma.at(-1).type, "notice");
  assert.deepEqual(luma.at(-1).messages[1].updateComponents.components[0].children, ["c0"]);
  assert.equal(other.at(-1).type, "clear");
  router.activate(2);
  assert.equal(other.at(-1).type, "notice");
});
test("fits and ordinary replies clear warnings without opening website popups", () => {
  const { router, luma } = setup();
  router.publish({ type: "reply", cards }, "assistant");
  router.publish({ type: "reply", cards: reply.cards }, "assistant");
  assert.equal(luma.at(-1).type, "clear");
});
test("a dismissed warning stays closed across tabs, rewording and navigation", () => {
  const { router, luma, other } = setup();
  router.publish({ type: "reply", cards }, "assistant");
  router.dismiss([conflictKey(cards[0])]);
  router.activate(2);
  assert.equal(other.at(-1).type, "acknowledge");
  router.publish({ type: "reply", cards: [{ ...cards[0], note: "New wording" }] }, "assistant");
  assert.equal(other.at(-1).type, "clear");
  router.publish({ type: "reply", cards: [{ ...cards[0], verdict: "tight" }] }, "assistant");
  assert.equal(other.at(-1).type, "notice");
  assert.equal(luma.at(-1).type, "clear");
});
test("late A2UI from another session and unrecognized components are ignored", () => {
  const { router, luma } = setup();
  router.publish({ type: "reply", cards }, "session-A");
  router.publish({ type: "a2ui", messages }, "session-B");
  assert.deepEqual(luma.at(-1).messages, []);
  const unsafe = structuredClone(messages);
  unsafe[1].updateComponents.components.find((c) => c.id === "c0").component = "Image";
  router.publish({ type: "a2ui", messages: unsafe }, "session-A");
  assert.deepEqual(luma.at(-1).messages, []);
});
test("only the Orbs extension and configured backend root may publish UI", () => {
  const extension = "chrome-extension://orbs", backend = "http://localhost:8000";
  const source = (url, frameId = 0) => ({ url, frameId });
  assert(trustedSource(source(extension + "/client.html?widget=1", 2), extension, backend));
  assert(trustedSource(source(backend + "/"), extension, backend));
  assert(trustedSource(source("http://127.0.0.1:8000/"), extension, backend));
  for (const url of ["https://lu.ma/event", "https://evil.test/", backend + "/other", extension + "/popup.html"]) {
    assert.equal(trustedSource(source(url), extension, backend), false);
  }
  assert.equal(trustedSource(source(backend + "/", 1), extension, backend), false);
  assert.equal(trustedSource(source("http://127.0.0.1:8866/"), extension, backend), false);
});
test("disconnecting a website prevents delivery until it reconnects", () => {
  const router = new NoticeRouter(), received = [];
  const disconnect = router.connect(1, (m) => received.push(m));
  router.activate(1); disconnect(); router.publish({ type: "reply", cards }, "assistant");
  assert.equal(received.length, 0);
  router.connect(1, (m) => received.push(m));
  assert.equal(received.at(-1).type, "notice");
});
