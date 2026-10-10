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
        self._send_lock = asyncio.Lock()

    async def send(self, msg: dict) -> None:
        async with self._send_lock:
            await self.ws.send_json(msg)

    async def state(self, state: str, label: str | None = None) -> None:
        await self.send({"type": "state", "state": state} | ({"label": label} if label else {}))

    async def run_turn(self, text: str) -> None:
        self.turns += 1
        t0 = time.monotonic()
        timings: dict[str, float] = {}
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
        await self.send({"type": "audio_end"})
        await self.state("idle")
        timings["total"] = time.monotonic() - t0
        log.info("turn %d %r timings %s", self.turns, text, {k: round(v, 2) for k, v in timings.items()})

    async def handle(self, msg: dict) -> None:
        kind = msg.get("type")
        if kind == "text" and isinstance(msg.get("text"), str):
            await self.run_turn(msg["text"])
        else:
            log.warning("ignored message type %r", kind)


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
        while True:
            msg = await ws.receive_json()
            if isinstance(msg, dict):
                await session.handle(msg)
    except WebSocketDisconnect:
        pass
