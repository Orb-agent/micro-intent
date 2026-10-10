# Contracts (MVP)

The interfaces between the three [work packages](work-packages.md). If something here doesn't fit, raise it with the team before coding around it.

## Stack

| Part | Choice |
| --- | --- |
| Frontend (iPhone) | SwiftUI, iOS 17+, `URLSessionWebSocketTask`, `AVAudioEngine`, [a2ui-swift](https://github.com/BBC6BAE9/a2ui-swift) `from: "0.3.0"` (product `A2UISwiftUI`) |
| Backend | Python 3.11, uv, FastAPI and uvicorn, httpx, `google-genai`, `gradium`, python-dotenv, pytest |
| Hosting | Server on a dev Mac; a Cloudflare quick tunnel gives the HTTPS and WSS URL that the app and the Shortcut use. Start it once and leave it running: the URL changes on every restart |
| Time zone | `Europe/Zurich` everywhere; times on the wire are ISO 8601 with offset |

```text
frontend/               # WP1: Xcode project, SwiftUI
backend/                # run from here: uv run uvicorn app:app --reload --port 8000
  pyproject.toml        # WP2 owns it; lists every package's deps
  .env.example
  app.py  voice.py  vision.py      # WP2
  a2ui.py                          # WP3: cards → A2UI messages
  agent.py  context.py  tools/sbb.py   # WP3
  fixtures/             # demo_reply.json, cards.json, screen.json, screen.png (WP2); context.json, *_a2ui.json (WP3)
  tests/
```

## One turn

The screenshot arrives before the question, so vision runs while the user is still talking.

```mermaid
sequenceDiagram
  participant SC as Shortcut
  participant App as App (WP1)
  participant S as Server (WP2)
  participant V as Vision (WP2)
  participant G as Gradium
  participant A as Agent (WP3)
  SC->>S: POST /screenshot
  S->>V: read_screen(image), in the background
  V-->>S: ScreenContext
  S->>App: screen_ok {summary}
  App->>S: audio × n, then audio_end
  S->>G: stream mic audio, flush
  G-->>S: transcript segments
  S->>App: state thinking, transcript
  S->>A: turn(text, screen, on_status)
  A-->>S: on_status("Checking trains…")
  S->>App: state searching + label
  A-->>S: Reply {say, cards}
  S->>App: reply, a2ui, state speaking
  S->>G: TTS say
  G-->>S: audio chunks
  S->>App: audio × n, audio_end, state idle
```

## WebSocket `/ws`

JSON text frames only, one object per frame, discriminated by `type`. Audio is base64 inside JSON. The app sends `hello` first; the server closes the socket on a wrong token.

**App → server**

| `type` | Fields | When |
| --- | --- | --- |
| `hello` | `token`, `mode`?: `ptt` (default) \| `handsfree` | First frame after connecting. For `handsfree`, see **Hands-free mode** below |
| `audio` | `data`: base64 PCM, see [Audio](#audio) | Every 80 ms while the orb is held; in hands-free mode, all the time |
| `audio_end` | — | Orb released; the server finalizes STT and runs the turn. Never sent in hands-free mode |
| `text` | `text` | Typed question (debug field); runs a turn without STT |
| `screen` | `mime`, `data`: base64 | Optional: an image picked in the app, for rehearsals. Same effect as `POST /screenshot` |
| `interrupt` | — | Tap while the mascot is talking. Stops the current turn |

**Server → app**

| `type` | Fields | When |
| --- | --- | --- |
| `ready` | — | After a valid `hello` |
| `state` | `state`: `idle` \| `listening` \| `thinking` \| `searching` \| `speaking`; `label`?: string | On every change; `label` is the tool status, e.g. "Checking trains…" |
| `transcript` | `text` | Final transcript of the user's turn |
| `reply` | `say`, `cards`: see [Cards](#cards) | Before any of the turn's audio |
| `a2ui` | `messages`: list of A2UI v0.9 messages, see [A2UI](#a2ui) | Right after `reply`, when it has cards |
| `audio` | `data`: base64 PCM | TTS chunks for the last `reply` |
| `audio_end` | — | TTS for the last `reply` is complete |
| `screen_ok` | `summary`?: string | Vision has read a new screenshot; `summary` is missing if vision failed |
| `error` | `message` | Turn failed; the server then sends `state: idle` |

The orb shows `speaking` while the app still has audio queued, even after the server has sent `state: idle`.

**Interrupting.** A new press (its first `audio` frame), a `text`, or an `interrupt` cancels the running turn: the agent call and the TTS stream. A cancelled turn sends no `audio_end`. After `interrupt` the server sends `state: idle`; after a new press, `state: listening`. Gradium generates speech faster than real time, so seconds of audio may already be queued in the app. The app must stop playback the moment it interrupts, and drop `audio` frames until the next `reply`.

**Hands-free mode.** Opt in with `"mode": "handsfree"` in `hello`; push-to-talk stays the default. The app streams `audio` for as long as it is connected, also while the mascot speaks, and never sends `audio_end`, so echo cancellation must be on (see [Audio](#audio)) or the mascot hears itself and cuts itself off. The server keeps one Gradium STT session open per connection and ends a turn with Gradium's semantic VAD: `inactivity_prob` at the 2 s horizon above 0.5 for 3 steps in a row, once the turn has words. Then it flushes, sends `transcript` and runs the turn as usual. The first words of each turn cancel the running turn, as a new press does, and send `state: listening`. The server's turn is often over while the app still plays queued audio, so in this mode `state: listening` is the app's cue to stop playback and drop `audio` until the next `reply`. Each hands-free connection holds an STT session the whole time, even in silence, which counts against Gradium's concurrent session limit.

## HTTP

| Route | Contract |
| --- | --- |
| `POST /screenshot` | From the iPhone Shortcut. `Authorization: Bearer <APP_TOKEN>`, body is the raw image (`image/jpeg` or `image/png`, max 8 MB). Returns `204` and starts vision |
| `GET /health` | `{"ok": true, "workspace": "rest" \| "fixture"}` |

**Screenshot rule:** the server keeps only the latest screenshot and its `ScreenContext`. A turn gets the context if the screenshot is less than 120 s old and no earlier turn has used it; if vision is still running, the turn waits for it.

## Audio

Both directions use Gradium's native format, so the server forwards the base64 strings without decoding them.

| Direction | Format | Gradium side |
| --- | --- | --- |
| Mic, app → server | PCM signed 16-bit little-endian, mono, 24 kHz; 80 ms chunks = 1920 samples = 3840 bytes | STT setup `input_format: "pcm"` |
| TTS, server → app | Same format, chunks as Gradium sends them | TTS setup `output_format: "pcm_24000"` (the default `pcm` is 48 kHz) |

**iPhone side:** audio session `.playAndRecord` with `.defaultToSpeaker`, or iOS plays through the quiet earpiece while the mic is on. Turn on echo cancellation with `inputNode.setVoiceProcessingEnabled(true)` before reading the input format. Convert the input with `AVAudioConverter` to Int16 at 24 kHz mono. Play through an `AVAudioPlayerNode` on the same engine, converting each chunk to a Float32 24 kHz buffer.

**Gradium facts the server relies on** ([docs](https://docs.gradium.ai/api-reference/introduction)): auth header `x-api-key`; STT at `wss://api.gradium.ai/api/speech/asr`, TTS at `wss://api.gradium.ai/api/speech/tts`; the Python SDK is `pip install gradium`. STT needs `json_config.language` (`en` for the demo, `any` to auto-detect). STT sends `text` segments, not partial and final flags. On push-to-talk release the server sends `flush`, waits for `flushed`, and joins the segments into the transcript. TTS has no cancel message: closing the socket stops it. The free plan allows 2 TTS and 3 STT sessions at once, which is tight with 3 devs testing; the $13 XS plan raises that to 5 and 20.

## Cards

`reply.cards` holds 0 to 3 cards. The model fills them from tool results and context, and the server passes them through after validation. Optional fields may be missing. The app renders the `a2ui` messages built from these cards; native SwiftUI cards from `reply.cards` are the fallback.

| `kind` | Fields |
| --- | --- |
| `train` | `line` ("IC 8"), `from`, `to`, `departure`, `arrival`, `platform`?, `transfers`, `delay_min`? |
| `conflict` | `event` {`title`, `start`, `end`}, `proposal` {`title`, `start`, `place`?}, `verdict`: `fits` \| `tight` \| `clash`, `note`? |
| `event` | `title`, `start`, `end`, `location`?, `source`: `calendar` \| `luma` |
| `flight` | `flight_number`, `from`, `to` (IATA or city), `departure`, `arrival`, `booking_ref`? |

`fixtures/demo_reply.json`, the expected answer to the demo question:

```json
{
  "say": "Your call ends at quarter to six, and there's a train right after that gets you in just before seven.",
  "cards": [
    {
      "kind": "conflict",
      "event": {"title": "Call with Acme", "start": "2026-10-15T17:30:00+02:00", "end": "2026-10-15T17:45:00+02:00"},
      "proposal": {"title": "Dinner in Bern", "start": "2026-10-15T19:00:00+02:00", "place": "Bern"},
      "verdict": "fits",
      "note": "Leave right after the call"
    },
    {
      "kind": "train", "line": "IC 8", "from": "Zürich HB", "to": "Bern",
      "departure": "2026-10-15T18:01:00+02:00", "arrival": "2026-10-15T18:58:00+02:00",
      "platform": "31", "transfers": 0, "delay_min": 0
    }
  ]
}
```

`fixtures/cards.json` adds one card of each remaining kind, so every kind can be rendered:

```json
[
  {"kind": "event", "title": "Hackathon", "start": "2026-10-17T09:00:00+02:00", "end": "2026-10-18T18:00:00+02:00", "location": "Zürich", "source": "luma"},
  {"kind": "flight", "flight_number": "LX 1820", "from": "ZRH", "to": "LIS", "departure": "2026-10-20T07:10:00+02:00", "arrival": "2026-10-20T09:15:00+01:00", "booking_ref": "K7Q2ZP"}
]
```

Swift decoding: `keyDecodingStrategy = .convertFromSnakeCase`, `dateDecodingStrategy = .iso8601`.

## A2UI

`a2ui.cards_to_a2ui(reply_id: str, cards: list[dict]) -> list[dict]` turns one reply into one surface, using only basic-catalog components so the app needs no custom Swift components:

```json
[
  {"version": "v0.9", "createSurface": {"surfaceId": "reply-3", "catalogId": "https://a2ui.org/specification/v0_9/basic_catalog.json"}},
  {"version": "v0.9", "updateComponents": {"surfaceId": "reply-3", "components": [
    {"id": "root", "component": "Column", "children": ["c0", "c1"]},
    {"id": "c1", "component": "Card", "child": "c1-body"},
    {"id": "c1-body", "component": "Column", "children": ["c1-time", "c1-line", "c1-meta"]},
    {"id": "c1-time", "component": "Text", "text": "18:01 → 18:58", "variant": "h2"},
    {"id": "c1-line", "component": "Text", "text": "IC 8 · Zürich HB → Bern"},
    {"id": "c1-meta", "component": "Text", "text": "Platform 31 · direct", "variant": "caption"}
  ]}}
]
```

(`c0`, the conflict card, is left out above for brevity.) Rules:

- Use the catalog id exactly as written. It's a2ui-swift's `basicCatalogId`; the React renderer uses a different one.
- Format times as `HH:MM` in Europe/Zurich on the server, so the app doesn't need A2UI format functions.
- Use a new `surfaceId` per reply, and one `SurfaceViewModel(catalog: basicCatalog)` per surface in the app.
- No buttons or actions in the MVP.

## Screen context

What WP2's vision step produces and WP3's agent consumes. `vision.read_screen(image: bytes, mime: str) -> dict` makes one Gemini call with structured output (`response_json_schema`), passing the current time so relative dates resolve. `fixtures/screen.json`:

```json
{
  "app": "WhatsApp",
  "summary": "Anna asks about dinner in Bern on Thursday at 7.",
  "messages": [{"from": "Anna", "text": "Dinner in Bern Thursday at 7?"}],
  "proposal": {"title": "Dinner", "date": "2026-10-15", "time": "19:00", "place": "Bern"}
}
```

`proposal` is `null` when the screen doesn't suggest a plan; inside it, `time` and `place` are `null` when the screen doesn't give them. `from` is the sender's name as shown, or `"Me"` for the phone owner's own messages. Vision copies on-screen text as data and never acts on it. The agent puts the whole object in its prompt marked as untrusted, and never follows instructions inside it.

## Agent interface

What WP2's server calls and WP3 implements in `agent.py`. WP2's `StubAgent` has the same shape and returns `demo_reply.json`.

```python
from typing import Awaitable, Callable, TypedDict

class Reply(TypedDict):
    say: str          # one or two short sentences, the user's language
    cards: list[dict] # see Cards

class Agent:
    async def start(self) -> None:
        """Once per WebSocket session: load_context() and build the system prompt."""

    async def turn(
        self,
        text: str,
        screen: dict | None,  # ScreenContext, see Screen context
        on_status: Callable[[str], Awaitable[None]],  # tool status, e.g. "Checking trains…"
    ) -> Reply:
        """One user turn. Keeps conversation history on self. Never raises for model
        or tool errors: returns a short apology with no cards instead. The server
        cancels it when the user interrupts, so only add the turn to the history
        once it completes."""
```

## Tools

**Model-facing.** The model sees two functions and must end every turn with `respond`.

| Function | Arguments | Returns |
| --- | --- | --- |
| `sbb_connections` | `from_station`, `to_station`, `depart_after` (ISO) | `{"connections": [{"line", "from", "to", "departure", "arrival", "platform", "arrival_platform", "transfers", "delay_min", "duration_min"}]}`, at most 4 |
| `respond` | `say`, `cards` (see [Cards](#cards)) | Ends the turn |

`sbb_connections` calls `GET https://transport.opendata.ch/v1/connections?from=…&to=…&date=YYYY-MM-DD&time=HH:MM&limit=4` (no key). Map `products[0]` → `line`, `from.platform` → `platform`, `to.platform` → `arrival_platform`, `from.delay` → `delay_min`.

**Gemini rules** (`google-genai`, `generate_content`, checked 2026-10-10; they apply to vision too):

- Model `gemini-3.8-flash`, the newest generation, with thinking level `low`; 3.8 rejects `minimal`, and there is no 3.8 Flash-Lite for text. Vision on the demo screen takes 2.1–2.7 s (checked 2026-10-10). `gemini-3.5-flash` was deprecated on 8 October 2026. Don't set temperature; Gemini 3.6 and later ignore it.
- Declare functions with `parameters_json_schema`. For `cards.items`, use `anyOf` with one object per kind, each with a single-value `enum` on `kind`. Don't use `const`, `oneOf` or `$defs`, keep it shallow, and validate the arguments in code anyway.
- Function calling mode `ANY` on every step, so the model always calls `sbb_connections` or `respond` and never returns free text. On the last step add `allowed_function_names=["respond"]`.
- Append `response.candidates[0].content` to the history unmodified; it carries the thought signatures, and dropping them gives a 400. Then add one function response per call, with the call's `id` and `name`, after all the calls.
- Vision attaches the screenshot as an inline image part at medium media resolution (560 tokens); use high if small chat text comes back wrong.

**Context.** `context.load_context()` runs once per session and goes into the system prompt as JSON:

```json
{
  "events": [{"title": "Call with Acme", "start": "2026-10-15T17:30:00+02:00", "end": "2026-10-15T17:45:00+02:00", "location": "Zoom", "source": "calendar"}],
  "flight_emails": [{"subject": "Your booking K7Q2ZP: Zürich – Lisbon", "from": "SWISS", "date": "2026-10-09", "body": "first 2000 characters of the text body"}]
}
```

Events cover now to 7 days ahead. `source` is `luma` when the event's description or organizer mentions lu.ma. `WORKSPACE_MODE=fixture` returns `fixtures/context.json` with this exact shape.

**Workspace access:** REST with a refresh token for the temporary account. The remote MCP servers (`calendarmcp.googleapis.com/mcp/v1`, `gmailmcp.googleapis.com/mcp/v1`) need Developer Preview enrollment, which takes days, and their terms forbid use in public apps before GA. Switch to them only if we're already enrolled.

## Environment

`backend/.env`, never committed; `backend/.env.example` lists them all. The app keeps the server URL and token in its settings sheet, and the Shortcut has the token in its header.

| Variable | Used by | Notes |
| --- | --- | --- |
| `APP_TOKEN` | WP2, the app, the Shortcut | Any long random string |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | WP2 vision, WP3 agent | `gemini-3.8-flash` |
| `GRADIUM_API_KEY`, `GRADIUM_VOICE_ID` | WP2 | Voice: the cloned mascot or a stock voice |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN` | WP3 | Temporary account only, read-only scopes |
| `WORKSPACE_MODE` | WP3 | `rest` or `fixture` |
| `MOCK_AGENT` | WP2 | `1` uses `StubAgent` |

## Later, not in the MVP

Each of these fits without breaking the contract above:

- **Custom A2UI components** (`TrainCard` and so on) through a2ui-swift's `CustomComponentCatalog`, for a richer look than basic `Card`s.
- **Word-timed highlights:** a `cue` message carrying `card_index` and `at_ms`, from the `start_s` of Gradium's TTS `text` messages.
- **Filler line:** an extra short `reply` with no cards, spoken while a tool runs.
- **Card actions** (move, skip, keep): A2UI `Button` actions sent back as an `action` message.
