import { createHash } from 'node:crypto';

export interface PlanEvent {
  title: string;
  start: string;
  end: string;
  location?: string;
  url?: string;
}

export interface CalendarConflict {
  id: string;
  title: string;
  start: string;
  end: string;
}

export interface GoogleCalendarEventInput extends PlanEvent {
  description?: string;
}

export interface GoogleCalendarEvent {
  id?: string;
  summary?: string;
  status?: string;
  transparency?: string;
  attendees?: Array<{ self?: boolean; responseStatus?: string }>;
  start?: { dateTime?: string; date?: string; timeZone?: string };
  end?: { dateTime?: string; date?: string; timeZone?: string };
}

export class InputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InputError';
  }
}

const GOOGLE_CALENDAR_API = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';

/** Validate instants before they reach either the demo overlap check or Google. */
export function validateEvent(input: unknown): PlanEvent {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new InputError('event must be an object with title, start, and end.');
  }
  const event = input as Record<string, unknown>;
  const title = typeof event.title === 'string' ? event.title.trim() : '';
  if (!title) throw new InputError('event.title is required.');
  const start = validIsoInstant(event.start, 'event.start');
  const end = validIsoInstant(event.end, 'event.end');
  if (Date.parse(end) <= Date.parse(start)) {
    throw new InputError('event.end must be later than event.start.');
  }
  const location = optionalString(event.location, 'event.location');
  const url = optionalString(event.url, 'event.url');
  return { title, start, end, ...(location ? { location } : {}), ...(url ? { url } : {}) };
}

function validIsoInstant(value: unknown, field: string): string {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d{1,9})?)?(?:Z|[+-]\d\d:\d\d)$/.test(value)) {
    throw new InputError(`${field} must be an ISO 8601 date-time with a timezone, such as 2026-10-14T18:30:00+02:00.`);
  }
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) throw new InputError(`${field} is not a valid date-time.`);
  return new Date(timestamp).toISOString();
}

function optionalString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string') throw new InputError(`${field} must be a string.`);
  return value.trim() || undefined;
}

/** Return deterministic synthetic conflicts anchored to the selected event. */
export function makeDemoConflicts(event: PlanEvent): CalendarConflict[] {
  const start = Date.parse(event.start);
  const end = Date.parse(event.end);
  const duration = end - start;
  const conflictStart = start + Math.floor(duration * 0.35);
  const conflictEnd = Math.min(end, conflictStart + Math.max(15 * 60_000, Math.floor(duration * 0.25)));
  return [{
    id: `demo-${start}`,
    title: 'Focus block (demo event)',
    start: new Date(conflictStart).toISOString(),
    end: new Date(conflictEnd).toISOString(),
  }];
}

export function eventOverlaps(event: PlanEvent, conflict: CalendarConflict): boolean {
  return Date.parse(event.start) < Date.parse(conflict.end) && Date.parse(conflict.start) < Date.parse(event.end);
}

/** Convert Google timed and all-day events to comparable ISO instants. */
export function toConflict(event: GoogleCalendarEvent, calendarTimeZone = 'UTC'): CalendarConflict | null {
  const start = googleDateToInstant(event.start, calendarTimeZone);
  const end = googleDateToInstant(event.end, calendarTimeZone);
  if (!event.id || !start || !end || Date.parse(start) >= Date.parse(end)) return null;
  return { id: event.id, title: event.summary?.trim() || '(Untitled)', start, end };
}

function googleDateToInstant(value: GoogleCalendarEvent['start'], calendarTimeZone: string): string | null {
  if (!value) return null;
  if (value.dateTime) {
    const time = Date.parse(value.dateTime);
    return Number.isFinite(time) ? new Date(time).toISOString() : null;
  }
  if (value.date && /^\d{4}-\d\d-\d\d$/.test(value.date)) {
    // Google all-day events use midnight in the calendar's own timezone, with
    // an exclusive end date. Resolve that wall time explicitly, independent of
    // the backend machine's timezone.
    return zonedMidnightToInstant(value.date, calendarTimeZone);
  }
  return null;
}

