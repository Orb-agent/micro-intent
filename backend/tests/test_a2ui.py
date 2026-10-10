"""Tests for A2UI conversion (Task 2 in WP3)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from a2ui import cards_to_a2ui

FIXTURES = Path(__file__).parent.parent / "fixtures"


def _verify_surface(messages: list[dict], expected_surface_id: str, expected_cards_count: int) -> None:
    assert len(messages) == 2
    create_msg, update_msg = messages[0], messages[1]

    assert create_msg["version"] == "v0.9"
    assert create_msg["createSurface"]["surfaceId"] == expected_surface_id
    assert create_msg["createSurface"]["catalogId"] == "https://a2ui.org/specification/v0_9/basic_catalog.json"

    assert update_msg["version"] == "v0.9"
    assert update_msg["updateComponents"]["surfaceId"] == expected_surface_id

    components = update_msg["updateComponents"]["components"]
    comp_map = {c["id"]: c for c in components}

    assert "root" in comp_map
    root = comp_map["root"]
    assert root["component"] == "Column"
    assert len(root["children"]) == expected_cards_count

    # Check that all referenced child ids exist
    for comp in components:
        if "children" in comp:
            for child_id in comp["children"]:
                assert child_id in comp_map, f"Child id {child_id} referenced in {comp['id']} not found in components"
        if "child" in comp:
            child_id = comp["child"]
            assert child_id in comp_map, f"Child id {child_id} referenced in {comp['id']} not found in components"


def test_demo_reply_a2ui():
    demo_reply = json.loads((FIXTURES / "demo_reply.json").read_text())
    messages = cards_to_a2ui("reply-3", demo_reply["cards"])
    _verify_surface(messages, "reply-3", len(demo_reply["cards"]))

    # Verify fixture file exists and matches
    fixture_data = json.loads((FIXTURES / "demo_a2ui.json").read_text())
    assert fixture_data == messages


def test_cards_a2ui():
    cards = json.loads((FIXTURES / "cards.json").read_text())
    messages = cards_to_a2ui("cards", cards)
    _verify_surface(messages, "cards", len(cards))

    # Verify fixture file exists and matches
    fixture_data = json.loads((FIXTURES / "cards_a2ui.json").read_text())
    assert fixture_data == messages


@pytest.mark.parametrize(
    "card",
    [
        {
            "kind": "train",
            "line": "IC 8",
            "from": "Zürich HB",
            "to": "Bern",
            "departure": "2026-10-15T18:01:00+02:00",
            "arrival": "2026-10-15T18:58:00+02:00",
            "platform": "31",
            "transfers": 0,
            "delay_min": 0,
        },
        {
            "kind": "conflict",
            "event": {"title": "Call with Acme", "start": "2026-10-15T17:30:00+02:00", "end": "2026-10-15T17:45:00+02:00"},
            "proposal": {"title": "Dinner in Bern", "start": "2026-10-15T19:00:00+02:00", "place": "Bern"},
            "verdict": "fits",
            "note": "Leave right after the call",
        },
        {
            "kind": "event",
            "title": "Hackathon",
            "start": "2026-10-17T09:00:00+02:00",
            "end": "2026-10-18T18:00:00+02:00",
            "location": "Zürich",
            "source": "luma",
        },
        {
            "kind": "flight",
            "flight_number": "LX 1820",
            "from": "ZRH",
            "to": "LIS",
            "departure": "2026-10-20T07:10:00+02:00",
            "arrival": "2026-10-20T09:15:00+01:00",
            "booking_ref": "K7Q2ZP",
        },
    ],
)
def test_each_card_kind_has_root_and_valid_children(card):
    messages = cards_to_a2ui("test-surf", [card])
    _verify_surface(messages, "test-surf", 1)
