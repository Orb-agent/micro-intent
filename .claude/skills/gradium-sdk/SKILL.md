---
name: gradium-sdk
description: Write Python code with the official Gradium SDK (pip install gradium) for text-to-speech, speech-to-text, speech-to-speech translation, voice cloning, and credit checks. Use whenever the user wants Gradium in a Python app, script, notebook, FastAPI/voice-agent backend, or asks to "use the gradium package" — the SDK wraps the WebSocket protocol, base64 handling, and NDJSON parsing so you don't reimplement them. Covers the async client, one-shot vs pull-stream vs realtime call shapes, result objects, the bundled gradium CLI, and the exact method signatures of SDK v0.6. For raw HTTP/WebSocket calls from other languages, use the gradium-api skill instead.
license: MIT
compatibility: Requires internet access, Python 3.10+, pip install gradium, and a Gradium API key (GRADIUM_API_KEY).
metadata: {"openclaw": {"requires": {"env": ["GRADIUM_API_KEY"]}, "primaryEnv": "GRADIUM_API_KEY"}}
---

# Gradium Python SDK

```bash
pip install gradium          # imports as `gradium`, ships a `gradium` CLI
export GRADIUM_API_KEY=...   # picked up automatically
```

```python
import gradium
client = gradium.client.GradiumClient()          # or api_key="..."
```

The client is **async-first**: every speech method is `await`-able. In
scripts, wrap calls in `asyncio.run(...)`. Default `base_url` is
`https://api.gradium.ai/api/` — override only for self-hosted or
private deployments. If old code sets an EU URL, remove it (single global host
now).

## Three call shapes per modality

Each of TTS / STT / S2S comes in three flavors — pick by how your data
arrives:

| Shape | TTS | STT | S2S | When |
| --- | --- | --- | --- | --- |
| Buffered one-shot | `client.tts(setup, text)` | `client.stt(setup, audio)` | `client.s2s(setup, audio)` | Have all input, want the whole result |
| Pull-stream | `client.tts_stream(setup, text_or_gen)` | `client.stt_stream(setup, audio_gen)` | `client.s2s_stream(...)` | Input may be a generator; iterate results as they come |
| Realtime (context manager) | `client.tts_realtime(**setup)` | `client.stt_realtime(**setup)` | `client.s2s_realtime(**setup)` | Live bidirectional: send while receiving (mics, agents) |

Note the call-shape asymmetry: one-shot/pull take a **setup dict**;
realtime takes the same fields as **keyword arguments**.

## One-shot examples (tested)

```python
import asyncio, gradium

async def main():
    client = gradium.client.GradiumClient()

    # TTS -> TTSResult(raw_data, sample_rate, output_format, request_id, text_with_timestamps)
    res = await client.tts(
        setup={"voice_id": "YTpq7expH9539ERJ", "output_format": "wav",
               "json_config": {"temp": 0.5}},
        text="The Python SDK wraps the websocket protocol in three lines.")
    with open("out.wav", "wb") as f:
        f.write(res.raw_data)              # container bytes -> write raw_data
    for w in res.text_with_timestamps[:3]:  # word-level timing
        print(w.text, w.start_s, w.stop_s)

    # STT -> STTResult(text, text_with_timestamps, request_id)
    stt = await client.stt(
        setup={"model_name": "default", "input_format": "wav",
               "json_config": {"language": "en",
                               "keywords": {"words": ["Gradium"], "boost": 3}}},
        audio=open("out.wav", "rb").read())
    print(stt.text)                         # already space-joined

asyncio.run(main())
```

- `TTSResult.raw_data` holds the encoded audio (write it to disk);
  a `pcm`/`pcm16` view exists as numpy arrays for DSP — don't confuse
  the two.
- `STTResult.text` is the assembled transcript — the SDK handles the
  word-joining that raw-API users must do themselves.
- `client.stt(...)` also accepts a numpy float array with
  `sample_rate=` (use 24000).

## Realtime shape

```python
async with client.stt_realtime(
    model_name="default", input_format="pcm_24000",
    json_config={"language": "en"},
) as stt:
    async def send():
        async for chunk in mic_chunks():       # bytes, ~80 ms
            await stt.send_audio(chunk)
        await stt.send_eos()
    async def recv():
        async for msg in stt:                  # dicts: text/step/end_of_stream
            if msg["type"] == "text":
                on_word(msg["text"])
            elif msg["type"] == "step":
                on_vad(msg["vad"])             # semantic VAD for turn-taking
            elif msg["type"] == "end_of_stream":
                return
    await asyncio.gather(send(), recv())
```

TTS realtime mirrors it with `send_text(...)` / `send_eos()` and yields
`audio` messages. `send_flush()` forces pending output (turn-taking).
Setup fields are the wire-protocol ones: `voice_id`, `model_name`,
`input_format`/`output_format`, `json_config` (settings dicts —
`temp`, `cfg_coef`, `padding_bonus`, `keywords`, `delay_in_frames`,
`target_language`), `pronunciation_id`, `close_ws_on_eos`,
`client_req_id`.

## S2S translation

```python
res = await client.s2s(
    setup={"model_name": "s2s-translate", "stt_model_name": "stt-translate",
           "tts_model_name": "default", "voice_id": "sVLgzKMqaptUdaY8",  # es voice!
           "input_format": "pcm", "output_format": "wav",
           "json_config": {"target_language": "es"}},
    audio=audio_bytes)
```

The `voice_id` must be a voice in the target language. See the
gradium-speech-translation skill for the full workflow.

## Voices, credits

```python
voice = await client.voice_create(pathlib.Path("sample.wav"),
                                  name="My narrator")   # ~10s+ clean speech
uid = voice["uid"]           # use as voice_id; ignore the advisory "wait" note
await client.voice_list();  await client.voice_get(uid)
await client.voice_update(uid, name="Renamed")
await client.voice_delete(uid)
bal = await client.credits() # {"remaining_credits": ..., "allocated_credits": ...}
```

`client.credits()` is also the cheapest "is this key valid" probe.

## Bundled CLI

```bash
gradium tts --text "Hello" --voice-id YTpq7expH9539ERJ --output out.wav
gradium stt --input recording.wav
```

Handy for smoke tests without writing code (`gradium tts -h` for flags).

## Common mistakes

1. Writing `res.pcm` to a file — that's a numpy array; write
   `res.raw_data`.
2. Calling speech methods without an event loop — they're coroutines;
   use `asyncio.run` or an async framework.
3. Passing setup as kwargs to `client.tts(...)` (dict!) or as a dict to
   `client.tts_realtime(...)` (kwargs!).
4. Rebuilding transcripts from `text_with_timestamps` with `"".join` —
   use `STTResult.text`.
5. Hardcoding the API key — the client reads `GRADIUM_API_KEY`.
