import test from 'node:test';
import assert from 'node:assert/strict';
import { addGoogleCalendarEvent, eventOverlaps, listGoogleConflicts, makeDemoConflicts, stableGoogleEventId, toConflict, validateEvent, InputError } from './calendarService.js';
import { buildRoutes, deterministicSummary, summaryContainsScheduleDetail } from './agentEngine.js';
import { currentPosition, isTravelIntent } from '../src/location.js';

test('travel intent includes departure questions but not calendar-only requests', () => {
  for (const text of ['How do I get there?', 'When should I leave?', '¿A qué hora salgo?', 'Cómo llegar al evento']) assert.equal(isTravelIntent(text), true);
  assert.equal(isTravelIntent('Check my calendar for conflicts'), false);
});

test('location is fresh and coordinates become the Maps origin', async () => {
  const geo = { getCurrentPosition(success: PositionCallback, _error?: PositionErrorCallback | null, options?: PositionOptions) {
    assert.equal(options?.maximumAge, 30_000);
    assert.equal(options?.timeout, 12_000);
    success({ coords: { latitude: 47.37, longitude: 8.54, accuracy: 18 } } as GeolocationPosition);
  } };
  const result = await currentPosition(geo);
  const event = validateEvent({ title: 'Meetup', location: 'Kraftwerk, Zurich', start: '2026-10-14T16:30:00Z', end: '2026-10-14T18:30:00Z' });
  const url = new URL(buildRoutes(event, result.origin).mapsUrl);
  assert.equal(url.searchParams.get('origin'), '47.37,8.54');
  assert.equal(url.searchParams.get('destination'), 'Kraftwerk, Zurich');
});

test('location denial and timeout produce a manual fallback, not an invented location', async () => {
  for (const code of [1, 2, 3]) {
    const geo = { getCurrentPosition(_success: PositionCallback, error?: PositionErrorCallback | null) { error?.({ code } as GeolocationPositionError); } };
    await assert.rejects(currentPosition(geo), /starting point/);
  }
});

test('validates timezone-bearing event dates and rejects missing or reversed dates', () => {
  const event = validateEvent({ title: 'Talk', start: '2026-10-14T18:30:00+02:00', end: '2026-10-14T20:30:00+02:00' });
  assert.equal(event.start, '2026-10-14T16:30:00.000Z');
  assert.throws(() => validateEvent({ title: 'Talk', start: '2026-10-14T18:30', end: '2026-10-14T20:30' }), InputError);
  assert.throws(() => validateEvent({ title: 'Talk', start: '2026-10-14T20:30:00Z', end: '2026-10-14T18:30:00Z' }), InputError);
});

test('demo conflict is synthetic but always overlaps the selected event', () => {
  const event = validateEvent({ title: 'Meetup', start: '2026-10-14T16:30:00Z', end: '2026-10-14T18:30:00Z' });
  const [conflict] = makeDemoConflicts(event);
  assert.equal(conflict.title, 'Focus block (demo event)');
  assert.equal(eventOverlaps(event, conflict), true);
});

test('deterministic summaries are English and use Europe/Zurich display times', () => {
  const event = validateEvent({ title: 'Creative Coding Meetup', start: '2026-10-14T16:30:00Z', end: '2026-10-14T18:30:00Z' });
  const demo = deterministicSummary('Quiero asistir a este evento', event, makeDemoConflicts(event), 'demo');
  assert.match(demo, /Simulated calendar/);
  assert.match(demo, /Wed, 14 Oct 2026, 18:30–20:30 CEST/);
  assert.doesNotMatch(demo, /Quiero asistir|Simulación|conflicto|calendario/);
  const google = deterministicSummary('¿Tengo conflictos?', event, [], 'google');
  assert.match(google, /^No conflicts found in Google Calendar/);
  assert.match(google, /Wed, 14 Oct 2026, 18:30–20:30 CEST/);
});

test('rejects model summaries that add incorrect or repeated schedule details', () => {
  assert.equal(summaryContainsScheduleDetail('The event is Friday, October 10, 2026 at 18:00.'), true);
  assert.equal(summaryContainsScheduleDetail('It is scheduled for Fri, 10 Oct at 18:00 CEST.'), true);
  assert.equal(summaryContainsScheduleDetail('Your calendar check is clear for this event.'), false);
});

