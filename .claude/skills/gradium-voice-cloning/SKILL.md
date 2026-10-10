---
name: gradium-voice-cloning
description: Clone voices and manage the voice library with the Gradium API. Use when creating a custom voice from an audio sample, cloning someone's voice for TTS, managing (listing, renaming, deleting) cloned voices, choosing a voice for a Gradium app, or making cloned speech sound more (or less) like the original speaker — even if the user just says "make it sound like me" or "use my voice for the narration". Covers the voices CRUD API, sample requirements, similarity tuning with cfg_coef, and the flagship voice catalog.
license: MIT
compatibility: Requires internet access and a Gradium API key (GRADIUM_API_KEY).
metadata: {"openclaw": {"requires": {"env": ["GRADIUM_API_KEY"]}, "primaryEnv": "GRADIUM_API_KEY"}}
---

# Gradium Voice Cloning & Voice Library

Two sources of voices, both used the same way — pass their ID as
`voice_id` in any TTS or S2S request:

- **Flagship catalog** — curated, production-quality voices in en/fr/de/
  es/pt. IDs are listed in the gradium-text-to-speech skill's
  `references/flagship-voices.md` (the API does not enumerate them;
  `GET /voices/` returns only your clones).
- **Custom clones** — created from ~10+ seconds of clean speech, owned
  by your organization.

## Consent first

Clone only voices you have the right to use: the user's own voice, a
speaker who consented, or licensed material. If the request is to clone
a celebrity or someone who hasn't consented, raise it instead of
proceeding.

## Create a clone

```bash
curl -fS -X POST https://api.gradium.ai/api/voices/ \
  -H "x-api-key: $GRADIUM_API_KEY" \
  -F "audio_file=@sample.wav" \
  -F "name=Support narrator" \
  -F "description=Cloned from studio take 3"
```

Facts that save round-trips (all verified):
- The multipart part name is exactly **`audio_file`** — anything else
  422s with a "Field required" pointing at it.
- Returns **201** with `{"uid": "...", "error": "Please wait a bit till
  the voice is ready to be used."}` — that `error` field is an advisory,
  not a failure. In practice the voice is usable within seconds; retry
  TTS once if the first call complains about embeddings.
- Optional fields: `language` (`en|fr|de|es|pt` hint), `start_s` (offset
  into the file to start sampling from, default 0.0). The clone samples
  ~10 s from `start_s` — point it past intros/silence.

### Sample quality drives clone quality

- ≥10 s of continuous, clean, single-speaker speech; 15–30 s is better.
- No music, crosstalk, or heavy noise; natural speaking pace.
- WAV or other common formats; format is inferred from the filename.
- The clone inherits language/accent from the sample — record in the
  language you'll synthesize.

## Use, tune, manage

Use the returned `uid` as `voice_id` in TTS. If the clone sounds too
generic or too artifact-y, tune **`cfg_coef`** in the TTS `json_config`:
higher = closer to the original speaker (2.0 default; 2.0–3.0 is the
useful band; 4.0 max before artifacts).

```bash
# List your clones            (flagship voices are NOT in this list)
curl -fS https://api.gradium.ai/api/voices/ -H "x-api-key: $GRADIUM_API_KEY"
# Inspect / rename / delete
curl -fS https://api.gradium.ai/api/voices/{uid} -H "x-api-key: $GRADIUM_API_KEY"
curl -fS -X PUT https://api.gradium.ai/api/voices/{uid} \
  -H "x-api-key: $GRADIUM_API_KEY" -H "Content-Type: application/json" \
  -d '{"name": "New name"}'
curl -fS -X DELETE https://api.gradium.ai/api/voices/{uid} \
  -H "x-api-key: $GRADIUM_API_KEY"        # 204 on success, irreversible
```

`PUT` accepts `name`, `description`, `language`, `start_s`, `tags`,
`rank`. Deleting a voice breaks any stored `voice_id` references to it —
scan configs before deleting.

## Verify a clone objectively

Generate a line with the clone and round-trip it through Gradium STT
(`POST /api/post/speech/asr`): the transcript should match your text.
For similarity, generate the same line with the clone and the original
sample side by side and listen; push `cfg_coef` up if it drifts, down
if it crackles.

## Common mistakes

1. Multipart part named `file`/`audio` → 422; it must be `audio_file`.
2. Treating the create response's advisory `error` string as a failure.
3. Expecting flagship voices in `GET /voices/` — catalog IDs come from
   the docs, not the API.
4. Sampling from t=0 when the file opens with silence/music — set
   `start_s`.
5. Cloning from a noisy phone recording and then blaming `cfg_coef` —
   fix the sample first.
