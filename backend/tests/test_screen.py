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
