---
name: gradium-docs
description: Find the right Gradium documentation page for any voice AI task. Use whenever someone needs Gradium docs, asks which Gradium API or transport to use, wants to migrate an existing voice integration from another provider to Gradium, is debugging a Gradium integration and needs the authoritative reference, or asks a Gradium question you can't answer confidently from the other gradium skills. Every Gradium docs page is fetchable as clean markdown — this skill maps tasks to exact URLs so you fetch one page instead of crawling.
license: MIT
compatibility: Requires internet access.
---

# Gradium docs finder

Two agent-friendly properties of docs.gradium.ai — use them instead of
browsing:

1. **`https://docs.gradium.ai/llms.txt`** — the complete index, one
   line per page with a description.
2. **Append `.md` to any docs URL** to get the page as raw markdown,
   e.g. `https://docs.gradium.ai/guides/text-to-speech-rest.md`.

Docs describe current behavior well, but a few wire-level details are
only in the OpenAPI spec
(`https://docs.gradium.ai/api-reference/openapi.json`): multipart field
names, pronunciation rule schemas, exact response codes. When a request
400s/422s against something a guide shows, trust the spec and the error
body over the guide.

## Task → page map (all under `https://docs.gradium.ai/`)

| Task | Page |
| --- | --- |
| First integration, SDK install | `guides/installation.md` |
| TTS: pick REST vs WebSocket | `guides/text-to-speech-overview.md` |
| TTS one-shot / streaming | `guides/text-to-speech-rest.md` / `guides/text-to-speech.md` |
| Voice speed, temperature, similarity | `guides/voice-settings.md` |
| STT batch / realtime | `guides/speech-to-text-rest.md` / `guides/speech-to-text.md` |
| STT language, latency, keywords | `guides/transcription-settings.md` |
| Turn-taking / endpointing / VAD | `guides/recipes/turn-taking.md` |
| Boosting names & jargon | `guides/recipes/keyword-boosting.md` |
| Live speech translation | `guides/speech-to-speech.md` + `guides/speech-to-speech-settings.md` |
| WebSocket lifecycle, multiplexing | `guides/websocket-lifecycle.md`, `guides/multiplexing.md` |
| Browser/mobile auth (tokens) | `guides/browser-websockets.md` |
| LLM → TTS streaming | `guides/recipes/llm-to-tts.md` |
| Mic → STT in the browser | `guides/recipes/browser-microphone-stt.md` |
| Twilio / telephony codecs | `guides/recipes/telephony-audio.md` |
| Voice library & cloning | `guides/voices/{overview,flagship-voices,custom-voices,manage-voices}.md` |
| Pronunciation & text normalization | `guides/text-rewriting.md` + API reference `pronunciations` pages |
| Limits (300s sessions, formats) | `guides/limits.md` |
| Error shapes | `guides/errors.md` |
| Billing / credits | `guides/credits.md` |
| Release notes | `guides/release-notes/2026-08.md` (and siblings) |

## Migrating from another voice API

Purpose-built per-provider guides with endpoint/auth/field mappings
live under `guides/migration/` — start at `guides/migration/index.md`
and pick the one matching the existing integration.

Note: Gradium emits word-level timestamps (`start_s`/`stop_s` on `text`
messages), even where older material describes them as segment-level.

## Agent-framework integrations

`integrations/agent-frameworks/{gradbot,livekit,openclaw,pipecat}.md` —
plus web-search tool integrations under `integrations/web-search/`.
For building complete voice agents with Gradium, prefer the dedicated
gradbot skill/framework (`https://gradium.ai/gradbot`).

## Escalation

If docs and observed API behavior disagree, note the `request_id` from
the `ready` message and contact support@gradium.ai.
