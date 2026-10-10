---
name: gradium-text-to-speech
description: Convert text to natural-sounding speech with the Gradium TTS API. Use when generating audio from text, creating voiceovers or narration, building voice apps or realtime voice agents, streaming LLM output as speech, tuning voice speed/expressiveness, adding pauses, fixing pronunciation of brand names or jargon, or synthesizing speech in English, French, German, Spanish, or Portuguese — even if the user just says "make this talk", "read this aloud", or "generate audio". Covers one-shot REST synthesis, low-latency WebSocket streaming, word-level timestamps, voice settings, pronunciation dictionaries, and telephony output formats.
license: MIT
compatibility: Requires internet access and a Gradium API key (GRADIUM_API_KEY).
metadata: {"openclaw": {"requires": {"env": ["GRADIUM_API_KEY"]}, "primaryEnv": "GRADIUM_API_KEY"}}
---

# Gradium Text-to-Speech

Auth: `x-api-key: $GRADIUM_API_KEY` header. Model: `model_name`
defaults to `"default"` — omit it unless told otherwise. Voices are
16-character `voice_id` strings; each voice has a native language
(`en`, `fr`, `de`, `es`, `pt`). Pick from the flagship catalog in
[references/flagship-voices.md](references/flagship-voices.md) or clone
your own (gradium-voice-cloning skill). A safe default English voice
for quick tests: `YTpq7expH9539ERJ`.

## Decide: REST or WebSocket

- **Finished text, want a file** → REST POST. One request, raw bytes back.
- **Text still being generated (LLM), or latency matters** → WebSocket.
  Audio chunks start arriving while later text is still being sent.

A 300-second session cap applies to both; for long-form content, split
at sentence or paragraph boundaries and synthesize per chunk.

## One-shot REST

```bash
curl -fS -X POST https://api.gradium.ai/api/post/speech/tts \
  -H "x-api-key: $GRADIUM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello, world!", "voice_id": "YTpq7expH9539ERJ",
       "output_format": "wav", "only_audio": true}' \
  > output.wav
```

Or run the bundled, tested script (Python, stdlib + requests):

```bash
python scripts/tts.py "Text to speak" --voice YTpq7expH9539ERJ --out speech.wav
python scripts/tts.py "Faster please" --speed fast --format opus --out speech.ogg
```

With `only_audio: false` the response becomes an NDJSON stream carrying
base64 `audio` chunks **and `text` messages with word-level
`start_s`/`stop_s` timestamps** — use that mode when you need karaoke-style
alignment, subtitles, or viseme timing without a WebSocket.

## Output formats

`wav` (48 kHz, 16-bit mono — default choice for files), `opus`
(Ogg-wrapped, ~12× smaller, for web delivery), `pcm` (raw 48 kHz for
piping into players/mixers), `pcm_8000|16000|22050|24000|44100|48000`,
and telephony codecs `ulaw_8000` / `alaw_8000` (feed these straight to
Twilio-style media streams — no transcoding step).

## Voice settings (`json_config`)

Pass as a JSON object in the request body (REST) or inside `setup`
(WebSocket):

| Option | Range (default) | What it does |
| --- | --- | --- |
| `temp` | 0.0–1.4 (0.7) | Sampling temperature. `0.0` = deterministic, reproducible reads; higher = more varied delivery |
| `padding_bonus` | −4.0–4.0 (0.0) | Speaking speed. **Negative = faster**, positive = slower. ±2.0 is already a strong effect (≈±30% duration) |
| `cfg_coef` | 1.0–4.0 (2.0) | Voice similarity for cloned voices. 2.0–3.0 covers most cloning work; >4.0 risks artifacts |
| `rewrite_rules` | language code | Pre-synthesis text normalization: expands "Dr.", "5th", "$20" etc. Set to the text's language, e.g. `"en"` |

```json
{"text": "…", "voice_id": "…", "output_format": "wav", "only_audio": true,
 "json_config": {"temp": 0.5, "padding_bonus": -1.0}}
```

## Inline tags

- `<flush>` — force the model to emit audio for everything received so
  far. Use at sentence/answer boundaries in streaming; don't sprinkle it
  mid-clause (hurts prosody).
- `<break time="1.5s" />` — insert a pause, 0.1–2.0 s. Better than
  ellipses or commas for deliberate pacing.

## Fixing pronunciation

Two mechanisms, pick by transport:

- **WebSocket sessions**: create a pronunciation dictionary once, then
  reference it per session with top-level `pronunciation_id` in `setup`
  (next to `voice_id`, *not* inside `json_config`). Rules use
  `original`/`rewrite` fields:
  ```bash
  curl -fS -X POST https://api.gradium.ai/api/pronunciations/ \
    -H "x-api-key: $GRADIUM_API_KEY" -H "Content-Type: application/json" \
    -d '{"name": "brand-terms", "language": "en",
         "rules": [{"original": "SQL", "rewrite": "sequel"},
                   {"original": "Gradium", "rewrite": "gray dee um"}]}'
  ```
  (Returns 201 with a `uid`; manage via GET/PUT/DELETE `/api/pronunciations/{uid}`.)
- **REST one-shots**: use `rewrite_rules` in `json_config` for
  language-wide normalization, or pre-rewrite the text yourself before
  sending.

## WebSocket streaming

Connect to `wss://api.gradium.ai/api/speech/tts` with the `x-api-key`
header (browsers: a short-lived `?token=` from
`GET /api/api-keys/token`, exchanged server-side).

```json
{"type": "setup", "voice_id": "YTpq7expH9539ERJ", "output_format": "pcm"}
{"type": "text", "text": "First sentence of the answer. "}
{"type": "text", "text": "More text as the LLM produces it. <flush>"}
{"type": "end_of_stream"}
```

Read messages until the server's `end_of_stream`: `ready` first
(carries `sample_rate`, `frame_size`, `request_id` — log it), then
interleaved `audio` (base64, decode and buffer/play in arrival order)
and `text` (word timestamps). A terminal `error` message ends the
request. See [references/streaming.md](references/streaming.md) for a
complete tested Python client, the LLM-token-feeding pattern, and
multiplexing several utterances over one socket.

## Judging output quality

When iterating on settings, verify results objectively: round-trip the
audio through Gradium STT and compare the transcript to the input text,
and check duration with `ffprobe`. Speed-setting effects show up
directly in duration; pronunciation-rule effects show up in the
transcript. The STT call is *not* multipart — send the raw bytes as the
body, and join the word tokens from the NDJSON reply with spaces:

```bash
curl -fsS -X POST https://api.gradium.ai/api/post/speech/asr \
  -H "x-api-key: $GRADIUM_API_KEY" -H "Content-Type: audio/wav" \
  --data-binary @out.wav | python3 -c "
import sys, json
print(' '.join(json.loads(l)['text'].strip() for l in sys.stdin
               if l.strip() and json.loads(l)['type'] == 'text'))"
```

(Full STT options live in the gradium-speech-to-text skill.)

## Common mistakes

1. `Embeddings not found for <id>` → the `voice_id` doesn't exist (typo,
   deleted clone, or a voice from another provider).
2. Putting `pronunciation_id` inside `json_config` — it's a top-level
   setup field.
3. Using a voice whose language doesn't match the text — it "works" but
   sounds accented/garbled. Match voice language to text language.
4. Streaming without `<flush>` at the end of short utterances — the
   model waits for more context and the tail arrives late.
5. Re-encoding `wav` output to 48 kHz — it already is 48 kHz mono.
