#!/usr/bin/env python3
"""Translate (or re-voice) an audio file with Gradium speech-to-speech.

Tested against api.gradium.ai. Requires: pip install websockets, plus
ffmpeg on PATH for input conversion.

Usage:
  export GRADIUM_API_KEY=...
  python s2s.py talk.wav --to es --voice sVLgzKMqaptUdaY8 --out talk_es.wav
  python s2s.py talk.wav --to en --voice NbpkqMVS3CJeq2j8 --out revoiced.wav
"""
import argparse
import asyncio
import base64
import io
import json
import os
import subprocess
import sys
import tempfile
import wave

import websockets
from websockets.exceptions import WebSocketException

CHUNK = 24000 * 2 // 12  # ~80 ms of 24 kHz 16-bit mono
MAX_AUDIO_BYTES = 64 * 1024 * 1024


async def run(args: argparse.Namespace, key: str) -> int:
    # apad: the S2S pipeline finalizes its last segment on silence; audio
    # that stops dead on the final word gets its last sentence truncated.
    pcm = subprocess.run(
        ["ffmpeg", "-v", "quiet", "-i", args.audio, "-af", "apad=pad_dur=2",
         "-t", "296", "-f", "s16le", "-ar", "24000", "-ac", "1", "-"],
        capture_output=True, check=True, timeout=60).stdout
    if not pcm:
        print("ffmpeg produced no audio — check the input file", file=sys.stderr)
        return 1
    if len(pcm) > 24000 * 2 * 295:
        print("input exceeds the 300s session cap — split it at silences first",
              file=sys.stderr)
        return 1

    async with websockets.connect(
        "wss://api.gradium.ai/api/speech/s2s",
        additional_headers={"x-api-key": key},
    ) as ws:
        await ws.send(json.dumps({
            "type": "setup", "model_name": "s2s-translate",
            "stt_model_name": "stt-translate", "tts_model_name": "default",
            "voice_id": args.voice, "input_format": "pcm_24000",
            "output_format": "wav",
            "json_config": {"target_language": args.to},
        }))
        ready = json.loads(await asyncio.wait_for(ws.recv(), timeout=30))
        if ready.get("type") != "ready":
            print("setup rejected", file=sys.stderr)
            return 1

        async def producer():
            # Pace chunks near real-time. Blasting audio at max speed races
            # the translate pipeline and it drops sentences (verified: 16x
            # real-time feeds truncated intermittently; ~real-time never did).
            for i in range(0, len(pcm), CHUNK):
                await ws.send(json.dumps({
                    "type": "audio",
                    "audio": base64.b64encode(pcm[i:i + CHUNK]).decode()}))
                await asyncio.sleep(0.06)
            await ws.send(json.dumps({"type": "end_of_stream"}))

        chunks, text = bytearray(), []
        async def consumer():
            async for raw in ws:
                m = json.loads(raw)
                if m["type"] == "audio":
                    chunks.extend(base64.b64decode(m["audio"], validate=True))
                    if len(chunks) > MAX_AUDIO_BYTES:
                        raise ValueError("translated audio exceeds 64 MiB")
                elif m["type"] == "text":
                    text.append(m["text"].strip())
                elif m["type"] == "end_of_stream":
                    return
                elif m["type"] == "error":
                    raise ValueError("translation provider returned an error")
            raise ValueError("translation closed before end_of_stream")

        tasks = [asyncio.create_task(producer()), asyncio.create_task(consumer())]
        try:
            await asyncio.wait_for(asyncio.gather(*tasks), timeout=330)
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        with wave.open(io.BytesIO(chunks), "rb") as audio:
            if not audio.readframes(1):
                raise ValueError("translation returned empty audio")
        # Replace the requested file only after a complete, valid response.
        with tempfile.TemporaryDirectory(dir=os.path.dirname(os.path.abspath(args.out))) as tmp:
            path = os.path.join(tmp, "translated.wav")
            with open(path, "wb") as f:
                f.write(chunks)
            os.replace(path, args.out)
        print(f"wrote {args.out} ({len(chunks)} bytes)")
        print(f"translated text: {' '.join(text)}")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Gradium speech-to-speech translation")
    p.add_argument("audio", help="input audio (any ffmpeg-readable format)")
    p.add_argument("--to", required=True, choices=["en", "fr", "de", "es", "pt"])
    p.add_argument("--voice", required=True,
                   help="voice_id in the TARGET language (flagship or clone)")
    p.add_argument("--out", default="translated.wav")
    args = p.parse_args()
    key = os.environ.get("GRADIUM_API_KEY")
    if not key:
        print("GRADIUM_API_KEY is not set", file=sys.stderr)
        return 1
    try:
        return asyncio.run(run(args, key))
    except (OSError, ValueError, EOFError, wave.Error, asyncio.TimeoutError,
            subprocess.SubprocessError, WebSocketException) as exc:
        print(f"translation failed ({type(exc).__name__}); output preserved", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
