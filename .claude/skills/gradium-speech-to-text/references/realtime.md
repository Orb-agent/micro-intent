# Gradium realtime STT: WebSocket client + turn-taking

Tested patterns for `wss://api.gradium.ai/api/speech/asr`.

## Wire protocol

Client → server (JSON text frames):

```json
{"type": "setup", "model_name": "default", "input_format": "pcm_24000",
 "json_config": {"language": "en", "delay_in_frames": 8,
                 "keywords": {"words": ["Gradium"], "boost": 3}}}
{"type": "audio", "audio": "<base64 PCM chunk>"}
{"type": "flush", "flush_id": 1}
{"type": "end_of_stream"}
```

Server → client: `ready`, `text` (word + `start_s`), `end_text`
(`stop_s`), `step` (VAD), `flushed`, `error`, `end_of_stream`.

`input_format` values: `pcm` (24 kHz), `pcm_8000|16000|22050|24000|44100|48000`,
`wav`, `opus`, `ulaw_8000`, `alaw_8000`. Browser mics capture 48 kHz —
either resample to 24 kHz in an AudioWorklet or declare `pcm_48000`.

## Tested client (Python)

```python
import asyncio, base64, json, os
import websockets

KEY = os.environ["GRADIUM_API_KEY"]
CHUNK = 24000 * 2 // 12          # ~80 ms of 24 kHz 16-bit mono

async def transcribe_stream(pcm_source):
    async with websockets.connect(
        "wss://api.gradium.ai/api/speech/asr",
        additional_headers={"x-api-key": KEY},
    ) as ws:
        await ws.send(json.dumps({
            "type": "setup", "model_name": "default",
            "input_format": "pcm_24000",
            "json_config": {"language": "en"},
        }))
        ready = json.loads(await ws.recv())
        assert ready["type"] == "ready", ready

        async def producer():
            async for chunk in pcm_source:            # bytes, ~80 ms each
                await ws.send(json.dumps({
                    "type": "audio",
                    "audio": base64.b64encode(chunk).decode(),
                }))
            await ws.send(json.dumps({"type": "flush", "flush_id": 1}))
            await ws.send(json.dumps({"type": "end_of_stream"}))

        words = []
        async def consumer():
            async for raw in ws:
                m = json.loads(raw)
                if m["type"] == "text":
                    words.append(m["text"].strip())
                elif m["type"] == "step":
                    handle_vad(m.get("vad", []))      # see below
                elif m["type"] == "end_of_stream":
                    return

        await asyncio.gather(producer(), consumer())
        return " ".join(words)
```

Send audio at roughly real-time pace for live sources. For "streaming a
file", pacing can be faster, but don't dump the whole file in one frame.

## Turn-taking with semantic VAD

Every ~80 ms the server sends a `step` message:

```json
{"type": "step", "vad": [
  {"horizon_s": 0.5, "inactivity_prob": 0.02},
  {"horizon_s": 1.0, "inactivity_prob": 0.09},
  {"horizon_s": 2.0, "inactivity_prob": 0.31},
  {"horizon_s": 3.0, "inactivity_prob": 0.55}]}
```

`inactivity_prob` at horizon H = the model's probability that the
speaker will still be silent H seconds from now. It is **semantic**:
"I'd like a large pepperoni…" holds a low probability even through a
pause, because the sentence is obviously unfinished.

A working turn-end policy:

```python
def handle_vad(vad):
    p = next((v["inactivity_prob"] for v in vad if v["horizon_s"] == 2.0), 0)
    if p > 0.7 and has_pending_words():
        end_of_turn()        # send flush, hand transcript to the LLM
```

- Tune the threshold (0.6–0.85) and horizon (1.0–2.0 s) to your product:
  lower threshold / shorter horizon = snappier but interrupts slow
  talkers; higher = polite but laggy.
- On turn end, send `{"type": "flush", "flush_id": N}` — the model emits
  any withheld words, then a `flushed` message with your `flush_id`.
  Take the transcript *after* `flushed`, not before, or you lose the
  last word or two.
- Don't add Silero/local VAD in front — Gradium's VAD is part of the
  model; a second VAD gates the audio it needs and double-fires turns.

## Latency tuning

`delay_in_frames` (default 10, i.e. 800 ms of lookahead) is the main
knob: 5–8 for conversational agents, 16 for accuracy-priority
streaming. Keyword boosting matters more at low delay values.

## Barge-in note (voice agents)

If the agent's own TTS output can reach the microphone, the STT will
transcribe the agent talking to itself. Use echo cancellation or gate
the mic during playback — but remember gating kills barge-in; real
fixes are AEC-based.
