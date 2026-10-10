import asyncio
import base64
import json
import time

import pytest
from fastapi.testclient import TestClient

import app as server
from tests.test_app import FakeTranscriber, fake_speak, kinds, receive_turn

SCREEN = json.loads((server.FIXTURES / "screen.json").read_text())
PNG = b"\x89PNG\r\n\x1a\nfake"
AUTH = {"Authorization": "Bearer test-token", "Content-Type": "image/png"}


def fake_read_screen(image, mime):
    return SCREEN


def failing_read_screen(image, mime):
    raise RuntimeError("Gemini is down")


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("MOCK_AGENT", "1")
    monkeypatch.setattr(server.voice, "speak", fake_speak)
    monkeypatch.setattr(server.voice, "Transcriber", FakeTranscriber)
    monkeypatch.setattr(server, "read_screen", fake_read_screen)
    monkeypatch.setattr(server, "latest", None)
    with TestClient(server.app) as client:  # one event loop, so vision tasks outlive the POST
        yield client


def connect(client):
    ws = client.websocket_connect("/ws")
    conn = ws.__enter__()
    conn.send_json({"type": "hello", "token": "test-token"})
    assert conn.receive_json() == {"type": "ready"}
    return ws, conn


@pytest.mark.parametrize("headers, body, status", [
    ({"Content-Type": "image/png"}, PNG, 401),
    ({"Authorization": "Bearer nope", "Content-Type": "image/png"}, PNG, 401),
    ({"Authorization": "test-token", "Content-Type": "image/png"}, PNG, 401),
    ({"Authorization": "Bearer test-token", "Content-Type": "text/plain"}, PNG, 415),
    (AUTH, b"x" * (server.SCREEN_MAX_BYTES + 1), 413),
    (AUTH, PNG, 204),
    ({"Authorization": "Bearer test-token", "Content-Type": "image/jpeg"}, b"\xff\xd8\xff", 204),
])
def test_post_screenshot_status(client, headers, body, status):
    assert client.post("/screenshot", content=body, headers=headers).status_code == status
    assert (server.latest is not None) == (status == 204)


def test_screen_ok_reaches_session(client):
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json() == {"type": "screen_ok", "summary": SCREEN["summary"]}
    ctx.__exit__(None, None, None)
    assert server.sessions == set()


def test_screen_frame(client, monkeypatch):
    seen = []
    monkeypatch.setattr(server, "read_screen", lambda image, mime: seen.append((image, mime)) or SCREEN)
    ctx, ws = connect(client)
    ws.send_json({"type": "screen", "mime": "image/png", "data": base64.b64encode(PNG).decode()})
    assert ws.receive_json() == {"type": "screen_ok", "summary": SCREEN["summary"]}
    ctx.__exit__(None, None, None)
    assert seen == [(PNG, "image/png")]


def test_bad_screen_frames_are_ignored(client):
    ctx, ws = connect(client)
    ws.send_json({"type": "screen", "mime": "image/png", "data": "not base64!"})
    ws.send_json({"type": "screen", "mime": "image/gif", "data": base64.b64encode(PNG).decode()})
    ws.send_json({"type": "screen", "mime": "image/png"})
    ws.send_json({"type": "text", "text": "hi"})
    assert ws.receive_json() == {"type": "state", "state": "thinking"}  # no screen_ok
    ctx.__exit__(None, None, None)
    assert server.latest is None


def b64(image):
    return base64.b64encode(image).decode()


def send_screen(client, monkeypatch, recent):
    """A `screen` frame with `recent`; returns the read_screen calls as (image, mime, kwargs)."""
    seen = []
    monkeypatch.setattr(server, "read_screen", lambda image, mime, **kw: seen.append((image, mime, kw)) or SCREEN)
    ctx, ws = connect(client)
    ws.send_json({"type": "screen", "mime": "image/png", "data": b64(PNG), "recent": recent})
    assert ws.receive_json() == {"type": "screen_ok", "summary": SCREEN["summary"]}
    ctx.__exit__(None, None, None)
    return seen


def test_screen_frame_with_recent(client, monkeypatch):
    frames = [b"frame 1", b"frame 2", b"frame 3"]
    assert send_screen(client, monkeypatch, [b64(f) for f in frames]) == [(PNG, "image/png", {"earlier": frames})]


MB = 1024 * 1024


@pytest.mark.parametrize("recent", [
    [b64(b"frame 1"), "not base64!", b64(b"frame 3")],
    [b64(b"frame 1"), 7],
    [b64(b"frame 1"), ""],
    b64(b"frame 1"),
    [b64(b"x" * 4 * MB)] * 2,  # 8 MB, over the limit with the current frame
    [b64(b"frame")] * 10,
], ids=["bad base64", "not a string", "empty image", "not a list", "over 8 MB", "10 frames"])
def test_bad_recent_keeps_the_current_frame(client, monkeypatch, caplog, recent):
    assert send_screen(client, monkeypatch, recent) == [(PNG, "image/png", {})]
    assert "dropped recent screen frames" in caplog.text


