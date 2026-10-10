import asyncio

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

import app as server


class FakeTranscriber:
    def __init__(self):
        self.chunks = []

    def push(self, b64):
        self.chunks.append(b64)

    async def finish(self):
        return "Can I make it?" if self.chunks else ""

    def cancel(self):
        pass


class OfflineTranscriber(server.voice.Transcriber):
    """The real push(), which base64-decodes, without opening Gradium."""

    def __init__(self):
        self._queue = asyncio.Queue()

    def cancel(self):
        pass


async def fake_speak(text):
    for chunk in ("AAAA", "BBBB"):
        yield chunk


async def slow_speak(text):
    yield "AAAA"
    await asyncio.sleep(5)  # long enough to interrupt
    yield "BBBB"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("MOCK_AGENT", "1")
    monkeypatch.setattr(server.voice, "speak", fake_speak)
    monkeypatch.setattr(server.voice, "Transcriber", FakeTranscriber)
    return TestClient(server.app)


def connect(client):
    ws = client.websocket_connect("/ws")
    conn = ws.__enter__()
    conn.send_json({"type": "hello", "token": "test-token"})
    assert conn.receive_json() == {"type": "ready"}
    return ws, conn


def receive_turn(ws):
    """Messages up to and including the final `state: idle`."""
    msgs = []
    while True:
        msgs.append(ws.receive_json())
        if msgs[-1] == {"type": "state", "state": "idle"}:
            return msgs


def kinds(msgs):
    return [m["type"] + (":" + m["state"] if m["type"] == "state" else "") for m in msgs]


def test_text_turn_order(client):
    ctx, ws = connect(client)
    ws.send_json({"type": "text", "text": "Can I make it?"})
    msgs = receive_turn(ws)
    ctx.__exit__(None, None, None)
    assert kinds(msgs) == [
        "state:thinking", "state:searching", "reply", "state:speaking",
        "audio", "audio", "audio_end", "state:idle",
    ]
    reply = msgs[2]
    assert [c["kind"] for c in reply["cards"]] == ["conflict", "train"]
    assert msgs[4]["data"] == "AAAA"


def test_voice_turn(client):
    ctx, ws = connect(client)
    ws.send_json({"type": "audio", "data": "AAAA"})
    ws.send_json({"type": "audio", "data": "BBBB"})
    ws.send_json({"type": "audio_end"})
    msgs = receive_turn(ws)
    ctx.__exit__(None, None, None)
    assert kinds(msgs)[:4] == ["state:listening", "transcript", "state:thinking", "state:searching"]
    assert msgs[1]["text"] == "Can I make it?"


def test_audio_end_without_audio_is_ignored(client):
    ctx, ws = connect(client)
    ws.send_json({"type": "audio_end"})  # no audio: ignored
    ws.send_json({"type": "text", "text": "hi"})
    assert ws.receive_json() == {"type": "state", "state": "thinking"}
    ctx.__exit__(None, None, None)


def test_wrong_token_is_rejected(client):
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"type": "hello", "token": "nope"})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 1008


def test_non_dict_hello_is_rejected(client):
    with client.websocket_connect("/ws") as ws:
        ws.send_json(["hello", "test-token"])
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 1008


def test_malformed_frames_are_ignored(client):
    ctx, ws = connect(client)
    ws.send_text("{not json")
    ws.send_bytes(b"\x00")
    ws.send_json({"type": "text", "text": "hi"})
    assert ws.receive_json() == {"type": "state", "state": "thinking"}
    ctx.__exit__(None, None, None)


def test_bad_base64_audio_is_ignored(client, monkeypatch):
    monkeypatch.setattr(server.voice, "Transcriber", OfflineTranscriber)
    ctx, ws = connect(client)
    ws.send_json({"type": "audio", "data": "AAA"})  # bad padding: push() raises binascii.Error
    assert ws.receive_json() == {"type": "state", "state": "listening"}
    ws.send_json({"type": "text", "text": "hi"})
    assert ws.receive_json() == {"type": "state", "state": "thinking"}
    ctx.__exit__(None, None, None)


def speak_slowly_until_first_audio(client, monkeypatch):
    monkeypatch.setattr(server.voice, "speak", slow_speak)
    ctx, ws = connect(client)
    ws.send_json({"type": "text", "text": "Can I make it?"})
    while ws.receive_json()["type"] != "audio":
        pass
    return ctx, ws


def test_interrupt_stops_speech(client, monkeypatch):
    ctx, ws = speak_slowly_until_first_audio(client, monkeypatch)
    ws.send_json({"type": "interrupt"})
    assert ws.receive_json() == {"type": "state", "state": "idle"}  # no more audio, no audio_end
    ctx.__exit__(None, None, None)


def test_talking_over_the_mascot_interrupts(client, monkeypatch):
    ctx, ws = speak_slowly_until_first_audio(client, monkeypatch)
    ws.send_json({"type": "audio", "data": "AAAA"})
    assert ws.receive_json() == {"type": "state", "state": "listening"}
    ws.send_json({"type": "audio_end"})
    msgs = receive_turn(ws)
    ctx.__exit__(None, None, None)
    assert kinds(msgs)[:2] == ["transcript", "state:thinking"]
