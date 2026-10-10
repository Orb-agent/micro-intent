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
async def ag(monkeypatch):
    monkeypatch.setenv("WORKSPACE_MODE", "fixture")  # agent.py loads backend/.env, which may say rest
    a = Agent()
    await a.start()
    return a


def user_text(call: dict) -> str:
    """The text of the last user_input step a create call sent."""
    return [s for s in call["input"] if s["type"] == "user_input"][-1]["content"][0]["text"]


def results(call: dict) -> list[dict]:
    """The function_result steps that close a create call's input."""
    out = []
    for s in reversed(call["input"]):
        if s["type"] != "function_result":
            break
        out.insert(0, s)
    return out


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
    assert "kind must be train, conflict, event, flight or link" in (schema_error(bad_card, RESPOND_SCHEMA, "respond") or "")

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
    assert inter.calls[0]["store"] is False  # store=True added 1.5-6 s per step
    assert "<trains>" in user_text(inter.calls[0])
    assert [s["type"] for s in ag.history] == ["user_input", "function_call", "function_result"]


@pytest.mark.asyncio
async def test_prefetch_skips_all_day_events(ag, fake_interactions, sbb_requests):
    # Calendar REST gives all-day events a bare date; comparing it with the plan's time used to raise.
    ag.events.append({"title": "Holiday", "start": "2026-10-15", "end": "2026-10-16", "source": "calendar"})
    fake_interactions(FakeInteraction("i-0", [FakeStep("function_call", "respond", DEMO)]))
    seen, on_status = statuses()

    assert await ag.turn("Can I make it?", SCREEN, on_status) == DEMO
    assert len(sbb_requests) == 1


@pytest.mark.asyncio
async def test_no_conflict_connection_defaults_to_winterthur(ag, monkeypatch):
    ag.events = []
    queries = []

    async def connections(**args):
        queries.append(args)
        return {"connections": []}

    monkeypatch.setattr(agent, "sbb_connections", connections)
    _, on_status = statuses()
    now = agent.datetime(2026, 10, 15, 15, 0, tzinfo=agent.TZ)
    result = await ag._prefetch_trains(SCREEN, now, on_status)
    assert result["query"] == {
        "from_station": "Winterthur", "to_station": "Bern",
        "depart_after": "2026-10-15T17:00:00+02:00",
    }
    assert queries == [result["query"]]
    # Zurich now needs a connection; Winterthur is the local default.
    local = {"proposal": {**SCREEN["proposal"], "place": "Winterthur"}}
    assert await ag._prefetch_trains(local, now, on_status) is None


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
    # Step 1 resends the whole turn: the question, the model's call unmodified, then its result
    sent = inter.calls[1]["input"]
    assert [(s["type"], s.get("call_id") or s.get("id")) for s in sent] == [
        ("user_input", None), ("function_call", "call-sbb"), ("function_result", "call-sbb")
    ]
    assert sent[1] == FakeStep("function_call", "sbb_connections", SBB_ARGS, id="call-sbb").model_dump()


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
    # contracts § Tools: forced function calling, respond only, on the retry
    assert inter.calls[1]["generation_config"]["tool_choice"] == {"allowed_tools": {"mode": "any", "tools": ["respond"]}}


@pytest.mark.asyncio
async def test_cancelled_turn_leaves_history_unchanged(ag, fake_interactions):
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "respond", DEMO)])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "sbb_connections", SBB_ARGS)])
    fake_interactions(i0, i1, HANG)
    seen, on_status = statuses()

    # Completed turn
    await ag.turn("Can I make it?", SCREEN, on_status)
    before = list(ag.history)

    # In-flight second turn cancelled
    task = asyncio.create_task(ag.turn("And the next train?", None, on_status))
    await asyncio.sleep(0.01)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert ag.history == before


@pytest.mark.asyncio
async def test_next_turn_answers_the_last_respond_call(ag, fake_interactions):
    # A chained interaction ending on an unanswered call gets a 400, so turn 2 answers turn 1's calls first.
    i0 = FakeInteraction("i-0", [
        FakeStep("function_call", "sbb_connections", SBB_ARGS, id="call-sbb"),
        FakeStep("function_call", "respond", DEMO, id="call-resp"),
    ])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "respond", DEMO, id="call-resp-2")])
    inter = fake_interactions(i0, i1)
    seen, on_status = statuses()

    await ag.turn("Can I make it?", None, on_status)
    assert [s["type"] for s in inter.calls[0]["input"]] == ["user_input"]
    assert user_text(inter.calls[0]) == "Can I make it?"

    await ag.turn("And the next train?", None, on_status)
    sent = inter.calls[1]["input"]
    assert [(s["type"], s.get("call_id")) for s in sent] == [
        ("user_input", None), ("function_call", None), ("function_call", None),
        ("function_result", "call-sbb"), ("function_result", "call-resp"), ("user_input", None)
    ]
    assert json.loads(sent[4]["result"]) == {"ok": True} and not sent[4]["is_error"]
    assert sent[3]["is_error"]
    assert sent[5]["content"] == [{"type": "text", "text": "And the next train?"}]
    assert [r["call_id"] for r in results({"input": ag.history})] == ["call-resp-2"]


