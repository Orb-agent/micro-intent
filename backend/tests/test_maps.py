"""Maps tools on hand-made responses in the documented shape (contracts § Tools); no live calls."""

from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest

from tools.maps import PLACES_URL, ROUTES_URL, maps_route, maps_search_places

FIXTURES = Path(__file__).parent.parent / "fixtures"


@pytest.fixture
def google(monkeypatch):
    """A client that records requests and answers with the given JSON."""
    monkeypatch.setenv("GOOGLE_MAPS_API_KEY", "test-key")
    requests: list[httpx.Request] = []

    def make(body: bytes) -> httpx.AsyncClient:
        def handler(request: httpx.Request) -> httpx.Response:
            requests.append(request)
            return httpx.Response(200, content=body)

        return httpx.AsyncClient(transport=httpx.MockTransport(handler))

    return make, requests


def assert_google_request(request: httpx.Request, url: str, field_mask: str) -> dict:
    assert request.method == "POST"
    assert str(request.url) == url  # no query string, so the key is never in the URL
    assert request.headers["X-Goog-Api-Key"] == "test-key"
    assert request.headers["X-Goog-FieldMask"] == field_mask
    return json.loads(request.content)


async def test_search_places(google):
    make, requests = google
    async with make((FIXTURES / "maps_places.json").read_bytes()) as client:
        result = await maps_search_places("Bundeshaus Bern", client=client)

    body = assert_google_request(requests[0], PLACES_URL, "places.displayName,places.formattedAddress")
    assert body == {"textQuery": "Bundeshaus Bern", "pageSize": 5}
    assert result == {
        "places": [
            {"name": "Federal Palace of Switzerland", "address": "Bundesplatz 3, 3005 Bern, Switzerland"},
            {"name": "Bundesplatz", "address": "Bundesplatz, 3011 Bern, Switzerland"},
        ]
    }


async def test_route_walk(google):
    make, requests = google
    async with make((FIXTURES / "maps_route.json").read_bytes()) as client:
        result = await maps_route("Bern station", "Bundesplatz 3, Bern", "WALK", client=client)

    body = assert_google_request(requests[0], ROUTES_URL, "routes.duration,routes.distanceMeters")
    assert body == {
        "origin": {"address": "Bern station"},
        "destination": {"address": "Bundesplatz 3, Bern"},
        "travelMode": "WALK",
    }
    assert result == {"duration_min": 9, "distance_km": 0.6}  # "530s", 640 m


async def test_empty_answers(google):
    make, _ = google
    async with make(b"{}") as client:
        assert await maps_search_places("nowhere", client=client) == {"places": []}
        assert await maps_route("A", "B", "DRIVE", client=client) == {"error": "no route found"}


async def test_route_rejects_transit(google):
    make, requests = google
    async with make(b"{}") as client:
        with pytest.raises(ValueError):
            await maps_route("Zürich HB", "Bern", "TRANSIT", client=client)
    assert requests == []
