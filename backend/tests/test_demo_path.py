"""Smoke test of the demo path without network: scripted planner plus scripted SBB timetable."""

import os

os.environ["MICRO_INTENT_FORCE_FALLBACK"] = "true"
os.environ["GEMINI_API_KEY"] = ""
os.environ["GOOGLE_API_KEY"] = ""
os.environ["CALENDAR_SOURCE"] = "mock"

from fastapi.testclient import TestClient  # noqa: E402

from app import sbb  # noqa: E402
from app.main import app  # noqa: E402

DEMO = {
    "intent": "Am I free, and how do I get there from Winterthur?",
    "context": {
        "url": "https://luma.com/agentic-ai-hack-zurich",
        "title": "{Tech: Europe} Agentic AI Hack Zurich · Luma",
        "selection": {"text": "Saturday, October 10 · 18:00 - 21:00 · Zurich"},
    },
    "now": "2026-10-10T14:00:00+02:00",
}


def _components(turn):
    return {c["component"]: c for m in turn["cards"] if "updateComponents" in m for c in m["updateComponents"]["components"]}


def _action(name, action_id, surface_id):
    return {
        "version": "v0.9.1",
        "action": {
            "name": name,
            "surfaceId": surface_id,
            "sourceComponentId": "root",
            "timestamp": "2026-10-10T12:00:00Z",
            "context": {"action_id": action_id},
        },
    }


def test_demo_path_offline(monkeypatch):
    def no_network(*args, **kwargs):
        raise OSError("offline")

    monkeypatch.setattr(sbb.httpx, "get", no_network)
    client = TestClient(app)
    assert client.post("/demo/reset").json() == {"ok": True}

    turn = client.post("/intent", json=DEMO).json()
    assert turn["source"] == "fallback"
    assert "Team sync" in turn["say"]
    comps = _components(turn)
    assert comps["EventCard"]["availability"] == "conflict"
    assert comps["EventCard"]["addAction"]["event"]["name"] == "confirm"
    conflict = comps["ConflictCard"]
    assert conflict["conflict"]["title"] == "Team sync"
    train = comps["TrainCard"]
    assert train["live"] is False
    recommended = next(c for c in train["connections"] if c["recommended"])
    assert recommended["products"][0].startswith("IC")

    move_id = conflict["move"]["action"]["event"]["context"]["action_id"]
    surface = next(
        m["createSurface"]["surfaceId"] for m in turn["cards"] if "createSurface" in m and "conflict" in m["createSurface"]["surfaceId"]
    )
    done = client.post("/action", json=_action("confirm", move_id, surface)).json()
    assert done["status"] == "done"
    assert done["cards"] == [{"version": "v0.9.1", "deleteSurface": {"surfaceId": surface}}]
    assert client.post("/action", json=_action("confirm", move_id, surface)).json()["status"] == "already_done"

    # The conflict is gone after the approved move.
    again = _components(client.post("/intent", json=DEMO).json())
    assert again["EventCard"]["availability"] == "free"
    assert "ConflictCard" not in again
