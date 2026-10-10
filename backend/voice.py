"""Gradium speech in and out, in the wire format of contracts § Audio
(PCM s16le, mono, 24 kHz, base64).

Checks, from backend/:
    uv run python voice.py tts "Hello from the beaver"   # writes out.wav, prints time to first audio
    uv run python voice.py stt out.wav                    # prints the transcript
    uv run python voice.py design "A gruff old Swiss train conductor, 55 to 65, ..."  # new voice, then out.wav
"""

import asyncio
import base64
import json
import logging
import os
import sys
import time
import wave
from collections.abc import AsyncIterator, Awaitable, Callable

import certifi

# python.org builds on macOS ship without CA certs. aiohttp (inside gradium) builds its
# TLS context at import time, so this must run before `import gradium`.
os.environ.setdefault("SSL_CERT_FILE", certifi.where())

import aiohttp  # noqa: E402  (gradium's own transport)
import gradium  # noqa: E402
import httpx  # noqa: E402

SAMPLE_RATE = 24000
CHUNK_BYTES = 3840  # 80 ms
DEFAULT_VOICE_ID = "JuMRs5W5S52hzuge"  # Cormac: bright, warm, cheerful (flagship catalog)

# Voice Design (docs.gradium.ai/guides/voices/voice-design): a voice from a written description.
API_URL = "https://api.gradium.ai/api"
DESIGN_LANGUAGES = ["en", "fr", "es", "pt", "de"]
DESIGN_CFG_SCALE = 10.0  # the docs' value for one candidate per conversational turn
DESIGN_POLL_S = 1.0
DESIGN_TIMEOUT_S = 30.0  # an unknown json_config key returns 201 and never gets ready

# Hands-free end of turn, from the semantic VAD in Gradium's `step` messages (one per 80 ms).
END_HORIZON_S = 2.0  # read the `vad` entry with this horizon_s
END_PROB = 0.5  # its inactivity_prob must be above this...
END_STEPS = 3  # ...for this many steps in a row, once the turn has text
REOPEN_AFTER_S = 1.0  # a closed hands-free session reopens on the next audio, at most once a second
BACKLOG_CHUNKS = 25  # hands-free audio waiting for a session: the newest 2 s, older chunks drop

# Gradium keyword boosting for the demo's place names. Case-sensitive, hence the variants.
# Synthetic test voices still say "Bern" like "burn", so the agent also resolves names.
_PLACES = ["Bern", "Zürich", "Zurich", "Basel", "Luzern", "Geneva", "Lausanne"]
KEYWORDS = {"words": _PLACES + [p.lower() for p in _PLACES] + ["SBB"], "boost": 3}

log = logging.getLogger("voice")
_client: gradium.client.GradiumClient | None = None


def client() -> gradium.client.GradiumClient:
    global _client
    if _client is None:
        _client = gradium.client.GradiumClient()  # reads GRADIUM_API_KEY
    return _client


async def speak(text: str, voice_id: str | None = None) -> AsyncIterator[str]:
    """Yield base64 PCM chunks for `text`. One TTS socket per reply."""
    voice_id = voice_id or os.environ.get("GRADIUM_VOICE_ID") or DEFAULT_VOICE_ID
    async with client().tts_realtime(
        model_name="default", voice_id=voice_id, output_format="pcm_24000"
    ) as tts:
        await tts.send_text(text)
        await tts.send_eos()
        async for msg in _messages(tts):  # raw frames: base64 audio passes through as is
            if msg["type"] == "audio":
                yield msg["audio"]
            elif msg["type"] == "end_of_stream":
                break


async def design_voice(description: str, language: str = "en") -> str:
    """A new voice from a casting brief: one candidate, waited for, then converted into a
    permanent voice_id that speak() accepts (candidates are REST-only). A few seconds."""
    # ponytail: every design takes a custom-voice slot and nothing frees it; past the
    # allowance Gradium answers 409. Delete the replaced voice if demos hit that.
    async with httpx.AsyncClient(base_url=API_URL, headers={"x-api-key": os.environ["GRADIUM_API_KEY"]}) as http:
        body = {"prompt": description, "language": language, "json_config": {"cfg_scale": DESIGN_CFG_SCALE}}
        candidate = _ok(await http.post("/voice-generator/generate", json=body))["embeddings"][0]["embedding_id"]
        deadline = time.monotonic() + DESIGN_TIMEOUT_S
        while True:
            found = _ok(await http.get("/voice-generator/embeddings", params={"embedding_id": candidate}))
            if any(e["ready"] for e in found["embeddings"]):  # an unknown id is an empty list, not 404
                break
            if time.monotonic() > deadline:
                raise TimeoutError(f"voice candidate {candidate} not ready after {DESIGN_TIMEOUT_S:.0f} s")
            await asyncio.sleep(DESIGN_POLL_S)
        body = {"voxium_embedding_id": candidate, "name": f"Beaver {candidate[-6:]}", "description": description}
        return _ok(await http.post("/voices/from-embedding", json=body))["uid"]


