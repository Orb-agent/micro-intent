"""Stand-in for the iPhone app: speaks a WAV file (or types text) into /ws and
prints what comes back. The mascot's answer is saved to reply.wav.

From backend/, with the server running:
    uv run python fake_app.py out.wav
    uv run python fake_app.py --text "Can I make it?"
    uv run python fake_app.py out.wav --url wss://<tunnel>/ws
    uv run python fake_app.py --text "Can I make it?" --interrupt-after 1.0
    uv run python fake_app.py out.wav --handsfree    # then 3 s of silence and no audio_end
"""

import argparse
import array
import asyncio
import base64
import json
import os
import ssl
import time
import wave

import certifi
import websockets
from dotenv import load_dotenv

CHUNK_BYTES = 3840  # 80 ms of 24 kHz s16 mono


def speech_end(pcm: bytes) -> int:
    """Byte offset just past the last chunk with a sample louder than -36 dBFS."""
    samples = array.array("h", pcm)
    last = max((i for i, x in enumerate(samples) if abs(x) > 500), default=0)
    return (last * 2 // CHUNK_BYTES + 1) * CHUNK_BYTES


async def mic(ws, pcm: bytes) -> None:
    for i in range(0, len(pcm), CHUNK_BYTES):  # paced like a live mic
        chunk = base64.b64encode(pcm[i : i + CHUNK_BYTES]).decode()
        await ws.send(json.dumps({"type": "audio", "data": chunk}))
        await asyncio.sleep(0.08)


async def main(args: argparse.Namespace) -> None:
    tls = ssl.create_default_context(cafile=certifi.where()) if args.url.startswith("wss") else None
    async with websockets.connect(args.url, max_size=None, ssl=tls) as ws:
        mode = {"mode": "handsfree"} if args.handsfree else {}
        await ws.send(json.dumps({"type": "hello", "token": os.environ["APP_TOKEN"]} | mode))
        print(json.loads(await ws.recv()))
        silence = None
        if args.text:
            await ws.send(json.dumps({"type": "text", "text": args.text}))
        else:
            with wave.open(args.wav, "rb") as f:
                pcm = f.readframes(f.getnframes())
            if args.handsfree:  # the mic stays open; the server hears the end of the turn
                end = speech_end(pcm)  # TTS WAVs trail off in silence; time from the last word
                await mic(ws, pcm[:end])
                silence = asyncio.create_task(mic(ws, pcm[end:] + bytes(3 * 24000 * 2)))
            else:
                await mic(ws, pcm)
                await ws.send(json.dumps({"type": "audio_end"}))
        released = time.monotonic()
        audio, first_audio, transcript = bytearray(), None, None
        while True:
            msg = json.loads(await ws.recv())
            if msg["type"] == "transcript":
                transcript = time.monotonic() - released
            if msg["type"] == "audio":
                if first_audio is None:
                    first_audio = time.monotonic() - released
                    if args.interrupt_after is not None:
                        asyncio.get_running_loop().call_later(
                            args.interrupt_after,
                            lambda: asyncio.ensure_future(ws.send(json.dumps({"type": "interrupt"}))),
                        )
                audio += base64.b64decode(msg["data"])
                continue
            print(f"{time.monotonic() - released:5.2f}s", json.dumps(msg, ensure_ascii=False)[:160])
            if msg == {"type": "state", "state": "idle"}:
                break
        if silence is not None:
            silence.cancel()
        with wave.open("reply.wav", "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(24000)
            f.writeframes(bytes(audio))
        if transcript is not None:
            print(f"transcript {transcript:.2f}s after end of speech")
        if first_audio is not None:
            print(f"first audio {first_audio:.2f}s after end of speech; reply.wav is {len(audio) / 48000:.1f}s")


if __name__ == "__main__":
    load_dotenv()
    load_dotenv("../.env")
    p = argparse.ArgumentParser()
    p.add_argument("wav", nargs="?")
    p.add_argument("--text")
    p.add_argument("--url", default="ws://localhost:8000/ws")
    p.add_argument("--interrupt-after", type=float, help="seconds after first audio")
    p.add_argument("--handsfree", action="store_true", help="hello with mode handsfree, no audio_end")
    asyncio.run(main(p.parse_args()))
