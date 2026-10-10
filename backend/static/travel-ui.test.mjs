import assert from "node:assert/strict";
import { test } from "node:test";
import { travelPlan } from "./travel-ui.mjs";

const now = Date.parse("2026-10-15T15:00:00+02:00");
const event = { kind: "event", title: "Dinner", start: "2026-10-15T19:00:00+02:00",
  location: "Restaurant & Bar, Bern" };
const train = { kind: "train", from: "Winterthur", to: "Bern", line: "IC 1",
  departure: "2026-10-15T17:30:00+02:00", arrival: "2026-10-15T18:50:00+02:00" };

test("no-conflict attendance offers a transit route from Winterthur to the venue", () => {
  const plan = travelPlan([event, train], "¿Puedo asistir?", now);
  const url = new URL(plan.url);
  assert.equal(url.origin, "https://www.google.com");
  assert.equal(url.searchParams.get("origin"), "Winterthur");
  assert.equal(url.searchParams.get("destination"), event.location);
  assert.equal(url.searchParams.get("travelmode"), "transit");
  assert.equal(plan.start, event.start);
  assert.equal(plan.train, train);
});

test("each conflict verdict suppresses the no-conflict popup", () => {
  for (const verdict of ["fits", "tight", "clash"]) {
    assert.equal(travelPlan([event, train, { kind: "conflict", verdict }], "attend", now), null);
  }
});

test("late, delayed, past and malformed connections are not suggested", () => {
  for (const update of [{ arrival: "2026-10-15T19:01:00+02:00" }, { delay_min: 11 },
    { departure: "2026-10-15T14:00:00+02:00" }, { arrival: "invalid" }]) {
    assert.equal(travelPlan([event, { ...train, ...update }], "attend", now), null);
  }
});

test("listing events stays quiet; explicit attendance can open Maps without a train", () => {
  assert.equal(travelPlan([event], "What's on today?", now), null);
  const plan = travelPlan([event], "Quiero ir al evento", now);
  assert.equal(plan.origin, "Winterthur");
  assert.equal(plan.train, null);
});

test("a train-only reply still offers its connection; explicit origins are preserved", () => {
  const plan = travelPlan([{ ...train, from: "Basel SBB" }], "Can I make it?", now);
  assert.equal(plan.destination, "Bern");
  assert.equal(plan.origin, "Basel SBB");
  assert.equal(travelPlan([], "attend", now), null);
});
