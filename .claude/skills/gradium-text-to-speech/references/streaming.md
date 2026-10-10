# Gradium TTS WebSocket streaming

Tested client patterns for `wss://api.gradium.ai/api/speech/tts`.
All frames are JSON text; audio travels as base64 inside `audio`
messages. Server auth: `x-api-key` header. Browser auth: `?token=`
(short-lived token from `GET /api/api-keys/token`, minted server-side).

## Minimal streaming client (Python, tested)

```python
import asyncio, base64, json, os
import websockets  # pip install websockets

KEY = os.environ["GRADIUM_API_KEY"]

async def speak(chunks: list[str], out_path: str = "out.wav") -> None:
    async with websockets.connect(
        "wss://api.gradium.ai/api/speech/tts",
        additional_headers={"x-api-key": KEY},
    ) as ws:
        await ws.send(json.dumps({
            "type": "setup",
            "voice_id": "YTpq7expH9539ERJ",
            "output_format": "wav",           # pcm for live playback
        }))
        ready = json.loads(await ws.recv())   # {"type":"ready","sample_rate":48000,...}
        assert ready["type"] == "ready", ready

        for chunk in chunks:
            await ws.send(json.dumps({"type": "text", "text": chunk}))
        await ws.send(json.dumps({"type": "end_of_stream"}))

        audio, words = [], []
        async for raw in ws:
            m = json.loads(raw)
            if m["type"] == "audio":
                audio.append(base64.b64decode(m["audio"]))
            elif m["type"] == "text":         # word-level timestamps
                words.append((m["text"], m["start_s"], m["stop_s"]))
            elif m["type"] == "end_of_stream":
                break
            elif m["type"] == "error":
                raise RuntimeError(m)
        with open(out_path, "wb") as f:
            f.write(b"".join(audio))

asyncio.run(speak(["Streaming synthesis over a websocket. ",
                   "Second chunk arrives while the first is playing."]))
```

Observed behavior: the first `audio` message arrives almost immediately
after `end_of_stream` for short inputs, and mid-stream for longer ones;
`text` messages are one per word.

## Feeding LLM tokens

Send text as it arrives from the model; append `<flush>` at natural
boundaries (end of sentence or of the whole answer) so the tail is
synthesized without waiting for more context:

```python
async for token in llm_stream:
    buffer += token
    if buffer.endswith((".", "!", "?")):
        await ws.send(json.dumps({"type": "text", "text": buffer + " "}))
        buffer = ""
# ...at the end of the answer:
await ws.send(json.dumps({"type": "text", "text": buffer + " <flush>"}))
await ws.send(json.dumps({"type": "end_of_stream"}))
```

Run the send loop and the receive loop as two concurrent tasks
(`asyncio.gather`) — waiting for all audio before sending more text
defeats the purpose of streaming.

## Reusing and multiplexing one socket

Opening a socket per utterance adds latency. Options in `setup`:

| Mode | Setup | Behavior |
| --- | --- | --- |
| Single-use (default) | — | Socket closes after `end_of_stream` |
| Sequential reuse | `"close_ws_on_eos": false` | Send a fresh `setup` per utterance on the same socket |
| Concurrent multiplex | `close_ws_on_eos: false` + unique `client_req_id` on **every** message | Interleaved requests; the server echoes `client_req_id` on every response — route by it |

Reusing a `client_req_id` while that request is still active is a
protocol error. One socket per output sample rate: the sample rate is
fixed at `setup` time.

## Interrupting (barge-in)

To cut the agent off mid-utterance (user started talking), simply close
the socket — or, when multiplexing, stop reading that `client_req_id`
and start a new request. `end_of_stream` is a *graceful* finish that
still delivers remaining audio; closing is the interrupt.

## Session limits

300 s per session. For long-form narration, synthesize per paragraph on
a reused socket rather than one giant session.
