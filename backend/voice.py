"""Gradium speech in and out, in the wire format of contracts § Audio
(PCM s16le, mono, 24 kHz, base64).

Checks, from backend/:
    uv run python voice.py tts "Hello from the beaver"   # writes out.wav, prints time to first audio
    uv run python voice.py stt out.wav                    # prints the transcript
"""

import asyncio
import base64
import os
import sys
import time
import wave
from collections.abc import AsyncIterator

import certifi

# python.org builds on macOS ship without CA certs. aiohttp (inside gradium) builds its
# TLS context at import time, so this must run before `import gradium`.
os.environ.setdefault("SSL_CERT_FILE", certifi.where())

import gradium  # noqa: E402

SAMPLE_RATE = 24000
CHUNK_BYTES = 3840  # 80 ms
DEFAULT_VOICE_ID = "JuMRs5W5S52hzuge"  # Cormac: bright, warm, cheerful (flagship catalog)

_client: gradium.client.GradiumClient | None = None


def client() -> gradium.client.GradiumClient:
    global _client
    if _client is None:
        _client = gradium.client.GradiumClient()  # reads GRADIUM_API_KEY
    return _client


async def speak(text: str) -> AsyncIterator[str]:
    """Yield base64 PCM chunks for `text`. One TTS socket per reply."""
    voice_id = os.environ.get("GRADIUM_VOICE_ID") or DEFAULT_VOICE_ID
    async with client().tts_realtime(
        model_name="default", voice_id=voice_id, output_format="pcm_24000"
    ) as tts:
        await tts.send_text(text)
        await tts.send_eos()
        async for msg in tts:
            if msg["type"] == "audio":
                yield base64.b64encode(msg["audio"]).decode()
            elif msg["type"] == "end_of_stream":
                break


class Transcriber:
    """One push-to-talk turn: push() base64 chunks as they arrive, then finish()."""

    def __init__(self, language: str = "en"):
        self._queue: asyncio.Queue[bytes | None] = asyncio.Queue()
        self._task = asyncio.create_task(self._run(language))

    def push(self, b64: str) -> None:
        self._queue.put_nowait(base64.b64decode(b64))

    async def finish(self) -> str:
        """End of speech: Gradium drains the remaining text, then closes."""
        self._queue.put_nowait(None)
        return await self._task

    def cancel(self) -> None:
        self._task.cancel()

    async def _run(self, language: str) -> str:
        parts: list[str] = []
        async with client().stt_realtime(
            model_name="default", input_format="pcm", json_config={"language": language}
        ) as stt:

            async def send() -> None:
                while (chunk := await self._queue.get()) is not None:
                    await stt.send_audio(chunk)
                await stt.send_eos()

            sender = asyncio.create_task(send())
            try:
                async for msg in stt:
                    if msg["type"] == "text":
                        parts.append(msg["text"])
                    elif msg["type"] == "end_of_stream":
                        break
            finally:
                sender.cancel()
        return " ".join(p.strip() for p in parts if p.strip())


async def _cli_tts(text: str) -> None:
    t0 = time.monotonic()
    first = None
    pcm = bytearray()
    async for chunk in speak(text):
        first = first or time.monotonic() - t0
        pcm += base64.b64decode(chunk)
    with wave.open("out.wav", "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(bytes(pcm))
    print(f"out.wav: {len(pcm) / 2 / SAMPLE_RATE:.2f} s audio, first audio after {first:.2f} s")


async def _cli_stt(path: str) -> None:
    with wave.open(path, "rb") as f:
        assert (f.getframerate(), f.getnchannels(), f.getsampwidth()) == (SAMPLE_RATE, 1, 2), "need 24 kHz mono s16"
        pcm = f.readframes(f.getnframes())
    stt = Transcriber()
    for i in range(0, len(pcm), CHUNK_BYTES):  # paced like a live mic
        stt.push(base64.b64encode(pcm[i : i + CHUNK_BYTES]).decode())
        await asyncio.sleep(0.08)
    t0 = time.monotonic()
    text = await stt.finish()
    print(f"transcript ({time.monotonic() - t0:.2f} s after end of audio): {text!r}")


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv("../.env")
    cmd, arg = sys.argv[1], sys.argv[2]
    asyncio.run(_cli_tts(arg) if cmd == "tts" else _cli_stt(arg))
