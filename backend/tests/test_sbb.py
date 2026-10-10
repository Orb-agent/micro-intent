"""Tests for SBB connections tool."""

from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest
from tools.sbb import compact, sbb_connections

FIXTURES = Path(__file__).parent.parent / "fixtures"
SBB_FIXTURE = (FIXTURES / "sbb_zurich_bern.json").read_bytes()


def test_compact_fixture():
    raw = json.loads(SBB_FIXTURE.decode())
    result = compact(raw)
    assert len(result["connections"]) == 4

    first = result["connections"][0]
    assert first["line"] == "IC 8"
    assert first["from"] == "Zürich HB"
    assert first["to"] == "Bern"
    assert first["departure"] == "2026-10-15T18:01:00+02:00"
    assert first["arrival"] == "2026-10-15T18:58:00+02:00"
    assert first["platform"] == "31"
    assert first["arrival_platform"] == "6"
    assert first["transfers"] == 0
    assert first["delay_min"] == 0
    assert first["duration_min"] == 57


@pytest.mark.asyncio
async def test_sbb_connections_mock():
    def handler(request: httpx.Request) -> httpx.Response:
        assert "from=Z%C3%BCrich+HB" in str(request.url) or "from=Zürich+HB" in str(request.url) or "from=Z%C3%BCrich%20HB" in str(request.url)
        return httpx.Response(200, content=SBB_FIXTURE)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        result = await sbb_connections("Zürich HB", "Bern", "2026-10-15T17:55:00+02:00", client=client)

    assert len(result["connections"]) == 4
    assert result["connections"][0]["line"] == "IC 8"
