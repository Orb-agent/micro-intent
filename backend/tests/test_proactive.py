"""contracts § Proactive turns: a freshly read screenshot starts a turn on its own."""

import asyncio
import json

import pytest
from fastapi.testclient import TestClient

import app as server
from tests.test_agent import DEMO, SCREEN, FakeInteraction, FakeStep, fake_interactions, sbb_requests  # noqa: F401
from tests.test_app import FakeTranscriber, fake_speak, kinds, receive_turn
from tests.test_screen import AUTH, connect

PNG = (server.FIXTURES / "screen.png").read_bytes()  # Anna's dinner invitation in Bern
OFFER = DEMO | {"say": "Anna asks about dinner in Bern at seven. Your call ends at quarter to six and "
                       "the 18:01 gets you there. Shall I add it?"}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("PROACTIVE_SCREEN", "1")
    monkeypatch.setattr(server.voice, "speak", fake_speak)
    monkeypatch.setattr(server.voice, "Transcriber", FakeTranscriber)
    monkeypatch.setattr(server, "read_screen", lambda image, mime: SCREEN if image == PNG else {"summary": "Home"})
    monkeypatch.setattr(server, "latest", None)
    monkeypatch.setattr(server, "offered", None)
    with TestClient(server.app) as client:  # one event loop, so vision tasks outlive the POST
        yield client


class RecordingAgent:
    """Speaks up about every screen; records what each turn was asked."""

    def __init__(self, delay=0.0):
        self.texts, self.delay = [], delay

    async def start(self):
        pass

    async def turn(self, text, screen, on_status):
        self.texts.append(text)
        await asyncio.sleep(self.delay)
        return OFFER


def test_screenshot_starts_a_proactive_turn(client, monkeypatch, fake_interactions, sbb_requests):
    monkeypatch.setenv("MOCK_AGENT", "0")
    monkeypatch.setenv("WORKSPACE_MODE", "fixture")
    model = fake_interactions(FakeInteraction("i-0", [FakeStep("function_call", "respond", OFFER)]))
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json() == {"type": "screen_ok", "summary": SCREEN["summary"]}
    msgs = receive_turn(ws)
    ctx.__exit__(None, None, None)
    assert kinds(msgs) == [
        "state:thinking", "state:searching", "reply", "a2ui", "state:speaking",
        "audio", "audio", "audio_end", "state:idle",
    ]
    assert msgs[2] == {"type": "reply", "say": OFFER["say"], "cards": OFFER["cards"]}
    assert [c["kind"] for c in msgs[2]["cards"]] == ["conflict", "train"]
    asked = model.calls[0]["input"][-1]["content"][0]["text"]
    assert server.PROACTIVE in asked and "<screen_context>" in asked and "<trains>" in asked
    assert len(sbb_requests) == 1  # the train prefetch for the plan on screen
    assert server.latest.used  # the follow-up "yes" doesn't get the screen a second time


def test_cached_screenshot_starts_no_turn(client, monkeypatch):
    agent = RecordingAgent()
    monkeypatch.setattr(server, "make_agent", lambda: agent)
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json()["type"] == "screen_ok"
    receive_turn(ws)  # the proactive turn
    client.post("/screenshot", content=PNG, headers=AUTH)  # the same bytes: the cached reading
    assert ws.receive_json()["type"] == "screen_ok"
    ws.send_json({"type": "text", "text": "Thanks"})
    assert kinds(receive_turn(ws))[0] == "state:thinking"
    ctx.__exit__(None, None, None)
    assert agent.texts == [server.PROACTIVE, "Thanks"]


def test_no_proactive_turn_while_the_user_talks_or_a_turn_runs(client, monkeypatch):
    agent = RecordingAgent(delay=0.5)
    monkeypatch.setattr(server, "make_agent", lambda: agent)
    ctx, ws = connect(client)
    ws.send_json({"type": "text", "text": "Can I make it?"})
    assert ws.receive_json() == {"type": "state", "state": "thinking"}
    client.post("/screenshot", content=PNG, headers=AUTH)  # read while the turn runs
    msgs = receive_turn(ws)
    assert "screen_ok" in kinds(msgs)
    ws.send_json({"type": "audio", "data": "AAAA"})  # holding the orb
    assert ws.receive_json() == {"type": "state", "state": "listening"}
    client.post("/screenshot", content=b"home screen", headers=AUTH)
    assert ws.receive_json() == {"type": "screen_ok", "summary": "Home"}
    ws.send_json({"type": "audio_end"})
    msgs = receive_turn(ws)
    ctx.__exit__(None, None, None)
    assert kinds(msgs)[:2] == ["transcript", "state:thinking"]
    assert agent.texts == ["Can I make it?", "Can I make it?"]  # never PROACTIVE
