import asyncio
import json
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from google.genai import types

import dev_agent
import vision

FIXTURES = Path(__file__).parent.parent / "fixtures"
DEMO = json.loads((FIXTURES / "demo_reply.json").read_text())
SCREEN = json.loads((FIXTURES / "screen.json").read_text())
SBB = (FIXTURES / "sbb_zurich_bern.json").read_bytes()
SBB_ARGS = {"from_station": "Zürich HB", "to_station": "Bern", "depart_after": "2026-10-15T17:55:00+02:00"}
HANG = object()  # a step that never returns, to be cancelled


def calls(*named: tuple[str, dict]) -> types.GenerateContentResponse:
    parts = [
        types.Part(function_call=types.FunctionCall(id=f"call-{i}", name=name, args=args))
        for i, (name, args) in enumerate(named)
    ]
    return types.GenerateContentResponse(candidates=[types.Candidate(content=types.Content(role="model", parts=parts))])


class FakeModels:
    def __init__(self, *steps):
        self.steps = list(steps)
        self.calls = []

    async def generate_content(self, **kwargs):
        self.calls.append({**kwargs, "contents": list(kwargs["contents"])})
        step = self.steps.pop(0)
        if step is HANG:
            await asyncio.Event().wait()
        if isinstance(step, Exception):
            raise step
        return step


@pytest.fixture
def fake(monkeypatch):
    def install(*steps):
        models = FakeModels(*steps)
        monkeypatch.setattr(vision, "_client", SimpleNamespace(aio=SimpleNamespace(models=models)))
        return models

    return install


@pytest.fixture
def sbb_requests(monkeypatch):
    """httpx without network: every request gets the recorded transport.opendata.ch response."""
    requests = []

    def handler(request):
        requests.append(request)
        return httpx.Response(200, content=SBB)

    real = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    return requests


@pytest.fixture
async def agent():
    agent = dev_agent.DevAgent()
    await agent.start()
    return agent


def statuses():
    seen = []

    async def on_status(label):
        seen.append(label)

    return seen, on_status


def function_responses(content: types.Content) -> list[types.FunctionResponse]:
    return [p.function_response for p in content.parts]


async def test_sbb_then_respond(agent, fake, sbb_requests, monkeypatch):
    monkeypatch.delenv("GEMINI_MODEL", raising=False)
    first = calls(("sbb_connections", SBB_ARGS))
    models = fake(first, calls(("respond", DEMO)))
    seen, on_status = statuses()

    assert await agent.turn("Can I make it?", SCREEN, on_status) == DEMO
    assert seen == ["Checking trains…", "Checking trains…"]  # the prefetch, then the model's own call

    params = sbb_requests[0].url.params
    assert (params["from"], params["to"], params["date"], params["time"], params["limit"]) == (
        "Zürich HB", "Bern", "2026-10-15", "17:55", "4",
    )  # fmt: skip

    user, model, tool = models.calls[1]["contents"]
    assert "<screen_context>" in user.parts[0].text and "Dinner in Bern" in user.parts[0].text
    assert "<trains>" in user.parts[1].text and '"IC 8"' in user.parts[1].text  # prefetched for the plan
    assert user.parts[2].text == "Can I make it?"
    assert model is first.candidates[0].content  # appended unmodified
    (response,) = function_responses(tool)
    assert (response.id, response.name) == ("call-0", "sbb_connections")
    assert response.response["connections"][0] == {
        "line": "IC 8", "from": "Zürich HB", "to": "Bern",
        "departure": "2026-10-15T18:01:00+02:00", "arrival": "2026-10-15T18:58:00+02:00",
        "platform": "31", "arrival_platform": "6", "transfers": 0, "delay_min": 0, "duration_min": 57,
    }  # fmt: skip
    assert len(response.response["connections"]) == 4

    config = models.calls[0]["config"]
    assert models.calls[0]["model"] == "gemini-3.8-flash"
    assert config.temperature is None
    assert config.thinking_config.thinking_level == types.ThinkingLevel.LOW
    assert config.tool_config.function_calling_config.mode == types.FunctionCallingConfigMode.ANY
    assert config.tool_config.function_calling_config.allowed_function_names is None
    assert len(agent.history) == 1 and len(agent.history[0]) == 5  # user, model, tool, model, respond's response


async def test_invalid_cards_retry_once_then_no_cards(agent, fake, sbb_requests):
    bad = {"say": "Take the 18:01.", "cards": [{**DEMO["cards"][1], "departure": "18:01"}]}
    models = fake(calls(("sbb_connections", SBB_ARGS)), calls(("respond", bad)), calls(("respond", bad)))
    seen, on_status = statuses()

    assert await agent.turn("Can I make it?", None, on_status) == {"say": "Take the 18:01.", "cards": []}

    assert len(models.calls) == 3
    (error,) = function_responses(models.calls[2]["contents"][-1])
    assert error.name == "respond" and "departure must be ISO 8601" in error.response["error"]
    last = models.calls[2]["config"].tool_config.function_calling_config
    assert last.mode == types.FunctionCallingConfigMode.ANY and last.allowed_function_names == ["respond"]


async def test_cancelled_turn_leaves_history_unchanged(agent, fake, sbb_requests):
    models = fake(calls(("respond", DEMO)), calls(("sbb_connections", SBB_ARGS)), HANG)
    seen, on_status = statuses()
    await agent.turn("Can I make it?", SCREEN, on_status)
    before = agent.history

    async def second_step_running():
        while len(models.calls) < 3:
            await asyncio.sleep(0)

    task = asyncio.create_task(agent.turn("And the next train?", None, on_status))
    await asyncio.wait_for(second_step_running(), 1)  # the turn has SBB results, not yet respond
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert agent.history is before and len(before) == 1


async def test_model_error_returns_apology(agent, fake):
    fake(RuntimeError("503"))
    seen, on_status = statuses()
    assert await agent.turn("Can I make it?", None, on_status) == {"say": dev_agent.SORRY, "cards": []}
    assert agent.history == []


async def test_no_train_prefetch_without_a_plan_on_screen(agent, fake, sbb_requests):
    models = fake(calls(("respond", {"say": "Hi!", "cards": []})))
    seen, on_status = statuses()
    screen = {**SCREEN, "proposal": None}

    assert await agent.turn("Hello", screen, on_status) == {"say": "Hi!", "cards": []}

    assert sbb_requests == [] and seen == []
    (user,) = models.calls[0]["contents"]
    assert [p.text.split(">")[0] for p in user.parts] == ["<screen_context", "Hello"]