class RecordingAgent:
    def __init__(self):
        self.screens = []

    async def start(self):
        pass

    async def turn(self, text, screen, on_status):
        self.screens.append(screen)
        return json.loads((server.FIXTURES / "demo_reply.json").read_text())


@pytest.fixture
def agent(monkeypatch):
    agent = RecordingAgent()
    monkeypatch.setattr(server, "make_agent", lambda: agent)
    return agent


def ask(ws):
    ws.send_json({"type": "text", "text": "Can I make it?"})
    return receive_turn(ws)


def test_next_turn_gets_the_screen_once(client, agent):
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json()["type"] == "screen_ok"
    ask(ws)
    ask(ws)
    ctx.__exit__(None, None, None)
    assert agent.screens == [SCREEN, None]


def test_turn_waits_for_running_vision(client, agent, monkeypatch, caplog):
    monkeypatch.setattr(server, "read_screen", lambda image, mime: time.sleep(0.3) or SCREEN)
    caplog.set_level("INFO", logger="app")
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    msgs = ask(ws)  # sent while vision still runs
    ctx.__exit__(None, None, None)
    assert "screen_ok" in kinds(msgs)
    assert agent.screens == [SCREEN]
    assert "'vision_wait'" in caplog.text


def test_old_screenshot_is_not_used(client, agent):
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json()["type"] == "screen_ok"
    server.latest.at -= server.SCREEN_MAX_AGE + 1
    ask(ws)
    ctx.__exit__(None, None, None)
    assert agent.screens == [None]


def test_turn_moves_on_to_a_newer_screenshot(monkeypatch):
    async def read(image, mime):
        if image == b"A":
            await asyncio.sleep(5)  # slow; cancelled when B arrives
        return {"summary": image.decode()}

    async def turn_while_b_arrives():
        server.store_screenshot(b"A", "image/png")
        turn = asyncio.create_task(server.take_screen())
        await asyncio.sleep(0)  # the turn now waits on A
        server.store_screenshot(b"B", "image/png")
        return await turn

    monkeypatch.setattr(server, "read_screen", read)
    monkeypatch.setattr(server, "latest", None)
    shot, screen = asyncio.run(turn_while_b_arrives())
    assert (shot.id, screen) == (2, {"summary": "B"})


def post_and_ask(client, ws, image):
    client.post("/screenshot", content=image, headers=AUTH)
    assert ws.receive_json()["type"] == "screen_ok"  # still sent for a reused reading
    ask(ws)


def test_unchanged_screen_is_read_once(client, agent, monkeypatch):
    seen = []
    monkeypatch.setattr(server, "read_screen", lambda image, mime: seen.append(image) or {"summary": image.decode()})
    ctx, ws = connect(client)
    for image in (b"chat", b"chat", b"calendar", b"chat"):
        post_and_ask(client, ws, image)
    server.latest.read_at -= server.SCREEN_MAX_AGE + 1  # vision read "today" too long ago
    post_and_ask(client, ws, b"chat")
    ctx.__exit__(None, None, None)
    assert seen == [b"chat", b"calendar", b"chat", b"chat"]
    assert [s["summary"] for s in agent.screens] == ["chat", "chat", "calendar", "chat", "chat"]  # each turn gets it


def test_failed_reading_is_not_reused(client, agent, monkeypatch):
    seen = []

    def down_once(image, mime):
        seen.append(image)
        if len(seen) == 1:
            raise RuntimeError("Gemini is down")
        return SCREEN

    monkeypatch.setattr(server, "read_screen", down_once)
    ctx, ws = connect(client)
    post_and_ask(client, ws, PNG)
    post_and_ask(client, ws, PNG)
    ctx.__exit__(None, None, None)
    assert len(seen) == 2 and agent.screens == [None, SCREEN]


def test_vision_failure(client, agent, monkeypatch):
    monkeypatch.setattr(server, "read_screen", failing_read_screen)
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json() == {"type": "screen_ok"}
    msgs = ask(ws)
    ctx.__exit__(None, None, None)
    assert "reply" in kinds(msgs)
    assert agent.screens == [None]


def test_interrupted_turn_leaves_the_screen_for_the_re_ask(client, agent, monkeypatch):
    calls = []

    async def slow_first_turn(text, screen, on_status):
        calls.append(screen)
        if len(calls) == 1:
            await asyncio.sleep(5)  # the user interrupts this one
        return json.loads((server.FIXTURES / "demo_reply.json").read_text())

    monkeypatch.setattr(agent, "turn", slow_first_turn)
    ctx, ws = connect(client)
    client.post("/screenshot", content=PNG, headers=AUTH)
    assert ws.receive_json()["type"] == "screen_ok"
    ws.send_json({"type": "text", "text": "Can I make it?"})
    deadline = time.monotonic() + 2
    while not calls and time.monotonic() < deadline:
        time.sleep(0.01)
    ws.send_json({"type": "text", "text": "Wait, can I make it?"})  # interrupts the first turn
    receive_turn(ws)
    ctx.__exit__(None, None, None)
    assert calls == [SCREEN, SCREEN]
