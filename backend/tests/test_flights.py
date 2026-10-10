"""Flight search on a hand-made SerpApi response; no live calls."""

from __future__ import annotations

import logging

import httpx
import pytest
from conftest import google_fixture

from tools.flights import SERPAPI_URL, flights_search


async def test_without_key_only_a_link(no_google):
    result = await flights_search("zrh", "LIS", "2026-10-20")
    assert result["flights"] == []
    assert result["google_flights_url"] == (
        "https://www.google.com/travel/flights?q=One%20way%20flights%20from%20ZRH%20to%20LIS%20on%202026-10-20"
    )


async def test_serpapi(no_google, monkeypatch):
    monkeypatch.setenv("SERPAPI_API_KEY", "test-serp")
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=google_fixture("serpapi_flights.json"))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await flights_search("ZRH", "LIS", "2026-10-20", client=client)

    assert str(requests[0].url).startswith(SERPAPI_URL)
    params = requests[0].url.params
    assert (params["engine"], params["departure_id"], params["arrival_id"], params["type"]) == ("google_flights", "ZRH", "LIS", "2")
    assert result["google_flights_url"].startswith("https://www.google.com/travel/flights?hl=en")
    assert result["flights"] == [
        {"flight_number": "LX 1820", "airline": "SWISS", "from": "ZRH", "to": "LIS",
         "departure": "2026-10-20T07:10:00+02:00", "arrival": "2026-10-20T09:15:00+01:00",
         "stops": 0, "duration_min": 185, "price_chf": 182},
        {"flight_number": "IB 3471", "airline": "Iberia", "from": "ZRH", "to": "LIS",
         "departure": "2026-10-20T06:00:00+02:00", "arrival": "2026-10-20T10:20:00+01:00",
         "stops": 1, "duration_min": 320, "price_chf": 149},
    ]


async def test_serpapi_error_never_shows_the_key(no_google, monkeypatch, caplog):
    monkeypatch.setenv("SERPAPI_API_KEY", "test-serp")
    caplog.set_level(logging.INFO, logger="httpx")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "Invalid API key."})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(ValueError) as e:
            await flights_search("ZRH", "LIS", "2026-10-20", client=client)
    assert str(e.value) == "SerpApi HTTP 401: Invalid API key."
    assert "test-serp" not in caplog.text


async def test_rejects_bad_dates(no_google):
    with pytest.raises(ValueError):
        await flights_search("ZRH", "LIS", "next Tuesday")


def test_round_trip_link():
    from tools.flights import google_flights_url

    assert google_flights_url("ZRH", "LIS", "2026-10-20", "2026-10-23") == (
        "https://www.google.com/travel/flights?q=Flights%20from%20ZRH%20to%20LIS%20on%202026-10-20%20through%202026-10-23"
    )
