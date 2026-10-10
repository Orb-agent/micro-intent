---
name: migrate-to-gradium
description: Migrate codebases from ElevenLabs, Cartesia, or Deepgram voice APIs to Gradium. Use when the user asks to switch voice, TTS, STT, speech, transcription, websocket, streaming audio, or provider adapter code to Gradium; says "migrate to Gradium", "switch the voice API to Gradium", "move from Cartesia/Deepgram/ElevenLabs", or wants compatibility-style endpoint/auth/field rewrites for voice API integrations.
license: MIT
compatibility: Requires internet access and a Gradium API key (GRADIUM_API_KEY) for smoke tests.
---

# Migrate to Gradium

Use this skill to update application code from Cartesia, Deepgram, or
ElevenLabs voice APIs to Gradium while preserving the app's existing
provider-adapter shape.

## Workflow

1. **Find provider boundaries first.** Search for provider names,
   endpoint hosts, SDK imports, env vars, and terms such as `tts`,
   `stt`, `transcribe`, `listen`, `speak`, `voice`, `websocket`, and
   `audio`.
2. **Identify the flow.**
   - Complete text-to-speech: replace with `POST /api/post/speech/tts`.
   - Streaming text-to-speech: replace with `wss /api/speech/tts`.
   - Complete speech-to-text: replace with `POST /api/post/speech/asr`.
   - Streaming speech-to-text: replace with `wss /api/speech/asr`.
3. **Preserve the adapter contract.** Keep callers, return types, file
   writes, playback, transcript collectors, and streaming callbacks
   stable whenever possible. Make the smallest provider-layer change.
4. **Replace secrets safely.** Use `GRADIUM_API_KEY`; never print or
   commit API keys. If a `.env` exists, verify it is ignored before
   reading variable names.
5. **Map fields and messages.** Load
   `references/provider-mapping.md` when provider-specific details are
   needed.
6. **Test with tiny smoke inputs.** Exercise at least one migrated path:
   small TTS text, small WAV/PCM STT sample, or a short WebSocket
   session. Store generated audio in `/tmp` unless the user asks
   otherwise.

## Gradium Endpoints

REST base URL: `https://api.gradium.ai/api`

WebSocket base URL: `wss://api.gradium.ai/api`

| Flow | Endpoint |
| --- | --- |
| TTS POST | `POST https://api.gradium.ai/api/post/speech/tts` |
| TTS WebSocket | `wss://api.gradium.ai/api/speech/tts` |
| STT POST | `POST https://api.gradium.ai/api/post/speech/asr` |
| STT WebSocket | `wss://api.gradium.ai/api/speech/asr` |

Auth header for all Gradium calls:

```text
x-api-key: ${GRADIUM_API_KEY}
```

## Canonical Gradium Payloads

TTS POST returns raw audio bytes when `only_audio` is true:

```json
{
  "text": "Hello from Gradium.",
  "voice_id": "YTpq7expH9539ERJ",
  "output_format": "wav",
  "only_audio": true
}
```

TTS WebSocket messages:

```json
{"type":"setup","voice_id":"YTpq7expH9539ERJ","model_name":"default","output_format":"wav"}
{"type":"text","text":"Hello from Gradium."}
{"type":"end_of_stream"}
```

STT POST sends raw audio bytes with a matching content type, commonly
`audio/wav`.

STT WebSocket messages:

```json
{"type":"setup","model_name":"default","input_format":"pcm"}
{"type":"audio","audio":"base64_encoded_audio"}
{"type":"end_of_stream"}
```

## Implementation Notes

- Use an existing Gradium SDK already present in the project if the
  codebase uses it. Otherwise prefer direct HTTP/WebSocket changes
  inside the provider adapter instead of introducing a new dependency.
- For WebSockets, Gradium expects JSON messages. TTS and STT audio
  chunks from Gradium are base64 in `audio` messages.
- For STT, set `input_format` or `Content-Type` to match the actual
  audio: `pcm`, `wav`, `opus`, `ulaw_8000`, `alaw_8000`, etc.
- For TTS, use Gradium `voice_id` values. Do not reuse provider voice
  IDs unless the project has a mapping table.
- If exact provider-specific migration details matter, read
  `references/provider-mapping.md`.

## Verification

Run the project's normal tests, then add focused smoke checks when
possible:

- TTS POST: assert HTTP success and response length is non-trivial.
- TTS WebSocket: assert at least one `audio` message and
  `end_of_stream`.
- STT POST: assert at least one `text` message or transcript segment.
- STT WebSocket: assert setup receives `ready`, then transcript or
  terminal message is received.

Do not include generated audio, `.env`, API keys, or temporary smoke
scripts in commits unless the user explicitly asks.
