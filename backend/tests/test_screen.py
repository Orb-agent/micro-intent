import base64
import json

import pytest
from fastapi.testclient import TestClient

import app as server
from tests.test_app import FakeTranscriber, fake_speak

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
