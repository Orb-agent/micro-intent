---
name: gradium-api
description: Integrate the Gradium voice API (text-to-speech, speech-to-text, speech-to-speech translation, voice cloning, pronunciation dictionaries) with direct HTTP or WebSocket calls — no SDK required. Use whenever the user wants to call Gradium from curl, JavaScript/TypeScript, Go, Rust, or any language without an official SDK, from an edge runtime that cannot install packages, or explicitly asks for raw REST/WebSocket code. Also use as the wire-level reference when debugging any Gradium integration, including SDK-based ones — this skill documents the exact endpoints, auth, message grammar, and error shapes. For Python SDK code, prefer the gradium-sdk skill.
license: MIT
compatibility: Requires internet access and a Gradium API key (GRADIUM_API_KEY).
metadata: {"openclaw": {"requires": {"env": ["GRADIUM_API_KEY"]}, "primaryEnv": "GRADIUM_API_KEY"}}
---

# Gradium API (raw HTTP / WebSocket)

Gradium is a low-latency voice AI platform: streaming text-to-speech,
real-time speech-to-text with semantic VAD, live speech-to-speech
translation, and voice cloning. Languages: `en`, `fr`, `de`, `es`, `pt`.

## Base URLs and auth

| Transport | URL |
| --- | --- |
| REST | `https://api.gradium.ai/api` |
| WebSocket | `wss://api.gradium.ai/api/speech/{tts\|asr\|s2s}` |

Every server-side request authenticates with the **`x-api-key` header**
(not `Authorization: Bearer`). Read the key from the `GRADIUM_API_KEY`
env var; never hardcode it. Browser/mobile clients must never see the
API key — exchange it server-side for a short-lived token
(`GET /api/api-keys/token`) and connect with `?token=...` instead.

There is exactly one global host. If old code or a plugin references
`eu.api.gradium.ai`, replace it — the regional split is retired, and the
stale host fails WebSocket auth with a misleading
`1008 API key is revoked or expired` even when the key is valid.

## Choosing an endpoint

| You have | You want | Use |
| --- | --- | --- |
| A finished text block | An audio file | `POST /api/post/speech/tts` with `only_audio: true` |
| Text arriving incrementally (LLM tokens) | Audio ASAP | TTS WebSocket |
| A complete audio file | A transcript | `POST /api/post/speech/asr` |
| Live audio (mic, telephony) | Live transcript + turn-taking | STT WebSocket |
| Live audio in language A | Live audio in language B | S2S WebSocket (WebSocket only, no REST) |

## TTS: one-shot POST

```bash
curl -fS -X POST https://api.gradium.ai/api/post/speech/tts \
  -H "x-api-key: $GRADIUM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello from Gradium.", "voice_id": "YTpq7expH9539ERJ",
       "output_format": "wav", "only_audio": true}' \
  > output.wav
```

- `only_audio: true` → response body is raw audio bytes in
  `output_format`. Easiest "text in, file out" path.
- `only_audio: false` (or omitted) → response is newline-delimited JSON
  (NDJSON) using the same message types as the WebSocket (`ready`,
  `audio` with base64 payload, `text` with word timestamps, `error`,
  `end_of_stream`). Good for prototyping streaming handling with plain
  HTTP.
- Optional body fields: `model_name` (default `"default"`),
  `json_config` (voice settings object — accepted in the body or as a
  URL-encoded JSON string in the `json_config` query parameter; both
  work, the docs only show the query form).
- Output formats: `wav` (48 kHz 16-bit mono), `opus` (Ogg), `pcm`
  (48 kHz), `pcm_8000|16000|22050|24000|44100|48000`, `ulaw_8000`,
  `alaw_8000`.

Voice IDs come from the flagship catalog or your cloned voices — see the
gradium-voice-cloning skill. Voice tuning (`temp`, `cfg_coef`,
`padding_bonus`, `rewrite_rules`) and the `<flush>` / `<break time="1.5s" />`
inline tags are covered in the gradium-text-to-speech skill.

## STT: one-shot POST

Send raw audio bytes as the body; the response streams NDJSON.

```bash
curl -fS -X POST 'https://api.gradium.ai/api/post/speech/asr?json_config=%7B%22language%22%3A%22en%22%7D' \
  -H "x-api-key: $GRADIUM_API_KEY" \
  -H "Content-Type: audio/wav" \
  --data-binary @input.wav
```

- `Content-Type` declares the input format: `audio/wav`, `audio/pcm`,
  `audio/ogg` (Opus). For raw PCM variants use the `input_format` query
  parameter (`pcm_16000`, `ulaw_8000`, ...). Bare `pcm` means 24 kHz
  16-bit signed mono.
- Advanced options go in the `json_config` **query parameter** as a
  URL-encoded JSON string (the body is occupied by audio): `language`,
  `temp`, `delay_in_frames` (latency vs quality), `padding_bonus`, and
  `keywords` for boosting names/jargon. The `keywords` value is an
  object — get the shape exactly right (see the warning below):
  ```json
  {"language": "en", "keywords": {"words": ["Gradium"], "boost": 3}}
  ```
- **Assembling the transcript** — this is the gotcha everyone hits:
  `text` messages are word-level tokens *without* separators. Join them
  with a space and strip:

```python
transcript = " ".join(m["text"].strip() for m in messages if m["type"] == "text")
```

