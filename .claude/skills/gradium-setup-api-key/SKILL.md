---
name: gradium-setup-api-key
description: Set up and validate a Gradium API key. Use when the user needs to configure Gradium credentials, when any Gradium call fails with 401/403 or "API key is revoked or expired", when GRADIUM_API_KEY is missing from the environment, or when the user mentions getting access to Gradium. Checks whether a working key is already configured first and only walks through setup when needed. Also covers safe key handling for browser apps (short-lived tokens).
license: MIT
compatibility: Requires internet access to gradium.ai and api.gradium.ai.
---

# Gradium API key setup

## Step 0 — check what's already configured

A key may already exist. Check in order: the `GRADIUM_API_KEY`
environment variable, then a `.env` file in the project root. If found,
validate it before doing anything else:

```bash
curl -fsS https://api.gradium.ai/api/usages/credits -H "x-api-key: $GRADIUM_API_KEY"
```

- `{"remaining_credits": ...}` → key works; report the balance and stop.
  Setup is done.
- 401/403 → key is invalid or revoked; continue below.
- Valid over HTTP but a WebSocket rejects with `1008 API key is revoked
  or expired` → the code is almost certainly pointing at the retired
  `eu.api.gradium.ai` host; fix the URL to `api.gradium.ai`
  (or `GRADIUM_MODEL_ENDPOINT=wss://api.gradium.ai/api/speech/asr` for
  the LiveKit plugin), not the key.

## Step 1 — get a key (user does this, not you)

Send the user to their Gradium account at https://gradium.ai (sign in →
API keys). Ask them to create a key and put it in the project's `.env`
themselves:

```
GRADIUM_API_KEY=their_key_here
```

Never ask the user to paste the key into chat, never echo or log a key,
and never commit `.env` (ensure it's in `.gitignore`). If a key ever
appears in chat or a file you're sharing, treat it as leaked and advise
rotating it.

## Step 2 — validate and confirm

Re-read `.env` (treat it as the source of truth), export it into the
environment, and run the credits check above. On success, tell the user
the key works and show the remaining-credits number as proof.

## Browser and mobile apps

The API key must stay server-side. For client WebSockets, mint a
short-lived single-use token on your server and hand that to the
client:

```bash
curl -fS https://api.gradium.ai/api/api-keys/token -H "x-api-key: $GRADIUM_API_KEY"
# -> {"token": "...", "expires_at": "..."}
```

The client connects with `wss://api.gradium.ai/api/speech/tts?token=...`.
The token is consumed on connect — mint one per session, on demand,
behind your own auth.

## Quick reference

- Header: `x-api-key: <key>` (not `Authorization: Bearer`).
- Cheapest validity probe: `GET /api/usages/credits`.
- One global host: `api.gradium.ai`. Anything referencing
  `eu.api.gradium.ai` is stale.
