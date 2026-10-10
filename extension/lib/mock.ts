// Local stand-in for the backend with the docs/API.md shapes (A2UI v0.9.1 turns, /action).
// Used when the backend mode is `mock`, or in `auto` mode when the backend is unreachable,
// so the overlay always demos.
import { storage } from '#imports';
import type { ActionMessage, ActionResponse, IntentRequest, PageContext, Turn } from '../src/api/types';
import { A2UI_VERSION, CATALOG_ID, type A2uiAction, type A2uiMessage } from '../src/ui/a2ui/protocol';

interface PendingAction {
  surfaceId: string;
  message: string;
  say: string;
}
// Session storage, so a confirm still works after the service worker restarts.
const pendingItem = storage.defineItem<Record<string, PendingAction>>('session:mock-pending', { fallback: {} });

const DAYS = [
  ['sunday', 'sonntag'],
  ['monday', 'montag'],
  ['tuesday', 'dienstag'],
  ['wednesday', 'mittwoch'],
  ['thursday', 'donnerstag'],
  ['friday', 'freitag'],
  ['saturday', 'samstag'],
];

function iso(d: Date): string {
  const pad = (n: number) => String(Math.floor(Math.abs(n))).padStart(2, '0');
  const off = -d.getTimezoneOffset();
  const local = new Date(d.getTime() + off * 60_000).toISOString().slice(0, 19);
  return `${local}${off >= 0 ? '+' : '-'}${pad(off / 60)}:${pad(off % 60)}`;
}

const addMin = (d: Date, min: number) => new Date(d.getTime() + min * 60_000);
const hhmm = (d: Date) => d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
const dayLabel = (d: Date) => d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });

function textOf(ctx: PageContext): string {
  return [ctx.selection?.text, ctx.selection?.element?.text, ctx.gaze?.text].filter(Boolean).join(' ');
}

/** Best-effort date and time from what the user is looking at. */
function guessWhen(text: string): Date {
  const lower = text.toLowerCase();
  const now = new Date();
  const when = new Date(now);
  when.setSeconds(0, 0);
  const dayIdx = DAYS.findIndex((names) => names.some((n) => lower.includes(n)));
  if (dayIdx >= 0) when.setDate(now.getDate() + ((dayIdx - now.getDay() + 7) % 7));
  else if (/\btomorrow\b|\bmorgen\b/.test(lower)) when.setDate(now.getDate() + 1);
  const hm = lower.match(/\b([01]?\d|2[0-3])[:.]([0-5]\d)\b/);
  const ampm = lower.match(/\b(1[0-2]|[1-9])\s*(am|pm)\b/);
  const at = lower.match(/\bat\s+(1[0-2]|[1-9])\b/);
  if (hm) when.setHours(Number(hm[1]), Number(hm[2]));
  else if (ampm) when.setHours((Number(ampm[1]) % 12) + (ampm[2] === 'pm' ? 12 : 0), 0);
  else if (at) when.setHours(Number(at[1]) + (Number(at[1]) < 8 ? 12 : 0), 0);
  else when.setHours(18, 0);
  return when;
}

function guessTitle(ctx: PageContext): string {
  const raw = (ctx.title || ctx.selection?.text || 'Event').replace(/\s*[·|]\s*Luma$/i, '').replace(/\s+/g, ' ').trim();
  return raw.length > 56 ? `${raw.slice(0, 53)}…` : raw;
}

function guessPlace(text: string): string {
  if (/zürich|zurich/i.test(text)) return 'Zürich';
  const m = text.match(/\b(?:in|nach)\s+([A-ZÄÖÜ][\wäöüé-]+)/);
  return m?.[1] ?? 'Zürich';
}

let seq = 0;
const newId = (p: string) => `${p}_mock${Date.now().toString(36)}${seq++}`;
const event = (name: string, action_id: string): A2uiAction => ({ event: { name, context: { action_id } } });