export async function listGoogleConflicts(event: PlanEvent, accessToken: string, calendarTimeZone = defaultTimeZone()): Promise<CalendarConflict[]> {
  const url = new URL(GOOGLE_CALENDAR_API);
  url.searchParams.set('timeMin', event.start);
  url.searchParams.set('timeMax', event.end);
  url.searchParams.set('singleEvents', 'true');
  url.searchParams.set('orderBy', 'startTime');
  url.searchParams.set('maxResults', '2500');
  const headers = { Authorization: `Bearer ${accessToken}` };
  const items: GoogleCalendarEvent[] = [];
  let pageToken: string | undefined;
  let responseTimeZone: string | undefined;
  do {
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    else url.searchParams.delete('pageToken');
    const response = await fetchGoogle(url, { headers });
    if (!response.ok) throw await googleApiError(response, 'Could not read Google Calendar');
    const data = await response.json() as { items?: GoogleCalendarEvent[]; nextPageToken?: string; timeZone?: string };
    items.push(...(data.items ?? []));
    responseTimeZone = data.timeZone || responseTimeZone;
    pageToken = data.nextPageToken;
  } while (pageToken);
  // events.list is compatible with calendar.events and returns the calendar's
  // timeZone. The request value is a fallback for APIs/proxies that omit it.
  const timeZoneCandidate = responseTimeZone || calendarTimeZone;
  const timeZone = safeTimeZone(timeZoneCandidate) ? timeZoneCandidate : defaultTimeZone();
  return items.filter((item) => item.status !== 'cancelled' && item.transparency !== 'transparent' &&
      !item.attendees?.some((attendee) => attendee.self && attendee.responseStatus === 'declined'))
    .map((item) => toConflict(item, timeZone)).filter((item): item is CalendarConflict => item !== null)
    .filter((item) => eventOverlaps(event, item));
}

function defaultTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
}

export function safeTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

function zonedMidnightToInstant(date: string, timeZone: string): string | null {
  const target = Date.parse(`${date}T00:00:00.000Z`);
  if (!Number.isFinite(target)) return null;
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
    });
    let candidate = target;
    // Correct the UTC guess by the difference between its formatted wall time
    // and the requested local midnight. A second pass handles DST transitions.
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const parts = Object.fromEntries(formatter.formatToParts(new Date(candidate))
        .filter((part) => part.type !== 'literal').map((part) => [part.type, Number(part.value)]));
      const represented = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
      const corrected = candidate + (target - represented);
      if (corrected === candidate) break;
      candidate = corrected;
    }
    return new Date(candidate).toISOString();
  } catch {
    return null;
  }
}

export function stableGoogleEventId(event: GoogleCalendarEventInput): string {
  const safe = validateEvent(event);
  const content = JSON.stringify([safe.title, safe.start, safe.end, safe.location || '', safe.url || '']);
  // Google event IDs accept lowercase base32hex characters; hexadecimal is a
  // valid subset and gives retries a deterministic key without storing state.
  return `mi${createHash('sha256').update(content).digest('hex')}`;
}

export async function addGoogleCalendarEvent(event: GoogleCalendarEventInput, accessToken: string): Promise<{ id: string; htmlLink?: string; alreadyExists?: boolean }> {
  const safe = validateEvent(event);
  const id = stableGoogleEventId(safe);
  const response = await fetchGoogle(GOOGLE_CALENDAR_API, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      id,
      summary: safe.title,
      location: safe.location,
      source: safe.url ? { title: safe.title, url: safe.url } : undefined,
      start: { dateTime: safe.start },
      end: { dateTime: safe.end },
    }),
  });
  if (response.status === 409) {
    const existingResponse = await fetchGoogle(`${GOOGLE_CALENDAR_API}/${id}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!existingResponse.ok) throw await googleApiError(existingResponse, 'Could not verify the existing event');
    const existing = await existingResponse.json() as { id?: string; htmlLink?: string };
    if (!existing.id) throw new Error('Google Calendar did not confirm the existing event.');
    return { id: existing.id, ...(existing.htmlLink ? { htmlLink: existing.htmlLink } : {}), alreadyExists: true };
  }
  if (!response.ok) throw await googleApiError(response, 'Could not add the event to Google Calendar');
  const created = await response.json() as { id?: string; htmlLink?: string };
  if (!created.id) throw new Error('Google Calendar did not confirm event creation.');
  return { id: created.id, ...(created.htmlLink ? { htmlLink: created.htmlLink } : {}), alreadyExists: false };
}

async function fetchGoogle(input: string | URL, init: RequestInit): Promise<Response> {
  try {
    return await fetch(input, { ...init, signal: AbortSignal.timeout(10_000) });
  } catch {
    throw new Error('Google Calendar did not respond in time. Please try again.');
  }
}

async function googleApiError(response: Response, prefix: string): Promise<Error> {
  // Avoid exposing provider payloads, which may contain private account details.
  if (response.status === 401 || response.status === 403) return new Error(`${prefix}: the access token expired or lacks calendar permission.`);
  if (response.status === 404) return new Error(`${prefix}: the calendar was not found.`);
  return new Error(`${prefix} (HTTP ${response.status}).`);
}