def _ok(r: httpx.Response) -> dict:
    """The JSON body; Gradium's `detail` in the error, e.g. 409 Custom voice limit reached."""
    if r.is_error:
        raise RuntimeError(f"Gradium {r.status_code}: {r.text[:200]}")
    return r.json()


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
            model_name="default", input_format="pcm", json_config={"language": language, "keywords": KEYWORDS}
        ) as stt:

            async def send() -> None:
                while (chunk := await self._queue.get()) is not None:
                    await stt.send_audio(chunk)
                await stt.send_eos()

            sender = asyncio.create_task(send())
            try:
                async for msg in _messages(stt):
                    if msg["type"] == "text":
                        parts.append(msg["text"])
                    elif msg["type"] == "end_of_stream":
                        break
            finally:
                sender.cancel()
        return " ".join(p.strip() for p in parts if p.strip())


async def _messages(stream) -> AsyncIterator[dict]:
    """STT or TTS messages. Use instead of `async for msg in stream`: in gradium 0.6.4 that
    spins forever, freezing the event loop, when the connection drops without a close frame."""
    async for frame in stream._ws:  # aiohttp stops iterating on any close
        if frame.type == aiohttp.WSMsgType.TEXT:
            msg = json.loads(frame.data)
            if msg["type"] == "error":
                raise RuntimeError(f"Gradium error: {msg}")
            yield msg


class TurnDetector:
    """Hands-free end of turn: inactivity_prob at END_HORIZON_S above END_PROB for
    END_STEPS `step`s in a row, counted only once the turn has text."""

    def __init__(self) -> None:
        self.words: list[str] = []
        self._streak = 0

    def feed(self, msg: dict) -> bool:
        """One STT message in; True when the turn has ended."""
        if msg["type"] == "text" and msg["text"].strip():
            self.words.append(msg["text"].strip())
        elif msg["type"] == "step" and self.words:
            p = next((v["inactivity_prob"] for v in msg["vad"] if v["horizon_s"] == END_HORIZON_S), 0.0)
            self._streak = self._streak + 1 if p > END_PROB else 0
            return self._streak >= END_STEPS
        return False

    def take(self) -> str:
        """The turn's text; starts the next turn."""
        text, self.words, self._streak = " ".join(self.words), [], 0
        return text


class ContinuousTranscriber:
    """Hands-free: one STT session per WebSocket, open across turns. push() base64 chunks
    for as long as the mic is on. Awaits on_speech() at a turn's first words and
    on_turn(text) at its end. If Gradium closes the session, the next push() reopens it."""

    def __init__(
        self,
        on_speech: Callable[[], Awaitable[None]],
        on_turn: Callable[[str], Awaitable[None]],
        language: str = "en",
    ):
        self._on_speech, self._on_turn, self._language = on_speech, on_turn, language
        self._queue: asyncio.Queue[bytes] = asyncio.Queue(BACKLOG_CHUNKS)
        self._turn = TurnDetector()  # outlives a session, so a turn survives a reopen
        self._task: asyncio.Task | None = None
        self._opened = float("-inf")

    def push(self, b64: str) -> None:
        closed = self._task is None or self._task.done()
        if closed and time.monotonic() - self._opened > REOPEN_AFTER_S:
            self._opened = time.monotonic()
            self._task = asyncio.create_task(self._run())
        if self._queue.full():  # no session drains it: drop the oldest, never replay a stale backlog
            self._queue.get_nowait()
        self._queue.put_nowait(base64.b64decode(b64))

    def cancel(self) -> None:
        if self._task is not None:
            self._task.cancel()

    async def _run(self) -> None:
        try:
            async with client().stt_realtime(
                model_name="default", input_format="pcm", json_config={"language": self._language, "keywords": KEYWORDS}
            ) as stt:

                async def send() -> None:
                    while True:
                        await stt.send_audio(await self._queue.get())

                sender = asyncio.create_task(send())
                try:
                    await self._listen(stt)
                finally:
                    sender.cancel()
        except Exception:
            log.exception("hands-free STT failed")
        log.info("hands-free STT session closed; the next audio reopens it")

    async def _listen(self, stt) -> None:
        # A flush sent on a closed session gets no `flushed`; an ended turn flushes again on the next `step`.
        turn, flushing = self._turn, False
        async for msg in _messages(stt):
            fresh = not turn.words
            ended = turn.feed(msg)
            if fresh and turn.words:
                await self._on_speech()
            if ended and not flushing:  # flush makes Gradium emit the words it holds back
                flushing = True
                await stt.send_flush()
            elif msg["type"] == "flushed" and flushing:
                flushing = False
                await self._on_turn(turn.take())


async def _cli_tts(text: str, voice_id: str | None = None) -> None:
    t0 = time.monotonic()
    first = None
    pcm = bytearray()
    async for chunk in speak(text, voice_id):
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


async def _cli_design(description: str) -> None:
    t0 = time.monotonic()
    voice_id = await design_voice(description)
    print(f"voice_id {voice_id}, designed in {time.monotonic() - t0:.2f} s")
    await _cli_tts("Hello! This is my brand new voice. How do I sound?", voice_id)


if __name__ == "__main__":
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv("../.env")
    cmd, arg = sys.argv[1], sys.argv[2]
    asyncio.run({"tts": _cli_tts, "stt": _cli_stt, "design": _cli_design}[cmd](arg))
