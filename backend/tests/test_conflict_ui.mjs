import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { attentionIndices, conflictKey, selectCardMessages, createConflictPopup } from "../static/conflict-ui.mjs";

const fixture = JSON.parse(readFileSync(new URL("../fixtures/demo_reply.json", import.meta.url), "utf8"));
const messages = JSON.parse(readFileSync(new URL("../fixtures/demo_a2ui.json", import.meta.url), "utf8"));
const clash = { ...fixture.cards[0], verdict: "clash" };

test("only tight or clashing plans request attention", () => {
  assert.deepEqual(attentionIndices(fixture.cards), []);
  assert.deepEqual(attentionIndices([fixture.cards[1], clash, { ...clash, verdict: "tight" }]), [1, 2]);
  assert.deepEqual(attentionIndices([{ ...clash, verdict: "unknown" }, null]), []);
});

test("popup surface contains the conflict, not the accompanying train", () => {
  const selected = selectCardMessages(messages, [0]);
  assert.deepEqual(selected[1].updateComponents.components[0].children, ["c0"]);
  assert(!JSON.stringify(selected).includes("c1"));
  assert.deepEqual(messages[1].updateComponents.components[0].children, ["c0", "c1"]);
});

test("malformed catalogs, references and cycles cannot render a popup", () => {
  for (const mutate of [
    (m) => { m[0].createSurface.catalogId = "https://untrusted.invalid/catalog"; },
    (m) => { m[1].updateComponents.components.find((c) => c.id === "c0").child = "c1-body"; },
    (m) => { m[1].updateComponents.components.find((c) => c.id === "c0-body").children.push("c0"); },
    (m) => { m[1].updateComponents.components.find((c) => c.id === "c0").component = "Image"; },
  ]) {
    const copy = structuredClone(messages);
    mutate(copy);
    assert.throws(() => selectCardMessages(copy, [0]));
  }
});

test("dismissal identity ignores rephrased advice but notices a changed plan", () => {
  assert.equal(conflictKey(clash), conflictKey({ ...clash, note: "Different advice" }));
  assert.notEqual(conflictKey(clash), conflictKey({ ...clash, verdict: "tight" }));
  assert.notEqual(conflictKey(clash), conflictKey({ ...clash, proposal: { ...clash.proposal, start: "2026-10-15T20:00:00+02:00" } }));
});

function harness(loadRenderer = async () => { throw new Error("offline"); }) {
  const popup = { hidden: true, addEventListener() {} };
  const content = { dataset: {}, children: [], replaceChildren(...nodes) { this.children = nodes; },
    ownerDocument: { createElement: (tag) => ({ tag }) } };
  const controller = createConflictPopup({ popup, content, dismissButton: { addEventListener() {} },
    renderFallback: (cards) => { content.children = cards; }, loadRenderer });
  return { popup, content, controller };
}

test("acknowledging a conflict prevents duplicate notices until the plan changes", () => {
  const { popup, controller } = harness();
  controller.setReply([clash]);
  assert.equal(popup.hidden, false);
  controller.dismiss();
  controller.setReply([{ ...clash, note: "Rephrased warning" }]);
  assert.equal(popup.hidden, true);
  controller.setReply([{ ...clash, verdict: "tight" }]);
  assert.equal(popup.hidden, false);
  controller.setReply(fixture.cards);
  assert.equal(popup.hidden, true);
});

test("failed library loading keeps the conflict visible in the native fallback", async () => {
  const { popup, content, controller } = harness();
  controller.setReply([clash]);
  assert.equal(await controller.receiveMessages(messages), false);
  assert.equal(popup.hidden, false);
  assert.equal(content.dataset.renderer, "fallback");
  assert.deepEqual(content.children, [clash]);
});

test("late A2UI loading cannot revive a dismissed or superseded notice", async () => {
  for (const replace of [false, true]) {
    let resolve;
    const loading = new Promise((done) => { resolve = done; });
    const { popup, content, controller } = harness(() => loading);
    controller.setReply([clash]);
    const pending = controller.receiveMessages(messages);
    if (replace) controller.setReply(fixture.cards); else controller.dismiss();
    resolve({});
    assert.equal(await pending, false);
    assert.equal(popup.hidden, true);
    assert.deepEqual(content.children, []);
  }
});
