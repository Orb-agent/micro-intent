# Micro Intent API (v1)

This is the contract between the backend, the client shell (Chrome extension or desktop app) and the webapp.
Every part is built against this file in parallel, so keep it stable.
Any change to the contract must be documented here (see [Changelog](#changelog)) and called out in the PR description.

## Basics

- Base URL: `http://localhost:8080` locally, the Cloud Run service URL when deployed.
- All bodies are JSON (`Content-Type: application/json`), UTF-8.
- Times are ISO 8601 with offset, e.g. `2026-10-10T18:00:00+02:00`; the backend works in `Europe/Zurich`.
- CORS is open (`*`), so any client shell and the webapp can call it directly.
- No auth in v1 (hackathon demo); one shared profile.
- The Gemini key lives only in the backend; clients never see it (voice uses [ephemeral tokens](#post-voicetoken)).
- Page and screen content is untrusted input: the agent treats it as data, never as instructions, and stays read-only until the user confirms an action.

## Generative UI: A2UI v0.9.1

Cards are [A2UI](https://a2ui.org) v0.9.1 server-to-client messages (`createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`, each with `"version": "v0.9.1"`).
The agent never emits free-form UI: it only picks components from the trusted client catalog below, and the backend fills them with data from its tools.
The client renders them with a React A2UI renderer that registers this catalog.

- `catalogId`: `https://micro-intent.app/a2ui/catalog/v1` (an identifier, not a resolvable URL).
- One card = one surface; the root component of every surface has `id: "root"` and is one of the catalog components.
- Buttons inside components are A2UI actions (`{"event": {"name": ..., "context": {...}}}` for the backend, `{"functionCall": {"call": "openUrl", ...}}` for local ones).
- When the user taps a server action, the client sends the standard A2UI client-to-server `action` message to [`POST /action`](#post-action).

### The turn contract

Every agent turn ends with one internal tool call `respond(say, cards)`; the backend never parses model free text.
Each turn response has the same shape, whether from `/intent`, `/intent/stream` or `/action`:

```json
{
  "turn_id": "turn_3f9a1c",
  "say": "Heads up: Team sync overlaps at six. The 17:31 IC 8 gets you there by 17:57.",
  "source": "agent",
  "cards": [
    { "version": "v0.9.1", "createSurface": { "surfaceId": "turn_3f9a1c_event", "catalogId": "https://micro-intent.app/a2ui/catalog/v1" } },
    { "version": "v0.9.1", "updateComponents": { "surfaceId": "turn_3f9a1c_event", "components": [ { "id": "root", "component": "EventCard", "...": "..." } ] } }
  ]
}
```

| Field | Notes |
| --- | --- |
| `turn_id` | Unique per turn; prefixes all surface ids of the turn. |
| `say` | One short spoken line. The client speaks it (TTS) and shows the Orb in `speaking` state meanwhile. Always present. |
| `source` | `agent` (Gemini answered live) or `fallback` (scripted path because Gemini or a service failed). Show a subtle badge for `fallback`. |
| `cards` | Flat list of A2UI v0.9.1 messages, in order. Feed them to the A2UI message processor as-is. May be empty. |

### Catalog `https://micro-intent.app/a2ui/catalog/v1`

Props marked * are always present.
Action props are A2UI `Action` objects; the backend sets their `context`, so the client only forwards it.

#### Orb

Client-driven assistant indicator (package `thinking-orbs` from libraries.dev/orbs).
The backend does not send Orb surfaces in v1; the client drives the state from the turn lifecycle and the [stream events](#post-intentstream).

| Prop | Notes |
| --- | --- |
| `state`* | `idle`, `listening`, `thinking`, `searching`, `speaking`. |

#### EventCard

The event the user looked at, with availability.

| Prop | Notes |
| --- | --- |
| `title`* | Event title. |
| `start`*, `end` | ISO times. |
| `location`, `url` | Optional. |
| `availability`* | `free`, `conflict` or `unknown`. |
| `addAction` | Optional confirm action: add the event (and the recommended train) to the calendar. Carries `preview`. |

#### ConflictCard

A calendar entry that overlaps the event, with three choices: move, skip, keep.

| Prop | Notes |
| --- | --- |
| `conflict`* | `{ "eventId", "title", "start", "end", "calendar" }`. |
| `eventTitle`* | The event it collides with. |
| `move` | `{ "label", "preview", "newStart", "newEnd", "action" }` - proposal to move the conflicting entry to a free slot; `action` is a confirm action. Absent if no free slot was found. |
| `skipAction`* | Skip the new event (nothing is written). |
| `keepAction`* | Keep both as they are (nothing is written). |

#### TrainCard

Public transport connections (SBB).

| Prop | Notes |
| --- | --- |
| `from`*, `to`* | Station names. |
| `connections`* | List of `{ "departure", "arrival", "durationMin", "transfers", "products": ["IC 8"], "platform", "recommended" }`, at most 4. |
| `live`* | `true` for live SBB data, `false` for the scripted timetable fallback. |
| `openAction`* | Local action `{"functionCall": {"call": "openUrl", "args": {"url": "..."}}}` to the route. |

#### ReminderCard

| Prop | Notes |
| --- | --- |
| `text`*, `at`* | Reminder text and time. |
| `preview`* | What will be written. |
| `confirmAction`*, `rejectAction`* | Server actions. |

#### MessageDraftCard

A message to a contact (e.g. notify family), only a draft until approved.
The body is editable through the data model: the surface's data model holds `/draft/body`, the text field binds to it, and `sendAction` sends the edited body back.

| Prop | Notes |
| --- | --- |
| `to`* | `{ "name", "relation", "channel" }`; `channel` is `sms`, `whatsapp` or `email`. |
| `body`* | `{ "path": "/draft/body" }` (A2UI data binding). |
| `preview`* | What will be sent. |
| `sendAction`*, `discardAction`* | Server actions; `sendAction.event.context.body` is bound to `/draft/body`. |

#### ConfirmCard

Generic human checkpoint for any other write action (e.g. create calendar entries).

| Prop | Notes |
| --- | --- |
| `title`* | Short label, e.g. "Add to calendar". |
| `preview`* | Exactly what will be written. |
| `tool`* | Backend tool, e.g. `calendar_create`. |
| `confirmAction`*, `rejectAction`* | Server actions. |

#### Server action names

| `event.name` | Meaning | `context` |
| --- | --- | --- |
| `confirm` | Human approves a write action; only now is it executed. | `action_id`*, optional edits (`body`, `start`, `end`, `text`, `at`). |
| `reject` | Human declines a write action; nothing is executed. | `action_id`*. |
| `skip` | ConflictCard: skip the new event. | `action_id` of the move proposal (rejected). |
| `keep` | ConflictCard: keep both. | `action_id` of the move proposal (rejected). |

### Example: demo turn

Intent "Am I free, and how do I get there from Winterthur?" on the hackathon's Luma page (abridged):

```json
{
  "turn_id": "turn_3f9a1c",
  "say": "Heads up: Team sync overlaps at six. The 17:31 IC 8 from Winterthur gets you there by 17:57.",
  "source": "agent",
  "cards": [
    { "version": "v0.9.1", "createSurface": { "surfaceId": "turn_3f9a1c_conflict", "catalogId": "https://micro-intent.app/a2ui/catalog/v1" } },
    { "version": "v0.9.1", "updateComponents": { "surfaceId": "turn_3f9a1c_conflict", "components": [ {
      "id": "root",
      "component": "ConflictCard",
      "conflict": { "eventId": "evt_team_sync_20261010", "title": "Team sync", "start": "2026-10-10T18:00:00+02:00", "end": "2026-10-10T18:30:00+02:00", "calendar": "Work" },
      "eventTitle": "Agentic AI Hack Zurich",
      "move": {
        "label": "Move Team sync to 16:30",
        "preview": "Move \"Team sync\" from 18:00-18:30 to 16:30-17:00 on Sat 10 Oct.",
        "newStart": "2026-10-10T16:30:00+02:00",
        "newEnd": "2026-10-10T17:00:00+02:00",
        "action": { "event": { "name": "confirm", "context": { "action_id": "act_9b1e04" } } }
      },
      "skipAction": { "event": { "name": "skip", "context": { "action_id": "act_9b1e04" } } },
      "keepAction": { "event": { "name": "keep", "context": { "action_id": "act_9b1e04" } } }
    } ] } },
    { "version": "v0.9.1", "createSurface": { "surfaceId": "turn_3f9a1c_train", "catalogId": "https://micro-intent.app/a2ui/catalog/v1" } },
    { "version": "v0.9.1", "updateComponents": { "surfaceId": "turn_3f9a1c_train", "components": [ {
      "id": "root",
      "component": "TrainCard",
      "from": "Winterthur",
      "to": "Zürich HB",
      "live": true,
      "connections": [
        { "departure": "2026-10-10T17:31:00+02:00", "arrival": "2026-10-10T17:57:00+02:00", "durationMin": 26, "transfers": 0, "products": ["IC 8"], "platform": "4", "recommended": true }
      ],
      "openAction": { "functionCall": { "call": "openUrl", "args": { "url": "https://www.google.com/maps/dir/?api=1&origin=Winterthur&destination=Z%C3%BCrich+HB&travelmode=transit" } } }
    } ] } }
  ]
}
```

## Endpoints at a glance

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/intent` | Page context + intent in, one turn (`say` + A2UI `cards`) out. Never executes write actions. |
| `POST` | `/intent/stream` | Same, as Server-Sent Events with orb states and a filler line while tools run. |
| `POST` | `/action` | A2UI client-to-server `action` message (confirm / reject / skip / keep). The human checkpoint. |
| `POST` | `/confirm` | Shorthand for `/action` with a plain `{ "action_id", "approved", "edits" }` body. |
| `GET` | `/profile` | Read the user profile. |
| `PUT` | `/profile` | Update the user profile (partial merge). |
| `POST` | `/voice/token` | Short-lived Gemini Live token for voice input. |
| `GET` | `/health` | Liveness plus which sources are live or mocked. |
| `POST` | `/demo/reset` | Reset mock calendar, pending actions and reminders to the seeded demo state. |

## POST /intent

### Request

```json
{
  "intent": "Am I free, and how do I get there from Winterthur?",
  "context": {
    "url": "https://luma.com/example-event",
    "title": "{Tech: Europe} Agentic AI Hack Zurich - Luma",
    "selection": {
      "text": "Saturday, October 10 · 18:00 - 21:00 · Zurich",
      "element": { "tag": "div", "text": "Saturday, October 10 ...", "selector": "main > div.event-time", "attributes": { "aria-label": "Event time" } }
    },
    "gaze": { "text": "Saturday, October 10 · 18:00 - 21:00", "selector": "main > div.event-time", "x": 412, "y": 230, "dwell_ms": 900 },
    "page_text": "Optional visible-text excerpt of the page or screen, max 20000 chars."
  },
  "locale": "en",
  "now": "2026-10-10T14:00:00+02:00"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `intent` | yes | What the user said or typed, verbatim. |
| `context.url` | yes | Page URL (or app/window name in a desktop shell). |
| `context.title` | yes | Page or window title. |
| `context.selection` | no | What the user marked. `text` is the selected text; `element` describes the marked element when there is no text selection. |
| `context.gaze` | no | What the user looked at (eye tracking). All fields optional. |
| `context.page_text` | no | Extra page/screen text for grounding. Trimmed to 20000 chars server-side. |
| `locale` | no | `en` (default from profile) or `de`. `say` and card texts come back in this language. |
| `now` | no | Client clock; defaults to server time. Lets the demo pin "today". |

### Response

A [turn](#the-turn-contract).
`/intent` always answers `200` with a turn, including on internal errors (then a fallback or error turn).
Only malformed requests get `422`.

## POST /intent/stream

Same request as `/intent`; the response is `text/event-stream` with these events (each `data:` is JSON):

| `event:` | `data` | Client behaviour |
| --- | --- | --- |
| `orb` | `{ "state": "thinking" \| "searching" }` | Set the Orb state. |
| `filler` | `{ "say": "Checking your calendar and trains..." }` | Speak/show the filler line while tools run. |
| `turn` | A full [turn](#the-turn-contract). | Render `cards`, speak `say`, Orb to `speaking`. Last event. |

Order: `orb thinking` → `filler` → `orb searching` → `turn`.
Use it from `fetch` with a streaming reader (EventSource cannot POST).

## POST /action

The human checkpoint.
The backend executes a write action only through this endpoint (or `/confirm`), once per action id.

### Request: A2UI v0.9.1 client-to-server message

```json
{
  "version": "v0.9.1",
  "action": {
    "name": "confirm",
    "surfaceId": "turn_3f9a1c_conflict",
    "sourceComponentId": "root",
    "timestamp": "2026-10-10T14:00:12Z",
    "context": { "action_id": "act_9b1e04" }
  }
}
```

### Response

A [turn](#the-turn-contract) plus the outcome:

```json
{
  "turn_id": "turn_77d0b2",
  "say": "Done. Team sync is now at 16:30.",
  "source": "agent",
  "cards": [
    { "version": "v0.9.1", "deleteSurface": { "surfaceId": "turn_3f9a1c_conflict" } }
  ],
  "action_id": "act_9b1e04",
  "status": "done",
  "message": "Moved \"Team sync\" to 16:30-17:00.",
  "result": { "event": { "id": "evt_team_sync_20261010", "title": "Team sync", "start": "2026-10-10T16:30:00+02:00", "end": "2026-10-10T17:00:00+02:00" } }
}
```

| `status` | HTTP | Meaning |
| --- | --- | --- |
| `done` | 200 | Executed; the surface that carried the action is deleted (`deleteSurface`). For `draft_message`, `result.message_sent.deep_link` is an `sms:`/`wa.me`/`mailto:` link the client may open to actually send. |
| `rejected` | 200 | `reject`, `skip` or `keep`; nothing executed; the surface is deleted. |
| `failed` | 200 | Execution failed; `message` says why. The action stays pending and may be retried. |
| `already_done` | 200 | This id was already handled; nothing executed again. |
| `not_found` | 404 | Unknown or expired id (pending actions expire after 30 minutes). |

## POST /confirm

Shorthand for clients without an A2UI action message at hand; same response as `/action`.

```json
{ "action_id": "act_9b1e04", "approved": true, "edits": { "body": "Hi Mom, I'll be home around 22:30." } }
```

`approved: false` equals `reject`.

## GET /profile

```json
{
  "name": "Batu",
  "home": "Winterthur",
  "transport": "public",
  "contacts": [
    { "id": "mom", "name": "Mom", "relation": "mother", "channel": "sms", "address": "+41790000000" }
  ],
  "large_mode": false,
  "locale": "en"
}
```

| Field | Notes |
| --- | --- |
| `name` | Display name. |
| `home` | Home town or station, used as default origin for travel ("from home"). |
| `transport` | `public` (default), `car`, `bike`, `walk`. Only `public` gets live connections in v1. |
| `contacts` | People the agent may draft messages to ("tell my mom"). `channel`: `sms`, `whatsapp`, `email`. |
| `large_mode` | Accessibility mode: the client renders large type and fewer choices. |
| `locale` | Default language (`en` or `de`). |

## PUT /profile

Partial merge: send only the fields to change; omitted fields keep their value.
`contacts`, when sent, replaces the whole list.
Returns the full updated profile (same shape as `GET /profile`).

```json
{ "home": "Winterthur", "large_mode": true }
```

## POST /voice/token

Voice sits behind one client-side interface so the provider can change (Gemini Live now, Gradium STT/TTS possible).
This endpoint serves the Gemini Live provider: it mints a short-lived, single-use auth token so the client streams microphone audio straight to Gemini Live without holding the API key.

Request body: `{}` (optional `{ "locale": "de" }`).

```json
{
  "provider": "gemini-live",
  "token": "auth_tokens/abc123...",
  "model": "gemini-3.8-live",
  "api_version": "v1alpha",
  "expires_at": "2026-10-10T14:30:00Z",
  "new_session_expires_at": "2026-10-10T14:01:00Z"
}
```

Client usage (JS SDK `@google/genai`):

```js
const { token, model, api_version } = await (await fetch(`${API}/voice/token`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" })).json();
const ai = new GoogleGenAI({ apiKey: token, httpOptions: { apiVersion: api_version } });
const session = await ai.live.connect({ model, config: { responseModalities: ["TEXT"], inputAudioTranscription: {} }, callbacks: { /* ... */ } });
```

The token allows one session start within about a minute (`new_session_expires_at`) and that session may run until `expires_at`.
Use the input transcription as the `intent` for `POST /intent`.
Returns `503` with `{ "detail": "..." }` if the backend has no Gemini key; the client should then fall back to typed input or the Web Speech API.

## GET /health

```json
{ "ok": true, "version": "0.1.0", "model": "gemini-3.8-flash", "calendar": "mock", "gemini": true, "force_fallback": false }
```

## POST /demo/reset

Resets the mock calendar (back to the planted "Team sync 18:00-18:30" conflict), drops pending actions, reminders and sent messages.
Returns `{ "ok": true }`.
Call it before each demo run.

## Errors

- `422`: request validation failed (FastAPI default body: `{ "detail": [...] }`).
- `404`: unknown resource (e.g. action id).
- `503`: a required backend secret is missing (voice token only).
- `/intent` never returns `5xx` for agent or upstream failures; it returns a fallback or error turn instead.

## Changelog

- v1 (2026-10-10): initial contract.
- v1 (2026-10-10, before any implementation): cards switched from a home-made UI spec to A2UI v0.9.1 with a custom catalog; every turn is `respond(say, cards)`; added `/intent/stream` (orb states + filler) and `/action` (A2UI action messages); `/confirm` kept as shorthand; voice token gained `provider`.
