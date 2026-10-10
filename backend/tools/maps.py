"""Google Maps tools: Places API (New) text search and Routes API (contracts § Tools)."""

from __future__ import annotations

import os
from typing import Any

import httpx

PLACES_URL = "https://places.googleapis.com/v1/places:searchText"
ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"
MODES = ("WALK", "DRIVE", "BICYCLE")  # public transport goes through sbb_connections


async def _post(url: str, body: dict, field_mask: str, client: httpx.AsyncClient | None) -> dict[str, Any]:
    if client is None:
        async with httpx.AsyncClient(timeout=5.0) as http:
            return await _post(url, body, field_mask, http)
    # The key goes in a header, never in the URL; the field mask is required.
    headers = {"X-Goog-Api-Key": os.environ["GOOGLE_MAPS_API_KEY"], "X-Goog-FieldMask": field_mask}
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
