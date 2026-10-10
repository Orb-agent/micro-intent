"""Google Maps tools: Places API (New) text search and Routes API (contracts § Tools).

Live smoke test, from backend/:
    uv run python -m tools.maps places "Bundeshaus Bern"
    uv run python -m tools.maps route "Bern station" "Bundesplatz 3, Bern" WALK
"""

from __future__ import annotations

import argparse
import os
from typing import Any

import httpx

from tools.google_auth import NotConfigured, smoke

PLACES_URL = "https://places.googleapis.com/v1/places:searchText"
ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
MODES = ("WALK", "DRIVE", "BICYCLE")  # public transport goes through sbb_connections


async def _post(url: str, body: dict, field_mask: str, client: httpx.AsyncClient | None) -> dict[str, Any]:
    if client is None:
        async with httpx.AsyncClient(timeout=5.0) as http:
            return await _post(url, body, field_mask, http)
    if not (key := os.environ.get("GOOGLE_MAPS_API_KEY")):
        raise NotConfigured("Google Maps not configured: set GOOGLE_MAPS_API_KEY")
    # The key goes in a header, never in the URL; the field mask is required.
    headers = {"X-Goog-Api-Key": key, "X-Goog-FieldMask": field_mask}
    r = await client.post(url, json=body, headers=headers)
    r.raise_for_status()
    return r.json()


async def maps_search_places(query: str, client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    data = await _post(
        PLACES_URL, {"textQuery": query, "pageSize": 5}, "places.displayName,places.formattedAddress", client
    )
    places = data.get("places", [])[:5]  # no results comes back as {}
    return {"places": [{"name": p.get("displayName", {}).get("text", ""), "address": p.get("formattedAddress", "")} for p in places]}


async def maps_route(origin: str, destination: str, mode: str, client: httpx.AsyncClient | None = None) -> dict[str, Any]:
    mode = mode.upper()
    if mode not in MODES:
        raise ValueError(f"mode must be one of {', '.join(MODES)}")
    body = {"origin": {"address": origin}, "destination": {"address": destination}, "travelMode": mode}
    data = await _post(ROUTES_URL, body, "routes.duration,routes.distanceMeters", client)
    if not data.get("routes"):
        return {"error": "no route found"}
    route = data["routes"][0]
    # duration is a string such as "1260s"; zero values are left out of the JSON.
    seconds = float(route.get("duration", "0s").rstrip("s"))
    return {"duration_min": round(seconds / 60), "distance_km": round(route.get("distanceMeters", 0) / 1000, 1)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Live smoke test for the Maps tools")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("places").add_argument("query", nargs="?", default="Bundeshaus Bern")
    route = sub.add_parser("route")
    route.add_argument("origin", nargs="?", default="Bern station")
    route.add_argument("destination", nargs="?", default="Bundesplatz 3, Bern")
    route.add_argument("mode", nargs="?", default="WALK")
    args = parser.parse_args()
    if args.command == "places":
        smoke(lambda: maps_search_places(args.query))
    else:
        smoke(lambda: maps_route(args.origin, args.destination, args.mode))
