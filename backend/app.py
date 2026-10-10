"""FastAPI server: the app's WebSocket, the screenshot endpoint, and turn orchestration.

Protocol and interfaces: docs/contracts.md. Run from backend/:
    uv run uvicorn app:app --reload --port 8000
"""

import asyncio
import hmac
import json
import logging
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

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
            log.warning("agent.py not available yet, using StubAgent")
    return StubAgent()


def token_ok(token: object) -> bool:
    expected = os.environ.get("APP_TOKEN", "")
    return bool(expected) and isinstance(token, str) and hmac.compare_digest(token, expected)


app = FastAPI()


@app.get("/health")
async def health():
    return {"ok": True, "workspace": os.environ.get("WORKSPACE_MODE", "fixture")}


class Session:
    def __init__(self, ws: WebSocket):
        self.ws = ws
        self.agent = make_agent()
        self.turns = 0
        self.stt: voice.Transcriber | None = None
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

        try:
            reply = await self.agent.turn(text, None, on_status)
        except Exception:
            log.exception("turn failed")
            await self.send({"type": "error", "message": "Sorry, something went wrong."})
            await self.state("idle")
            return
        timings["agent"] = time.monotonic() - t0

        await self.send({"type": "reply", "say": reply["say"], "cards": reply["cards"]})
        if cards_to_a2ui and reply["cards"]:
            messages = cards_to_a2ui(f"reply-{self.turns}", reply["cards"])
            await self.send({"type": "a2ui", "messages": messages})
        await self.state("speaking")
        try:
            async for chunk in voice.speak(reply["say"]):
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

    def start_turn(self, coro) -> None:
        """Turns run as tasks so the receive loop can still hear an interrupt."""
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
        if kind == "audio" and isinstance(msg.get("data"), str):
            if self.stt is None:  # a new press; talking over the mascot interrupts it
                await self.interrupt()
                self.stt = voice.Transcriber()
                await self.state("listening")
            self.stt.push(msg["data"])
        elif kind == "audio_end" and self.stt is not None:
            stt, self.stt = self.stt, None
            self.start_turn(self.voice_turn(stt))
        elif kind == "text" and isinstance(msg.get("text"), str):
            await self.interrupt()
            self.start_turn(self.run_turn(msg["text"]))
        elif kind == "interrupt":
            if await self.interrupt():
                await self.state("idle")
        else:
            log.warning("ignored message type %r", kind)

    def close(self) -> None:
        if self.stt is not None:
            self.stt.cancel()
        if self.turn_task is not None:
            self.turn_task.cancel()


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    try:
        hello = await ws.receive_json()
        if hello.get("type") != "hello" or not token_ok(hello.get("token")):
            await ws.close(code=1008)
            return
        session = Session(ws)
        await session.agent.start()
        await session.send({"type": "ready"})
        try:
            while True:
                msg = await ws.receive_json()
                if isinstance(msg, dict):
                    await session.handle(msg)
        finally:
            session.close()
    except WebSocketDisconnect:
        pass
