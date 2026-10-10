"""Tests for WP3 Agent with Interactions API (fixtures/mocks)."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import httpx
import pytest

import agent
from agent import Agent, RESPOND_SCHEMA, SBB_SCHEMA, SORRY, schema_error

FIXTURES = Path(__file__).parent.parent / "fixtures"
DEMO = json.loads((FIXTURES / "demo_reply.json").read_text())
SCREEN = json.loads((FIXTURES / "screen.json").read_text())
SBB = (FIXTURES / "sbb_zurich_bern.json").read_bytes()
SBB_ARGS = {"from_station": "Zürich HB", "to_station": "Bern", "depart_after": "2026-10-15T17:55:00+02:00"}
HANG = object()


class FakeStep:
    def __init__(self, step_type: str, name: str | None = None, arguments: dict | None = None, id: str = "call-1"):
        self.type = step_type
        self.name = name
        self.arguments = arguments or {}
        self.id = id

    def model_dump(self, **kwargs):
        return {"type": self.type, "name": self.name, "arguments": self.arguments, "id": self.id}


class FakeInteraction:
    def __init__(self, id: str, steps: list[FakeStep], status: str = "requires_action"):
        self.id = id
        self.steps = steps
        self.status = status


class FakeInteractions:
    def __init__(self, *rounds: Any):
        self.rounds = list(rounds)
        self.calls: list[dict[str, Any]] = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        r = self.rounds.pop(0)
        if r is HANG:
            await asyncio.Event().wait()
        if isinstance(r, Exception):
            raise r
        return r


@pytest.fixture
def fake_interactions(monkeypatch):
    def install(*rounds):
        inter = FakeInteractions(*rounds)
        fake_client = SimpleNamespace(aio=SimpleNamespace(interactions=inter))
        monkeypatch.setattr(agent, "client", lambda: fake_client)
        return inter

    return install


@pytest.fixture
def sbb_requests(monkeypatch):
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(200, content=SBB)

    real = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    return requests


@pytest.fixture
async def ag():
    a = Agent()
    await a.start()
    return a


def statuses():
    seen = []

    async def on_status(label):
        seen.append(label)

    return seen, on_status


def test_schema_error_validation():
    # Valid respond
    assert schema_error(DEMO, RESPOND_SCHEMA, "respond") is None

    # Missing say
    assert schema_error({"cards": []}, RESPOND_SCHEMA, "respond") == "respond.say is missing"

    # Too many cards
    assert "at most 3" in (schema_error({"say": "Hi", "cards": [1, 2, 3, 4]}, RESPOND_SCHEMA, "respond") or "")

    # Invalid card kind
    bad_card = {"say": "Hi", "cards": [{"kind": "spaceship"}]}
    assert "kind must be train, conflict, event or flight" in (schema_error(bad_card, RESPOND_SCHEMA, "respond") or "")

    # Valid SBB args
    assert schema_error(SBB_ARGS, SBB_SCHEMA, "sbb_connections") is None


@pytest.mark.asyncio
async def test_agent_turn_with_prefetch(ag, fake_interactions, sbb_requests):
    # Model immediately calls respond on step 0 because prefetch provided trains
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "respond", DEMO)])
    inter = fake_interactions(i0)
    seen, on_status = statuses()

    reply = await ag.turn("Can I make it?", SCREEN, on_status)
    assert reply == DEMO
    assert seen == ["Checking trains…"]
    assert len(inter.calls) == 1
    assert ag.last_interaction_id == "i-0"


@pytest.mark.asyncio
async def test_agent_turn_with_tool_call_then_respond(ag, fake_interactions, sbb_requests):
    # Step 0: sbb_connections, Step 1: respond
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "sbb_connections", SBB_ARGS, id="call-sbb")])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "respond", DEMO, id="call-resp")])
    inter = fake_interactions(i0, i1)
    seen, on_status = statuses()

    reply = await ag.turn("Can I make it?", None, on_status)
    assert reply == DEMO
    assert seen == ["Checking trains…"]
    assert len(inter.calls) == 2
    assert inter.calls[1]["previous_interaction_id"] == "i-0"
    # Verify function_result payload sent in step 1
    input_results = inter.calls[1]["input"]
    assert len(input_results) == 1
    assert input_results[0]["type"] == "function_result"
    assert input_results[0]["call_id"] == "call-sbb"


@pytest.mark.asyncio
async def test_invalid_cards_retry_once_then_no_cards(ag, fake_interactions, sbb_requests):
    bad = {"say": "Take the 18:01.", "cards": [{**DEMO["cards"][1], "departure": "18:01"}]}  # not ISO date-time
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "respond", bad, id="call-0")])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "respond", bad, id="call-1")])
    inter = fake_interactions(i0, i1)
    seen, on_status = statuses()

    reply = await ag.turn("Can I make it?", None, on_status)
    assert reply == {"say": "Take the 18:01.", "cards": []}
    assert len(inter.calls) == 2


@pytest.mark.asyncio
async def test_cancelled_turn_leaves_history_unchanged(ag, fake_interactions):
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "respond", DEMO)])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "sbb_connections", SBB_ARGS)])
    fake_interactions(i0, i1, HANG)
    seen, on_status = statuses()

    # Completed turn
    await ag.turn("Can I make it?", SCREEN, on_status)
    assert ag.last_interaction_id == "i-0"

    # In-flight second turn cancelled
    task = asyncio.create_task(ag.turn("And the next train?", None, on_status))
    await asyncio.sleep(0.01)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    # last_interaction_id remains i-0
    assert ag.last_interaction_id == "i-0"


@pytest.mark.asyncio
async def test_model_error_returns_apology(ag, fake_interactions):
    fake_interactions(RuntimeError("503 Service Unavailable"))
    seen, on_status = statuses()

    reply = await ag.turn("Can I make it?", None, on_status)
    assert reply == {"say": SORRY, "cards": []}
