---
name: gradium-speech-translation
description: Translate spoken audio into another language as audio (speech-to-speech), or re-voice a recording in a different voice, using the Gradium S2S API. Use when translating a recording or live stream into English, French, German, Spanish, or Portuguese speech, dubbing audio/video content into another language, building a live interpreter, or swapping the narrator's voice on an existing recording — even if the user says "dub this", "make this Spanish", "live translate my mic", or "change who's speaking". Combines with voice cloning to dub content in the original speaker's own cloned voice.
license: MIT
compatibility: Requires internet access and a Gradium API key (GRADIUM_API_KEY). ffmpeg recommended for audio prep.
metadata: {"openclaw": {"requires": {"env": ["GRADIUM_API_KEY"]}, "primaryEnv": "GRADIUM_API_KEY"}}
---

# Gradium Speech-to-Speech (translation, dubbing, re-voicing)

One WebSocket pipeline: transcribe → translate → re-synthesize.
Audio goes in, translated audio (plus the translated text) comes out.
**WebSocket only** — there is no REST S2S endpoint:
`wss://api.gradium.ai/api/speech/s2s`, auth `x-api-key` header.

## Setup message

```json
{"type": "setup",
 "model_name": "s2s-translate",
 "stt_model_name": "stt-translate",
 "tts_model_name": "default",
 "voice_id": "sVLgzKMqaptUdaY8",
 "input_format": "pcm_24000",
 "output_format": "wav",
 "json_config": {"target_language": "es"}}
```

- `model_name: "s2s-translate"` is the only S2S model today; pair it
  with `stt_model_name: "stt-translate"` and `tts_model_name: "default"`.
- `target_language`: `en`, `fr`, `de`, `es`, `pt`.
- **`voice_id` must be a voice in the target language** — a Spanish
  flagship voice for `"es"`, etc. (catalog in the gradium-text-to-speech
  skill). A cloned voice works too: clone the original speaker, then
  dub into their own voice.
- Formats mirror TTS/STT: `pcm` in = 24 kHz mono, out = 48 kHz;
  `wav`, `opus`, explicit `pcm_*` rates, `ulaw_8000`/`alaw_8000`.

Then stream `{"type": "audio", "audio": "<base64>"}` chunks and finish
with `end_of_stream`. Responses: `ready`, `audio` (translated speech),
`text` (the **translated** transcript — save it as your subtitle
track), `end_of_stream`.

Run the bundled tested script:

```bash
python scripts/s2s.py talk.wav --to es --voice sVLgzKMqaptUdaY8 --out talk_es.wav
```

## Re-voicing (verified, undocumented)

Setting `target_language` equal to the source language performs clean
**voice conversion**: same words, different voice. Verified: an English
recording "translated" to `en` with a different voice came back with
the transcript preserved verbatim. Use this to swap narrators or
anonymize a speaker without re-recording. Treat it as a pragmatic trick
rather than a contract — it rides on the translation pipeline.

## Two reliability rules for file inputs (verified, easy to miss)

Both matter — either one alone still truncates intermittently:

1. **Pad trailing silence.** The pipeline finalizes its last segment on
   silence; input that stops dead on the final word loses its last
   sentence even though `end_of_stream` was sent. Append ~2 s
   (`ffmpeg -af "apad=pad_dur=2"`).
2. **Pace chunks near real-time.** Feeding a file at maximum speed
   races the translate stage and whole sentences get dropped, randomly.
   Sleep ~60–80 ms between 80 ms chunks.

The bundled script does both automatically. Live sources (mics) are
naturally real-time-paced with trailing silence and don't hit either.

## Dubbing a file end-to-end

1. Extract mono audio: `ffmpeg -i video.mp4 -ar 24000 -ac 1 audio.wav`
2. Sessions cap at 300 s — split longer audio at silences
   (`ffmpeg -af silencedetect`) and run each segment through S2S.
3. Optional: clone the original speaker (gradium-voice-cloning skill)
   and pass the clone's uid as `voice_id` so the dub keeps their voice.
4. Concatenate segment outputs; remux:
   `ffmpeg -i video.mp4 -i dubbed.wav -map 0:v -map 1:a -c:v copy out.mp4`
5. The `text` messages give you the translated script with the audio —
   keep them for subtitles/QC.

Expect duration drift: translated speech is rarely the same length as
the source. For tight lip-sync, dub per-segment and adjust pacing with
TTS `padding_bonus` on a re-synthesis pass rather than time-stretching
audio.

## Judging translation output

Round-trip the output through Gradium STT with `language` set to the
target (`POST /api/post/speech/asr`) and sanity-check the transcript.
Names and brands may be "translated" too (e.g. "Gradium" became "el
gradiente" in an es dub) — protect proper nouns by adding them to an
STT keyword boost on the *input* side, or fix the script and
re-synthesize that segment with plain TTS.

## Common mistakes

1. Voice language ≠ `target_language` — the request may run but output
   quality collapses; always pair them.
2. Looking for a REST endpoint — S2S is WebSocket-only.
3. Feeding stereo 44.1 kHz audio as `pcm` — downmix/resample to the
   declared format first.
4. Expecting the original-language transcript in `text` messages —
   they carry the translation.
5. One 20-minute session — split at 300 s.
