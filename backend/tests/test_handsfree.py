import asyncio
import json
from types import SimpleNamespace

import aiohttp
import pytest
from fastapi.testclient import TestClient

import app as server
import voice
from test_app import fake_speak, kinds, receive_turn, slow_speak


def step(p2, p_other=0.9):
    """A `step` whose 2.0 s horizon is not at index 2, so picking by index would read p_other."""
    return {"type": "step", "vad": [
        {"horizon_s": 0.5, "inactivity_prob": p_other},
        {"horizon_s": 2.0, "inactivity_prob": p2},
        {"horizon_s": 1.0, "inactivity_prob": p_other},
        {"horizon_s": 3.0, "inactivity_prob": p_other},
    ]}


def text(t):
    return {"type": "text", "text": t, "start_s": 0.0}


def test_end_of_turn_rule():
    turn = voice.TurnDetector()
    assert not any(turn.feed(step(0.99)) for _ in range(5))  # silence before any words: no turn
    assert not turn.feed(text("Can"))
    assert not turn.feed(text(" "))  # blank segments are not words
    assert [turn.feed(step(0.9)) for _ in range(2)] == [False, False]
    assert not turn.feed(step(0.4, p_other=0.99))  # 2.0 s horizon dips: the streak restarts
    assert not turn.feed(text("I"))
    assert [turn.feed(step(0.6, p_other=0.0)) for _ in range(3)] == [False, False, True]
    assert turn.take() == "Can I"
    assert not any(turn.feed(step(0.99)) for _ in range(5))  # next turn starts empty


async def test_flush_then_emit_one_turn():
    msgs = [text("Can"), text("I"), step(0.9), step(0.9), step(0.9), step(0.9),
            text("go"), {"type": "flushed", "flush_id": 0}, text("Next")]
    events, flushes = [], []

    async def frames():
        for m in msgs:
            yield SimpleNamespace(type=aiohttp.WSMsgType.TEXT, data=json.dumps(m))

    async def send_flush():
        flushes.append(len(events))

    async def on_speech():
        events.append("speech")

    async def on_turn(t):
        events.append(t)

    stt = SimpleNamespace(_ws=frames(), send_flush=send_flush)
    await voice.ContinuousTranscriber(on_speech, on_turn)._listen(stt)
    assert events == ["speech", "Can I go", "speech"]  # the word after `flush` joins the turn
    assert flushes == [1]  # one flush, after the first words


class FakeListener:
    """Stands in for voice.ContinuousTranscriber; the test scripts it through `audio` data:
    "words" is a turn's first words, "end:<text>" is the end of the turn, anything else is mic noise."""

    def __init__(self, on_speech, on_turn):
        self.on_speech, self.on_turn = on_speech, on_turn
        self.queue = asyncio.Queue()
        self.task = None

    def push(self, b64):
        self.task = self.task or asyncio.create_task(self.run())
        self.queue.put_nowait(b64)

    async def run(self):
        while True:
            data = await self.queue.get()
            if data == "words":
                await self.on_speech()
            elif data.startswith("end:"):
                await self.on_turn(data[4:])

    def cancel(self):
        if self.task:
            self.task.cancel()


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("MOCK_AGENT", "1")
    monkeypatch.setattr(server.voice, "speak", fake_speak)
    monkeypatch.setattr(server.voice, "ContinuousTranscriber", FakeListener)
    return TestClient(server.app)


def hello(ws):
    ws.send_json({"type": "hello", "token": "test-token", "mode": "handsfree"})
    assert ws.receive_json() == {"type": "ready"}


def mic(ws, data):
    ws.send_json({"type": "audio", "data": data})


def test_end_of_turn_starts_a_turn(client):
    with client.websocket_connect("/ws") as ws:
        hello(ws)
        mic(ws, "noise")
        mic(ws, "words")
        assert ws.receive_json() == {"type": "state", "state": "listening"}
        mic(ws, "end:Can I make it?")
        msgs = receive_turn(ws)
    assert kinds(msgs) == [
        "transcript", "state:thinking", "state:searching", "reply", "state:speaking",
        "audio", "audio", "audio_end", "state:idle",
    ]
    assert msgs[0]["text"] == "Can I make it?"


def test_speech_during_a_turn_interrupts_it(client, monkeypatch):
    monkeypatch.setattr(server.voice, "speak", slow_speak)
    with client.websocket_connect("/ws") as ws:
        hello(ws)
        mic(ws, "words")
        mic(ws, "end:Can I make it?")
        while ws.receive_json()["type"] != "audio":
            pass
        mic(ws, "words")  # the user talks over the mascot
        assert ws.receive_json() == {"type": "state", "state": "listening"}  # no more audio, no audio_end
        ws.send_json({"type": "interrupt"})  # the turn is already cancelled, so no `state: idle`
        mic(ws, "end:And on Friday?")
        msgs = receive_turn(ws)
    assert kinds(msgs)[:2] == ["transcript", "state:thinking"]
    assert msgs[0]["text"] == "And on Friday?"
