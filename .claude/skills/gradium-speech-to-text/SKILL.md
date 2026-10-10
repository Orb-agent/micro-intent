---
name: gradium-speech-to-text
description: "Transcribe audio to text with the Gradium STT API. Use when converting audio or video recordings to text, transcribing meetings/podcasts/voicemail, building live captioning or dictation, streaming microphone audio for a voice agent, detecting when a speaker has finished talking (turn-taking / endpointing / VAD), or making a transcriber recognize product names, brands, and jargon correctly — even if the user just says \"get the text out of this recording\" or \"my transcriber keeps misspelling our product name\". Covers batch REST transcription, realtime WebSocket streaming with semantic VAD, keyword boosting, timestamps, and telephony audio formats. Languages: English, French, German, Spanish, Portuguese."
license: MIT
compatibility: Requires internet access and a Gradium API key (GRADIUM_API_KEY). ffmpeg recommended for format conversion.
metadata: {"openclaw": {"requires": {"env": ["GRADIUM_API_KEY"]}, "primaryEnv": "GRADIUM_API_KEY"}}
---

# Gradium Speech-to-Text

Auth: `x-api-key: $GRADIUM_API_KEY`. Model: `model_name: "default"`.
Languages: `en`, `fr`, `de`, `es`, `pt` — set `language` in
`json_config` whenever you know it; it measurably improves accuracy.

## Decide: REST or WebSocket

- **Complete file on disk** → `POST /api/post/speech/asr`. One HTTP
  request, NDJSON response.
- **Live audio** (microphone, telephony, agent input) → WebSocket
  `wss://api.gradium.ai/api/speech/asr`. Adds semantic VAD events and
  `flush` for turn-taking.

Sessions cap at 300 s — split long recordings at silences (ffmpeg
`silencedetect`) and transcribe segments separately.

## Batch transcription (REST)

```bash
python scripts/transcribe.py recording.wav --language en
```

The bundled script (tested) handles config encoding, transcript
assembly, and optional keyword boosting. Raw form:

```bash
curl -fS -X POST 'https://api.gradium.ai/api/post/speech/asr?json_config=%7B%22language%22%3A%22en%22%7D' \
  -H "x-api-key: $GRADIUM_API_KEY" \
  -H "Content-Type: audio/wav" \
  --data-binary @recording.wav
```

- The audio goes in the body; **all options go in the `json_config`
  query parameter** (URL-encoded JSON) because the body is raw audio.
- `Content-Type` declares input format: `audio/wav` (PCM 16/24/32-bit),
  `audio/pcm` (raw 16-bit mono; bare `pcm` = 24 kHz, or use the
  `input_format` query param for `pcm_16000` etc.), `audio/ogg` (Opus),
  and telephony `ulaw_8000`/`alaw_8000` via `input_format`.
- MP3/M4A/video are **not** accepted — convert first:
  `ffmpeg -i input.mp4 -ar 24000 -ac 1 out.wav`

### Assembling the transcript (the #1 gotcha)

The NDJSON stream emits one `text` message per word **without
separators**. Naive concatenation produces `"thisisallgluedtogether"`.
Always:

```python
words = [m["text"].strip() for m in msgs if m["type"] == "text"]
transcript = " ".join(words)
```

### Message types

| Type | Fields | Meaning |
| --- | --- | --- |
| `ready` | `request_id`, `sample_rate`, `frame_size`, `delay_in_frames` | Session accepted; log `request_id` |
| `text` | `text`, `start_s` | One word + its start time |
| `end_text` | `stop_s` | End timestamp of the preceding segment |
| `step` | `vad`: `[{horizon_s, inactivity_prob}, ...]` | Semantic VAD, ~every 80 ms (WebSocket) |
| `flushed` | `flush_id` | All audio before your `flush` is now transcribed |
| `error` | `message` | Terminal failure — stop reading |
| `end_of_stream` | — | Done |

Word timestamps are genuinely word-level (`start_s` per word, `stop_s`
via `end_text`) — enough for subtitles/SRT — **but they run on the
decoder clock, which leads audio time by ≈ `delay_in_frames` × 80 ms**
(verified: the same file transcribed at delay 10 vs 40 shifts every
timestamp by 2.4 s). For alignment work, set `delay_in_frames`
explicitly and subtract `delay_in_frames * 0.08` from every timestamp;
the bundled script does this. Don't rely on the server default — on the
REST endpoint it is much larger than the documented 10.

## Tuning (`json_config`)

| Option | Values (default) | Use |
| --- | --- | --- |
| `language` | `en fr de es pt` (auto) | Set it whenever known |
| `delay_in_frames` | 0–80 (10) | Latency↔quality. Each frame = 80 ms of lookahead. 5–10 for voice agents, 16+ for accuracy-first batch. `0` is accepted but can return **no words at all** — stay ≥4. Also shifts timestamps (see above) |
| `temp` | 0.0–1.5 | Raise slightly only if the model returns nothing on hard audio |
| `padding_bonus` | −4.0–4.0 | Emit text sooner (negative) or later (positive); rarely needed |
| `keywords` | `{"words": [...], "boost": -6..6}` | See below |

## Keyword boosting — make it spell your names right

Without boosting, Gradium STT hears "Gradium" as "Gratium". With it,
domain terms come out exactly right. Pass up to 500 single-token terms:

```json
{"language": "en",
 "keywords": {"words": ["Gradium", "gradium", "Mbappé", "Mbappe"], "boost": 3}}
```

Rules that matter (verified):
- **Single tokens only, no spaces** — split "Ferran Torres" into
  "Ferran", "Torres".
- **Case- and accent-sensitive** — include the variants you expect;
  each variant counts toward the 500 limit.
- `boost` is exponential (log-prob space): `3` is the strong default,
  `4` for very rare/foreign terms, above ~5 the decoder can loop on the
  keyword. Negative values suppress a word you never want.
- Boosting helps most at low `delay_in_frames`, where the model has
  less context to figure names out on its own.

## Realtime WebSocket + turn-taking

Full tested client and the semantic-VAD turn-taking recipe (how to
decide "the user is done talking" from `step` messages, thresholds, and
`flush` on turn end) live in
[references/realtime.md](references/realtime.md). Read it before
building a voice agent input path. Key facts:

- Send `{"type": "setup", "model_name": "default", "input_format":
  "pcm_24000", "json_config": {...}}`, then base64 `audio` chunks
  (~80 ms each), then `end_of_stream`.
- Gradium's VAD is **semantic** — it predicts whether the user is done
  *talking about something*, not just silence. `step.vad` gives
  inactivity probabilities at 0.5/1/2/3-second horizons.
- Do not bolt Silero or another local VAD on top — it conflicts with
  Gradium's turn detection and adds latency.
- On turn end, send `flush` to force out the final words instead of
  waiting for more audio.
- Browser clients: never embed the API key; mint a short-lived token
  server-side (`GET /api/api-keys/token`) and connect with `?token=`.

## Common mistakes

1. Gluing `text` messages together without spaces.
2. Uploading MP3/M4A directly — convert to WAV/PCM/Opus first.
3. Options in the POST body — they go in the `json_config` query param.
4. Multi-word or lowercase-only keyword entries.
5. Running a second VAD in front of Gradium's.
6. Treating `step` messages as transcript — they're VAD telemetry.
7. Expecting diarization or word-level confidence — Gradium doesn't
   expose these today; don't fabricate them downstream.
