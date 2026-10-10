"""FastAPI server: the app's WebSocket, the screenshot endpoint, and turn orchestration.

Protocol and interfaces: docs/contracts.md. Run from backend/:
    uv run uvicorn app:app --reload --port 8000
"""

import asyncio
import base64
import contextlib
import hmac
import inspect
import json
import logging
import os
import time
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse

import voice

HERE = Path(__file__).parent
load_dotenv(HERE / ".env")
load_dotenv(HERE.parent / ".env")
FIXTURES = HERE / "fixtures"

log = logging.getLogger("app")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")

try:  # WP3 ships a2ui.py; until then we send `reply` only.
    from a2ui import cards_to_a2ui
except ImportError:
    cards_to_a2ui = None

try:  # vision.py is written in parallel; without it every screenshot reads as None.
    from vision import read_screen
except ImportError:
    read_screen = None

SCREEN_MIMES = {"image/jpeg", "image/png"}
SCREEN_MAX_BYTES = 8 * 1024 * 1024
SCREEN_MAX_RECENT = 9  # earlier frames in one `screen` message
SCREEN_CLIP_MAX_BYTES = 8 * 1024 * 1024  # `data` and `recent` together, decoded
SCREEN_MAX_AGE = 120  # s; contracts § HTTP, screenshot rule
VISION_WAIT = 5  # s a turn waits for a running vision call


@dataclass
class Screenshot:
    id: int
    image: bytes
    mime: str
    at: float  # time.monotonic() when received
    task: asyncio.Task | None = None  # read_screen in the background; its result is the ScreenContext
    used: bool = False
    earlier: list[bytes] = field(default_factory=list)  # frames from the seconds before, oldest first


# Single user: one latest screenshot, shared by all sessions.
latest: Screenshot | None = None
sessions: set["Session"] = set()


class StubAgent:
    """Same shape as WP3's Agent (contracts § Agent interface)."""

    async def start(self) -> None:
        pass

    async def turn(self, text, screen, on_status):
        await on_status("Checking trains…")
        await asyncio.sleep(1)
        return json.loads((FIXTURES / "demo_reply.json").read_text())


def make_agent():
    if os.environ.get("MOCK_AGENT", "1") != "1":
        try:
            from agent import Agent

            return Agent()
        except ImportError:
            pass
        try:  # prototype stand-in until WP3's agent.py lands
            from dev_agent import DevAgent

            log.info("agent.py not available yet, using DevAgent")
            return DevAgent()
        except ImportError:
            log.warning("no agent.py or dev_agent.py, using StubAgent")
    return StubAgent()


def token_ok(token: object) -> bool:
    expected = os.environ.get("APP_TOKEN", "")
    return bool(expected) and isinstance(token, str) and hmac.compare_digest(token, expected)


async def broadcast(msg: dict) -> None:
    for session in list(sessions):
        try:
            await session.send(msg)
        except Exception:
            log.warning("could not send %s to a session", msg["type"])


async def read_latest(shot: Screenshot) -> dict | None:
    """Run vision on one screenshot, tell every session, return its ScreenContext or None."""
    t0 = time.monotonic()
    screen = None
    if read_screen is None:
        log.warning("vision.py not available, screenshot %d not read", shot.id)
    else:
        earlier = {"earlier": shot.earlier} if shot.earlier else {}
        try:
            if inspect.iscoroutinefunction(read_screen):
                screen = await read_screen(shot.image, shot.mime, **earlier)
            else:  # a sync read_screen must not block the event loop
                screen = await asyncio.to_thread(read_screen, shot.image, shot.mime, **earlier)
        except Exception:
            log.exception("vision failed on screenshot %d", shot.id)
        screen = screen if isinstance(screen, dict) else None
    summary = screen.get("summary") if screen else None
    log.info("screenshot %d read in %.2fs: %r", shot.id, time.monotonic() - t0, summary)
    await broadcast({"type": "screen_ok"} | ({"summary": summary} if summary else {}))
    return screen


def store_screenshot(image: bytes, mime: str, earlier=()) -> None:
    """Keep only the latest screenshot and start reading it."""
    global latest
    if latest and latest.task:
        latest.task.cancel()  # its context is stale now
    latest = Screenshot(latest.id + 1 if latest else 1, image, mime, time.monotonic(), earlier=list(earlier))
    latest.task = asyncio.create_task(read_latest(latest))
    log.info("screenshot %d: %d bytes %s, %d earlier", latest.id, len(image), mime, len(earlier))


