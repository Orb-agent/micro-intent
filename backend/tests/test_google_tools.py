"""The Google tools on the agent: declared only when usable, and never failing a turn."""

from __future__ import annotations

import json

import httpx
import pytest
from test_agent import FakeInteraction, FakeStep, ag, fake_interactions, statuses  # noqa: F401

import agent
from a2ui import cards_to_a2ui
from tools import google

WORKSPACE = {"calendar_events", "calendar_free_slots", "gmail_search", "gmail_read", "tasks_list", "drive_search", "drive_read"}


def names() -> set[str]:
    return {t["name"] for t in agent.tool_declarations()}


def test_workspace_tools_declared_only_with_rest_and_oauth(no_google, fake_google, monkeypatch):
    monkeypatch.setenv("WORKSPACE_MODE", "rest")
    assert WORKSPACE | {"flights_search"} <= names()
    monkeypatch.setenv("WORKSPACE_MODE", "fixture")
    assert not WORKSPACE & names()
    monkeypatch.setenv("WORKSPACE_MODE", "rest")
    monkeypatch.delenv("GOOGLE_REFRESH_TOKEN")
    assert not WORKSPACE & names()
    assert "flights_search" in names()  # still useful without any key: it gives a link


def test_every_google_tool_is_declared_once():
    declared = [d["name"] for d in [*google.WORKSPACE_DECLARATIONS, google.FLIGHTS_DECLARATION]]
    assert sorted(declared) == sorted(google.GOOGLE_TOOLS)


@pytest.mark.parametrize("name, args", [
    ("calendar_events", {"time_min": "2026-10-15", "time_max": "2026-10-16"}),
    ("calendar_free_slots", {"time_min": "2026-10-15", "time_max": "2026-10-16"}),
    ("gmail_search", {"query": "flight"}),
    ("gmail_read", {"message_id": "18f2a1"}),
    ("tasks_list", {}),
    ("drive_search", {"query": "packing"}),
    ("drive_read", {"file_id": "1AbC"}),
])
async def test_missing_credentials_never_raise(no_google, name, args):
    result = await google.run(name, args)
    assert result["error"].startswith("not configured: Google account not configured: set GOOGLE_CLIENT_ID")


async def test_bad_model_arguments_never_raise(no_google):
    assert (await google.run("flights_search", {"origin": "ZRH"}))["error"].startswith("invalid arguments")
    assert (await google.run("tasks_list", {"list": "x"}))["error"].startswith("invalid arguments")


async def test_api_error_never_raises(fake_google, monkeypatch):
    real = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(fake_google.handler), **kw))
    fake_google.route("/tasks/v1/users/@me/lists", {"error": {"code": 403, "message": "Tasks API disabled"}}, status=403)
    assert await google.run("tasks_list", {}) == {"error": "Google answered HTTP 403"}


async def test_flight_search_without_key_ends_in_a_link_card(ag, fake_interactions, no_google):  # noqa: F811
    search = {"origin": "ZRH", "destination": "LIS", "departure_date": "2026-10-20"}
    link = "https://www.google.com/travel/flights?q=One%20way%20flights%20from%20ZRH%20to%20LIS%20on%202026-10-20"
    card = {"kind": "link", "title": "Flights Zürich → Lisbon", "url": link, "detail": "Tue 20 Oct"}
    answer = {"say": "I can't see live fares, but here's the search on Google Flights.", "cards": [card]}
    i0 = FakeInteraction("i-0", [FakeStep("function_call", "flights_search", search, id="call-flights")])
    i1 = FakeInteraction("i-1", [FakeStep("function_call", "respond", answer)])
    inter = fake_interactions(i0, i1)
    seen, on_status = statuses()

    assert await ag.turn("Find me a flight to Lisbon on the 20th", None, on_status) == answer
    assert seen == ["Searching flights…"]
    result = json.loads(inter.calls[1]["input"][0]["result"])
    assert result["flights"] == [] and result["google_flights_url"] == link

    components = cards_to_a2ui("reply-1", answer["cards"])[1]["updateComponents"]["components"]
    texts = {c["id"]: c.get("text") for c in components}
    assert texts["c0-title"] == "Flights Zürich → Lisbon"
    assert texts["c0-meta"] == f"[Open in Google Flights]({link})"


def test_link_card_only_links_https():
    components = cards_to_a2ui("r", [{"kind": "link", "title": "X", "url": "javascript:alert(1)"}])[1]["updateComponents"]["components"]
    assert [c["id"] for c in components] == ["root", "c0", "c0-body", "c0-title"]
    other = cards_to_a2ui("r", [{"kind": "link", "title": "X", "url": "https://evilgoogle.com/travel/flights"}])
    assert other[1]["updateComponents"]["components"][-1]["text"] == "[Open evilgoogle.com](https://evilgoogle.com/travel/flights)"


def test_link_card_passes_the_respond_schema():
    card = {"kind": "link", "title": "Flights ZRH → LIS", "url": "https://www.google.com/travel/flights?q=x"}
    assert agent.schema_error({"say": "Here.", "cards": [card]}, agent.RESPOND_SCHEMA, "respond") is None
    assert agent.schema_error({"say": "Here.", "cards": [{"kind": "link", "title": "x"}]}, agent.RESPOND_SCHEMA, "respond") == "respond.cards[0].url is missing"