test('Google all-day end dates remain exclusive for overlap checks', () => {
  const allDay = toConflict({
    id: 'holiday', summary: 'All-day',
    start: { date: '2026-10-14' }, end: { date: '2026-10-15' },
  });
  assert.ok(allDay);
  const sameDay = validateEvent({ title: 'Meetup', start: '2026-10-14T12:00:00Z', end: '2026-10-14T13:00:00Z' });
  const nextDay = validateEvent({ title: 'Meetup', start: '2026-10-15T00:00:00Z', end: '2026-10-15T01:00:00Z' });
  assert.equal(eventOverlaps(sameDay, allDay!), true);
  assert.equal(eventOverlaps(nextDay, allDay!), false);
});

test('Google all-day dates use the calendar timezone, including summer time', () => {
  const allDay = toConflict({
    id: 'local-day',
    start: { date: '2026-10-14' }, end: { date: '2026-10-15' },
  }, 'Europe/Zurich');
  assert.equal(allDay?.start, '2026-10-13T22:00:00.000Z');
  assert.equal(allDay?.end, '2026-10-14T22:00:00.000Z');
});

test('Google conflict lookup follows every page and filters non-blocking/cancelled events', async () => {
  const event = validateEvent({ title: 'Meetup', start: '2026-10-14T09:00:00Z', end: '2026-10-14T10:00:00Z' });
  const originalFetch = globalThis.fetch;
  const calls: Array<{ url: string; authorization: string | null }> = [];
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' || input instanceof URL ? input.toString() : input.url);
    calls.push({ url: url.toString(), authorization: new Headers(init?.headers).get('Authorization') });
    if (!url.searchParams.has('pageToken')) {
      return new Response(JSON.stringify({
        timeZone: 'Europe/Zurich', nextPageToken: 'next',
        items: [{ id: 'cancelled', status: 'cancelled', start: { date: '2026-10-14' }, end: { date: '2026-10-15' } }],
      }), { status: 200 });
    }
    return new Response(JSON.stringify({ items: [
      { id: 'all-day', summary: 'All day', start: { date: '2026-10-14' }, end: { date: '2026-10-15' } },
      { id: 'transparent', transparency: 'transparent', start: { dateTime: '2026-10-14T09:10:00Z' }, end: { dateTime: '2026-10-14T09:20:00Z' } },
      { id: 'declined', attendees: [{ self: true, responseStatus: 'declined' }], start: { dateTime: '2026-10-14T09:10:00Z' }, end: { dateTime: '2026-10-14T09:20:00Z' } },
      { id: 'busy', summary: 'Busy', start: { dateTime: '2026-10-14T09:10:00Z' }, end: { dateTime: '2026-10-14T09:20:00Z' } },
    ] }), { status: 200 });
  }) as typeof fetch;
  try {
    const conflicts = await listGoogleConflicts(event, 'test-token');
    assert.deepEqual(conflicts.map((conflict) => conflict.id), ['all-day', 'busy']);
    assert.equal(calls.length, 2);
    assert.equal(new URL(calls[1].url).searchParams.get('pageToken'), 'next');
    assert.equal(calls[0].authorization, 'Bearer test-token');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Google event ID is stable and duplicate insert retries resolve to the existing event', async () => {
  const event = { title: 'Talk', start: '2026-10-14T18:30:00+02:00', end: '2026-10-14T20:30:00+02:00', location: 'Zürich' };
  const id = stableGoogleEventId(event);
  assert.equal(id, stableGoogleEventId(event));
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    calls += 1;
    if (init?.method === 'POST') {
      const body = JSON.parse(String(init.body));
      assert.equal(body.id, id);
      return new Response('{}', { status: 409 });
    }
    return new Response(JSON.stringify({ id, htmlLink: 'https://calendar.google.com/event' }), { status: 200 });
  }) as typeof fetch;
  try {
    const result = await addGoogleCalendarEvent(event, 'test-token');
    assert.equal(result.id, id);
    assert.equal(result.alreadyExists, true);
    assert.equal(calls, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