Message types in the NDJSON stream: `ready` (session metadata), `text`
(word + `start_s`), `end_text` (segment `stop_s`), `step` (VAD
probabilities), `error`, `end_of_stream`.

## WebSocket protocol (shared grammar)

All three WebSocket endpoints speak JSON text frames with the same
lifecycle. Authenticate with the `x-api-key` header (server) or
`?token=` (browser).

1. **Send `setup`** — first message, picks models and formats:
   ```json
   {"type": "setup", "model_name": "default", "voice_id": "...",
    "output_format": "wav", "input_format": "pcm_24000",
    "json_config": {"language": "en"}}
   ```
   TTS needs `voice_id` + `output_format`; STT needs `input_format`;
   S2S needs both plus `stt_model_name`/`tts_model_name` (see the
   gradium-speech-translation skill).
2. **Wait for `ready`** — carries `request_id`, `sample_rate`,
   `frame_size`. Log `request_id` for support/debugging.
3. **Send input** — TTS: `{"type": "text", "text": "..."}` messages;
   STT/S2S: `{"type": "audio", "audio": "<base64>"}` chunks (~80 ms
   chunks work well).
4. **Flush when you need output now** — TTS: put the literal tag
   `<flush>` inside a `text` message at a sentence boundary; STT: send
   `{"type": "flush", "flush_id": 1}` and match the `flushed` reply.
5. **Send `{"type": "end_of_stream"}`** — graceful finish. Read
   responses until the server's `end_of_stream`, then the socket closes
   (unless `close_ws_on_eos: false` in setup).

Responses: `audio` (base64), `text` (word + `start_s`/`stop_s`
timestamps), `step` (STT semantic VAD: array of
`{horizon_s, inactivity_prob}` — see turn-taking in the
gradium-speech-to-text skill), `flushed`, `error`, `end_of_stream`.

**Multiplexing:** to reuse one socket, set `close_ws_on_eos: false` in
setup; to run concurrent requests on it, also put a unique
`client_req_id` on every message of each logical request — the server
echoes it on every response so you can route. Reusing a live
`client_req_id` is a protocol error.

Sessions cap at **300 seconds**; split long text at sentence boundaries
and long audio at silences.

## Voices, pronunciation dictionaries, credits

CRUD endpoints (REST, `x-api-key`):

| Action | Call | Notes |
| --- | --- | --- |
| Clone a voice | `POST /api/voices/` (multipart) | Part name for the sample is **`audio_file`**; fields `name`, `description`, `start_s`. Returns **201** with `uid` |
| List / get / update / delete | `GET/GET/PUT/DELETE /api/voices/[{uid}]` | Delete returns **204**. List shows only your custom voices, not the flagship catalog |
| Pronunciation dictionaries | `POST/GET/PUT/DELETE /api/pronunciations/[{uid}]` | Rules are `{"original": "SQL", "rewrite": "sequel"}` (not pattern/replacement). Apply per-session via top-level `pronunciation_id` in a TTS `setup` |
| Credit balance | `GET /api/usages/credits` | Also the cheapest key-validity check |

## Errors

- REST errors: `{"detail": "..."}` with 400 (bad request — e.g.
  `Embeddings not found for <voice_id>` means an unknown voice), 401
  (bad key), 422 (validation — `detail` is an array naming the exact
  missing/invalid field; read it, it is accurate).
- Mid-stream failures arrive as `{"type": "error", ...}` messages in
  NDJSON/WebSocket streams — handle them in the read loop, then treat
  the request as terminated.
- **Exception (verified):** an invalid `json_config` value on the ASR
  POST endpoint (e.g. `keywords` as a bare array instead of the object
  shape) returns a **silent empty 200** — no `detail`, no `error`
  message, zero-byte body. If a transcription comes back empty, suspect
  your `json_config` shape first; the STT *WebSocket* does report the
  same mistake properly (`{"type":"error","message":"parsing keywords...","code":1011}`),
  so reproducing the setup there is a fast way to see the real error.
- Success codes vary: 200 for speech, 201 for creates, 204 for deletes.

## Common mistakes

1. Using `Authorization: Bearer` — Gradium wants `x-api-key`.
2. Concatenating STT `text` messages without a space separator.
3. Sending audio as binary WebSocket frames — Gradium WebSockets are
   JSON text frames with base64 `audio` fields.
4. Uploading a clone sample under a part name other than `audio_file`.
5. Writing pronunciation rules as `pattern`/`replacement` instead of
   `original`/`rewrite`.
6. Passing STT options in the POST body — the body is raw audio; options
   go in the `json_config` query parameter.
7. Following redirects with custom API-key headers. Use the canonical URL;
   reject redirects unless the destination is verified as the same HTTPS origin.
8. Expecting `GET /voices/` to list flagship voices — it only returns
   your custom clones; flagship IDs live in the docs voice library.
9. Treating the 300 s session cap as an error — it's a design limit;
   chunk your work.

## Reference

- Full docs index (agent-friendly): `https://docs.gradium.ai/llms.txt` —
  every page is fetchable as markdown by appending `.md`.
- OpenAPI spec: `https://docs.gradium.ai/api-reference/openapi.json`
- Migrating from another voice API: per-provider guides with
  endpoint/auth/field mappings at
  `https://docs.gradium.ai/guides/migration/index.md`
- Support: support@gradium.ai