def decode_recent(recent: object, current: int) -> list[bytes]:
    """The `recent` frames of a `screen` message, oldest first. All or none: any bad entry, or
    too many bytes together with the `current` frame's, drops them all but never the current frame."""
    if recent is None:
        return []
    try:
        if not isinstance(recent, list) or len(recent) > SCREEN_MAX_RECENT:
            raise ValueError(f"not a list of at most {SCREEN_MAX_RECENT}")
        frames = [base64.b64decode(data, validate=True) for data in recent]
        if not all(0 < len(f) <= SCREEN_MAX_BYTES for f in frames):
            raise ValueError("an empty or too big frame")
        if current + sum(map(len, frames)) > SCREEN_CLIP_MAX_BYTES:
            raise ValueError(f"over {SCREEN_CLIP_MAX_BYTES} bytes together")
    except (TypeError, ValueError) as e:
        log.warning("dropped recent screen frames, kept the current one: %s", e)
        return []
    return frames


async def take_screen() -> tuple[Screenshot | None, dict | None]:
    """The latest screenshot and its ScreenContext if fresh and unused (contracts § HTTP).

    The caller marks it used once its turn completes, so a turn the user interrupts
    leaves the screen for the question they ask next."""
    deadline = time.monotonic() + VISION_WAIT
    while True:
        shot = latest
        if shot is None or shot.used or time.monotonic() - shot.at > SCREEN_MAX_AGE:
            return None, None
        await asyncio.wait({shot.task}, timeout=max(0, deadline - time.monotonic()))  # never cancels the vision task
        if shot is latest or not shot.task.cancelled():
            break  # else a newer screenshot cancelled it: wait on that one, same deadline
    if not shot.task.done() or shot.task.cancelled():
        log.warning("screenshot %d not read within %ds, turn goes without it", shot.id, VISION_WAIT)
        return None, None
    return shot, shot.task.result()


app = FastAPI()


@app.get("/")
async def prototype_client():
    """Mac prototype client (static/index.html); the iPhone app doesn't use it."""
    return FileResponse(HERE / "static" / "index.html")


@app.get("/health")
async def health():
    return {"ok": True, "workspace": os.environ.get("WORKSPACE_MODE", "fixture")}


@app.post("/screenshot", status_code=204)
async def screenshot(request: Request) -> Response:
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token_ok(token):
        raise HTTPException(401)
    mime = request.headers.get("content-type", "").split(";")[0].strip().lower()
    if mime not in SCREEN_MIMES:
        raise HTTPException(415)
    image = bytearray()
    async for chunk in request.stream():  # count bytes; Content-Length can lie
        image += chunk
        if len(image) > SCREEN_MAX_BYTES:
            raise HTTPException(413)
    store_screenshot(bytes(image), mime)
    return Response(status_code=204)