@pytest.mark.asyncio
async def test_model_error_returns_apology(ag, fake_interactions):
    fake_interactions(RuntimeError("503 Service Unavailable"))
    seen, on_status = statuses()

    reply = await ag.turn("Can I make it?", None, on_status)
    assert reply == {"say": SORRY, "cards": []}


def test_maps_tools_declared_only_with_key(monkeypatch):
    monkeypatch.delenv("GOOGLE_MAPS_API_KEY", raising=False)
    monkeypatch.setenv("WORKSPACE_MODE", "fixture")
    assert [t["name"] for t in agent.tool_declarations()] == ["flights_search", "sbb_connections", "design_voice", "respond"]
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "test-key")
    assert {"maps_search_places", "maps_route"} <= {t["name"] for t in agent.tool_declarations()}


@pytest.mark.asyncio
async def test_agent_turn_with_maps_route(ag, fake_interactions, monkeypatch):
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "test-key")
    route = (FIXTURES / "maps_route.json").read_bytes()
    real = httpx.AsyncClient
    monkeypatch.setattr(
        httpx, "AsyncClient",
        lambda **kw: real(transport=httpx.MockTransport(lambda r: httpx.Response(200, content=route)), **kw),
    )
    walk = {"origin": "Bern station", "destination": "Bundesplatz 3, Bern", "mode": "WALK"}
    answer = {"say": "It's a nine-minute walk.", "cards": []}
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "maps_route", walk, id="call-route")])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "respond", answer)])
    inter = fake_interactions(i0, i1)
    seen, on_status = statuses()

    assert await ag.turn("How far is the Bundeshaus from the station on foot?", None, on_status) == answer
    assert seen == ["Checking the route…"]
    assert "maps_route" in {t["name"] for t in inter.calls[0]["tools"]}
    result = results(inter.calls[1])[0]
    assert result["call_id"] == "call-route"
    assert json.loads(result["result"]) == {"duration_min": 9, "distance_km": 0.6}


PIRATE = {"description": "A gruff Bristolian pirate, 45 to 60, low gravelly voice, for narration.", "language": "en"}


def respond(say: str, mood: str | None = None, id: str = "i") -> FakeInteraction:
    args = {"say": say, "cards": []} | ({"mood": mood} if mood else {})
    return FakeInteraction(id, [FakeStep("function_call", "respond", args)])


@pytest.mark.asyncio
async def test_designed_voice_speaks_every_later_reply(ag, fake_interactions, monkeypatch):
    designed = []

    async def design_voice(description, language):
        designed.append((description, language))
        return "pirate-voice"

    monkeypatch.setattr(agent.voice, "design_voice", design_voice)
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "design_voice", PIRATE, id="call-voice")])
    inter = fake_interactions(i0, respond("Arr, how do I sound?"), respond("Hello again."))
    seen, on_status = statuses()

    reply = await ag.turn("Talk like a pirate", None, on_status)
    assert reply == {"say": "Arr, how do I sound?", "cards": [], "voice_id": "pirate-voice"}
    assert designed == [(PIRATE["description"], "en")] and seen == ["Designing a voice…"]
    assert json.loads(results(inter.calls[1])[0]["result"]) == {"ok": True}
    assert (await ag.turn("Hi", None, on_status))["voice_id"] == "pirate-voice"


@pytest.mark.asyncio
async def test_failed_voice_design_keeps_the_default_voice(ag, fake_interactions, monkeypatch):
    async def design_voice(description, language):
        raise RuntimeError("Gradium 409: Custom voice limit reached")

    monkeypatch.setattr(agent.voice, "design_voice", design_voice)
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "design_voice", PIRATE)])
    inter = fake_interactions(i0, respond("I can't change my voice."))
    seen, on_status = statuses()

    assert await ag.turn("Talk like a pirate", None, on_status) == {"say": "I can't change my voice.", "cards": []}
    assert json.loads(results(inter.calls[1])[0]["result"]) == {"error": "voice design failed: RuntimeError"}


