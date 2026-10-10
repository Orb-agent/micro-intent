# backend

Python FastAPI service behind the Micro Intent clients.
It implements the contract in [`../docs/API.md`](../docs/API.md).

## How a turn works

1. `POST /intent` (or `/intent/stream`) gets the page context and the spoken intent.
2. A Gemini agent (`gemini-3.8-flash`, Interactions API, function calling) reads with tools: `calendar_free_busy`, `sbb_connections`, `shared_free_slot`.
   Today's calendar is preloaded into the prompt to save a round trip.
3. Write tools (`calendar_create`, `calendar_move`, `set_reminder`, `draft_message`) never write: they register a pending action with a server-written preview.
4. The agent ends with `respond(say, cards)`, picking components from the A2UI catalog.
   `app/compose.py` fills them with tool data and guarantees that every conflict, the trains and every pending action get a card.
5. The human taps a button; the client posts the A2UI `action` to `/action` (or `/confirm`), and only then is the action executed, once.

If Gemini fails or takes longer than `MICRO_INTENT_AGENT_TIMEOUT_S` (40 s), the scripted planner in `app/fallback.py` builds the same kind of turn (`source: "fallback"`).
If transport.opendata.ch is down, `sbb_connections` returns a scripted Winterthur - Zürich timetable (`TrainCard.live: false`).

## Run locally

```sh
cd backend
uv venv -p 3.13 .venv && uv pip install -p .venv/bin/python -r requirements-dev.txt
set -a; . ~/.config/micro-intent/gemini.env; set +a   # GEMINI_API_KEY; never commit it
.venv/bin/uvicorn app.main:app --port 8080
```

Without a key (or with `MICRO_INTENT_FORCE_FALLBACK=true`) everything runs on the scripted path.
See [`../.env.example`](../.env.example) for all settings.

## Demo path

```sh
curl -s -X POST localhost:8080/demo/reset
curl -s -X POST localhost:8080/intent -H 'content-type: application/json' -d '{
  "intent": "Am I free, and how do I get there from Winterthur?",
  "context": {"url": "https://luma.com/...", "title": "{Tech: Europe} Agentic AI Hack Zurich · Luma",
              "selection": {"text": "Saturday, October 10 · 18:00 - 21:00 · Zurich"}}
}'
```

Expected: `EventCard` (availability `conflict`, "Add event + train"), `ConflictCard` for the planted "Team sync 18:00-18:30" with a move proposal, `TrainCard` with the recommended IC.

Smoke test (offline, scripted path): `.venv/bin/python -m pytest -q`.

## Calendar

`CALENDAR_SOURCE=mock` (default) seeds a daily "Team sync 18:00-18:30" for the user, plus entries for the contacts `anna` and `mom` (for `shared_free_slot`).
`CALENDAR_SOURCE=google` uses the Google Calendar API behind the same interface, either with an OAuth user token file (`GOOGLE_CALENDAR_TOKEN_FILE`) or with application default credentials.
On Cloud Run the simplest setup is to share a demo calendar with the runtime service account and set `GOOGLE_CALENDAR_ID` to that calendar's id.
Reads fall back to the mock if Google fails; writes do not.

## Deploy

`backend/deploy.sh` deploys to Cloud Run (project `agentic26zrh-2067`, region `europe-west6` by default) from source via Cloud Build, with the key in Secret Manager.
State (pending actions, profile, mock calendar) is in memory, so the service runs with exactly one warm instance.