class Session:
    def __init__(self, ws: WebSocket, handsfree: bool = False):
        self.ws = ws
        self.agent = make_agent()
        self.turns = 0
        self.stt: voice.Transcriber | None = None
        self.listener = voice.ContinuousTranscriber(self.heard_speech, self.heard_turn) if handsfree else None
        self.turn_task: asyncio.Task | None = None
        self._send_lock = asyncio.Lock()

    async def send(self, msg: dict) -> None:
        async with self._send_lock:
            await self.ws.send_json(msg)

    async def state(self, state: str, label: str | None = None) -> None:
        await self.send({"type": "state", "state": state} | ({"label": label} if label else {}))

    async def run_turn(self, text: str, timings: dict[str, float] | None = None) -> None:
        self.turns += 1
        t0 = time.monotonic()
        timings = timings or {}
        await self.state("thinking")

        async def on_status(label: str) -> None:
            await self.state("searching", label)

        shot, screen = await take_screen()
        timings["vision_wait"] = time.monotonic() - t0
        t_agent = time.monotonic()
        try:
            reply = await self.agent.turn(text, screen, on_status)
        except Exception:
            log.exception("turn failed")
            await self.send({"type": "error", "message": "Sorry, something went wrong."})
            await self.state("idle")
            return
        timings["agent"] = time.monotonic() - t_agent
        if shot is not None:
            shot.used = True

        await self.send({"type": "reply", "say": reply["say"], "cards": reply["cards"]})
        if cards_to_a2ui and reply["cards"]:
            messages = cards_to_a2ui(f"reply-{self.turns}", reply["cards"])
            await self.send({"type": "a2ui", "messages": messages})
        await self.state("speaking")
        try:  # aclosing: an interrupt closes the TTS socket now, not when GC finds it
            async with contextlib.aclosing(voice.speak(reply["say"])) as chunks:
                async for chunk in chunks:
                    timings.setdefault("first_audio", time.monotonic() - t0)
                    await self.send({"type": "audio", "data": chunk})
        except Exception:
            log.exception("TTS failed")  # the reply text and cards are already on screen
        await self.send({"type": "audio_end"})
        await self.state("idle")
        timings["total"] = time.monotonic() - t0
        log.info("turn %d %r timings %s", self.turns, text, {k: round(v, 2) for k, v in timings.items()})

    async def voice_turn(self, stt: voice.Transcriber) -> None:
        t0 = time.monotonic()
        try:
            text = await stt.finish()
        except Exception:
            log.exception("STT failed")
            text = ""
        if not text:
            await self.send({"type": "error", "message": "Sorry, I didn't catch that."})
            await self.state("idle")
            return
        await self.send({"type": "transcript", "text": text})
        await self.run_turn(text, {"stt": time.monotonic() - t0})

    async def heard_speech(self) -> None:
        """Hands-free: the user's first words of a turn; talking over the mascot interrupts it."""
        await self.interrupt()
        await self.state("listening")

    async def heard_turn(self, text: str) -> None:
        """Hands-free: Gradium's VAD says the user is done."""
        await self.interrupt()
        await self.send({"type": "transcript", "text": text})
        await self.start_turn(self.run_turn(text))

    async def start_turn(self, coro) -> None:
        """One turn at a time: cancel the running one first. Turns run as tasks so the
        receive loop can still hear an interrupt."""
        await self.interrupt()
        self.turn_task = asyncio.create_task(coro)

    async def interrupt(self) -> bool:
        """Cancel the running turn: the agent call and the TTS socket. True if one was running."""
        task, self.turn_task = self.turn_task, None
        if task is None or task.done():
            return False
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass
        log.info("turn %d interrupted", self.turns)
        return True

    async def handle(self, msg: dict) -> None:
        kind = msg.get("type")
        if kind == "audio" and self.listener is not None and isinstance(msg.get("data"), str):
            self.listener.push(msg["data"])  # hands-free: the mic never stops, no audio_end
        elif kind == "audio" and isinstance(msg.get("data"), str):
            if self.stt is None:  # a new press; talking over the mascot interrupts it
                await self.interrupt()
                self.stt = voice.Transcriber()
                await self.state("listening")
            self.stt.push(msg["data"])
        elif kind == "audio_end" and self.stt is not None:
            stt, self.stt = self.stt, None
            await self.start_turn(self.voice_turn(stt))
        elif kind == "text" and isinstance(msg.get("text"), str):
            await self.start_turn(self.run_turn(msg["text"]))
        elif kind == "screen":
            try:
                image = base64.b64decode(msg.get("data"), validate=True)
            except (TypeError, ValueError):
                image = b""
            if msg.get("mime") in SCREEN_MIMES and 0 < len(image) <= SCREEN_MAX_BYTES:
                store_screenshot(image, msg["mime"], decode_recent(msg.get("recent"), len(image)))
            else:
                log.warning("ignored screen frame: bad mime, base64 or size")
        elif kind == "interrupt":
            if await self.interrupt():
                await self.state("idle")
        else:
            log.warning("ignored message type %r", kind)

    def close(self) -> None:
        if self.stt is not None:
            self.stt.cancel()
        if self.listener is not None:
            self.listener.cancel()
        if self.turn_task is not None:
            self.turn_task.cancel()


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    # A malformed frame: bad JSON (ValueError), a binary frame (KeyError), bad base64 (ValueError).
    # Not RuntimeError: Starlette raises it on every receive once the socket is gone.
    bad_frame = (ValueError, KeyError, TypeError)
    try:
        try:
            hello = await ws.receive_json()
        except bad_frame:
            hello = None
        if not isinstance(hello, dict) or hello.get("type") != "hello" or not token_ok(hello.get("token")):
            await ws.close(code=1008)
            return
        session = Session(ws, handsfree=hello.get("mode") == "handsfree")
        await session.agent.start()
        await session.send({"type": "ready"})
        sessions.add(session)
        try:
            while True:
                try:
                    msg = await ws.receive_json()
                    if isinstance(msg, dict):
                        await session.handle(msg)
                except bad_frame as e:
                    log.warning("ignored malformed frame: %r", e)
        finally:
            sessions.discard(session)
            session.close()
    except WebSocketDisconnect:
        pass
