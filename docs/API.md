# Micro Intent API (v1)

This is the contract between the backend, the Chrome extension and the webapp.
Every part is built against this file in parallel, so keep it stable.
Any change to the contract must be documented here (see [Changelog](#changelog)) and called out in the PR description.

## Basics

- Base URL: `http://localhost:8080` locally, the Cloud Run service URL when deployed.
- All bodies are JSON (`Content-Type: application/json`), UTF-8.
- Times are ISO 8601 with offset, e.g. `2026-10-10T18:00:00+02:00`; the backend works in `Europe/Zurich`.
- CORS is open (`*`), so the extension (`chrome-extension://...`) and the webapp can call it directly.
- No auth in v1 (hackathon demo); one shared profile with id `default`.
- The Gemini key lives only in the backend; clients never see it (voice uses [ephemeral tokens](#post-voicetoken)).

## Endpoints at a glance

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/intent` | Page context + spoken/typed intent in, UI-spec card out. Never executes write actions. |
| `POST` | `/confirm` | Human approves (or rejects) one write action by id; only now is it executed. |
| `GET` | `/profile` | Read the user profile. |
| `PUT` | `/profile` | Update the user profile (partial merge). |
| `POST` | `/voice/token` | Short-lived Gemini Live token for voice input in the extension. |
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
      "element": {
        "tag": "div",
        "text": "Saturday, October 10 ...",
        "selector": "main > div.event-time",
        "attributes": { "aria-label": "Event time" }
      }
    },
    "gaze": {
      "text": "Saturday, October 10 · 18:00 - 21:00",
      "selector": "main > div.event-time",
      "x": 412,
      "y": 230,
      "dwell_ms": 900
    },
    "page_text": "Optional visible-text excerpt of the page, max 20000 chars."
  },
  "locale": "en",
  "now": "2026-10-10T14:00:00+02:00"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `intent` | yes | What the user said or typed, verbatim. |
| `context.url` | yes | Page URL. |
| `context.title` | yes | `document.title`. |
| `context.selection` | no | What the user marked. `text` is the selected text; `element` describes the clicked/marked element when there is no text selection. |
| `context.gaze` | no | What the user looked at (eye tracking). Same shape as `selection.element` plus screen coordinates and dwell time. All fields optional. |
| `context.page_text` | no | Extra page text for grounding. Trimmed to 20000 chars server-side. |
| `locale` | no | `en` (default) or `de`. Card texts come back in this language. |
| `now` | no | Client clock; defaults to server time. Lets the demo pin "today". |

At least one of `selection`, `gaze` or `page_text` should be present; with none, the agent only sees URL and title.

### Response: UI-spec card

`/intent` always answers `200` with a card, including on internal errors (then `card_type: "error"`).
Only malformed requests get `422`.

```json
{
  "card_id": "card_7f3a2c",
  "card_type": "event_plan",
  "status": "conflict",
  "title": "Agentic AI Hack Zurich - Demo",
  "subtitle": "Sat 10 Oct · 18:00-21:00 · Zurich",
  "summary": "You have Team sync 18:00-18:30. The IC 5 at 17:02 from Winterthur gets you there by 17:28.",
  "speak": "You have a conflict with Team sync at six. The 17:02 IC from Winterthur gets you there in time.",
  "large_mode": false,
  "source": "agent",
  "sections": [
    {
      "type": "event",
      "title": "Agentic AI Hack Zurich - Demo",
      "start": "2026-10-10T18:00:00+02:00",
      "end": "2026-10-10T21:00:00+02:00",
      "location": "Zurich",
      "url": "https://luma.com/example-event"
    },
    {
      "type": "conflict",
      "title": "Team sync",
      "start": "2026-10-10T18:00:00+02:00",
      "end": "2026-10-10T18:30:00+02:00",
      "calendar": "Work"
    },
    {
      "type": "connections",
      "from": "Winterthur",
      "to": "Zürich HB",
      "items": [
        {
          "departure": "2026-10-10T17:02:00+02:00",
          "arrival": "2026-10-10T17:28:00+02:00",
          "duration_min": 26,
          "transfers": 0,
          "products": ["IC 5"],
          "platform": "4",
          "recommended": true
        }
      ]
    }
  ],
  "actions": [
    {
      "id": "act_9b1e04",
      "label": "Move Team sync to 17:00",
      "kind": "confirm",
      "style": "primary",
      "tool": "calendar_move",
      "preview": "Move \"Team sync\" from 18:00-18:30 to 17:00-17:30 on Sat 10 Oct.",
      "requires_confirmation": true
    },
    {
      "id": "act_c2d871",
      "label": "Add event + travel to calendar",
      "kind": "confirm",
      "style": "secondary",
      "tool": "calendar_create",
      "preview": "Create \"Agentic AI Hack Zurich - Demo\" 18:00-21:00 and \"Train IC 5 Winterthur → Zürich HB\" 17:02-17:28.",
      "requires_confirmation": true
    },
    {
      "id": "act_44aa10",
      "label": "Open SBB timetable",
      "kind": "open_url",
      "style": "secondary",
      "url": "https://www.sbb.ch/en?von=Winterthur&nach=Z%C3%BCrich%20HB",
      "requires_confirmation": false
    },
    {
      "id": "act_0d77e2",
      "label": "Dismiss",
      "kind": "dismiss",
      "style": "ghost",
      "requires_confirmation": false
    }
  ]
}
```

#### Card fields

| Field | Type | Notes |
| --- | --- | --- |
| `card_id` | string | Unique per response. |
| `card_type` | enum | `event_plan`, `travel`, `calendar`, `reminder`, `message_draft`, `shared_slot`, `info`, `error`. Pick a layout/icon by it; all types use the same `sections` rendering. |
| `status` | enum | `ok`, `conflict`, `warning`, `error`. Drives the accent color. |
| `title` | string | Short headline. |
| `subtitle` | string? | One line under the title. |
| `summary` | string | One or two sentences answering the intent. Always present. |
| `speak` | string? | Shorter, speakable variant of `summary` for TTS. |
| `large_mode` | bool | Mirrors `profile.large_mode`: render bigger type, fewer sections, at most two actions visible. |
| `source` | enum | `agent` (Gemini answered live) or `fallback` (scripted demo path because a service failed). Show a subtle badge for `fallback`. |
| `sections` | array | Ordered content blocks, see below. Unknown `type`s must be ignored by clients. |
| `actions` | array | Ordered buttons, see below. |

#### Section types

All fields not marked required may be absent.

| `type` | Fields |
| --- | --- |
| `event` | `title`*, `start`*, `end`, `location`, `url` |
| `conflict` | `title`*, `start`*, `end`*, `calendar` |
| `free` | `text`* (e.g. "You are free 18:00-21:00.") |
| `connections` | `from`*, `to`*, `items`*: list of `{departure*, arrival*, duration_min, transfers, products[], platform, recommended}` |
| `slots` | `title`, `items`*: list of `{start*, end*, label}` (e.g. shared free slots) |
| `message` | `to`*: `{name*, relation, channel, address}`, `body`*, `editable` (bool; edits go back via `/confirm`) |
| `reminder` | `at`*, `text`* |
| `fields` | `items`*: list of `{label*, value*}` generic key-value rows |
| `text` | `text`* (plain text paragraph) |

#### Action kinds

| `kind` | Meaning | Client behaviour |
| --- | --- | --- |
| `confirm` | A write action (calendar create/move, reminder, send message). Always `requires_confirmation: true`. Nothing has happened yet. | Show `preview`, and only after an explicit user tap call `POST /confirm` with the `id`. |
| `open_url` | Open `url` in a new tab. | No backend call. |
| `followup` | Ask a follow-up. Carries `intent` (string). | Call `POST /intent` with this `intent` and the same `context`. |
| `dismiss` | Close the card. | No backend call. Optionally call `/confirm` with `approved: false` for pending confirm actions. |

Action fields: `id`* (unique, stable until confirmed or expired), `label`*, `kind`*, `style` (`primary` \| `secondary` \| `danger` \| `ghost`), `tool` (backend tool name for `confirm`), `preview` (human-readable effect, required for `confirm`), `requires_confirmation`* (bool), `url` (for `open_url`), `intent` (for `followup`), `expires_at` (pending confirm actions expire after 30 minutes).

## POST /confirm

The human checkpoint.
The backend executes a write action only through this endpoint, once per action id.

### Request

```json
{
  "action_id": "act_9b1e04",
  "approved": true,
  "edits": { "body": "Hi Mom, I'll be home around 22:30." }
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `action_id` | yes | `id` of a `confirm` action from an `/intent` card. |
| `approved` | no | Default `true`. `false` cancels the pending action (nothing is executed). |
| `edits` | no | User edits before approval. Supported: `body` for message drafts, `start`/`end` for calendar actions, `text`/`at` for reminders. |

### Response

```json
{
  "action_id": "act_9b1e04",
  "status": "done",
  "message": "Moved \"Team sync\" to 17:00-17:30.",
  "result": { "event_id": "evt_team_sync", "start": "2026-10-10T17:00:00+02:00", "end": "2026-10-10T17:30:00+02:00" },
  "card": { "card_id": "card_...", "card_type": "calendar", "status": "ok", "title": "Done", "summary": "Moved \"Team sync\" to 17:00-17:30.", "sections": [], "actions": [] }
}
```

| `status` | HTTP | Meaning |
| --- | --- | --- |
| `done` | 200 | Executed. `result` holds tool output, `card` is a small result card to render in place. |
| `rejected` | 200 | `approved: false`; nothing executed. |
| `failed` | 200 | Execution failed; `message` says why. The action stays pending and may be retried. |
| `already_done` | 200 | This id was already executed; nothing executed again. |
| `not_found` | 404 | Unknown or expired id. |

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
| `large_mode` | Accessibility mode: large type, fewer choices. Echoed on every card. |
| `locale` | Default card language (`en` or `de`). |

## PUT /profile

Partial merge: send only the fields to change; omitted fields keep their value.
`contacts`, when sent, replaces the whole list.
Returns the full updated profile (same shape as `GET /profile`).

```json
{ "home": "Winterthur", "large_mode": true }
```

## POST /voice/token

Mints a short-lived, single-use Gemini Live auth token so the extension can stream microphone audio straight to Gemini Live without holding the API key.

Request body: `{}` (optional `{ "locale": "de" }`).

```json
{
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
- `/intent` never returns `5xx` for agent or upstream failures; it returns a `fallback` or `error` card instead.

## Changelog

- v1 (2026-10-10): initial contract.
