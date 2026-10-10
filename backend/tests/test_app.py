import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

import app as server


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("MOCK_AGENT", "1")
    return TestClient(server.app)


def receive_until(ws, msg_type):
    msgs = []
    while True:
        msg = ws.receive_json()
        msgs.append(msg)
        if msg["type"] == msg_type and msg.get("state", "idle") == "idle":
            return msgs


def test_text_turn_order(client):
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"type": "hello", "token": "test-token"})
        assert ws.receive_json() == {"type": "ready"}
        ws.send_json({"type": "text", "text": "Can I make it?"})
        msgs = receive_until(ws, "state")
    types = [(m["type"], m.get("state")) for m in msgs]
    assert types[0] == ("state", "thinking")
    assert ("state", "searching") in types
    reply_at = types.index(("reply", None))
    assert types.index(("state", "searching")) < reply_at < types.index(("state", "idle"))
    reply = msgs[reply_at]
    assert [c["kind"] for c in reply["cards"]] == ["conflict", "train"]


def test_wrong_token_is_rejected(client):
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"type": "hello", "token": "nope"})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 1008