@pytest.mark.asyncio
async def test_mood_switches_the_voice_once_per_change(ag, fake_interactions, monkeypatch):
    looked_up = []

    async def mood_voice(mood):
        looked_up.append(mood)
        return {"stressed": "calm-voice"}.get(mood)

    monkeypatch.setattr(agent.voice, "mood_voice", mood_voice)
    fake_interactions(
        respond("Take the 18:01. How are you feeling?"),
        respond("Breathe, you'll make it.", "stressed"),
        respond("Still on time.", "stressed"),
        respond("Glad you're fine.", "neutral"),
    )
    seen, on_status = statuses()

    assert "voice_id" not in await ag.turn("Can I make it?", None, on_status)
    assert (await ag.turn("Pretty stressed", None, on_status))["voice_id"] == "calm-voice"
    assert seen == ["Tuning my voice…"]
    assert (await ag.turn("Still on time?", None, on_status))["voice_id"] == "calm-voice"
    assert "voice_id" not in await ag.turn("I'm fine now", None, on_status)  # neutral: the default voice
    assert looked_up == ["stressed", "neutral"]


def test_invalid_mood_fails_the_respond_schema():
    assert "respond.mood must be one of" in schema_error({"say": "Hi", "cards": [], "mood": "furious"}, RESPOND_SCHEMA, "respond")


@pytest.mark.asyncio
async def test_slow_step_is_hedged(ag, fake_interactions, monkeypatch):
    # The first request hangs; past HEDGE_AFTER an identical second one races it and wins.
    monkeypatch.setattr(agent, "HEDGE_AFTER", 0.01)
    inter = fake_interactions(HANG, FakeInteraction("i-1", [FakeStep("function_call", "respond", DEMO)]))
    seen, on_status = statuses()

    assert await ag.turn("Can I make it?", None, on_status) == DEMO
    assert len(inter.calls) == 2 and inter.calls[0] == inter.calls[1]


@pytest.mark.asyncio
async def test_failed_hedge_waits_for_the_first_request(ag, fake_interactions, monkeypatch):
    monkeypatch.setattr(agent, "HEDGE_AFTER", 0.0)

    class Slow(FakeInteractions):
        async def create(self, **kwargs):
            if not self.calls:
                self.calls.append(kwargs)
                await asyncio.sleep(0.05)
                return FakeInteraction("i-0", [FakeStep("function_call", "respond", DEMO)])
            return await super().create(**kwargs)

    inter = Slow(RuntimeError("503 Service Unavailable"))
    monkeypatch.setattr(agent, "client", lambda: SimpleNamespace(aio=SimpleNamespace(interactions=inter)))
    seen, on_status = statuses()
    assert await ag.turn("Can I make it?", None, on_status) == DEMO


def test_workspace_tools_follow_the_granted_scopes(monkeypatch):
    for name in ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REFRESH_TOKEN"):
        monkeypatch.setenv(name, "x")
    monkeypatch.setenv("WORKSPACE_MODE", "rest")
    monkeypatch.delenv("GOOGLE_MAPS_API_KEY", raising=False)
    scopes = {"https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/gmail.readonly"}
    names = {t["name"] for t in agent.tool_declarations(scopes)}
    assert {"calendar_events", "gmail_search", "flights_search", "respond"} <= names
    assert not names & {"tasks_list", "drive_search", "drive_read"}  # 403 for this token: a wasted step
    assert "tasks_list" in {t["name"] for t in agent.tool_declarations(None)}  # unknown scopes: declare all


@pytest.mark.asyncio
async def test_prefetch_ignores_a_morning_event_before_an_evening_plan(ag, fake_interactions, sbb_requests):
    # Live calendar, 2026-10-10: an exam until 10:30 made the prefetch look for 10:40 trains to a 19:00
    # dinner, and the model called sbb_connections again and put the exam in a conflict card.
    ag.events = [{"title": "Mathematics exam", "start": "2026-10-15T09:00:00+02:00", "end": "2026-10-15T10:30:00+02:00"}]
    fake_interactions(FakeInteraction("i-0", [FakeStep("function_call", "respond", DEMO)]))
    seen, on_status = statuses()

    await ag.turn("Can I make it?", SCREEN, on_status)
    assert sbb_requests[0].url.params["time"] == "17:00"


def test_small_talk_is_dropped_from_say():
    assert agent.drop_small_talk("Yes, take the 18:01. How are you feeling today?") == "Yes, take the 18:01."
    assert agent.drop_small_talk("Yes! How are you? You're in Bern at 18:58.") == "Yes! You're in Bern at 18:58."
    assert agent.drop_small_talk("Take the 18:01, you're there at 18:58.") == "Take the 18:01, you're there at 18:58."
    assert agent.drop_small_talk("How are you feeling?") == "How are you feeling?"  # never empty: that means silence


@pytest.mark.asyncio
async def test_turn_drops_the_feelings_question(ag, fake_interactions):
    fake_interactions(respond("Yes, take the 18:01. How are you feeling today?"))
    seen, on_status = statuses()
    assert (await ag.turn("Can I make it?", None, on_status))["say"] == "Yes, take the 18:01."