function surface(surfaceId: string, component: string, props: Record<string, unknown>): A2uiMessage[] {
  return [
    { version: A2UI_VERSION, createSurface: { surfaceId, catalogId: CATALOG_ID } },
    { version: A2UI_VERSION, updateComponents: { surfaceId, components: [{ id: 'root', component, ...props }] } },
  ] as A2uiMessage[];
}

export async function mockIntent(req: IntentRequest): Promise<Turn> {
  const ctx = req.context;
  const text = textOf(ctx);
  const intent = req.intent.toLowerCase();
  const when = guessWhen(text);
  const end = addMin(when, 180);
  const title = guessTitle(ctx);
  const place = guessPlace(text);
  const home = 'Winterthur';
  const turn = newId('turn');
  const pending: Record<string, PendingAction> = {};
  const cards: A2uiMessage[] = [];

  const dep = addMin(when, -29);
  const train = () =>
    cards.push(
      ...surface(`${turn}_train`, 'TrainCard', {
        from: home,
        to: `${place} HB`,
        live: false,
        connections: [
          { departure: iso(addMin(dep, -9)), arrival: iso(addMin(dep, 11)), durationMin: 20, transfers: 0, products: ['S12'], platform: '7' },
          { departure: iso(dep), arrival: iso(addMin(dep, 26)), durationMin: 26, transfers: 0, products: ['IC 8'], platform: '4', recommended: true },
          { departure: iso(addMin(dep, 15)), arrival: iso(addMin(dep, 43)), durationMin: 28, transfers: 0, products: ['IR 13'], platform: '3' },
        ],
        openAction: {
          functionCall: {
            call: 'openUrl',
            args: { url: `https://www.sbb.ch/en?von=${encodeURIComponent(home)}&nach=${encodeURIComponent(place)}` },
          },
        },
      }),
    );

  const addId = newId('act');
  let say: string;

  if (/remind|reminder|erinner/.test(intent)) {
    const id = newId('act');
    const at = addMin(dep, -15);
    const surfaceId = `${turn}_reminder`;
    pending[id] = { surfaceId, message: `Reminder set for ${hhmm(at)}.`, say: `Okay, I'll remind you at ${hhmm(at)}.` };
    cards.push(
      ...surface(surfaceId, 'ReminderCard', {
        text: `Leave for ${title}`,
        at: iso(at),
        preview: `Remind you on ${dayLabel(at)} at ${hhmm(at)}: "Leave for ${title}".`,
        confirmAction: event('confirm', id),
        rejectAction: event('reject', id),
      }),
    );
    say = `I can remind you at ${hhmm(at)}, fifteen minutes before your train.`;
  } else if (/mom|mum|tell|message|nachricht/.test(intent)) {
    const id = newId('act');
    const surfaceId = `${turn}_message`;
    pending[id] = { surfaceId, message: 'Message to Mom is ready to send.', say: 'Done. Tap to send it.' };
    cards.push(
      ...surface(surfaceId, 'MessageDraftCard', {
        to: { name: 'Mom', relation: 'mother', channel: 'sms' },
        body: { path: '/draft/body' },
        preview: 'Send an SMS to Mom.',
        sendAction: { event: { name: 'confirm', context: { action_id: id, body: { path: '/draft/body' } } } },
        discardAction: event('reject', id),
      }),
      {
        version: A2UI_VERSION,
        updateDataModel: { surfaceId, path: '/', value: { draft: { body: `Hi Mom, I'll be home around ${hhmm(addMin(end, 40))}.` } } },
      } as A2uiMessage,
    );
    say = 'Here is a draft for Mom. Edit it if you like.';
  } else if (/get there|train|how do i|route|travel|hinkommen|zug/.test(intent)) {
    train();
    say = `Take the IC 8 at ${hhmm(dep)}. You're in ${place} at ${hhmm(addMin(dep, 26))}.`;
  } else if (/add|calendar|save|kalender|eintragen/.test(intent)) {
    const surfaceId = `${turn}_confirm`;
    pending[addId] = { surfaceId, message: `Added "${title}" to your calendar.`, say: 'Done. It is in your calendar.' };
    cards.push(
      ...surface(surfaceId, 'ConfirmCard', {
        title: 'Add to calendar',
        preview: `Create "${title}" ${dayLabel(when)} ${hhmm(when)}-${hhmm(end)} in ${place}.`,
        tool: 'calendar_create',
        confirmAction: event('confirm', addId),
        rejectAction: event('reject', addId),
      }),
    );
    say = 'Add it to your calendar?';
  } else {
    // "Am I free?" and anything else: the full demo turn.
    const eventSurface = `${turn}_event`;
    pending[addId] = {
      surfaceId: eventSurface,
      message: `Added "${title}" and your train to the calendar.`,
      say: 'Done. Both are in your calendar.',
    };
    cards.push(
      ...surface(eventSurface, 'EventCard', {
        title,
        start: iso(when),
        end: iso(end),
        location: place,
        url: ctx.url,
        availability: 'conflict',
        addAction: {
          label: 'Add event + train',
          preview: `Create "${title}" ${dayLabel(when)} ${hhmm(when)}-${hhmm(end)} + "IC 8 ${home} → ${place} HB" ${hhmm(dep)}-${hhmm(addMin(dep, 26))}.`,
          ...event('confirm', addId),
        },
      }),
    );
    const moveId = newId('act');
    const newStart = addMin(when, -85);
    const conflictSurface = `${turn}_conflict`;
    pending[moveId] = {
      surfaceId: conflictSurface,
      message: `Moved "Team sync" to ${hhmm(newStart)}-${hhmm(addMin(newStart, 30))}.`,
      say: `Done. Team sync is now at ${hhmm(newStart)}.`,
    };
    cards.push(
      ...surface(conflictSurface, 'ConflictCard', {
        conflict: { eventId: 'evt_team_sync', title: 'Team sync', start: iso(when), end: iso(addMin(when, 30)), calendar: 'Work' },
        eventTitle: title,
        move: {
          label: `Move Team sync to ${hhmm(newStart)}`,
          preview: `Move "Team sync" from ${hhmm(when)}-${hhmm(addMin(when, 30))} to ${hhmm(newStart)}-${hhmm(addMin(newStart, 30))} on ${dayLabel(when)}.`,
          newStart: iso(newStart),
          newEnd: iso(addMin(newStart, 30)),
          action: event('confirm', moveId),
        },
        skipAction: event('skip', moveId),
        keepAction: event('keep', moveId),
      }),
    );
    train();
    say = `Heads up: Team sync overlaps at ${hhmm(when)}. The ${hhmm(dep)} IC 8 from ${home} gets you there by ${hhmm(addMin(dep, 26))}.`;
  }

  await pendingItem.setValue({ ...(await pendingItem.getValue()), ...pending });
  await new Promise((r) => setTimeout(r, 700));
  return { turn_id: turn, say, source: 'fallback', cards };
}

export async function mockAction(msg: ActionMessage): Promise<ActionResponse> {
  const actionId = String(msg.action.context.action_id ?? '');
  const stored = await pendingItem.getValue();
  const hit = stored[actionId];
  const turn = newId('turn');
  if (!hit) {
    return { turn_id: turn, say: 'That expired.', source: 'fallback', cards: [], action_id: actionId, status: 'not_found' };
  }
  delete stored[actionId];
  await pendingItem.setValue(stored);
  const del = { version: A2UI_VERSION, deleteSurface: { surfaceId: hit.surfaceId } } as A2uiMessage;
  if (msg.action.name !== 'confirm') {
    return {
      turn_id: turn,
      say: msg.action.name === 'keep' ? 'Okay, keeping both.' : 'Okay, nothing changed.',
      source: 'fallback',
      cards: [del],
      action_id: actionId,
      status: 'rejected',
    };
  }
  await new Promise((r) => setTimeout(r, 600));
  return {
    turn_id: turn,
    say: hit.say,
    source: 'fallback',
    cards: [del],
    action_id: actionId,
    status: 'done',
    message: hit.message,
    result: /Mom/.test(hit.message) ? { message_sent: { deep_link: 'sms:+41790000000' } } : {},
  };
}
