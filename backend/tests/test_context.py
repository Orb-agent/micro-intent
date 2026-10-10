"""Tests for Workspace context loading (Task 4 in WP3)."""

from __future__ import annotations

import pytest
from context import load_context, load_context_sync


@pytest.mark.asyncio
async def test_load_context_fixture_mode(monkeypatch):
    monkeypatch.setenv("WORKSPACE_MODE", "fixture")
    data = await load_context()

    assert "events" in data
    assert "flight_emails" in data

    # Check planted call
    call = next((e for e in data["events"] if e["title"] == "Call with Acme"), None)
    assert call is not None
    assert call["start"] == "2026-10-15T17:30:00+02:00"

    # Check Luma event
    luma = next((e for e in data["events"] if e["source"] == "luma"), None)
    assert luma is not None
    assert luma["title"] == "Hackathon"

    # Check flight
    flight = next((f for f in data["flight_emails"] if "LX 1820" in f["body"]), None)
    assert flight is not None
    assert flight["from"] == "SWISS"


def test_load_context_sync():
    data = load_context_sync()
    assert "events" in data
    assert len(data["events"]) >= 5
